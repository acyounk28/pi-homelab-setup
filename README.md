# Pi homelab

1. Set up Home Assistant: run `docker compose up -d homeassistant`, then finish onboarding at `http://<pi-ip>:8123`.
2. Copy `.env.example` to `.env`; add your `HA_LONG_LIVED_ACCESS_TOKEN` and Cloudflare/service credentials.
3. Start the stack: `docker compose up -d --build`.

Sibling repos (`ha-device-mcp`, `flaim`, `citibike-lookup`, `homeassistant-service`) are cloned or fast-forwarded with `scripts/pull-all.sh` (`-n` dry run, `-p ssh|https`, `-d <parent-dir>`; see `--help`).
