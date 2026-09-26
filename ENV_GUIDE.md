# Environment setup guide (beginner-friendly)

This guide gets Home Assistant running in this Compose stack, then explains its connection to the MCP services and devices. Home Assistant is the bridge: when it controls a device, you do not need a separate device hardware token for this setup.

## 1. Prepare configuration and start Home Assistant

Clone `pi-homelab-setup`, `ha-device-mcp`, and `flaim` as sibling directories as described in README.md. From `pi-homelab-setup`, create the private environment file:

```sh
cp .env.example .env
nano .env
chmod 600 .env
```

Keep `HA_URL=http://homeassistant:8123` when using the included Compose bridge network. `homeassistant` is the Compose service name, so containers on that network resolve it automatically. `TZ` is the timezone used by the Home Assistant container; set it to the correct IANA timezone for your location if different. Do not put secrets in `.env.example`, and never commit/share `.env`.

Start the Home Assistant service first (this avoids needing the other repositories or credentials during initial onboarding):

```sh
sudo docker compose up -d homeassistant
sudo docker compose logs -f homeassistant
```

From a browser on the same LAN, visit `http://<pi-ip>:8123` (replace `<pi-ip>` with the Pi's actual LAN address). Wait for first startup, then create the Home Assistant owner/admin account and finish location/setup prompts. The saved config persists in `./ha-config`. Home Assistant is also reachable on the Docker host at `http://localhost:8123`.

If discovery of devices using mDNS, SSDP, or HomeKit does not work over bridge networking, Home Assistant may need Linux host networking. See README.md for the host-network alternative and its HA_URL change. Do not run both modes at once.

## 2. Create the Home Assistant access token

In the Home Assistant UI, click your profile/name, open Security, find Long-Lived Access Tokens, choose Create Token, give it a recognizable name, and copy it immediately. Put the complete token into `HA_LONG_LIVED_ACCESS_TOKEN` in `.env`. Keep `HA_URL=http://homeassistant:8123` for the included bridge configuration. This one Home Assistant token lets `ha-device-mcp` communicate with Home Assistant and its supported devices; you do not need separate Windmill, Pura, Oasis, or Hatch hardware tokens when HA controls those devices.

`HA_TIMEOUT_SECONDS` and `HA_VERIFY_SSL` can normally stay at their example defaults. `MCP_HOST`, `MCP_PORT`, and `MCP_PATH` are service settings; retain defaults. Replace `MCP_AUTH_TOKEN` with a strong unique secret (generate one on the host using `openssl rand -hex 32`). Add the public HA MCP hostname to comma-separated `MCP_ALLOWED_HOSTS` while retaining localhost entries.

## 3. Add device integrations and find entity IDs

In Home Assistant, open Settings -> Devices & services -> Add integration and add a compatible integration for each device. Which integration works depends on model, firmware, network, and desired controls. Device setup belongs in Home Assistant; do not look for per-device tokens to put in this deployment unless a particular HA integration itself asks you to authenticate with its provider.

- Windmill fan: try a compatible HomeKit Device/Controller, Local Tuya/Tuya integration, or another supported method. A smart plug can provide on/off power control, but usually not fan speed or mode. Once added, the entity may look like `fan.windmill_ac` or `fan.bedroom_fan`; use the actual entity ID shown in HA. The current `ha-device-mcp` application does not implement Windmill fan controls and does not read `WINDMILL_FAN_ENTITY_ID` or `WINDMILL_ENTITY_ID`; a visible HA entity alone will not make it controllable through that MCP server.
- Pura: add the compatible Pura integration/custom component (for example `ha-pura`) and complete its setup. It may provide `light.*` and `select.*` entities. Pura fragrance controls are not a fan entity.
- Oasis: add a supported Oasis Mini integration/custom component (such as `ha-oasis-control`); it may provide a `light.*` entity.
- Hatch: add a compatible Hatch integration/custom component (such as `ha_hatch`); depending on model, entities can include `light.*`, `media_player.*`, optional `switch.*`, and favorite `scene.*` entities.
- Other supported options can include native HA integrations, HomeKit, SmartThings, Tuya, or custom components, but availability varies by model. HA visibility does not automatically mean the MCP application supports control of that entity.

To obtain IDs, open Developer Tools -> States, search for the device, select its entity, and copy the complete ID including domain, such as `fan.`, `light.`, `select.`, `media_player.`, or `switch.`. Do not guess from the friendly name. The current `ha-device-mcp` supports explicit `OASIS_LIGHT_ENTITY_ID`, `PURA_NIGHTLIGHT_ENTITY_ID`, `PURA_FRAGRANCE_SELECT_ENTITY_ID`, `PURA_INTENSITY_SELECT_ENTITY_ID`, `HATCH_LIGHT_ENTITY_ID`, `HATCH_MEDIA_PLAYER_ENTITY_ID`, and `HATCH_POWER_SWITCH_ENTITY_ID`; omitted supported roles may be auto-discovered. It currently has no Windmill entity setting.

## 4. Start the rest of the homelab

After Home Assistant onboarding, integrations, and token setup, set the Flaim values in `.env` (ESPN cookies, league IDs, and a separate strong `FLAIM_MCP_AUTH_TOKEN`). Set `TUNNEL_TOKEN` if using Cloudflare Tunnel. Then, with all three sibling repositories present, validate and start the stack:

```sh
sudo docker compose config
sudo docker compose up -d --build
sudo docker compose ps
```

`docker compose config` can display secrets; keep its output private. ESPN `ESPN_S2` and `SWID` are sensitive browser cookies from the `espn.com` cookie store. ESPN league IDs come after `leagueId=` in the league URL; Sleeper league IDs are the path segment after `/leagues/`. Keep them private as appropriate.

## 5. Cloudflare and security

For the included bridge network, Cloudflare origins are `http://ha-mcp:8000` and `http://flaim-mcp:8001`; do not expose port 8123 publicly. Keep the unique MCP tokens and Home Assistant token private. The host can reach HA at `http://localhost:8123`, while other LAN clients use `http://<pi-ip>:8123`.

If switching Home Assistant to host networking for discovery, remove its `ports` and `networks` entries and set `network_mode: host`; HA then listens on the host's network. Set `HA_URL=http://host.docker.internal:8123` for ha-mcp and add `extra_hosts: ["host.docker.internal:host-gateway"]` to ha-mcp in Compose. Host mode is Linux-specific and bypasses Compose network isolation for HA. Choose one network mode deliberately; the checked-in configuration uses bridge mode and `http://homeassistant:8123`.
