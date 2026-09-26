# Environment setup guide (beginner-friendly)

This guide explains every value in `.env.example`, where to find it, and how Home Assistant connects to your devices. You do not need a separate hardware/API token for each device when Home Assistant already controls it.

## 1. Create your private `.env`

From the `pi-homelab-setup` directory:

```sh
cp .env.example .env
nano .env
chmod 600 .env
```

Replace placeholder values after `=`; do not add spaces around `=`. Save in nano with Ctrl+O, Enter, then Ctrl+X. `.env` contains secrets: never commit it, share it, or paste it into support requests.

## 2. The one Home Assistant connection

`HA_URL` is the address of your Home Assistant server reachable from the Docker host, including port 8123. Examples: `http://homeassistant.local:8123` or `http://192.168.1.50:8123` (use your actual address, not the example IP).

To create `HA_LONG_LIVED_ACCESS_TOKEN`, sign into Home Assistant as the account the service should use, click your profile/name, open Security, find Long-Lived Access Tokens, choose Create Token, name it, and copy it immediately. Paste the complete token into `.env`. Treat it like a password; a dedicated limited-permission HA user is preferable. This single Home Assistant token authorizes this server to communicate with devices HA controls. You do not need to find or enter separate Windmill, Pura, Oasis, or Hatch device hardware tokens for this bridge.

`HA_TIMEOUT_SECONDS` and `HA_VERIFY_SSL` are connection settings; keep the defaults unless you know why they need changing. `MCP_HOST`, `MCP_PORT`, and `MCP_PATH` are server settings; retain defaults. Set a unique, strong `MCP_AUTH_TOKEN` for the MCP endpoint. `MCP_ALLOWED_HOSTS` is a comma-separated hostname allowlist; retain localhost entries and add the public hostname used for HA MCP.

## 3. Make devices available in Home Assistant

Home Assistant is the single bridge: first integrate each device into HA, then use the entity HA creates. Integrations and entity availability depend on the device model, firmware, and installation; a device may not expose every control.

- Windmill fan: pair/add it to Home Assistant through a compatible route such as HomeKit Device/Controller, Local Tuya or the Tuya integration, or a smart plug (which provides plug power control, not fan speed controls). After setup, look in Developer Tools -> States for an entity, often `fan.windmill_ac` or `fan.bedroom_fan`; the actual ID may differ. Important: the current `ha-device-mcp` configuration does not define or consume `WINDMILL_FAN_ENTITY_ID` or `WINDMILL_ENTITY_ID` and does not provide Windmill fan tools. Do not add either variable expecting this MCP server to control it. A future/application change is needed to support Windmill here.
- Pura: add the Pura Home Assistant integration (for example the `ha-pura` custom integration) and complete its setup. It can expose entities such as `light.<device>_nightlight` and `select.<device>_fragrance` / `select.<device>_intensity`. Pura's fragrance controls are not fan entities.
- Oasis: add the supported Oasis Mini integration/custom component (such as `ha-oasis-control`). It can expose a light entity such as `light.oasis_mini_led`.
- Hatch: add the Hatch integration/custom component (such as `ha_hatch`). Depending on model, it may expose `light.*`, `media_player.*`, optional `switch.*`, and favorite `scene.*` entities.
- Other routes: a device may be brought into HA via a supported native integration, HomeKit, SmartThings, Tuya, or a compatible custom component. Use only a route that actually supports your model and desired controls. The MCP server can only operate entities/integrations it implements; making an entity visible in HA does not automatically add MCP tools for it.

### Find and copy an entity ID

In Home Assistant, open Developer Tools -> States. Search by device/friendly name. Select the entity and copy its exact entity ID, including its domain (`light.`, `select.`, `media_player.`, `switch.`, or `fan.`). Do not copy the display name or guess. For supported roles, put the ID in the matching optional `.env` setting listed in `.env.example`. The current `ha-device-mcp` supports explicit `OASIS_LIGHT_ENTITY_ID`, `PURA_NIGHTLIGHT_ENTITY_ID`, `PURA_FRAGRANCE_SELECT_ENTITY_ID`, `PURA_INTENSITY_SELECT_ENTITY_ID`, `HATCH_LIGHT_ENTITY_ID`, `HATCH_MEDIA_PLAYER_ENTITY_ID`, and `HATCH_POWER_SWITCH_ENTITY_ID`; it auto-discovers omitted supported roles when exactly one match exists. It does not support Windmill or generic `WINDMILL_*` variables at present.

## 4. Create the MCP bearer token

On the Docker host, run `openssl rand -hex 32` and paste the result into `MCP_AUTH_TOKEN`. Keep it private. The HA MCP client uses `Authorization: Bearer <token>` with the actual token replacing the placeholder. Do not reuse the Flaim token.

## 5. Flaim credentials

`ESPN_S2` and `SWID` are sensitive ESPN login cookies, not Home Assistant or device tokens. Sign into ESPN fantasy football in a browser, open browser Developer Tools -> Application/Storage -> Cookies -> `espn.com`, and copy the complete values for cookies named `espn_s2` and `SWID` into their matching variables. Keep them secret.

For `ESPN_LEAGUE_IDS`, copy the league ID value from the ESPN league URL after `leagueId=`. For `SLEEPER_LEAGUE_IDS`, copy the league ID segment from the Sleeper league URL after `/leagues/`. Use comma-separated IDs for multiple leagues. Set a separate strong `FLAIM_MCP_AUTH_TOKEN`; do not reuse the HA token. Keep the supplied Flaim host and port defaults.

## 6. Cloudflare Tunnel

In Cloudflare Zero Trust, open Networks -> Tunnels, select/create a tunnel and choose Docker/Linux setup. Copy only the token from the command's `--token` argument into `TUNNEL_TOKEN`. Treat it as a secret. Add public routes for `ha-mcp.yourdomain.com` to `http://ha-mcp:8000` and `flaim.yourdomain.com` to `http://flaim-mcp:8001` when cloudflared shares this Compose network. The HA hostname must also be in `MCP_ALLOWED_HOSTS`. Never expose the MCP ports directly to the public internet.

## 7. Validate and start

With the three sibling repositories cloned as described in README.md, run from this repository:

```sh
sudo docker compose config
sudo docker compose up -d --build
sudo docker compose ps
```

`docker compose config` can print secrets; keep its output private. `.env.example` holds placeholders only. If an entity is missing, verify the integration and exact ID in Developer Tools -> States. For Windmill control through this deployment, note that the currently deployed ha-device-mcp application does not implement that device; an environment variable alone cannot add support.
