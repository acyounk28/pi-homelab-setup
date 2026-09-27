# Device guides

Every guide follows the same structure so you never have to guess:

1. **Prerequisites** – what must exist before you start (account, app, network, component).
2. **Integration path** – which integration is used and why (cloud vs. local, HACS vs. built-in).
3. **Exact Home Assistant UI steps** – click-by-click.
4. **Verify** – how to prove the device and its entities work from HA.
5. **Expose to ha-device-mcp** – which entities the bridge needs, how they are auto-discovered, and how to pin them with `scripts/export_entities.py` when discovery is ambiguous.
6. **Troubleshooting** – the failures people actually hit.

| Device | Guide | Integration | Type | HA entities used by ha-device-mcp |
| --- | --- | --- | --- | --- |
| Pura 3 / Pura 4 | [pura.md](pura.md) | `pura` (natekspencer/ha-pura, HACS default) | Cloud (Pura account) | `light.*_nightlight`, `select.*_fragrance`, `select.*_intensity` |
| Oasis Lighting (Ambient lamps / Bulbs, Mixtiles) | [oasis-lighting.md](oasis-lighting.md) | `oasis` (longweekendprojects/oasis-lights, community, **not** HACS default) | Cloud only (Oasis account) | `light.<name>` — must be pinned as `OASIS_LIGHT_ENTITY_ID` |
| Hatch Rest / Rest+ / Restore | [hatch.md](hatch.md) | `ha_hatch` (dahlb/ha_hatch, HACS default) | Cloud (Hatch account) | `light.*_light`, `media_player.*_media_player`, `switch.*_power_switch` |
| Windmill AC | [windmill.md](windmill.md) | HomeKit Controller (local) **or** Tuya / tuya-local **or** WindmillAC (cloud) | Local or cloud | `fan.*` (must be pinned; no auto-discovery) |

Common to all guides:

- The three custom components are **already on disk** after `scripts/install-homeassistant.sh` (see `homeassistant/custom_components.txt`). You only need HACS itself if you want update notifications for them (Oasis Smart Lights needs to be added to HACS as a custom repository for that).
- "Oasis" here means **Oasis Lighting** by Mixtiles (heyoasis.com), not the Oasis Mini kinetic sand table; the latter's `oasis_mini` integration is unrelated and is no longer staged.
- Credentials for cloud integrations (Pura, Hatch, Oasis, WindmillAC) are entered **once in the HA UI** and stored by HA in `config/homeassistant/.storage/` (plain JSON, so keep that directory and its backups private). They never go in `.env`, this repo, or ha-device-mcp. ha-device-mcp only ever holds one secret: the HA long-lived access token.
- Entity IDs are read with `scripts/export_entities.py`; do not type them from memory.
- After adding or renaming devices, re-run `scripts/export_entities.py --merge-into .env` and `docker compose up -d ha-mcp`.
