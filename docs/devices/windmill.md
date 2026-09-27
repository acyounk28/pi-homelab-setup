# Windmill AC

Windmill has shipped three different radios/firmwares, so **first identify which path your unit supports**; only then follow that section. ha-device-mcp's Windmill tools drive a **`fan.*` entity** (on/off, percentage, preset, oscillation) and are only registered when `WINDMILL_FAN_ENTITY_ID` is set — there is no auto-discovery for Windmill.

| Path | When | Local? | Entities | Recommended |
| --- | --- | --- | --- | --- |
| **A. HomeKit Controller** (built into HA) | The unit's manual/sticker has an **Apple HomeKit setup code** (8 digits, QR), or the Windmill app offers "Add to Apple Home" | Yes, LAN only | `climate.*` + `fan.*` | **Yes** — no cloud, no custom component |
| **B. Tuya / Smart Life** | Older (≈2022) units that pair with the **Smart Life / Tuya Smart** app | Tuya cloud (or local with tuya-local) | `climate.*`, sometimes `fan.*`/`switch.*` | If A is not available |
| **C. WindmillAC (HACS custom repo)** | Newer units on the Windmill Air dashboard (Blynk) without HomeKit | Cloud | `climate.*` only | Last resort; needs a template fan for ha-device-mcp |

Identify: open the Windmill app → device settings. A HomeKit code or "Works with Apple Home" → **A**. Device was added through Smart Life → **B**. Neither, and you log into `dashboard.windmillair.com` → **C**.

Whichever path you use, the last section (§ Expose to ha-device-mcp) is the same.

---

## Path A — HomeKit Controller (local pairing)

### Prerequisites

