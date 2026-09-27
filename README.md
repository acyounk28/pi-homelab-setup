# Pi homelab

1. Set up Home Assistant: run `docker compose up -d homeassistant`, then finish onboarding at `http://<pi-ip>:8123`.
2. Copy `.env.example` to `.env`; add your `HA_LONG_LIVED_ACCESS_TOKEN` and Cloudflare/service credentials.
3. Start the stack: `docker compose up -d --build`.

## Start all services in order

Keep `pi-homelab-setup`, `ha-device-mcp`, `citibike-lookup`, and `flaim` as sibling checkouts. After setting up the `.env` file in this repository and completing Home Assistant onboarding, use this executable startup script **instead of step 3 above**. It needs Docker Compose, `curl`, and permission to access the Docker daemon (or run it with `sudo`).

```sh
scripts/start-all.sh
```

If the sibling `homeassistant-service` directory contains `docker-compose.yml`, the script starts that standalone Home Assistant stack first. For a new setup, clone it next to this repository and follow its onboarding instructions **instead of step 1 above** before starting the MCP services:

```sh
git clone https://github.com/acyounk28/homeassistant-service.git ../homeassistant-service
```

Otherwise the script starts this repository's `homeassistant` service. It waits for Home Assistant to respond on port 8123 before starting all other services declared in this repository's Compose file, including the HA bridge, Citi Bike, Flaim, and cloudflared. When using the standalone Home Assistant stack, it skips the duplicate `homeassistant` service in this repository. Check your existing Home Assistant configuration volume before switching between stacks; the two Compose files use different defaults. It does not start the other sibling repositories' standalone Compose stacks, which would duplicate MCP services and port bindings.

Repeated runs reuse unchanged containers. The script waits up to five minutes per startup stage for containers to run (and pass their health checks when configured), and prints `docker compose ps --all` for each started stack. If a stage fails, it exits nonzero and prints the available container status; inspect its logs with `docker compose logs --tail=100` in the affected repository. If Home Assistant already runs under the other Compose project, resolve the competing container and configuration volume before running the script.
