#!/usr/bin/env python3
"""BURN master server: the public server list.

A small, dependency-free HTTP JSON service (Python 3.9+ standard library only).
Game hosts register their public server and send a heartbeat every ~15 s;
entries without a heartbeat expire after 45 s. Players' server browsers
list the entries and connect to the hosts directly (the master never relays
game traffic).

The caller's public IP is taken from the connection (or from a trusted
reverse-proxy header, see --trust-proxy). A host can never claim an IP:
any "ip"/"address" field in the request body is ignored.

API (all JSON, UTF-8):
  GET    /v1/servers[?protocol=N]        -> {"servers": [...], "count": n, "now": t}
  POST   /v1/servers                     -> 201 {"id", "token", "address", "verified", "heartbeat_seconds", "expires_seconds"}
  POST   /v1/servers/<id>/heartbeat      -> 200 {"ok": true, "verified": ...}  (body: {"token", "players", ...})
  DELETE /v1/servers/<id>                -> 200 {"ok": true}                  (header X-Burn-Token or body {"token"})
  GET    /healthz                        -> 200 {"ok": true, "servers": n}

Run:  python3 burn_master.py --port 47290
Tests: python3 -m unittest discover -s server -p 'test_*.py'
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import logging
import os
import random
import re
import secrets
import socket
import struct
import threading
import time
import unicodedata
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

LOG = logging.getLogger("burn_master")

# --- Limits ------------------------------------------------------------------------

MAX_BODY = 2048
LIMITS = {"name": 48, "description": 160, "region": 16, "mode": 24, "version": 24}
TEXT_RE = {
    "region": re.compile(r"^[A-Za-z0-9 _-]*$"),
    "version": re.compile(r"^[0-9A-Za-z.+_-]*$"),
}
# Rate limit buckets: (capacity, refill tokens per second).
BUCKETS = {
    "list": (30, 1.0),          # browsing: 30 at once, then one per second
    "register": (6, 1.0 / 20),  # six registrations, then one per 20 s
    "heartbeat": (12, 1.0 / 4), # hosts beat every 15 s; slack for retries
    "delete": (10, 1.0 / 5),
}


def clean_text(value, limit: int) -> str:
    """Strip control/format characters, collapse whitespace, cut to `limit` characters."""
    if not isinstance(value, str):
        raise ValueError("must be a string")
    out = []
    for ch in value:
        cat = unicodedata.category(ch)
        if cat.startswith("C") or cat in ("Zl", "Zp"):
            out.append(" ")
        else:
            out.append(ch)
    text = re.sub(r"\s+", " ", "".join(out)).strip()
    return text[:limit].strip()


def as_int(value, lo: int, hi: int, field: str) -> int:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{field} must be a number")
    if isinstance(value, float) and not value.is_integer():
        raise ValueError(f"{field} must be a whole number")
    v = int(value)
    if v < lo or v > hi:
        raise ValueError(f"{field} must be between {lo} and {hi}")
    return v


def validate_listing(body: dict, partial: bool = False) -> dict:
    """Validates the descriptive fields of a server. Raises ValueError."""
    out = {}
    for field, limit in LIMITS.items():
        if field not in body:
            if partial:
                continue
            body = dict(body)
            body[field] = "" if field != "name" else None
        if body[field] is None:
            raise ValueError(f"{field} is required")
        text = clean_text(body[field], limit)
        pattern = TEXT_RE.get(field)
        if pattern is not None and not pattern.match(text):
            raise ValueError(f"{field} contains characters that are not allowed")
        out[field] = text
    if "name" in out and out["name"] == "":
        raise ValueError("name is required")
    if not partial or "protocol" in body:
        out["protocol"] = as_int(body.get("protocol"), 0, 100000, "protocol")
    if not partial or "port" in body:
        out["port"] = as_int(body.get("port"), 1024, 65535, "port")
    if not partial or "max_players" in body:
        out["max_players"] = as_int(body.get("max_players", 8), 1, 64, "max_players")
    if not partial or "players" in body:
        out["players"] = as_int(body.get("players", 0), 0, 64, "players")
    if not partial or "password" in body:
        pw = body.get("password", False)
        if not isinstance(pw, bool):
            raise ValueError("password must be true or false")
        out["password"] = pw
    return out


# --- Rate limiting -----------------------------------------------------------------

class RateLimiter:
    """Token buckets per (client ip, bucket name)."""

    def __init__(self, buckets=None, clock=time.monotonic):
        self.buckets = dict(buckets or BUCKETS)
        self.clock = clock
        self._state: dict[tuple[str, str], list[float]] = {}
        self._lock = threading.Lock()
        self._last_prune = clock()

    def allow(self, ip: str, bucket: str) -> tuple[bool, float]:
        cap, rate = self.buckets[bucket]
        now = self.clock()
        with self._lock:
            if now - self._last_prune > 60.0:
                self._prune(now)
            tokens, stamp = self._state.get((ip, bucket), (float(cap), now))
            tokens = min(float(cap), tokens + (now - stamp) * rate)
            if tokens >= 1.0:
                self._state[(ip, bucket)] = [tokens - 1.0, now]
                return True, 0.0
            self._state[(ip, bucket)] = [tokens, now]
            return False, (1.0 - tokens) / rate

    def _prune(self, now: float) -> None:
        self._last_prune = now
        for key in list(self._state):
            cap, rate = self.buckets[key[1]]
            tokens, stamp = self._state[key]
            if tokens + (now - stamp) * rate >= cap:
                del self._state[key]


# --- Reachability probe (ENet handshake) ----------------------------------------------

ENET_PEER_NONE = 0x0FFF
ENET_FLAG_SENT_TIME = 0x8000
ENET_FLAG_COMPRESSED = 0x4000
ENET_CMD_CONNECT = 2
ENET_CMD_VERIFY_CONNECT = 3
ENET_CMD_DISCONNECT = 4
ENET_CMD_ACK_FLAG = 0x80
ENET_CMD_UNSEQUENCED_FLAG = 0x40
ENET_CMD_SIZES = {1: 8, 2: 48, 3: 44, 4: 8, 5: 4, 6: 8, 7: 8, 8: 8, 9: 8, 10: 12, 11: 24, 12: 16}


def enet_connect_packet(connect_id: int, channels: int = 5) -> bytes:
    """An ENet CONNECT command, as enet_host_connect() sends it."""
    header = struct.pack(">HH", ENET_PEER_NONE | ENET_FLAG_SENT_TIME, int(time.monotonic() * 1000) & 0xFFFF)
    cmd = struct.pack(">BBH", ENET_CMD_CONNECT | ENET_CMD_ACK_FLAG, 0xFF, 1)
    body = struct.pack(
        ">HBBIIIIIIIIII",
        0,            # outgoingPeerID: our index for the server
        0xFF, 0xFF,   # session ids: let the server choose
        1392,         # mtu
        32768,        # window size
        channels,     # channel count (Godot: 3 game channels + 2 system channels)
        0, 0,         # bandwidth limits
        5000, 2, 2,   # throttle interval / acceleration / deceleration
        connect_id,
        0,            # connect data (a Godot client sends its peer id; we never finish)
    )
    return header + cmd + body


def parse_verify_connect(packet: bytes):
    """Returns (server_peer_id, session_id) from a VERIFY_CONNECT reply, or None."""
    if len(packet) < 4:
        return None
    peer_word = struct.unpack(">H", packet[:2])[0]
    if peer_word & ENET_FLAG_COMPRESSED:
        return None
    off = 4 if peer_word & ENET_FLAG_SENT_TIME else 2
    while off + 4 <= len(packet):
        command = packet[off] & 0x0F
        size = ENET_CMD_SIZES.get(command)
        if size is None or off + size > len(packet):
            return None
        if command == ENET_CMD_VERIFY_CONNECT:
            outgoing_peer_id, _incoming_session, outgoing_session = struct.unpack(">HBB", packet[off + 4:off + 8])
            return outgoing_peer_id, outgoing_session
        if command == 6 or command == 7:  # SEND_RELIABLE / SEND_UNRELIABLE carry a payload length
            data_len = struct.unpack(">H", packet[off + size - 2:off + size])[0]
            size += data_len
        off += size
    return None


def enet_disconnect_packet(server_peer_id: int, session_id: int) -> bytes:
    peer_word = (server_peer_id & 0x0FFF) | ((session_id & 0x3) << 12) | ENET_FLAG_SENT_TIME
    header = struct.pack(">HH", peer_word, int(time.monotonic() * 1000) & 0xFFFF)
    cmd = struct.pack(">BBH", ENET_CMD_DISCONNECT | ENET_CMD_UNSEQUENCED_FLAG, 0xFF, 2)
    return header + cmd + struct.pack(">I", 0)


def _plain_ip(addr: str) -> str:
    return addr[7:] if addr.startswith("::ffff:") else addr


def _probe_socket(ip: str, port: int):
    """A UDP socket and destination for `ip`. IPv4 goes through a dual-stack
    IPv6 socket when possible: Godot hosts bind dual-stack sockets, and on some
    systems (macOS loopback) their replies only reach IPv6 sockets."""
    if ":" in ip:
        try:
            return socket.socket(socket.AF_INET6, socket.SOCK_DGRAM), (ip, port, 0, 0)
        except OSError:
            return None, None
    try:
        s = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
        try:
            s.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
            return s, ("::ffff:" + ip, port, 0, 0)
        except OSError:
            s.close()
    except OSError:
        pass
    try:
        return socket.socket(socket.AF_INET, socket.SOCK_DGRAM), (ip, port)
    except OSError:
        return None, None


def probe_enet(ip: str, port: int, timeout: float = 2.0, attempts: int = 2) -> bool:
    """True when an ENet host answers a CONNECT on ip:port (UDP).

    The half-open connection is closed again with a DISCONNECT so it does not
    hold one of the host's player slots until ENet's own timeout.
    """
    connect_id = random.getrandbits(32)
    sock, target = _probe_socket(ip, port)
    if sock is None:
        return False
    with sock:
        sock.settimeout(timeout / max(1, attempts))
        for _ in range(max(1, attempts)):
            try:
                sock.sendto(enet_connect_packet(connect_id), target)
            except OSError:
                return False
            deadline = time.monotonic() + timeout / max(1, attempts)
            while time.monotonic() < deadline:
                try:
                    data, addr = sock.recvfrom(2048)
                except socket.timeout:
                    break
                except OSError:
                    return False
                if _plain_ip(addr[0]) != ip or addr[1] != port:
                    continue
                verify = parse_verify_connect(data)
                if verify is not None:
                    try:
                        sock.sendto(enet_disconnect_packet(*verify), target)
                    except OSError:
                        pass
                return True
    return False


# --- Registry ----------------------------------------------------------------------

PUBLIC_FIELDS = ("id", "name", "description", "version", "protocol", "region", "mode",
                 "players", "max_players", "password", "address", "ip", "port", "verified")


class Registry:
    def __init__(self, expiry: float = 45.0, max_servers: int = 2000, max_per_ip: int = 5,
                 probe=None, reprobe_seconds: float = 600.0, clock=time.monotonic):
        self.expiry = expiry
        self.max_servers = max_servers
        self.max_per_ip = max_per_ip
        self.probe = probe            # callable(ip, port) -> bool, or None (no probing)
        self.reprobe_seconds = reprobe_seconds
        self.clock = clock
        self._servers: dict[str, dict] = {}
        self._lock = threading.Lock()
        self._pool = ThreadPoolExecutor(max_workers=8, thread_name_prefix="probe") if probe else None

    def _expire(self, now: float) -> None:
        for sid in [s for s, e in self._servers.items() if now - e["last_seen"] > self.expiry]:
            LOG.info("expired %s (%s)", sid, self._servers[sid]["address"])
            del self._servers[sid]

    def register(self, ip: str, fields: dict) -> dict:
        now = self.clock()
        with self._lock:
            self._expire(now)
            # The same address registering again replaces its old entry (a restarted host).
            for sid, e in list(self._servers.items()):
                if e["ip"] == ip and e["port"] == fields["port"]:
                    del self._servers[sid]
            if sum(1 for e in self._servers.values() if e["ip"] == ip) >= self.max_per_ip:
                raise PermissionError("too many servers from this address")
            if len(self._servers) >= self.max_servers:
                raise OverflowError("the server list is full")
            sid = secrets.token_hex(8)
            entry = dict(fields)
            entry.update({
                "id": sid, "token": secrets.token_urlsafe(24), "ip": ip,
                "address": f"[{ip}]:{fields['port']}" if ":" in ip else f"{ip}:{fields['port']}",
                "players": min(fields.get("players", 0), fields["max_players"]),
                "verified": None if self.probe else False,
                "created": now, "last_seen": now, "probed_at": now,
            })
            self._servers[sid] = entry
            LOG.info("registered %s %s %r", sid, entry["address"], entry["name"])
        self._schedule_probe(sid, ip, fields["port"])
        return entry

    def _schedule_probe(self, sid: str, ip: str, port: int) -> None:
        if self._pool is None:
            return

        def run() -> None:
            ok = False
            try:
                ok = bool(self.probe(ip, port))
            except Exception:  # noqa: BLE001 - a failed probe must never kill the service
                LOG.exception("probe failed")
            with self._lock:
                e = self._servers.get(sid)
                if e is not None:
                    e["verified"] = ok
                    e["probed_at"] = self.clock()
        self._pool.submit(run)

    def heartbeat(self, sid: str, token: str, fields: dict) -> dict:
        now = self.clock()
        reprobe = None
        with self._lock:
            self._expire(now)
            e = self._servers.get(sid)
            if e is None:
                raise KeyError(sid)
            if not secrets.compare_digest(str(token), e["token"]):
                raise PermissionError("bad token")
            fields.pop("port", None)  # the address is fixed for the life of an entry
            e.update(fields)
            e["players"] = min(e["players"], e["max_players"])
            e["last_seen"] = now
            if self._pool is not None and e["verified"] is not True and now - e["probed_at"] > 60.0 \
                    or self._pool is not None and now - e["probed_at"] > self.reprobe_seconds:
                e["probed_at"] = now
                reprobe = (e["ip"], e["port"])
            result = {"ok": True, "verified": e["verified"], "address": e["address"]}
        if reprobe:
            self._schedule_probe(sid, *reprobe)
        return result

    def unregister(self, sid: str, token: str) -> None:
        with self._lock:
            e = self._servers.get(sid)
            if e is None:
                raise KeyError(sid)
            if not secrets.compare_digest(str(token), e["token"]):
                raise PermissionError("bad token")
            del self._servers[sid]
            LOG.info("unregistered %s", sid)

    def listing(self, protocol=None) -> list:
        now = self.clock()
        with self._lock:
            self._expire(now)
            out = []
            for e in self._servers.values():
                if protocol is not None and e["protocol"] != protocol:
                    continue
                item = {k: e[k] for k in PUBLIC_FIELDS}
                item["age"] = round(now - e["created"], 1)
                out.append(item)
        out.sort(key=lambda s: (-s["players"], s["name"].lower()))
        return out

    def count(self) -> int:
        with self._lock:
            self._expire(self.clock())
            return len(self._servers)


# --- HTTP ------------------------------------------------------------------------------

class MasterServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def server_bind(self):
        # "::" listens dual-stack (IPv4 clients appear as ::ffff:a.b.c.d).
        if self.address_family == socket.AF_INET6:
            try:
                self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
            except OSError:
                pass
        super().server_bind()

    def __init__(self, address, registry: Registry, limiter: RateLimiter, trust_proxy: str = "none"):
        self.registry = registry
        self.limiter = limiter
        self.trust_proxy = trust_proxy
        if ":" in address[0]:
            self.address_family = socket.AF_INET6
        super().__init__(address, Handler)


ID_RE = re.compile(r"^/v1/servers/([0-9a-f]{16})(/heartbeat)?/?$")


class Handler(BaseHTTPRequestHandler):
    server: MasterServer
    server_version = "BurnMaster/1"
    sys_version = ""
    timeout = 10  # seconds a client may take to send its request

    def log_message(self, fmt, *args):  # route http.server's access log through logging
        LOG.debug("%s %s", self.client_ip(), fmt % args)

    # -- helpers

    def client_ip(self) -> str:
        ip = self.client_address[0]
        mode = self.server.trust_proxy
        header = None
        if mode == "fly":
            header = self.headers.get("Fly-Client-IP")
        elif mode == "xff":
            xff = self.headers.get("X-Forwarded-For", "")
            # The right-most entry was added by our own proxy; left ones are client supplied.
            header = xff.split(",")[-1].strip() if xff else None
        elif mode == "real-ip":
            header = self.headers.get("X-Real-IP")
        if header:
            try:
                ip = str(ipaddress.ip_address(header.strip()))
            except ValueError:
                pass
        if ip.startswith("::ffff:"):
            ip = ip[7:]
        return ip

    def send_json(self, status: int, payload: dict, extra_headers=None) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        for k, v in (extra_headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def error(self, status: int, message: str, extra_headers=None) -> None:
        self.send_json(status, {"error": message}, extra_headers)

    def limited(self, bucket: str) -> bool:
        ok, wait = self.server.limiter.allow(self.client_ip(), bucket)
        if not ok:
            self.error(429, "too many requests", {"Retry-After": str(max(1, int(wait + 0.999)))})
        return not ok

    def read_json(self):
        length = self.headers.get("Content-Length")
        if length is None:
            if self.headers.get("Transfer-Encoding"):
                self.error(411, "Content-Length required")
                return None
            return {}
        try:
            n = int(length)
        except ValueError:
            self.error(400, "bad Content-Length")
            return None
        if n < 0 or n > MAX_BODY:
            self.error(413, "request body too large")
            return None
        raw = self.rfile.read(n) if n else b""
        if not raw:
            return {}
        try:
            data = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self.error(400, "body must be JSON")
            return None
        if not isinstance(data, dict):
            self.error(400, "body must be a JSON object")
            return None
        return data

    # -- routes

    def do_HEAD(self):
        self.do_GET()

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-Burn-Token")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        url = urlparse(self.path)
        if url.path in ("/healthz", "/v1/health"):
            self.send_json(200, {"ok": True, "servers": self.server.registry.count()})
            return
        if url.path == "/":
            self.send_json(200, {"service": "burn-master", "api": "/v1/servers"})
            return
        if url.path.rstrip("/") != "/v1/servers":
            self.error(404, "not found")
            return
        if self.limited("list"):
            return
        protocol = None
        q = parse_qs(url.query)
        if "protocol" in q:
            try:
                protocol = int(q["protocol"][0])
            except ValueError:
                self.error(400, "protocol must be a number")
                return
        servers = self.server.registry.listing(protocol)
        self.send_json(200, {"servers": servers, "count": len(servers), "now": int(time.time()),
                             "your_ip": self.client_ip()})

    def do_POST(self):
        url = urlparse(self.path)
        if url.path.rstrip("/") == "/v1/servers":
            self._register()
            return
        m = ID_RE.match(url.path)
        if m and m.group(2):
            self._heartbeat(m.group(1))
            return
        self.error(404, "not found")

    def do_DELETE(self):
        m = ID_RE.match(urlparse(self.path).path)
        if not m or m.group(2):
            self.error(404, "not found")
            return
        if self.limited("delete"):
            return
        body = self.read_json()
        if body is None:
            return
        token = self.headers.get("X-Burn-Token") or body.get("token", "")
        try:
            self.server.registry.unregister(m.group(1), token)
        except KeyError:
            self.error(404, "no such server")
            return
        except PermissionError:
            self.error(403, "bad token")
            return
        self.send_json(200, {"ok": True})

    def _register(self):
        if self.limited("register"):
            return
        body = self.read_json()
        if body is None:
            return
        try:
            fields = validate_listing(body)
        except ValueError as e:
            self.error(400, str(e))
            return
        if fields["players"] > fields["max_players"]:
            fields["players"] = fields["max_players"]
        try:
            entry = self.server.registry.register(self.client_ip(), fields)
        except PermissionError as e:
            self.error(429, str(e))
            return
        except OverflowError as e:
            self.error(503, str(e))
            return
        reg = self.server.registry
        self.send_json(201, {
            "id": entry["id"], "token": entry["token"], "address": entry["address"],
            "verified": entry["verified"], "heartbeat_seconds": max(5, int(reg.expiry / 3)),
            "expires_seconds": int(reg.expiry),
        })

    def _heartbeat(self, sid: str):
        if self.limited("heartbeat"):
            return
        body = self.read_json()
        if body is None:
            return
        token = body.pop("token", "") or self.headers.get("X-Burn-Token", "")
        try:
            fields = validate_listing(body, partial=True)
        except ValueError as e:
            self.error(400, str(e))
            return
        try:
            result = self.server.registry.heartbeat(sid, token, fields)
        except KeyError:
            self.error(404, "no such server (expired): register again")
            return
        except PermissionError:
            self.error(403, "bad token")
            return
        self.send_json(200, result)


def make_server(host: str = "0.0.0.0", port: int = 47290, expiry: float = 45.0, probe: bool = True,
                trust_proxy: str = "none", max_servers: int = 2000, max_per_ip: int = 5,
                probe_timeout: float = 2.0, buckets=None) -> MasterServer:
    prober = (lambda ip, p: probe_enet(ip, p, probe_timeout)) if probe else None
    registry = Registry(expiry=expiry, max_servers=max_servers, max_per_ip=max_per_ip, probe=prober)
    return MasterServer((host, port), registry, RateLimiter(buckets), trust_proxy)


def main(argv=None) -> None:
    env = os.environ.get
    ap = argparse.ArgumentParser(description="BURN master server (public server list)")
    ap.add_argument("--host", default=env("BURN_MASTER_HOST", "::"), help="bind address (\"::\" = IPv4 and IPv6)")
    ap.add_argument("--port", type=int, default=int(env("PORT", env("BURN_MASTER_PORT", "47290"))))
    ap.add_argument("--expiry", type=float, default=float(env("BURN_MASTER_EXPIRY", "45")),
                    help="seconds without heartbeat before an entry disappears")
    ap.add_argument("--no-probe", action="store_true", default=env("BURN_MASTER_PROBE", "1") == "0",
                    help="do not test that the host's UDP game port answers (entries stay unverified)")
    ap.add_argument("--probe-timeout", type=float, default=float(env("BURN_MASTER_PROBE_TIMEOUT", "2.0")))
    ap.add_argument("--trust-proxy", choices=["none", "fly", "xff", "real-ip"],
                    default=env("BURN_MASTER_TRUST_PROXY", "none"),
                    help="take the client IP from a reverse proxy header (only behind that proxy!)")
    ap.add_argument("--max-servers", type=int, default=int(env("BURN_MASTER_MAX_SERVERS", "2000")))
    ap.add_argument("--max-per-ip", type=int, default=int(env("BURN_MASTER_MAX_PER_IP", "5")))
    ap.add_argument("--log-level", default=env("BURN_MASTER_LOG", "INFO"))
    args = ap.parse_args(argv)
    logging.basicConfig(level=args.log_level.upper(), format="%(asctime)s %(levelname)s %(message)s")
    try:
        socket.socket(socket.AF_INET6, socket.SOCK_STREAM).close()
    except OSError:
        if args.host == "::":
            args.host = "0.0.0.0"  # no IPv6 on this machine
    srv = make_server(args.host, args.port, args.expiry, not args.no_probe, args.trust_proxy,
                      args.max_servers, args.max_per_ip, args.probe_timeout)
    LOG.info("BURN master listening on %s:%d (expiry %.0f s, probe %s, trust proxy %s)",
             args.host, srv.server_address[1], args.expiry, "off" if args.no_probe else "on", args.trust_proxy)
    print(f"BURN_MASTER_READY {srv.server_address[1]}", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        srv.server_close()


if __name__ == "__main__":
    main()
