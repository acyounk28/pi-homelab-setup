# Raspberry Pi Home Lab MCP services

Deploy Home Assistant `ha-device-mcp` and fantasy-sports `flaim-mcp` on a Raspberry Pi (or another Docker host) with Compose, then expose them through a Cloudflare Tunnel. Both services use MCP over HTTP; preserve bearer authentication and container security settings.

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

## 3. Configure the environment and devices

```sh
cp .env.example .env
nano .env
chmod 600 .env
```

For Home Assistant, configure `HA_URL`, one `HA_LONG_LIVED_ACCESS_TOKEN`, a unique `MCP_AUTH_TOKEN`, and `MCP_ALLOWED_HOSTS`. The token is created in the Home Assistant user profile under Security -> Long-Lived Access Tokens. Home Assistant is the bridge to devices: if HA controls a device, you do not need a separate hardware token for that device. Add each device to HA first using a compatible integration, then find its exact entity ID under Developer Tools -> States.

The current `ha-device-mcp` supports Pura, Oasis, and Hatch roles (see `.env.example` for their optional role-specific entity variables). Examples include Pura `light.*` / `select.*`, Oasis `light.*`, and Hatch `light.*`, `media_player.*`, optional `switch.*` and favorites `scene.*`; supported omitted IDs may be auto-discovered. The current application does not support a Windmill fan and does not consume `WINDMILL_ENTITY_ID` or `WINDMILL_FAN_ENTITY_ID`. Windmill may appear in HA via a compatible HomeKit, Local Tuya/Tuya route, or smart plug, with an entity such as `fan.windmill_ac`; that does not add Windmill controls to this MCP server. A smart plug exposes plug power rather than fan-speed controls. Do not set unsupported variables expecting them to work. See `ENV_GUIDE.md` for beginner-focused setup and device details.

For Flaim, set ESPN `ESPN_S2` and `SWID` cookies, `ESPN_LEAGUE_IDS`, `SLEEPER_LEAGUE_IDS`, and a separate strong `FLAIM_MCP_AUTH_TOKEN`. Set `TUNNEL_TOKEN` for the included token-based Cloudflare tunnel service. Never commit or share `.env`; its example contains placeholders only.

## 4. Configure Cloudflare Tunnel ingress

Create a Cloudflare Tunnel in the Cloudflare Zero Trust dashboard and configure public hostnames:

- `ha-mcp.yourdomain.com` -> `http://ha-mcp:8000`
- `flaim.yourdomain.com` -> `http://flaim-mcp:8001`

These service-name origins work when cloudflared shares the Compose network. Add the HA hostname to `MCP_ALLOWED_HOSTS`. For a locally managed tunnel, equivalent ingress rules can be configured in `cloudflared/config.yml`; if cloudflared runs outside the Compose network, use `http://localhost:8000` and `http://localhost:8001`. Do not expose MCP ports directly to the public internet; host port bindings are loopback-only.

## 5. Start services

```sh
sudo docker compose config
sudo docker compose up -d --build
sudo docker compose ps
sudo docker compose logs --tail=100 ha-mcp flaim-mcp cloudflared
```

`docker compose config` may print secrets; keep its output private. Confirm each application's documented health endpoint and MCP endpoint.

## 6. Register MCP endpoints in Poke

At https://poke.com/integrations/new register each server using its public MCP URL:

- `https://ha-mcp.yourdomain.com/mcp`
- `https://flaim.yourdomain.com/mcp`

Use the matching server's bearer token and verify each connection with a harmless read-only operation. Follow each application's documentation if its auth behavior changes; do not weaken authentication.

## Security and troubleshooting

The Compose configuration runs services as UID/GID 10001, drops Linux capabilities, enables `no-new-privileges`, uses a read-only container filesystem, and restarts unless stopped. Keep unique strong tokens, restrict Home Assistant permissions, keep secrets out of Git, and do not configure public router port forwarding. Check Compose status/logs, entity IDs, credentials, sibling repository layout, and Cloudflare service/port routing when troubleshooting. Redact secrets before sharing logs.

References: https://github.com/acyounk28/ha-device-mcp , https://github.com/acyounk28/flaim , https://docs.docker.com/engine/install/debian/ , https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/ .
