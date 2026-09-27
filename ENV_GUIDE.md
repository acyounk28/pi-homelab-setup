# Environment setup guide (beginner-friendly)

This guide gets Home Assistant running in this Compose stack, then explains its connection to the MCP services and devices. Home Assistant is the bridge: when it controls a device, you do not need a separate device hardware token for this setup.

## 1. Prepare configuration and start Home Assistant

Clone `pi-homelab-setup`, `ha-device-mcp`, `flaim`, and `citibike-lookup` as sibling directories as described in README.md. From `pi-homelab-setup`, create the private environment file:

```sh
cp .env.example .env
nano .env
chmod 600 .env
```

Keep `HA_URL=http://host.docker.internal:8123`: Home Assistant runs with `network_mode: host`, and `ha-mcp` reaches the host through the `host.docker.internal` alias that Compose adds for it. `HA_CONFIG_DIR` (default `./config/homeassistant`) is where Home Assistant stores its configuration and database; use an absolute path such as `/home/alex/homeassistant/config` if you prefer. `TZ` is the timezone used by the Home Assistant container; set it to the correct IANA timezone for your location if different. Do not put secrets in `.env.example`, and never commit/share `.env`.

Start the Home Assistant service first (this avoids needing the other repositories or credentials during initial onboarding):

```sh
sudo docker compose up -d homeassistant
sudo docker compose logs -f homeassistant
```

