# Raspberry Pi Home Lab MCP services

Deploy Home Assistant, Home Assistant `ha-device-mcp`, fantasy-sports `flaim-mcp`, and Citi Bike `citibike-mcp` on a Raspberry Pi (or another Docker host) with Compose, then expose the MCP services through a Cloudflare Tunnel. The included Home Assistant setup uses Linux host networking (for device discovery) and persistent `./config/homeassistant` storage.

## 1. Prepare the host

Install a 64-bit Raspberry Pi OS or compatible Linux, enable SSH, and install Docker Engine and the Compose plugin using Docker's official guide: https://docs.docker.com/engine/install/debian/ . Verify Docker and Compose:

```sh
sudo docker run --rm hello-world
sudo docker compose version
```

## 2. Clone the repositories as siblings

The Compose file builds from `../ha-device-mcp`, `../flaim`, and `../citibike-lookup` (plain sibling clones, not git submodules); keep all four repositories next to each other. Each service repo keeps its own runtime state out of git (Flaim's optional `config/leagues.json`, `.env` files), so `git pull` in any of them is conflict-free:

```sh
mkdir -p ~/services && cd ~/services
git clone https://github.com/acyounk28/pi-homelab-setup.git
git clone https://github.com/acyounk28/ha-device-mcp.git
git clone https://github.com/acyounk28/flaim.git
git clone https://github.com/acyounk28/citibike-lookup.git
cd pi-homelab-setup
```

## 3. Start Home Assistant and complete first-run setup

Create the private environment file and set `TZ` in `.env` to the appropriate IANA timezone. The example uses `HA_URL=http://host.docker.internal:8123`: Home Assistant runs on the host network, and `ha-mcp` (on the Compose bridge network) reaches it through the Docker host gateway.

```sh
cp .env.example .env
nano .env
chmod 600 .env
sudo docker compose up -d homeassistant
sudo docker compose logs -f homeassistant
```

Once startup completes, open `http://<pi-ip>:8123` from a browser on the same LAN (replace `<pi-ip>` with the Pi's actual address). Create the Home Assistant owner/admin account and complete the initial setup/location prompts. Configuration persists under `./config/homeassistant` (override with `HA_CONFIG_DIR` in `.env`). The host can also open `http://localhost:8123`.

Add devices in Home Assistant at Settings -> Devices & services -> Add integration. Use a compatible integration for each exact model (native integrations, HomeKit, Tuya/Local Tuya, SmartThings, or an appropriate custom component may apply). After integration setup, use Developer Tools -> States to copy exact entity IDs, or list them from the Pi with `scripts/get-ha-entities.sh <token>` (see below). Create a Home Assistant Long-Lived Access Token from your profile -> Security -> Long-Lived Access Tokens and put it in `.env` as `HA_LONG_LIVED_ACCESS_TOKEN`. This single HA token is the bridge for HA-controlled devices; do not enter separate device hardware tokens for this stack unless a particular HA integration requires provider authentication.

Windmill may appear through a compatible HomeKit/Tuya route or smart plug, as an entity such as `fan.windmill_ac`; smart plugs generally only provide power control. The current `ha-device-mcp` does not support Windmill controls and consumes neither `WINDMILL_ENTITY_ID` nor `WINDMILL_FAN_ENTITY_ID`. It currently supports Pura, Oasis, and Hatch roles (optional entity settings are documented in `.env.example`); Pura may expose `light.*`/`select.*`, Oasis `light.*`, and Hatch `light.*`, `media_player.*`, optional `switch.*` and favorite `scene.*`. HA exposing an entity does not automatically make it controllable through this MCP application. See `ENV_GUIDE.md` for beginner-oriented details.

## Home Assistant on Raspberry Pi (ARM64) in detail

### Container image and Compose service

`ghcr.io/home-assistant/home-assistant:stable` is a multi-arch image that publishes `linux/arm64` (and `amd64`), so the Raspberry Pi 5 / Pi 4 running 64-bit Raspberry Pi OS pulls the ARM64 variant automatically; no `platform:` override or Pi-specific tag is needed. (`homeassistant/home-assistant:stable` on Docker Hub is the same image.) The checked-in service in `docker-compose.yml` is:

```yaml
services:
  homeassistant:
    image: ghcr.io/home-assistant/home-assistant:stable
    container_name: homeassistant
    network_mode: host                                   # discovery (mDNS/SSDP/HomeKit/Matter); UI on <pi-ip>:8123
    environment:
      TZ: ${TZ:-America/New_York}                        # IANA timezone, from .env
    volumes:
      - ${HA_CONFIG_DIR:-./config/homeassistant}:/config # all HA state: configuration.yaml, .storage, database
      - /etc/localtime:/etc/localtime:ro                 # host clock/timezone
    restart: unless-stopped

  ha-mcp:
    # ...
    environment:
      HA_URL: ${HA_URL:-http://host.docker.internal:8123}
    extra_hosts:
      - "host.docker.internal:host-gateway"              # bridge container -> host-network HA
```

- `TZ` drives automation schedules and log timestamps; `.env.example` sets `TZ=America/New_York`. Change it there, not in the Compose file.
- `./config/homeassistant` (or `HA_CONFIG_DIR`, e.g. `/home/alex/homeassistant/config`) is created on first start and owned by the container's `root` user. Back it up (it contains the HA auth database and integration credentials) and never commit it; it is git-ignored.
- With host networking Home Assistant listens on every host interface (`0.0.0.0:8123`), so it is reachable from the LAN; the MCP services bind to `127.0.0.1` only.

To (re)start just Home Assistant and follow its startup:

```sh
sudo docker compose pull homeassistant
sudo docker compose up -d homeassistant
sudo docker compose logs -f homeassistant
```

First start on a Pi takes a few minutes while HA builds its database; wait for `Home Assistant initialized` in the logs. Upgrades are `docker compose pull homeassistant && docker compose up -d homeassistant`; the config volume is preserved.

### Host networking (default) vs bridge networking

The checked-in configuration uses `network_mode: host`, the standard for Home Assistant in Docker on Linux: discovery protocols (mDNS/Zeroconf, SSDP, HomeKit Controller, Matter, Thread) need HA to share the host's network stack. `ha-mcp` stays on the Compose bridge network and reaches HA at `http://host.docker.internal:8123` via `extra_hosts: host.docker.internal:host-gateway`. For Bluetooth integrations also mount `/run/dbus:/run/dbus:ro` into the `homeassistant` service.

If you would rather isolate HA on the bridge network (no local discovery, but only port 8123 is exposed), replace `network_mode: host` with:

```yaml
  homeassistant:
    # ...
    ports:
      - "8123:8123"
    networks:
      - homelab
```

and set `HA_URL=http://homeassistant:8123` in `.env` (the `extra_hosts` entry on `ha-mcp` is then unused but harmless). Use exactly one mode; do not keep `ports:`/`networks:` together with `network_mode: host`.

### Onboarding

Open `http://<pi-ip>:8123` from a browser on the same LAN (find the Pi's address with `hostname -I`; the Pi itself can use `http://localhost:8123`). Create the owner/admin account, set the home name/location/unit system/timezone (it should match `TZ`), and skip or accept the auto-discovered devices. Everything is written to `./config/homeassistant`. HA is bound to the LAN interface, so do not forward router port 8123 to the Pi; see the tunnel notes below for remote access.

### Create a Long-Lived Access Token for `ha-device-mcp`

`ha-mcp` authenticates to Home Assistant's REST API with a Long-Lived Access Token (LLAT) tied to one HA user. Recommended: create a dedicated, non-administrator HA user (Settings -> People -> Add person -> "Allow login") for the MCP bridge so the token's blast radius is limited, then log in as that user and:

1. Click the user name/avatar in the bottom-left of the HA sidebar to open the profile page.
2. Open the **Security** tab and scroll to **Long-lived access tokens**.
3. Click **Create token**, name it (e.g. `ha-device-mcp`), and copy the token immediately; HA shows it only once.
4. Put it in `.env`:

   ```sh
   HA_URL=http://host.docker.internal:8123
   HA_LONG_LIVED_ACCESS_TOKEN=<paste-token>
   ```

5. Restart the bridge and confirm it can reach HA:

   ```sh
   sudo docker compose up -d ha-mcp
   sudo docker compose logs --tail=50 ha-mcp
   curl -s http://127.0.0.1:8000/healthz
   ```

LLATs are valid for 10 years; revoke and rotate them from the same Security tab if `.env` is ever exposed. Only this one HA token is needed for HA-controlled devices (Pura, Oasis, Hatch); do not add per-device vendor tokens to `.env`.

### List entity IDs from the CLI

`scripts/get-ha-entities.sh` calls `GET /api/states` with the token and prints entity IDs grouped by domain (`climate`, `fan`, `light`, `switch`, `sensor` by default) with their current state and friendly name, ready to paste into `.env`:

```sh
# token as argument, HA on this machine (default URL http://localhost:8123)
scripts/get-ha-entities.sh <long-lived-access-token>

# explicit URL, or token from the environment / .env
scripts/get-ha-entities.sh <token> http://192.168.1.50:8123
set -a; . ./.env; set +a; scripts/get-ha-entities.sh http://localhost:8123

# other domains
scripts/get-ha-entities.sh -d light,media_player,scene <token>
```

It needs `curl` plus `jq` (or `python3`), exits non-zero with a plain message on a missing token, unreachable URL, or 401/403, and never prints the token (it is passed to curl through a private config file, not the command line). Copy the exact IDs into the `*_ENTITY_ID` variables documented in `.env.example`.

### Cloudflare Tunnel and Home Assistant

The included tunnel exposes only the three MCP services. **Recommended: keep the Home Assistant UI LAN-only** and reach it remotely through a VPN (Tailscale/WireGuard) or the official Home Assistant Companion app on the same network. `ha-mcp` talks to HA over the internal Compose network, so remote MCP clients (Poke, Claude, ChatGPT) never need HA itself to be public.

If you do decide to publish HA through the tunnel:

- Add a public hostname `ha.yourdomain.com -> http://host.docker.internal:8123` in Zero Trust (or an `ingress` entry in `cloudflared/config.yml` for a local-managed tunnel) and give the `cloudflared` service the same `extra_hosts: ["host.docker.internal:host-gateway"]` entry as `ha-mcp`, since HA is on the host network rather than the Compose bridge. Cloudflare proxies WebSockets, which the HA frontend requires.
- Put a Cloudflare Access policy (email/one-time PIN or identity provider) in front of that hostname. Note that the Companion app and many HA integrations do not handle the Access login page; if you need them remotely, prefer a VPN.
- Tell HA it sits behind a reverse proxy, otherwise it rejects the proxied requests with `400 Bad Request`. Add to `./config/homeassistant/configuration.yaml` and restart HA:

  ```yaml
  http:
    use_x_forwarded_for: true
    trusted_proxies:
      - 172.16.0.0/12   # Docker bridge range used by the pi-homelab network
  ```

- Cloudflare's free plan limits proxied request bodies to 100 MB, which affects backup downloads and large media uploads through the tunnel.

Security caveat: a public HA URL is a direct path to controlling your home. Anyone with the admin password (or a leaked LLAT) can operate every device, so require MFA on all HA accounts (Profile -> Security -> Multi-factor authentication), keep the MCP user non-admin, and never expose port 8123 via router port forwarding or a `0.0.0.0` tunnel origin without Access in front of it.

## 4. Configure environment and remaining services

Configure the HA URL/token, strong unique `MCP_AUTH_TOKEN`, and `MCP_ALLOWED_HOSTS` in `.env`. For Flaim set ESPN `ESPN_S2` and `SWID` cookies, `ESPN_LEAGUE_IDS`, `SLEEPER_LEAGUE_IDS`, and a separate strong `FLAIM_MCP_TOKEN` (24+ characters). Flaim reads all of these from `.env`; no `config/leagues.json` is required, and missing or placeholder ESPN cookies only disable ESPN tools while Sleeper keeps working (see `/health` for provider status). Set `TUNNEL_TOKEN` for the included Cloudflare tunnel service. For Citi Bike set `CITIBIKE_MCP_TOKEN` (falls back to `MCP_AUTH_TOKEN` if unset). Never commit or share `.env`; `.env.example` contains placeholders only.

Service contract (container DNS name, port, endpoints):

| Service | Origin | MCP endpoint | Health | Bearer token |
| --- | --- | --- | --- | --- |
| `ha-mcp` | `http://ha-mcp:8000` | `/mcp` | `/healthz` | `MCP_AUTH_TOKEN` |
| `flaim-mcp` | `http://flaim-mcp:8790` | `/mcp` (Streamable HTTP/SSE) | `/health` | `FLAIM_MCP_TOKEN` |
| `citibike-mcp` | `http://citibike-mcp:8002` | `/mcp` | `/readyz`, `/healthz` | `CITIBIKE_MCP_TOKEN` |

Ports are pinned in `docker-compose.yml` (not taken from `.env`) so they always match the tunnel origins. Host bindings are loopback-only (`127.0.0.1:<port>`).

## 5. Configure Cloudflare Tunnel ingress

Create a Cloudflare Tunnel in Zero Trust and configure public hostnames:

- `ha-mcp.yourdomain.com` -> `http://ha-mcp:8000`
- `flaim.yourdomain.com` -> `http://flaim-mcp:8790`
- `bike.yourdomain.com` -> `http://citibike-mcp:8002`

These service-name origins work when cloudflared shares the Compose network. Add the HA MCP hostname to `MCP_ALLOWED_HOSTS`. Do not expose Home Assistant port 8123 or MCP ports directly to the public internet.

## 6. Start and verify the stack

After Home Assistant first-run setup and environment configuration, run from this repository (with all three sibling repositories present):

```sh
sudo docker compose config
sudo docker compose up -d --build
sudo docker compose ps
sudo docker compose logs --tail=100 homeassistant ha-mcp flaim-mcp citibike-mcp cloudflared
curl -s http://127.0.0.1:8000/healthz  # ha-mcp
curl -s http://127.0.0.1:8790/health   # flaim: providers + config warnings
curl -s http://127.0.0.1:8002/readyz   # citibike: station count once feeds load
```

### Start all services in order

After configuring `.env` in this repository and completing Home Assistant onboarding, run `scripts/start-all.sh` from any directory instead of the manual `docker compose up` command above. Docker Compose, `curl`, and the sibling `ha-device-mcp`, `flaim`, and `citibike-lookup` checkouts are required. Use a Docker-enabled account, or run the script with `sudo` if Docker requires it.

```sh
scripts/start-all.sh
```

If a sibling `homeassistant-service` checkout has a `docker-compose.yml`, the script starts that standalone Home Assistant stack first, waits for its health check and for port 8123 to respond, then starts the other services from this repository's Compose file. If that sibling is absent, it starts this repository's `homeassistant` service first instead. It always omits this repository's `homeassistant` service when the standalone one is present: both declare the same container and port, but use different default configuration volumes. Do not switch between them without checking where your existing HA data lives. The other sibling repositories' standalone Compose stacks (including `flaim` and `ha-device-mcp`) are not started separately because this repository already runs their MCP services and would otherwise duplicate containers and port bindings.

Compose reuses unchanged containers on repeated runs. The script waits up to five minutes for HA readiness and for the remaining services to start or become healthy, then prints `docker compose ps --all` status for each started stack. If startup fails, it exits nonzero and shows status; check the affected stack's logs with `docker compose logs --tail=100`. If HA already runs under the other Compose project, resolve the competing HA container and its configuration volume before running the script; it will not stop or replace that project for you.

`docker compose config` may print secrets; keep its output private. Register the MCP endpoints at https://poke.com/integrations/new using `https://ha-mcp.yourdomain.com/mcp`, `https://flaim.yourdomain.com/mcp`, and `https://bike.yourdomain.com/mcp`, each with its matching bearer token. Verify using a harmless read-only operation.

## Security and troubleshooting

Keep unique strong tokens, restrict Home Assistant account permissions, keep secrets out of Git, and do not configure public router port forwarding. HA data is persisted in `./config/homeassistant` (`HA_CONFIG_DIR`); back it up securely. Check Compose status/logs, HA startup, exact entity IDs, sibling repository layout, and Cloudflare service/port routing when troubleshooting. Redact secrets before sharing logs.

- `421 Misdirected Request` from `ha-mcp` / `citibike-mcp`: `MCP_ALLOWED_HOSTS` / `CITIBIKE_MCP_ALLOWED_HOSTS` must contain the exact public hostname. `ha-mcp` and `citibike-mcp` both serve `/mcp` and both check the `Host` header, so they need separate hostnames.
- `401 unauthorized`: the matching MCP bearer token (`MCP_AUTH_TOKEN` / `FLAIM_MCP_TOKEN` / `CITIBIKE_MCP_TOKEN`), not the Home Assistant token.
- `citibike-mcp` unhealthy / `/readyz` 503: it could not fetch `GBFS_URL` yet or the last `GBFS_MAX_STALE_POLLS` polls failed (check outbound HTTPS/DNS from the Pi; `docker compose logs citibike-mcp` shows the failing feed URL). `cloudflared` waits for `ha-mcp` and `citibike-mcp` to report healthy before starting.

References: https://github.com/acyounk28/ha-device-mcp , https://github.com/acyounk28/flaim , https://github.com/acyounk28/citibike-lookup , https://docs.docker.com/engine/install/debian/ , https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/ .
