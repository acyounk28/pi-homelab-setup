# Pura 3 / Pura 4 smart diffuser

Integration: **Pura** (`custom_components/pura`, [natekspencer/ha-pura](https://github.com/natekspencer/ha-pura)). Cloud-based: HA logs into your Pura account and talks to Pura's API; the diffuser itself does not need to be reachable from the Pi.

ha-device-mcp tools backed by this integration: nightlight on/off/brightness/colour, fragrance slot selection, intensity.

## 1. Prerequisites

- [ ] Diffuser set up and working in the **Pura app** (Wi-Fi joined, fragrances installed, device named).
- [ ] A Pura account **with a password**. If you signed up with Apple/Google/Facebook you must add a password first (Pura app → Settings → sign out → *Sign into your account* → *Forgot your password?* → set one). Social login does not work with the integration.
- [ ] Home Assistant running and onboarded (`scripts/install-homeassistant.sh`, then `http://<pi-ip>:8123`).
- [ ] `custom_components/pura` present. It is staged by `scripts/install-homeassistant.sh`; confirm with:

  ```sh
  ls config/homeassistant/custom_components/pura/manifest.json
  ```

  If missing: `scripts/stage_components.sh --only pura && docker compose restart homeassistant`.

Nothing else: no HACS login, no developer token, no port forwarding.

## 2. Integration path

Cloud (Pura account credentials). Local control is not available for Pura hardware. The credentials are stored by HA in `config/homeassistant/.storage/core.config_entries` — keep that directory private and never commit it (it is git-ignored).

## 3. Home Assistant UI steps

1. **Settings → Devices & services → + Add integration** (bottom right).
2. Search **Pura**, select it. If it is not listed, the component is not loaded: restart HA (`docker compose restart homeassistant`) and check *Settings → System → Logs* for `custom_components.pura`.
3. Enter your Pura **email** and **password** → **Submit**.
4. HA lists every diffuser on the account. Assign each one an **Area** (e.g. `Bedroom`) → **Finish**.

Result: one device per diffuser, named after the device name in the Pura app.

## 4. Verify

**UI:** Settings → Devices & services → Pura → *1 device* → open it. Toggle the *Nightlight* light and change the *Fragrance* and *Intensity* selects; the diffuser should react within a few seconds and the Pura app should show the same state.

**Entities:** Developer Tools → States, filter on `pura`. Expected shape (names come from the device name in the Pura app, lower-cased, spaces → `_`):

| Entity | Example | Used by ha-device-mcp |
| --- | --- | --- |
| `light.<name>_nightlight` | `light.bedroom_pura_nightlight` | yes (`pura_nightlight`) |
| `select.<name>_fragrance` | `select.bedroom_pura_fragrance` | yes (`pura_fragrance`) |
| `select.<name>_intensity` | `select.bedroom_pura_intensity` | yes (`pura_intensity`) |
| `sensor.<name>_slot_1_*`, `sensor.<name>_slot_2_*` | fragrance name / remaining | no |
| `switch.<name>_away_mode`, `switch.<name>_ambient_mode` | | no |

**From the shell** (uses the token in `.env`):

```sh
scripts/export_entities.py
```

The `pura_*` rows should each show exactly one entity with a real state (`on`/`off` or a fragrance name), not `-` or `AMBIGUOUS`.

## 5. Expose to ha-device-mcp

ha-device-mcp auto-discovers Pura entities with `integration_entities('pura')` and picks the one `light.*` ending in `_nightlight`, the `select.*` ending in `_fragrance` and the `select.*` ending in `_intensity`. **With one diffuser, nothing to configure.**

With two or more diffusers, discovery is ambiguous and the bridge refuses to guess (`entity_ambiguous`). Pin the one you want:

```sh
scripts/export_entities.py \
  --pura-nightlight light.bedroom_pura_nightlight \
  --pura-fragrance  select.bedroom_pura_fragrance \
  --pura-intensity  select.bedroom_pura_intensity \
  --merge-into .env
docker compose up -d ha-mcp
```

This writes `PURA_NIGHTLIGHT_ENTITY_ID`, `PURA_FRAGRANCE_SELECT_ENTITY_ID`, `PURA_INTENSITY_SELECT_ENTITY_ID` into this repo's `.env` (and nothing else changes). Confirm from the bridge:

```sh
curl -s http://127.0.0.1:8000/healthz
```

then call the `discover_entities` / Pura status tool from your MCP client.

## 6. Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| "Pura" not in *Add integration* list | Component not loaded. `ls config/homeassistant/custom_components/pura`; restart HA; check logs for import errors (usually a HA version too old for the component — `docker compose pull && docker compose up -d`). |
| `Invalid authentication` on login | Social-login account without a password (see prerequisites), or 2FA on the Pura account. Set a password; the integration does not support MFA. |
| Login works, no devices | Device not finished in the Pura app, or belongs to another account (household sharing). Log in with the owning account. |
| Selects show `unavailable` | Diffuser offline (Wi-Fi) — check the Pura app. Entities recover automatically. |
| Fragrance select is empty | No fragrance vials detected; insert them and reload the integration (device page → ⋮ → *Reload*). |
| Changes take 10–30 s | Normal; the integration polls Pura's cloud. Pura's own app has the same latency. |
| ha-device-mcp `entity_not_configured` for `pura_*` | Integration not set up, or the entity name does not end in `_nightlight` / `_fragrance` / `_intensity` (renamed in HA). Either rename it back (Settings → Entities → entity → ⚙ → Entity ID) or pin it with `export_entities.py --pura-... --merge-into`. |
| ha-device-mcp `entity_ambiguous` | Two diffusers. Pin as in §5. |
| Pura credential change | Settings → Devices & services → Pura → ⋮ → *Reconfigure* (or delete and re-add). Nothing to change in `.env`. |
