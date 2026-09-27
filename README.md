# Pi homelab

1. Set up Home Assistant: run `docker compose up -d homeassistant`, then finish onboarding at `http://<pi-ip>:8123`.
2. Copy `.env.example` to `.env`; add your `HA_LONG_LIVED_ACCESS_TOKEN` and Cloudflare/service credentials.
3. Start the stack: `docker compose up -d --build`.

## Home Assistant details

- `scripts/install-homeassistant.sh` seeds `config/homeassistant/configuration.yaml` (from `homeassistant/configuration.yaml`) and stages HACS plus the custom components in `homeassistant/custom_components.txt` (Pura, Hatch, Oasis Smart Lights) before starting HA. Idempotent; flags `--no-start`, `--no-components`, `--force-components`.
- Device guides (prerequisites, integration path, exact clicks, verification, ha-device-mcp wiring): [Pura](docs/devices/pura.md) · [Hatch](docs/devices/hatch.md) · [Oasis Lighting](docs/devices/oasis-lighting.md) (heyoasis.com — not the Oasis Mini sand table) · [Windmill AC](docs/devices/windmill.md). Index: [docs/devices/README.md](docs/devices/README.md).
- Token and entity IDs for `ha-mcp`: `scripts/ha_token.py create --write-env .env`, then `scripts/export_entities.py --merge-into .env` and `docker compose up -d ha-mcp`. See [docs/ha-device-mcp.md](docs/ha-device-mcp.md). `OASIS_LIGHT_ENTITY_ID` and `WINDMILL_FAN_ENTITY_ID` must be pinned; Pura/Hatch are auto-discovered.
- HA runs with `network_mode: host` (mDNS/SSDP/HomeKit discovery) and listens on `<pi-ip>:8123`; `ha-mcp` reaches it at `http://host.docker.internal:8123` and waits for HA's healthcheck. Why, and the port map: [docs/networking.md](docs/networking.md). More beginner detail: `ENV_GUIDE.md`.
