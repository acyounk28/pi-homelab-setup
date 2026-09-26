# Raspberry Pi 5 MCP homelab for Poke

Docker Compose stack that runs self-hosted MCP servers on a Raspberry Pi 5 (arm64) and publishes them through one Cloudflare Zero Trust Tunnel, with no inbound router ports.

| Compose service | Source (sibling checkout) | Host bind → container | Transport / endpoint | Auth |
|---|---|---|---|---|
| `ha-mcp` | `../ha-device-mcp` (`Dockerfile`) | `127.0.0.1:8000` → `8000` | Streamable HTTP `/mcp` | `Authorization: Bearer $MCP_AUTH_TOKEN` |
| `flaim-mcp` | `../flaim/nfl-metrics` (`Dockerfile`) | `127.0.0.1:8001` → `8800` | SSE `/sse` (+ `/messages/`) by default; `/mcp` when `NFL_MCP_TRANSPORT=streamable-http` | `Authorization: Bearer $NFL_MCP_TOKEN` |
| `citibike-mcp` | `../citibike-lookup` | reserved `127.0.0.1:8002` | — | — |
| `cloudflared` | `cloudflare/cloudflared:latest` | none | tunnel connector | `TUNNEL_TOKEN` |

**`flaim-mcp` is the Flaim "NFL GM" server**, i.e. the Python FastMCP service at `flaim/nfl-metrics` (nflverse efficiency/usage metrics plus the GM tools: injury leverage, waivers/FAAB, trade scan, game environments, MILP lineup optimizer). The Flaim repo's *other* container — the Node gateway built from `flaim/Dockerfile` (ESPN/Sleeper/Yahoo league rosters, needs `FLAIM_MCP_TOKEN`, ESPN cookies and `config/leagues.json`) — is intentionally not part of this stack; add it from `flaim/docker-compose.yml` if you want it.

**`citibike-mcp` is not runnable yet.** `acyounk28/citibike-lookup` currently contains only a README (no Dockerfile, entrypoint, or environment contract), so the service is left as a commented block in `docker-compose.yml` with host port 8002 reserved. It will be enabled once that repo ships an image.

## Current status

Compose, `.env.example`, and these docs are prepared and `docker compose config` validates. Nothing in this repo has been deployed or tested on a Pi by the maintainers of this file; verify each step yourself. Cloudflare nameserver delegation, tunnel creation, public hostnames, and Poke registration are all manual steps below.

## Prepare the Pi

Install Raspberry Pi OS 64-bit (Bookworm), configure a user, SSH, and network, then:

```sh
sudo apt update && sudo apt full-upgrade -y && sudo reboot
```

Install Docker Engine + Compose plugin per https://docs.docker.com/engine/install/debian/ . Confirm `uname -m` prints `aarch64`, then `sudo docker run --rm hello-world` and `sudo docker compose version`. Every image here is built natively on the Pi (no `platform:` pins, no emulation); all Python dependencies used by `nfl-metrics` (polars, numpy, scipy, pyarrow) and `ha-device-mcp` ship aarch64 wheels.

## Clone (exact layout)

Compose uses relative build contexts, so the application repositories must be siblings of this repo:

```sh
mkdir -p ~/services && cd ~/services
git clone https://github.com/acyounk28/pi-homelab-setup.git
git clone https://github.com/acyounk28/ha-device-mcp.git
git clone https://github.com/acyounk28/flaim.git          # only flaim/nfl-metrics is built
git clone https://github.com/acyounk28/citibike-lookup.git # placeholder; no code yet
cd pi-homelab-setup
```

Resulting tree:

```
~/services/
├── pi-homelab-setup/   docker-compose.yml, .env
├── ha-device-mcp/      Dockerfile   -> ha-mcp
├── flaim/nfl-metrics/  Dockerfile   -> flaim-mcp
└── citibike-lookup/    (README only)
```

## Configure

```sh
cp .env.example .env
openssl rand -hex 32   # -> MCP_AUTH_TOKEN
openssl rand -hex 32   # -> NFL_MCP_TOKEN (must be >= 24 chars)
nano .env
chmod 600 .env
```

Variables, per service (all names come from the service code; none are invented):

- `ha-mcp` (`ha-device-mcp/src/ha_device_mcp/config.py`): `HA_URL`, `HA_LONG_LIVED_ACCESS_TOKEN`, `HA_TIMEOUT_SECONDS`, `HA_VERIFY_SSL`, optional `OASIS_LIGHT_ENTITY_ID`, `PURA_NIGHTLIGHT_ENTITY_ID`, `PURA_FRAGRANCE_SELECT_ENTITY_ID`, `PURA_INTENSITY_SELECT_ENTITY_ID`, `HATCH_LIGHT_ENTITY_ID`, `HATCH_MEDIA_PLAYER_ENTITY_ID`, `HATCH_POWER_SWITCH_ENTITY_ID`, `MCP_PATH`, `MCP_AUTH_TOKEN`, `MCP_ALLOWED_HOSTS`, `LOG_LEVEL`. `MCP_HOST`/`MCP_PORT` are fixed to `0.0.0.0`/`8000` by Compose. Use `HA_URL=http://host.docker.internal:8123` when Home Assistant runs on the same Pi (`extra_hosts` maps it to the host). Put the exact public hostname in `MCP_ALLOWED_HOSTS` or you will get `421 Misdirected Request`.
- `flaim-mcp` (`flaim/nfl-metrics/nfl_metrics/config.py`): `NFL_MCP_TOKEN`, `NFL_MCP_TRANSPORT`, `NFL_RAW_TTL_HOURS`, `NFL_DERIVED_TTL_HOURS`, `NFL_MAX_SEASONS_IN_MEMORY`, `POLARS_MAX_THREADS`; Compose fixes `NFL_DATA_DIR=/data/nfl`, `NFLREADPY_CACHE_DIR`, `HOST`, `PORT=8800`. `NFL_MEM_LIMIT` is a Compose memory limit (default `1536m`). Parquet caches live in the named volume `nfl-data`.
- `cloudflared`: `TUNNEL_TOKEN`.

