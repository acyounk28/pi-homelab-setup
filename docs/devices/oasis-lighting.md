# Oasis Lighting (Oasis Ambient lamps / Oasis Bulbs)

**Product:** *Oasis* smart lighting by **Mixtiles Ltd** — [heyoasis.com](https://heyoasis.com). Two hardware lines, both driven by the **Oasis Lighting** phone app (store listing *Oasis Lighting* / *Oasis Lights*, Android package `com.mixtiles.oasis`, publisher Mixtiles): the **Oasis Ambient** accent lamp (USB-C powered) and the **Oasis Bulb** (E26/GLS replacement). Warm↔cool white ("tones"/"warmth" presets, plus a colourful mode on newer firmware) with an automatic day→evening light cycle.

> **Not to be confused with** the **Oasis Mini** kinetic sand table (Grounded / Kinetic Oasis, app "Oasis", HA integration *Oasis Control* `oasis_mini`). That product shares only the name. Earlier revisions of this repository staged `natekspencer/ha-oasis-control` and documented the sand table; that was the wrong device and has been removed.

Integration used here: **Oasis Smart Lights** (`custom_components/oasis`, [longweekendprojects/oasis-lights](https://github.com/longweekendprojects/oasis-lights)) — a **community, cloud-polling** integration. Read [§2](#2-integration-path) before relying on it.

ha-device-mcp tools backed by this integration: `oasis_light_turn_on` / `oasis_light_turn_off` (`oasis_light` role) — **on/off, brightness, transition only**. `rgb_color`, `hs_color` and `effect` are not supported by the HA entity and will be ignored or rejected.

## 1. Prerequisites

- [ ] Lights set up in the **Oasis app**, assigned to rooms, and controllable from the app.
- [ ] Oasis account credentials. **Email + password** is the simplest path. Accounts created with **Sign in with Apple / Google** have no password; the integration has a paste-the-redirect-URL flow for those (see §3, step 3b) — it is fiddlier and less proven.
- [ ] The Pi has **outbound internet** (this is a cloud integration; there is nothing to reach on the LAN).
- [ ] `custom_components/oasis` present:

  ```sh
  ls config/homeassistant/custom_components/oasis/manifest.json
  ```

  If missing: `scripts/stage_components.sh --only oasis && docker compose restart homeassistant`.

Host networking, mDNS and Bluetooth on the Pi are **not** needed for this device.

## 2. Integration path

### What the hardware actually speaks (evidence)

| Fact | Source |
| --- | --- |
| Vendor-supported integrations are **Amazon Alexa** and **Google Home** only (Alexa skill "Oasis" by Mixtiles; vendor reply on Trustpilot, Jan 2026: "At the moment, the lights support Amazon Alexa and Google Home"). The privacy policy mentions HomeKit as a *possible* voice assistant, but no HomeKit setup exists in the app or docs. | [Alexa skill](https://www.amazon.com/Mixtiles-Oasis/dp/B0F6FDKQVS), [Trustpilot](https://www.trustpilot.com/review/heyoasis.com), [privacy policy](https://heyoasis.com/en/privacy) |
| **No Home Assistant integration** exists from the vendor, in HA core, or in the HACS default list. | [HA integrations index](https://www.home-assistant.io/integrations/) has no Oasis lighting entry; GitHub search |
| Oasis Ambient: **ESP32-C6-Mini** SoC, Wi-Fi, "private, proprietary protocol — no Matter, Thread, Zigbee or HomeKit". | [iFixit teardown](https://www.ifixit.com/Teardown/Oasis+Ambient+Teardown/221776) (June 2026) |
| Oasis Bulb: ESP32-C6, firmware stack **ESP RainMaker** (Espressif's AWS-hosted cloud). Phone→light control is **BLE Mesh**; the bulb keeps an outbound connection to the RainMaker cloud, which the app uses as its remote path. **No open TCP/UDP ports, no mDNS** → no LAN control surface. The firmware is Espressif RainMaker, **not Tuya**: the lights do not appear in Tuya / Smart Life, so the HA Tuya, LocalTuya and tuya-local integrations cannot see them; WLED, HomeKit Controller and Matter are equally off the table. | [longweekendprojects/oasis-lights README](https://github.com/longweekendprojects/oasis-lights) (port sweep + APK analysis) |
| Ambient 2 also uses the RainMaker model and BLE Mesh (independent reverse-engineering, macOS BLE bridge). | [malpern/oasis-lights-mac](https://github.com/malpern/oasis-lights-mac) |

Consequences: the **only** network path from the Pi to the lights is the **Oasis (RainMaker) cloud API** using your Oasis account. Local alternatives are (a) a Bluetooth-Mesh bridge that already holds the mesh keys (the macOS project above — not a Pi/HA-native path) or (b) reflashing the ESP32-C6 with ESPHome (destroys Oasis-app support, needs disassembly + UART).

### Chosen path: `longweekendprojects/oasis-lights` (cloud)

- Domain `oasis`, `iot_class: cloud_polling`, config-flow UI, releases tagged on GitHub (`0.3.1` at the time of writing). `scripts/stage_components.sh` downloads it from the release tag.
- Creates one `light.*` per Oasis light (brightness + colour temperature, 2000–4000 K) and a `select.*_warmth` with the app's six presets (Bright, Neutral, Soft, Glow, Amber, Candle).
- **Caveats you accept**: one-maintainer community project (created Aug 2026, not vendor-affiliated, not in HACS default so HACS will not show updates for it — add it as a *custom repository* in HACS if you want that); depends on Mixtiles' cloud staying up and unchanged; reported cloud state lags **15–25 s** behind writes; author tested with **Oasis Ambient GLS bulbs** — Ambient lamps are expected to appear too (same RainMaker account/node model) but that is *not* verified by this repository.
- Credentials are entered once in the HA UI and stored by HA in `config/homeassistant/.storage/` (plain JSON — keep private). Nothing Oasis-related goes in `.env`.

If this integration stops working there is currently **no fallback** other than the vendor app / Alexa / Google Home.

## 3. Home Assistant UI steps

1. **Settings → Devices & services → + Add integration**.
2. Search **Oasis Smart Lights** → select. (If it is not listed: component not on disk or failed to import — see §6.)
3. A menu asks *How do you sign in to the Oasis app?*
   - **3a. Email address and password** → enter the same credentials as the app → **Submit**.
   - **3b. Sign in with Apple or Google** → open the shown `applogin.heyoasis.com` link in a browser, sign in, and when the browser ends on an "invalid address" error starting with `rainmaker://`, copy that **whole URL** and paste it into the form → **Submit**.
   - *Paste an existing session token* and *Import from the Oasis bridge* are for the author's macOS bridge tooling; ignore them on the Pi.
4. Assign each discovered light to an **Area** → **Finish**.

## 4. Verify

**UI:** open one of the Oasis devices. Toggle the light, move brightness, change the *Warmth* select; the lamp should react within a couple of seconds, and HA's displayed state catches up after ~20 s (cloud polling).

**Entities:** Developer Tools → States, filter the light's name. Expected per light:

| Entity | Example | Used by ha-device-mcp |
| --- | --- | --- |
| `light.<light name>` | `light.living_room`, `light.bedroom_lamp` | yes (`oasis_light`) — **must be pinned**, see §5 |
| `select.<light name>_warmth` | `select.living_room_warmth` | no (HA only) |

Entity IDs follow the light/room names you set in the Oasis app (spaces → `_`, lower-case). There is **no** `_led` suffix and no `media_player`.

Shell check:

```sh
scripts/export_entities.py
```

`oasis_light` should list the `light.*` entities from the `oasis` integration; with exactly one light it resolves automatically, with several it is reported `AMBIGUOUS`.

## 5. Expose to ha-device-mcp

ha-device-mcp's **built-in** auto-discovery for `oasis_light` still targets the sand table (`integration_entities('oasis_mini')`, suffix `_led`) and will find nothing here → `entity_not_found`. **Always pin the entity**:

```sh
# one light: let the script pick it
scripts/export_entities.py --merge-into .env
# several lights: choose the one the bridge should control
scripts/export_entities.py --oasis-light light.living_room --merge-into .env
docker compose up -d ha-mcp
```

This sets `OASIS_LIGHT_ENTITY_ID` in this repo's `.env`; the bridge uses a configured ID verbatim and skips discovery. The bridge controls **one** light entity; to drive a whole room, create an HA *light group* (Settings → Devices & services → Helpers → Group → Light group) of the room's Oasis lights and pin the group's `light.*` ID instead.

Tool behaviour with this integration: `brightness_pct` and `transition` work; `rgb_color`/`hs_color` are dropped by HA because the entity only supports `color_temp`; `effect` fails validation (no `effect_list`). Colour temperature is not settable through the bridge today.

## 6. Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| *Oasis Smart Lights* not in *Add integration* list | Component missing/failed to import. `ls config/homeassistant/custom_components/oasis`, restart HA, read *Settings → System → Logs* (logger is set to `info` for `custom_components.oasis`). |
| `Oasis rejected those credentials` | Wrong email/password, or the account is Apple/Google-based (no password) → use step 3b. |
| `Oasis refused the sign-in` (Apple/Google flow) | Start the link again from the HA form; the author notes repeated sign-ins can produce sessions the Oasis API refuses. |
| `Could not reach the Oasis service` | Pi has no outbound HTTPS, or the RainMaker endpoint changed → check `curl -sI https://heyoasis.com`, then the integration's issues page. |
| Light `unavailable` | The light is offline in the Oasis cloud (unplugged / lost Wi-Fi). Check the app; nothing to do in HA. |
| Commands work but HA state looks stale | Expected: cloud state lags 15–25 s. |
| ha-device-mcp `entity_not_found` for `oasis_light` | `OASIS_LIGHT_ENTITY_ID` not set — bridge discovery targets `oasis_mini`. See §5. |
| ha-device-mcp `validation_error` on `effect` / colour ignored | Not supported by Oasis Lighting; use brightness only. |
| Want update notifications | HACS → ⋮ → *Custom repositories* → add `https://github.com/longweekendprojects/oasis-lights` (type *Integration*). |

## 7. Still unknown / how to firm this up

- Whether the **Ambient** lamp (vs. the bulb) appears identically through the cloud integration — confirm on your own lights and note the `model`/`sw_version` shown on the HA device page.
- Whether Mixtiles ships **Matter** or HomeKit later (their privacy policy leaves the door open). If the app ever offers a *Matter pairing code*, HA's built-in **Matter** integration would become the preferred, local path and this custom component could be dropped.
- If you want to report the exact hardware you have: model string on the lamp/bulb, Oasis app version, and the *About* / firmware line on the HA device page are the three data points that identify it.