- [ ] The unit's **HomeKit setup code** (`XXX-XX-XXX`). It is on a sticker on the unit/manual, or shown in the Windmill app. If you cannot find it, this path is not available for your unit.
- [ ] The AC is on the **same Wi-Fi network / subnet** as the Pi. HomeKit pairing uses mDNS (`_hap._tcp`) multicast and does not cross subnets or VLANs without an mDNS reflector.
- [ ] The AC is **not currently paired to Apple Home** (or any other HomeKit controller). A HomeKit accessory can have only one controller. To move it from Apple Home to HA: Apple Home app → device → *Remove Accessory*. Do **not** reset the AC unless removal fails.
- [ ] HA running with `network_mode: host` (this repo's default). Bridge networking breaks HomeKit discovery **and** pairing.
- [ ] No custom component is needed — HomeKit Controller ships with HA.

### UI steps

1. Power on the AC and wait ~1 min. HA should show a **Discovered: HomeKit Device — Windmill AC** card at *Settings → Devices & services*. If it doesn't appear within 2 min, see troubleshooting.
2. Click **Configure** on that card (or *+ Add integration → HomeKit Device* and choose the Windmill from the list).
3. Enter the **pairing code** exactly as printed (with dashes) → **Submit**. Pairing takes 5–20 s.
4. Assign an **Area** → **Finish**.

### Verify

Device page shows *Climate* and *Fan* entities. Change the target temperature and the fan speed; the unit should respond in under a second (this is local). The Windmill app will lag or not reflect the change — that's expected.

Developer Tools → States, filter `windmill`:

| Entity | Example | Used by ha-device-mcp |
| --- | --- | --- |
| `fan.windmill_ac` | fan speed / on-off | **yes** (`windmill_fan`) |
| `climate.windmill_ac` | mode, target temp | no (HA only) |
| `sensor.windmill_ac_*` | current temp | no |

### Troubleshooting (HomeKit path)

| Symptom | Cause / fix |
| --- | --- |
| No *Discovered* card | HA not on host networking (`docker inspect homeassistant --format '{{.HostConfig.NetworkMode}}'` must print `host`); AC on another subnet/VLAN; AC already paired elsewhere (paired accessories stop advertising as pairable). |
| `Unable to pair, please try again` | Code mistyped, or AC still paired to Apple Home. Remove it there first. |
| `Accessory is already paired` | Same as above; as a last resort factory-reset the AC's Wi-Fi/HomeKit (see Windmill manual) and re-add it in the Windmill app, then pair with HA before touching Apple Home. |
| Pairs but goes `unavailable` after a while | Wi-Fi power saving on the unit or the Pi. Give the AC a DHCP reservation; make sure the Pi's Wi-Fi/Ethernet is stable (`iw dev wlan0 set power_save off` if the Pi is on Wi-Fi). |
| Want it in Apple Home too | Pair with HA (this section), then expose it back to Apple via HA's *HomeKit Bridge* integration. |

---

## Path B — Tuya / Smart Life

### Prerequisites

- [ ] Unit set up in the **Smart Life** or **Tuya Smart** app (email/password account, not social login).
- [ ] For the built-in **Tuya** integration: nothing else — HA logs in with the Smart Life app account and a QR-code scan in the app. (The old IoT-platform developer account is no longer required.)
- [ ] For **local** control via [tuya-local](https://github.com/make-all/tuya-local) (HACS): the device's *local key* — obtained via the Tuya IoT platform or `tinytuya wizard`; more work, but no cloud dependency. Windmill support was added in tuya-local PR #2357.

### UI steps — cloud Tuya (simplest)

1. *Settings → Devices & services → + Add integration → **Tuya***.
2. Enter the **user code** from the Smart Life app (*Me → ⚙ Settings → Account and Security → User Code*) → **Submit**.
3. Scan the QR code shown by HA with the Smart Life app (*Me → scan icon*) → confirm in the app → **Submit** in HA.
4. Assign Areas → **Finish**.

### UI steps — tuya-local

1. Install the component (HACS → search *Tuya Local* → Download → restart HA), or add `make-all/tuya-local tuya_local latest` to `homeassistant/custom_components.txt` and run `scripts/stage_components.sh`.
2. *+ Add integration → Tuya Local* → enter device **IP**, **device ID** and **local key** → pick the *Windmill AC* device type when offered.

### Verify

Developer Tools → States, filter `windmill` / `tuya`. You will usually get `climate.windmill_ac`; some firmware also exposes `fan.*` or `switch.*`. If **no `fan.*` entity** exists, create a template fan — see below.

### Troubleshooting (Tuya path)

| Symptom | Cause / fix |
| --- | --- |
| Tuya QR login loops | Region mismatch; the Smart Life account's region must match the one HA guesses from the user code. Re-create the account in the correct region if needed. |
| Device shows but no controls | Tuya's cloud only exposes "standard instruction set" DPs. Switch to tuya-local, or set the device to standard mode in the Tuya IoT platform. |
| tuya-local: `Unable to connect` | Wrong local key (changes every time the device is re-paired), or Smart Life app kept open (some firmwares allow one local connection). |

---

## Path C — WindmillAC custom integration (cloud)

Unofficial, cloud-only, climate entity only. Use only when A and B are impossible.

### Prerequisites

- [ ] Unit visible at the Windmill Air dashboard; note your **Windmill auth token** from the dashboard (this is the only credential; it is entered in the HA UI and stored in HA's `.storage`, not in `.env`).
- [ ] Stage the component: uncomment the `bzellman/WindmillAC` line in `homeassistant/custom_components.txt`, run `scripts/stage_components.sh --only windmillac`, restart HA.

### UI steps

1. *+ Add integration → **WindmillAC*** → paste the token → **Submit**.
2. Assign an Area → **Finish**.

### Verify

`climate.windmill_ac` (name may vary) appears; change target temp/mode from the climate card. Because this is cloud, expect 2–10 s latency. There is **no `fan.*`** — continue with the template fan below.

---

## Getting a `fan.*` entity when the integration only provides `climate.*`

ha-device-mcp needs a fan entity. Create a **template fan** that wraps the climate entity. Save as `config/homeassistant/packages/windmill_fan.yaml` (the `packages:` include in `configuration.yaml` picks it up), adjust the `climate.windmill_ac` references and the `preset_modes` list, then *Developer Tools → YAML → Check configuration → Restart*:

```yaml
fan:
  - platform: template
    fans:
      windmill_ac:
        friendly_name: "Windmill AC fan"
        unique_id: windmill_ac_template_fan
        value_template: "{{ 'on' if states('climate.windmill_ac') not in ['off', 'unavailable', 'unknown'] else 'off' }}"
        preset_mode_template: "{{ state_attr('climate.windmill_ac', 'fan_mode') }}"
        # Copy the exact list from the climate entity's `fan_modes` attribute
        # (Developer Tools -> States); this is a static list, not a template.
        preset_modes: ["low", "medium", "high", "auto"]
        turn_on:
          action: climate.turn_on
          target: { entity_id: climate.windmill_ac }
        turn_off:
          action: climate.turn_off
          target: { entity_id: climate.windmill_ac }
        set_preset_mode:
          action: climate.set_fan_mode
          target: { entity_id: climate.windmill_ac }
          data: { fan_mode: "{{ preset_mode }}" }
```

This yields `fan.windmill_ac` with on/off and preset (fan-speed) support; `windmill_fan_set_percentage` in ha-device-mcp will report "not supported" for this entity, `set_preset_mode` works.

---

## Expose to ha-device-mcp (all paths)

1. Find the fan entity ID without guessing:

   ```sh
   scripts/export_entities.py
   ```

   The `windmill_fan` row lists every `fan.*` entity from HomeKit Controller, Tuya, tuya-local or the template platform. With exactly one, it is already selected.

2. Pin it (also needed when there are several fans, e.g. ceiling fans on HomeKit):

   ```sh
   scripts/export_entities.py --windmill fan.windmill_ac --merge-into .env
   docker compose up -d ha-mcp
   ```

   This sets `WINDMILL_FAN_ENTITY_ID=fan.windmill_ac` in this repo's `.env`. ha-device-mcp validates that the value starts with `fan.` and refuses to start otherwise.

3. Verify from the bridge: `curl -s http://127.0.0.1:8000/healthz`, then call `windmill_fan_get_status` from your MCP client. The Windmill tools are absent from the tool list until `WINDMILL_FAN_ENTITY_ID` is set and the container restarted.

| ha-device-mcp error | Meaning |
| --- | --- |
| Windmill tools missing | `WINDMILL_FAN_ENTITY_ID` unset → set it and `docker compose up -d ha-mcp`. |
| `entity ID must match fan.<lowercase_name>` at startup | You pinned a `climate.*` entity. Use the template fan above. |
| `entity_not_found` | Entity ID typo or renamed. Re-run `export_entities.py`. |
| `preset mode not supported` | Fan has no such preset; check `preset_modes` in Developer Tools → States. |