From a browser on the same LAN, visit `http://<pi-ip>:8123` (replace `<pi-ip>` with the Pi's actual LAN address). Wait for first startup, then create the Home Assistant owner/admin account and finish location/setup prompts. The saved config persists in `./config/homeassistant` (`HA_CONFIG_DIR`). Home Assistant is also reachable on the Docker host at `http://localhost:8123`.

Home Assistant uses Linux host networking so mDNS, SSDP, and HomeKit discovery work out of the box. README.md describes the bridge-network alternative and its `HA_URL` change. Do not run both modes at once.

## 2. Create the Home Assistant access token

In the Home Assistant UI, click your profile/name, open Security, find Long-Lived Access Tokens, choose Create Token, give it a recognizable name, and copy it immediately. Put the complete token into `HA_LONG_LIVED_ACCESS_TOKEN` in `.env`. Keep `HA_URL=http://host.docker.internal:8123` for the included host-network configuration. Alternatively `scripts/ha_token.py create --write-env .env` creates the token for you (docs/ha-device-mcp.md). This one Home Assistant token lets `ha-device-mcp` communicate with Home Assistant and its supported devices; you do not need separate Windmill, Pura, Oasis, or Hatch hardware tokens when HA controls those devices.

`HA_TIMEOUT_SECONDS` and `HA_VERIFY_SSL` can normally stay at their example defaults. `MCP_HOST`, `MCP_PORT`, and `MCP_PATH` are service settings; retain defaults. Replace `MCP_AUTH_TOKEN` with a strong unique secret (generate one on the host using `openssl rand -hex 32`). Add the public HA MCP hostname to comma-separated `MCP_ALLOWED_HOSTS` while retaining localhost entries.

## 3. Add device integrations and find entity IDs

In Home Assistant, open Settings -> Devices & services -> Add integration and add a compatible integration for each device. Which integration works depends on model, firmware, network, and desired controls. Device setup belongs in Home Assistant; do not look for per-device tokens to put in this deployment unless a particular HA integration itself asks you to authenticate with its provider.

Step-by-step guides for each device live in `docs/devices/` (see `docs/devices/README.md`); the short version:

- Windmill fan (`docs/devices/windmill.md`): HomeKit Controller (local) is preferred, Tuya / tuya-local or the WindmillAC cloud integration are fallbacks. `ha-device-mcp` needs a `fan.*` entity in `WINDMILL_FAN_ENTITY_ID` (no auto-discovery); the guide shows a template fan wrapping the `climate.*` entity.
- Pura (`docs/devices/pura.md`): the `pura` custom component (staged by the installer) provides `light.*_nightlight`, `select.*_fragrance`, `select.*_intensity`.
- Oasis Lighting (`docs/devices/oasis-lighting.md`): the lights from heyoasis.com (Mixtiles Oasis Ambient / Oasis Bulb, app "Oasis Lighting"). Only a community cloud integration (`oasis`, staged by the installer) exists; it needs your Oasis account. **Not** the Oasis Mini sand table (`ha-oasis-control`). Always set `OASIS_LIGHT_ENTITY_ID`.
- Hatch (`docs/devices/hatch.md`): the `ha_hatch` custom component provides `light.*_light`, `media_player.*`, optional `switch.*_power_switch`.
- Other supported options can include native HA integrations, HomeKit, SmartThings, Tuya, or custom components, but availability varies by model. HA visibility does not automatically mean the MCP application supports control of that entity.

To obtain IDs, open Developer Tools -> States, search for the device, select its entity, and copy the complete ID including domain, such as `fan.`, `light.`, `select.`, `media_player.`, or `switch.`. Do not guess from the friendly name. Easier: `scripts/export_entities.py --merge-into .env` discovers the entities for every role and writes the `*_ENTITY_ID` keys for you (`docs/ha-device-mcp.md`). `ha-device-mcp` reads `OASIS_LIGHT_ENTITY_ID`, `PURA_NIGHTLIGHT_ENTITY_ID`, `PURA_FRAGRANCE_SELECT_ENTITY_ID`, `PURA_INTENSITY_SELECT_ENTITY_ID`, `HATCH_LIGHT_ENTITY_ID`, `HATCH_MEDIA_PLAYER_ENTITY_ID`, `HATCH_POWER_SWITCH_ENTITY_ID` and `WINDMILL_FAN_ENTITY_ID`; omitted Pura/Hatch roles are auto-discovered, Oasis and Windmill must be set.

## 4. Start the rest of the homelab

After Home Assistant onboarding, integrations, and token setup, set the Flaim values in `.env` (ESPN cookies, league IDs, and a separate strong `FLAIM_MCP_TOKEN`). Set `TUNNEL_TOKEN` if using Cloudflare Tunnel. Then, with all three sibling repositories present, validate and start the stack:

```sh
sudo docker compose config
sudo docker compose up -d --build
sudo docker compose ps
```

`docker compose config` can display secrets; keep its output private. ESPN `ESPN_S2` and `SWID` are sensitive browser cookies from the `espn.com` cookie store. ESPN league IDs come after `leagueId=` in the league URL; Sleeper league IDs are the path segment after `/leagues/`. Keep them private as appropriate. Flaim consumes these variables directly (`SWID`/`ESPN_SWID`, `ESPN_S2`/`espn_s2`, `FLAIM_MCP_TOKEN` or legacy `FLAIM_MCP_AUTH_TOKEN` are all accepted); no `config/leagues.json` is needed. If the ESPN cookies are missing or still placeholders, `flaim-mcp` starts with ESPN disabled and reports `providers.espn: missing-credentials` at `/health`, while Sleeper leagues keep working.

## 5. Cloudflare and security

For the included Compose network, Cloudflare origins are `http://ha-mcp:8000`, `http://flaim-mcp:8790`, and `http://citibike-mcp:8002`; the Citi Bike service uses `CITIBIKE_MCP_TOKEN` (or `MCP_AUTH_TOKEN` if unset) and optional `CITIBIKE_MCP_ALLOWED_HOSTS`; do not expose port 8123 publicly. Keep the unique MCP tokens and Home Assistant token private. The host can reach HA at `http://localhost:8123`, while other LAN clients use `http://<pi-ip>:8123`.

Home Assistant runs with `network_mode: host` (Linux-specific; HA listens on the host's network and bypasses Compose network isolation), and `ha-mcp` reaches it via `HA_URL=http://host.docker.internal:8123` plus `extra_hosts: ["host.docker.internal:host-gateway"]`. To isolate HA on the bridge network instead, replace `network_mode: host` with `ports: ["8123:8123"]` and `networks: [homelab]` and set `HA_URL=http://homeassistant:8123`. Choose one network mode deliberately.
