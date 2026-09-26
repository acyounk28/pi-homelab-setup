# Raspberry Pi Home Lab MCP services

Deploy Home Assistant, Home Assistant `ha-device-mcp`, and fantasy-sports `flaim-mcp` on a Raspberry Pi (or another Docker host) with Compose, then expose the MCP services through a Cloudflare Tunnel. The included Home Assistant setup uses a Compose bridge network and persistent `./ha-config` storage.

## 1. Prepare the host

Install a 64-bit Raspberry Pi OS or compatible Linux, enable SSH, and install Docker Engine and the Compose plugin using Docker's official guide: https://docs.docker.com/engine/install/debian/ . Verify Docker and Compose:

```sh
sudo docker run --rm hello-world
sudo docker compose version
```

## 2. Clone the repositories as siblings

The Compose file builds from `../ha-device-mcp` and `../flaim`; keep all three repositories next to each other:

```sh
mkdir -p ~/services && cd ~/services
git clone https://github.com/acyounk28/pi-homelab-setup.git
git clone https://github.com/acyounk28/ha-device-mcp.git
git clone https://github.com/acyounk28/flaim.git
cd pi-homelab-setup
```

## 3. Start Home Assistant and complete first-run setup

Create the private environment file and set `TZ` in `.env` to the appropriate IANA timezone. The example uses `HA_URL=http://homeassistant:8123`, the Compose service DNS name used by `ha-mcp` on the shared bridge network.

```sh
cp .env.example .env
nano .env
chmod 600 .env
sudo docker compose up -d homeassistant
sudo docker compose logs -f homeassistant
```

Once startup completes, open `http://<pi-ip>:8123` from a browser on the same LAN (replace `<pi-ip>` with the Pi's actual address). Create the Home Assistant owner/admin account and complete the initial setup/location prompts. Configuration persists under `./ha-config`. The host can also open `http://localhost:8123`.

Add devices in Home Assistant at Settings -> Devices & services -> Add integration. Use a compatible integration for each exact model (native integrations, HomeKit, Tuya/Local Tuya, SmartThings, or an appropriate custom component may apply). After integration setup, use Developer Tools -> States to copy exact entity IDs. Create a Home Assistant Long-Lived Access Token from your profile -> Security -> Long-Lived Access Tokens and put it in `.env` as `HA_LONG_LIVED_ACCESS_TOKEN`. This single HA token is the bridge for HA-controlled devices; do not enter separate device hardware tokens for this stack unless a particular HA integration requires provider authentication.

Windmill may appear through a compatible HomeKit/Tuya route or smart plug, as an entity such as `fan.windmill_ac`; smart plugs generally only provide power control. The current `ha-device-mcp` does not support Windmill controls and consumes neither `WINDMILL_ENTITY_ID` nor `WINDMILL_FAN_ENTITY_ID`. It currently supports Pura, Oasis, and Hatch roles (optional entity settings are documented in `.env.example`); Pura may expose `light.*`/`select.*`, Oasis `light.*`, and Hatch `light.*`, `media_player.*`, optional `switch.*` and favorite `scene.*`. HA exposing an entity does not automatically make it controllable through this MCP application. See `ENV_GUIDE.md` for beginner-oriented details.

## Home Assistant networking choices

The checked-in Compose configuration uses a standard bridge network: HA maps host port `8123` to container port `8123`, persists `./ha-config:/config`, and `ha-mcp` connects to `http://homeassistant:8123`. This is straightforward and works for normal API traffic. Some discovery protocols (mDNS, SSDP, HomeKit) may require Home Assistant host networking on Linux. To switch, change the HA service to `network_mode: host` and remove its `ports` and `networks`; set `HA_URL=http://host.docker.internal:8123` and add `extra_hosts: ["host.docker.internal:host-gateway"]` to `ha-mcp`. Do not use both modes simultaneously. Host networking reduces network isolation; prefer bridge mode unless discovery requires host mode.

## 4. Configure environment and remaining services

Configure the HA URL/token, strong unique `MCP_AUTH_TOKEN`, and `MCP_ALLOWED_HOSTS` in `.env`. For Flaim set ESPN `ESPN_S2` and `SWID` cookies, `ESPN_LEAGUE_IDS`, `SLEEPER_LEAGUE_IDS`, and a separate strong `FLAIM_MCP_AUTH_TOKEN`. Set `TUNNEL_TOKEN` for the included Cloudflare tunnel service. Never commit or share `.env`; `.env.example` contains placeholders only.

## 5. Configure Cloudflare Tunnel ingress

Create a Cloudflare Tunnel in Zero Trust and configure public hostnames:

- `ha-mcp.yourdomain.com` -> `http://ha-mcp:8000`
- `flaim.yourdomain.com` -> `http://flaim-mcp:8001`

These service-name origins work when cloudflared shares the Compose network. Add the HA MCP hostname to `MCP_ALLOWED_HOSTS`. Do not expose Home Assistant port 8123 or MCP ports directly to the public internet.

## 6. Start and verify the stack

After Home Assistant first-run setup and environment configuration, run from this repository (with all three sibling repositories present):

```sh
sudo docker compose config
sudo docker compose up -d --build
sudo docker compose ps
sudo docker compose logs --tail=100 homeassistant ha-mcp flaim-mcp cloudflared
```

`docker compose config` may print secrets; keep its output private. Register the MCP endpoints at https://poke.com/integrations/new using `https://ha-mcp.yourdomain.com/mcp` and `https://flaim.yourdomain.com/mcp`, with the matching bearer token. Verify using a harmless read-only operation.

## Security and troubleshooting

Keep unique strong tokens, restrict Home Assistant account permissions, keep secrets out of Git, and do not configure public router port forwarding. HA data is persisted in `./ha-config`; back it up securely. Check Compose status/logs, HA startup, exact entity IDs, sibling repository layout, and Cloudflare service/port routing when troubleshooting. Redact secrets before sharing logs.

References: https://github.com/acyounk28/ha-device-mcp , https://github.com/acyounk28/flaim , https://docs.docker.com/engine/install/debian/ , https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/ .
