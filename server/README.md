# BURN master server

The public server list behind the in-game **Online** browser. It only stores a
list of hosts; players connect to the hosts directly (UDP, ENet). It never
relays game traffic, so it is tiny: one Python 3 file, standard library only.

- Hosts `POST /v1/servers` (name, description, version, protocol, region, mode,
  players / max players, password flag, game port), then heartbeat every 15 s.
  Entries without a heartbeat disappear after 45 s.
- The host's IP is the address the request came from (or a trusted proxy
  header, see below). A host can never claim an IP.
- After registering, the master sends one ENet CONNECT to the host's game port
  (only ever to the caller's own IP) and closes the half-open connection. If the
  host answers, the entry is `verified: true`; otherwise `false` (the browser
  shows "unverified": the host's port is probably not forwarded).
- Per-IP token-bucket rate limits, at most 5 servers per IP, 2 KB request
  bodies, length/charset limits on every field.

## Run locally

```sh
python3 server/burn_master.py --port 47290
python3 -m unittest discover -s server -p 'test_*.py'     # tests
curl http://127.0.0.1:47290/v1/servers
```

Then set the game's master URL (Settings file `[online] master_server_url`, or
the field at the bottom of the Online browser) to `http://127.0.0.1:47290`.
The default compiled into the game is `ServerList.DEFAULT_MASTER_URL` in
`network/server_list.gd`; change it to your deployed URL before a release.

Options (flags or environment variables): `--port`/`PORT`, `--expiry`,
`--no-probe`/`BURN_MASTER_PROBE=0`, `--trust-proxy none|fly|xff|real-ip`
(`BURN_MASTER_TRUST_PROXY`), `--max-servers`, `--max-per-ip`, `--log-level`.

**Only set `--trust-proxy` when the service really sits behind that proxy**;
otherwise anyone could fake their IP with a header.

## Deploy

Any small VPS or container host works. It needs an HTTPS (or HTTP) port in, and
outbound UDP for the reachability probe (without it, use `--no-probe`).

### Fly.io

```sh
cd server
fly launch --no-deploy --copy-config --name <your-app-name>   # uses fly.toml + Dockerfile
fly deploy
```

`fly.toml` sets `BURN_MASTER_TRUST_PROXY=fly` (Fly passes the client IP in
`Fly-Client-IP`). Keep exactly **one** machine: the list lives in memory
(`fly scale count 1`). The URL becomes `https://<your-app-name>.fly.dev`.

### Render

New "Web Service" from this repo, root directory `server`, runtime Docker.
Set the environment variable `BURN_MASTER_TRUST_PROXY=xff`. One instance only.

### Plain VPS

```sh
docker build -t burn-master server
docker run -d --restart unless-stopped -p 47290:47290 --name burn-master burn-master
```

Put Caddy/nginx in front for HTTPS if you like (then `--trust-proxy real-ip`
or `xff` and make sure the proxy overwrites that header).

## After deploying

1. Put the URL in `network/server_list.gd` (`DEFAULT_MASTER_URL`) and ship a build,
   or tell players to paste it into the Online browser's master field.
2. Hosts still need their UDP game port (47211) reachable: UPnP (automatic when
   the router allows it) or a manual port forward. The browser marks hosts the
   master could not reach as "unverified".

## Limits

In-memory only (a restart empties the list; hosts re-register within 15 s).
No accounts: anyone can list a server. Rate limits keep spam bounded, not
impossible. Passwords are checked by the game host, never sent to the master.
