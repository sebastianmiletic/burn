"""Tests for burn_master.py:  python3 -m unittest discover -s server -p 'test_*.py'"""
import json
import os
import socket
import struct
import sys
import threading
import time
import unittest
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import burn_master as bm  # noqa: E402

GOOD = {"name": "Ash Fire", "description": "come dig", "version": "0.5.1", "protocol": 5,
        "region": "eu", "mode": "campaign", "port": 47211, "players": 1, "max_players": 8, "password": False}


class FakeClock:
    def __init__(self):
        self.t = 1000.0

    def __call__(self):
        return self.t


class RegistryTests(unittest.TestCase):
    def setUp(self):
        self.clock = FakeClock()
        self.reg = bm.Registry(expiry=45, max_per_ip=2, clock=self.clock)

    def test_register_list_heartbeat_expiry(self):
        e = self.reg.register("1.2.3.4", bm.validate_listing(dict(GOOD)))
        self.assertEqual(e["address"], "1.2.3.4:47211")
        self.assertEqual(len(self.reg.listing()), 1)
        self.assertNotIn("token", self.reg.listing()[0])
        self.clock.t += 30
        self.reg.heartbeat(e["id"], e["token"], bm.validate_listing({"players": 3}, partial=True))
        self.assertEqual(self.reg.listing()[0]["players"], 3)
        self.clock.t += 40
        self.assertEqual(len(self.reg.listing()), 1, "heartbeat kept it alive")
        self.clock.t += 10
        self.assertEqual(self.reg.listing(), [], "expired after 45 s without heartbeat")
        with self.assertRaises(KeyError):
            self.reg.heartbeat(e["id"], e["token"], {})

    def test_bad_token_and_unregister(self):
        e = self.reg.register("1.2.3.4", bm.validate_listing(dict(GOOD)))
        with self.assertRaises(PermissionError):
            self.reg.heartbeat(e["id"], "nope", {})
        with self.assertRaises(PermissionError):
            self.reg.unregister(e["id"], "nope")
        self.reg.unregister(e["id"], e["token"])
        self.assertEqual(self.reg.listing(), [])

    def test_per_ip_limit_and_reregister_replaces(self):
        self.reg.register("1.2.3.4", bm.validate_listing(dict(GOOD)))
        self.reg.register("1.2.3.4", bm.validate_listing(dict(GOOD)))  # same port: replaces
        self.assertEqual(len(self.reg.listing()), 1)
        self.reg.register("1.2.3.4", bm.validate_listing(dict(GOOD, port=47212)))
        with self.assertRaises(PermissionError):
            self.reg.register("1.2.3.4", bm.validate_listing(dict(GOOD, port=47213)))

    def test_protocol_filter(self):
        self.reg.register("1.2.3.4", bm.validate_listing(dict(GOOD)))
        self.assertEqual(len(self.reg.listing(5)), 1)
        self.assertEqual(len(self.reg.listing(4)), 0)


class ValidationTests(unittest.TestCase):
    def test_cleaning_and_limits(self):
        f = bm.validate_listing(dict(GOOD, name="  A\x00B\nC  " + "x" * 100, description="d" * 500))
        self.assertTrue(f["name"].startswith("A B C"))
        self.assertEqual(len(f["name"]), 48)
        self.assertEqual(len(f["description"]), 160)

    def test_rejects(self):
        for bad in [dict(GOOD, name=""), dict(GOOD, name=5), dict(GOOD, port=80), dict(GOOD, port="x"),
                    dict(GOOD, max_players=0), dict(GOOD, password="yes"), dict(GOOD, region="<script>"),
                    dict(GOOD, players=True), {k: v for k, v in GOOD.items() if k != "name"}]:
            with self.assertRaises(ValueError, msg=str(bad)):
                bm.validate_listing(bad)

    def test_claimed_ip_is_ignored(self):
        f = bm.validate_listing(dict(GOOD, ip="9.9.9.9", address="9.9.9.9:1"))
        self.assertNotIn("ip", f)
        self.assertNotIn("address", f)


class RateLimitTests(unittest.TestCase):
    def test_bucket(self):
        clock = FakeClock()
        rl = bm.RateLimiter({"x": (3, 1.0)}, clock=clock)
        self.assertTrue(all(rl.allow("a", "x")[0] for _ in range(3)))
        ok, wait = rl.allow("a", "x")
        self.assertFalse(ok)
        self.assertGreater(wait, 0)
        self.assertTrue(rl.allow("b", "x")[0], "buckets are per IP")
        clock.t += 1.0
        self.assertTrue(rl.allow("a", "x")[0])


