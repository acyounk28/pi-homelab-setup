# Connecting ha-device-mcp

[acyounk28/ha-device-mcp](https://github.com/acyounk28/ha-device-mcp) is the MCP bridge (port **8000**, path `/mcp`) that lets LLM clients drive the Pura, Oasis Lighting, Hatch and Windmill devices through Home Assistant. It needs exactly three things from this repository: a reachable **HA URL**, a **long-lived access token**, and (where auto-discovery is ambiguous or absent) **entity IDs**. Nothing device-specific — no Pura/Hatch/Tuya passwords — ever reaches the bridge.

```
LLM client ──(Cloudflare tunnel, MCP bearer token)──▶ ha-mcp:8000 ──(HA LLAT)──▶ homeassistant:8123 ──(vendor creds in HA .storage)──▶ devices
```

## 1. Which variables the bridge reads

| Variable | Required | Where it comes from |
| --- | --- | --- |
| `HA_URL` | yes | `http://host.docker.internal:8123` (default in `docker-compose.yml`; HA is host-networked, ha-mcp reaches it through the Docker host gateway) |
| `HA_LONG_LIVED_ACCESS_TOKEN` | yes | `scripts/ha_token.py create` (below) |
| `MCP_AUTH_TOKEN` | strongly recommended | `openssl rand -hex 32` — bearer token clients send; unrelated to HA |
| `MCP_ALLOWED_HOSTS` | recommended | `ha-mcp,localhost,127.0.0.1,ha-mcp.<your-domain>` |
| `OASIS_LIGHT_ENTITY_ID` | **yes, always** — the bridge's built-in discovery looks for the Oasis Mini sand table (`oasis_mini`, `light.*_led`), not Oasis Lighting | `light.<room or lamp name>` from the `oasis` integration (see [devices/oasis-lighting.md](devices/oasis-lighting.md)) |
| `PURA_NIGHTLIGHT_ENTITY_ID` / `PURA_FRAGRANCE_SELECT_ENTITY_ID` / `PURA_INTENSITY_SELECT_ENTITY_ID` | only if >1 Pura | `light.*_nightlight`, `select.*_fragrance`, `select.*_intensity` |
| `HATCH_LIGHT_ENTITY_ID` / `HATCH_MEDIA_PLAYER_ENTITY_ID` / `HATCH_POWER_SWITCH_ENTITY_ID` | only if >1 Hatch | `light.*_light`, `media_player.*_media_player`, `switch.*_power_switch` |
| `WINDMILL_FAN_ENTITY_ID` | **yes, if you have a Windmill** — no auto-discovery | `fan.*` (see [devices/windmill.md](devices/windmill.md)) |

Auto-discovery rule (from `entities.py`): a role resolves automatically when `integration_entities('<integration>')` returns **exactly one** entity with the right domain and suffix. Zero → `entity_not_found`; two or more → `entity_ambiguous` and you must pin the ID. `scripts/export_entities.py` applies the same rule so its output predicts what the bridge will do.

## 2. Create the HA token (dedicated user, no password stored)

Do this once per bridge. Create a **separate, non-admin HA user** for the bridge so the token's blast radius is limited and it can be revoked without touching your own login.

1. HA → *Settings → People → + Add person* → name `ha-device-mcp`, toggle **Allow login**, set a strong password, **Administrator: off** → Create. (Non-admin users can call services and read states, which is all the bridge needs.)
2. From this repo:

   ```sh
   scripts/ha_token.py create --username ha-device-mcp --name ha-device-mcp \
     --write-env .env
   ```

   You are prompted for that user's password (not echoed, not stored). The script logs in through HA's normal auth flow, opens the WebSocket API, calls `auth/long_lived_access_token`, writes `HA_LONG_LIVED_ACCESS_TOKEN=…` into the target `.env` (mode 600) and prints **nothing but the token name**. Add `--print` only if you need to paste the token somewhere else.

   If the user has MFA enabled the script stops and tells you to use the UI path instead: log in as that user → *Profile → Security → Long-lived access tokens → Create token* → paste into `.env` yourself.

3. Verify without revealing anything: `scripts/ha_token.py verify` → prints the HA version and the user the token belongs to.

Rotate: `scripts/ha_token.py create --replace …` (revokes the same-named token first), then `docker compose up -d ha-mcp`.

## 3. Discover and pin entity IDs

```sh
scripts/export_entities.py                    # report only
scripts/export_entities.py --merge-into .env   # write unique IDs into the bridge .env
```

Sample report:

```
role                 result                                        note
oasis_light          light.living_room                             state=on
pura_nightlight      light.living_room_nightlight                  state=off
pura_fragrance       select.living_room_fragrance                  state=slot_1
pura_intensity       select.living_room_intensity                  state=medium
hatch_light          AMBIGUOUS                                     light.nursery_rest_light, light.bedroom_restore_light
hatch_media_player   AMBIGUOUS                                     media_player.nursery_rest_media_player, media_player.bedroom_restore_media_player
hatch_power_switch   switch.nursery_rest_power_switch              state=on
windmill_fan         -                                             no fan.* entity found; pass --windmill fan.<id> -> docs/devices/windmill.md
```

Resolve ambiguities by passing the exact IDs shown:

```sh
scripts/export_entities.py \
  --hatch-light light.nursery_rest_light \
  --hatch-media-player media_player.nursery_rest_media_player \
  --windmill fan.windmill_ac \
  --merge-into .env
```

`--merge-into` only touches the `*_ENTITY_ID` lines; tokens and other settings are preserved. Re-run any time you rename a device in HA (renaming changes the entity ID and breaks a pinned value — the report flags stale pins).

## 4. Start / restart the bridge

From this repo:

```sh
docker compose up -d --build ha-mcp
docker compose logs -f ha-mcp
```

Standalone (`ha-device-mcp/docker-compose.yml`): copy the same variables into `ha-device-mcp/.env` and `docker compose up -d --build`.

## 5. Verify end to end

```sh
curl -s http://127.0.0.1:8000/healthz          # {"status":"ok"}
curl -s http://127.0.0.1:8000/readyz           # HA reachable with the token
```

Then from an MCP client (or `npx @modelcontextprotocol/inspector http://127.0.0.1:8000/mcp` with header `Authorization: Bearer <MCP_AUTH_TOKEN>`):

1. `ha_status` → `ok: true`, HA version, `pura.start_timer` availability.
2. `discover_entities` → every role listed with a single `entity_id`; anything `ambiguous`/`missing` here is exactly what `export_entities.py` flagged.
3. `get_device_states` → live states; `unavailable` means the device is offline in HA, not a bridge problem.
4. A harmless write: `oasis_light_turn_on` with `brightness_pct: 20` (no `rgb_color`/`effect` — Oasis Lighting only exposes brightness + colour temperature in HA), or `hatch_set_volume` 10.

## 6. Troubleshooting map

| Bridge error | Fix |
| --- | --- |
| `ha_unreachable` | Bridge can't reach HA. `docker compose exec ha-mcp getent hosts host.docker.internal` must resolve; HA must be on host networking; see [networking.md](networking.md). |
| `unauthorized` | Token revoked/expired or belongs to a deleted user → `scripts/ha_token.py verify`, re-create. |
| `entity_ambiguous` | Pin the role's `*_ENTITY_ID` (§3). |
| `entity_not_found` | Integration not set up, device renamed, or pinned ID stale → `export_entities.py`. |
| Windmill tools missing from tool list | `WINDMILL_FAN_ENTITY_ID` unset. |
| Startup `ValidationError … must match fan.` | Pinned a `climate.*` for Windmill; create the template fan in [devices/windmill.md](devices/windmill.md). |
| `421 Misdirected Request` | Requested hostname not in `MCP_ALLOWED_HOSTS` — add your tunnel hostname. |
| HA logs `Login attempt or request with invalid authentication from 172.x.x.x` and later bans it | Bridge sending a bad token; fix the token **before** the ban lands, or delete `config/homeassistant/ip_bans.yaml` and restart HA. |

## Secrets checklist

- `.env` is git-ignored and mode 600; `scripts/*` never print tokens unless `--print`.
- Vendor credentials (Pura, Hatch, Tuya, Windmill dashboard token) live only in `config/homeassistant/.storage/core.config_entries` — also git-ignored. Back that directory up encrypted if you back it up at all.
- The MCP bearer token (`MCP_AUTH_TOKEN`) and the HA token are different secrets with different audiences; never reuse one as the other.
- Publishing `ha-mcp` through Cloudflare exposes only the MCP API, protected by the bearer token; add a Cloudflare Access policy for defence in depth.