Secrets are passed with explicit per-service `environment:` maps (not a shared `env_file`), so the HA token is never visible inside the NFL container and vice versa.

## Build and run

```sh
sudo docker compose config -q          # validates; full `config` output renders secrets
sudo docker compose up -d --build      # first build on a Pi 5: several minutes (Python wheels)
sudo docker compose ps
sudo docker compose logs --tail=100 ha-mcp flaim-mcp cloudflared
curl -i http://127.0.0.1:8000/healthz  # ha-mcp
curl -i http://127.0.0.1:8001/health   # flaim-mcp (nfl-metrics)
```

Both health endpoints are unauthenticated; every other path returns `401` without the correct bearer token. `cloudflared` starts only after both services report healthy.

## Cloudflare Tunnel

Create a remotely-managed tunnel (Zero Trust → Networks → Tunnels → Cloudflared), copy the connector token into `TUNNEL_TOKEN`, and add public hostnames. The connector runs inside the Compose network, so origins use Compose service names and **container** ports:

| Public hostname (example) | Origin service | Client URL for Poke |
|---|---|---|
| `ha.yourdomain.com` | `http://ha-mcp:8000` | `https://ha.yourdomain.com/mcp` |
| `nfl.yourdomain.com` | `http://flaim-mcp:8800` | `https://nfl.yourdomain.com/sse` (or `/mcp` with `NFL_MCP_TRANSPORT=streamable-http`) |

Separate hostnames are the recommended layout: `ha-mcp` validates the `Host` header (`MCP_ALLOWED_HOSTS`), and both servers use root-level paths (`/mcp`, `/sse`, `/messages/`), so a single hostname would require path rules that keep `ha-mcp` and a Streamable-HTTP `nfl-metrics` from both claiming `/mcp`. Path routing on one hostname *is* possible only with `NFL_MCP_TRANSPORT=sse`: route `/mcp` → `ha-mcp:8000` and `/sse` + `/messages*` → `flaim-mcp:8800`, with a `404` catch-all. Cloudflare Tunnel cannot rewrite paths, so a `/nfl/...` prefix layout is not feasible with these servers as written. For SSE, raise the origin **Connection timeout** / keep-alive in the hostname's HTTP settings; SSE streams are long-lived.

`cloudflared/config.yml` is the equivalent local-managed (credentials-file) ingress example; see `cloudflared/README.md`.

## Poke

At https://poke.com/integrations/new add one integration per server:

| Name | URL | Transport | Header |
|---|---|---|---|
| Home Assistant | `https://ha.yourdomain.com/mcp` | Streamable HTTP | `Authorization: Bearer <MCP_AUTH_TOKEN>` |
| NFL GM (Flaim) | `https://nfl.yourdomain.com/sse` | SSE | `Authorization: Bearer <NFL_MCP_TOKEN>` |

Never put tokens in URLs. Test a read-only tool first (e.g. `get_cache_status` on the NFL server). If Poke cannot send the bearer header for a server, fix client compatibility; do not disable server authentication.

## Hardening summary

Every application container: `read_only: true` root filesystem (writable paths are only a small `/tmp` tmpfs and, for `flaim-mcp`, the `/data` volume), `cap_drop: [ALL]`, `no-new-privileges:true`, `restart: unless-stopped`, log rotation, loopback-only host ports, non-root UID 10001 (`appuser` in `ha-device-mcp`, `nfl` in `nfl-metrics`; both re-asserted with `user:` in Compose). `cloudflared` runs with `cap_drop: [ALL]` and `no-new-privileges`. See [SECURITY.md](SECURITY.md) for host firewall/SSH steps. `nfl-metrics` disables FastMCP's DNS-rebinding host check so it can accept the tunnel hostname; keep its port loopback-only and its bearer token strong.

## Troubleshooting

- `sudo docker compose ps` / `logs --tail=200 <service>`: health and startup errors (redact secrets).
- `421 Misdirected Request` from `ha-mcp`: `MCP_ALLOWED_HOSTS` must contain the exact public hostname.
- `401 unauthorized`: the MCP bearer token (`MCP_AUTH_TOKEN` / `NFL_MCP_TOKEN`), not the Home Assistant token.
- `flaim-mcp` exits with `NFL_MCP_TOKEN is required` / `must be at least 24 characters`: fix `.env`.
- `flaim-mcp` OOM-killed on a 4 GB Pi: lower `NFL_MEM_LIMIT` only with care; keep `NFL_MAX_SEASONS_IN_MEMORY=1`.
- Read-only filesystem errors: mount only the specific path as a tmpfs/volume; do not remove `read_only`.
- Tunnel cannot reach origin: check the service is healthy and the origin uses the *container* port (`ha-mcp:8000`, `flaim-mcp:8800`), not the host port.
- Never fix problems by forwarding ports on the router or removing authentication.

References: https://github.com/acyounk28/ha-device-mcp , https://github.com/acyounk28/flaim/blob/main/docs/SELF-HOSTING.md , https://github.com/acyounk28/citibike-lookup , https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/ .