class EnetPacketTests(unittest.TestCase):
    def test_connect_layout(self):
        p = bm.enet_connect_packet(0x12345678)
        self.assertEqual(len(p), 52)
        self.assertEqual(p[0:2], b"\x8f\xff")
        self.assertEqual(p[4], 0x82)

    def test_parse_verify(self):
        pkt = struct.pack(">HH", 0x8000 | (1 << 12), 7)
        pkt += struct.pack(">BBHHH", 0x81, 0xFF, 1, 1, 7)  # ACK (8 bytes)
        pkt += struct.pack(">BBH", 0x83, 0xFF, 1) + struct.pack(">HBB", 3, 1, 2) + b"\x00" * 36
        self.assertEqual(bm.parse_verify_connect(pkt), (3, 2))
        self.assertIsNone(bm.parse_verify_connect(b"\x00"))

    def test_probe_closed_port(self):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
        s.close()
        self.assertFalse(bm.probe_enet("127.0.0.1", port, timeout=0.4))


class HttpTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = bm.make_server("127.0.0.1", 0, expiry=2.0, probe=True, probe_timeout=0.4,
                                 buckets={"list": (50, 10), "register": (4, 0.01), "heartbeat": (50, 10),
                                          "delete": (50, 10)})
        cls.base = "http://127.0.0.1:%d" % cls.srv.server_address[1]
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()

    def req(self, method, path, body=None, headers=None):
        data = json.dumps(body).encode() if body is not None else None
        r = urllib.request.Request(self.base + path, data=data, method=method, headers=headers or {})
        if data is not None:
            r.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(r, timeout=5) as resp:
                return resp.status, json.loads(resp.read() or b"{}")
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read() or b"{}")

    def test_a_flow(self):
        st, reg = self.req("POST", "/v1/servers", dict(GOOD, port=47219, ip="6.6.6.6"))
        self.assertEqual(st, 201)
        self.assertEqual(reg["address"], "127.0.0.1:47219", "the caller's IP, never the claimed one")
        st, lst = self.req("GET", "/v1/servers?protocol=5")
        self.assertEqual(st, 200)
        self.assertEqual([s["id"] for s in lst["servers"]], [reg["id"]])
        st, _ = self.req("POST", "/v1/servers/%s/heartbeat" % reg["id"], {"token": reg["token"], "players": 2})
        self.assertEqual(st, 200)
        st, _ = self.req("POST", "/v1/servers/%s/heartbeat" % reg["id"], {"token": "bad"})
        self.assertEqual(st, 403)
        time.sleep(1.0)
        self.assertIs(self.req("GET", "/v1/servers")[1]["servers"][0]["verified"], False,
                      "nothing answers on that port")
        st, _ = self.req("DELETE", "/v1/servers/%s" % reg["id"], headers={"X-Burn-Token": reg["token"]})
        self.assertEqual(st, 200)
        self.assertEqual(self.req("GET", "/v1/servers")[1]["count"], 0)

    def test_b_expiry(self):
        st, reg = self.req("POST", "/v1/servers", dict(GOOD, port=47218))
        self.assertEqual(st, 201)
        time.sleep(2.5)
        self.assertEqual(self.req("GET", "/v1/servers")[1]["count"], 0)
        self.assertEqual(self.req("POST", "/v1/servers/%s/heartbeat" % reg["id"], {"token": reg["token"]})[0], 404)

    def test_c_bad_requests(self):
        self.assertEqual(self.req("POST", "/v1/servers", dict(GOOD, port=1))[0], 400)
        self.assertEqual(self.req("GET", "/nope")[0], 404)
        r = urllib.request.Request(self.base + "/v1/servers", data=b"x" * 5000, method="POST")
        try:
            urllib.request.urlopen(r, timeout=5)
            code = 200
        except urllib.error.HTTPError as e:
            code = e.code
        except (ConnectionError, urllib.error.URLError):
            code = 413
        self.assertEqual(code, 413)

    def test_d_register_rate_limit(self):
        codes = [self.req("POST", "/v1/servers", dict(GOOD, port=48000 + i))[0] for i in range(6)]
        self.assertIn(429, codes)


if __name__ == "__main__":
    unittest.main()
