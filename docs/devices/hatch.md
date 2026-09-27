# Hatch Rest / Rest+ / Rest 2nd gen / Restore 2 / Restore 3

Integration: **Hatch Rest** (`custom_components/ha_hatch`, [dahlb/ha_hatch](https://github.com/dahlb/ha_hatch)). Cloud-based via your Hatch account (AWS IoT); the device does not need to be on the Pi's LAN.

ha-device-mcp tools backed by this integration: light on/off/brightness/colour (`hatch_light`), sound machine play/stop/volume/sound selection (`hatch_media_player`), power (`hatch_power_switch`), favourites/scenes.

## 1. Prerequisites

- [ ] Device set up and online in the **Hatch Sleep** app, with any favourites you want to trigger already created there.
- [ ] Hatch account **email + password** (Hatch does not offer social login; if you use "sign in with Apple" you cannot use this integration — create a password account and re-add the device).
- [ ] HA onboarded.
- [ ] `custom_components/ha_hatch` present:

  ```sh
  ls config/homeassistant/custom_components/ha_hatch/manifest.json
  ```

  If missing: `scripts/stage_components.sh --only ha_hatch && docker compose restart homeassistant`.

Bluetooth is **not** used; ignore any `bluetooth` discovery cards for Hatch.

## 2. Integration path

Cloud (Hatch account). Supported/tested models per upstream: Rest Mini, Rest+, Rest 2nd gen, Rest+ 2nd gen, Restore 2, Restore 3. Entities differ by model (see §4).

## 3. Home Assistant UI steps

1. **Settings → Devices & services → + Add integration**.
2. Search **Hatch Rest** (integration domain `ha_hatch`) → select.
3. Enter Hatch **email** and **password** → **Submit**. (The form is untranslated; fields are `username`, `password`.)
4. Each Hatch device on the account becomes a device; assign **Areas** → **Finish**.
5. Optional but recommended for a quieter log: device page → ⋮ → *Enable debug logging* only while troubleshooting.

## 4. Verify

**UI:** device page → toggle the *Light*, pick a colour; on the media player card press play, change *Sound mode* (built-in sounds on Rest/Rest+; favourites on Rest 2nd gen / Restore) and volume.

**Entities:** Developer Tools → States, filter `hatch`. Expected (`<name>` = device name from the Hatch app):

| Entity | Example | Models | Used by ha-device-mcp |
| --- | --- | --- | --- |
| `light.<name>_light` | `light.nursery_rest_light` | all | yes (`hatch_light`) |
| `media_player.<name>_media_player` | `media_player.nursery_rest_media_player` | all | yes (`hatch_media_player`) |
| `switch.<name>_power_switch` | `switch.nursery_rest_power_switch` | Rest+ / Rest 2nd gen / Restore | yes (`hatch_power_switch`, optional) |
| `scene.<name>_<favourite>` | | Rest 2nd gen, Rest+ 2nd gen, Restore 3 | HA only (favourites) |
| `switch.<name>_alarm_*`, `time.<name>_alarm_*` | | Restore family | no |
| `switch.<name>_toddler_lock`, `light.<name>_clock` | | Rest+ 2nd gen / Restore 3 | no |
| `sensor.<name>_battery`, `binary_sensor.<name>_charging` | | Rest+ | no |

Shell check:

```sh
scripts/export_entities.py
```

`hatch_light` and `hatch_media_player` must each resolve to one entity. `hatch_power_switch` may legitimately be `-` on a Rest Mini (no power switch); ha-device-mcp treats that role as optional.

## 5. Expose to ha-device-mcp

Auto-discovery: `integration_entities('ha_hatch')` filtered by domain and suffix (`_light`, `_media_player`, `_power_switch`). **One Hatch → nothing to configure.**

Two or more Hatch devices (e.g. two kids' rooms):

```sh
scripts/export_entities.py \
  --hatch-light        light.nursery_rest_light \
  --hatch-media-player media_player.nursery_rest_media_player \
  --hatch-power-switch switch.nursery_rest_power_switch \
  --merge-into .env
docker compose up -d ha-mcp
```

Sets `HATCH_LIGHT_ENTITY_ID`, `HATCH_MEDIA_PLAYER_ENTITY_ID`, `HATCH_POWER_SWITCH_ENTITY_ID`. Omit `--hatch-power-switch` on models without one.

## 6. Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| "Hatch Rest" not in *Add integration* | Component missing or failed to import. First start after staging can take a minute while HA installs the component's Python requirements (`awscrt`, `hatch_rest_api`) — watch `docker compose logs -f homeassistant`. On arm64 this needs a wheel; if the log shows a compile failure, `docker compose pull` to a newer HA image. |
| `Invalid authentication` | Wrong credentials or Apple-ID login. Use an email/password Hatch account. |
| Devices `unavailable` shortly after setup | Hatch cloud/MQTT reconnect; usually self-heals in under a minute. Persistent → device page → ⋮ → *Reload*. |
| New favourite not listed as a scene | Reload the integration (or restart HA); favourites are read at startup. |
| Alarm changes from the app not visible | Refreshed every 10 min; reload to force. Creating/deleting alarms is not supported by the integration. |
| ha-device-mcp `entity_ambiguous` for `hatch_*` | More than one Hatch; pin as in §5. |
| ha-device-mcp `entity_not_configured` for `hatch_power_switch` | Model has no power switch (Rest Mini). Expected; the bridge's other Hatch tools still work. |
| Renamed entity breaks discovery | Discovery relies on the `_light` / `_media_player` / `_power_switch` suffixes. Rename back or pin explicitly. |
