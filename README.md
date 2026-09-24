# Raspberry Pi 5 Home Assistant MCP server for Poke

Deploy acyounk28/ha-device-mcp on a Raspberry Pi 5 using Docker Compose, then optionally make it reachable through a secure HTTPS tunnel. The upstream server listens on port 8000 and serves MCP at `/mcp`; it uses Streamable HTTP, not the older SSE `/sse` transport. Do not use `/sse` as the endpoint.

## Prepare the Pi

Install Raspberry Pi OS 64-bit, enable SSH, update the system, and confirm `uname -m` reports `aarch64`. Prefer a DHCP reservation for a stable LAN address. Install Docker Engine and the Compose plugin using Docker's official Debian instructions: https://docs.docker.com/engine/install/debian/ .

## Get both repositories

The Compose build expects the upstream checkout in a sibling directory named `ha-device-mcp`:

```sh
mkdir -p ~/services && cd ~/services
git clone https://github.com/acyounk28/pi-homelab-setup.git
 git clone https://github.com/acyounk28/ha-device-mcp.git
cd pi-homelab-setup
cp .env.example .env
nano .env
chmod 600 .env
```

Edit `.env` with your actual values. `HA_URL` is the base URL for Home Assistant (for example `http://homeassistant.local:8123` if resolvable from the container, or `http://host.docker.internal:8123` if Home Assistant runs on the Pi host). Set `HA_LONG_LIVED_ACCESS_TOKEN` to a Home Assistant token. Set `MCP_AUTH_TOKEN` to a distinct, strong bearer token; do not reuse the HA token. `.env` is ignored by Git. Never commit or publish credentials.

The upstream Dockerfile starts `ha-device-mcp` itself. Compose builds the local sibling checkout, passes the upstream variable names, and publishes the service only on Pi loopback. The upstream image exposes `/healthz` for its healthcheck. The server settings are `MCP_HOST`, `MCP_PORT`, and `MCP_PATH`; defaults are `0.0.0.0`, `8000`, and `/mcp`. Additional optional entity-ID and logging variables are documented in the upstream `.env.example`.

Start and check the service:

```sh
docker compose config
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 mcp
curl -i http://127.0.0.1:8000/healthz
```

Use `http://127.0.0.1:8000/mcp` as the MCP Streamable HTTP endpoint. The MCP endpoint is not an SSE stream; do not test it using `curl -N` and expect a long-lived `text/event-stream` response. Configure clients to use Streamable HTTP and bearer authentication using `MCP_AUTH_TOKEN`.

## Remote access

Do not forward port 8000 on your router. If remote access is needed, use a maintained HTTPS tunnel such as Cloudflare Tunnel or Tailscale Funnel and point it to `http://127.0.0.1:8000`. Configure the public MCP URL with the `/mcp` path. An HTTPS tunnel encrypts transport but does not replace MCP authentication: retain `MCP_AUTH_TOKEN`, and configure `MCP_ALLOWED_HOSTS` to accept the hostname used by the tunnel. Confirm the client supports MCP Streamable HTTP and bearer authorization before publishing the endpoint. Keep tokens out of URLs and tunnel configuration where possible.

Register the MCP endpoint in Poke using the HTTPS URL ending in `/mcp`, Streamable HTTP transport, and the bearer token through the integration's supported secure credential field. Test with a harmless read-only operation first. Do not disable authentication to work around client incompatibility.

## Troubleshooting and security

- `docker compose logs --tail=200 mcp` shows startup errors; redact secrets before sharing logs.
- `docker compose config` validates the Compose configuration. Avoid sharing its output if it contains environment values.
- Check `http://127.0.0.1:8000/healthz` locally. Check the MCP route at `/mcp`; `/sse` is not the configured transport path.
- The Compose mapping binds only to loopback, so a tunnel on the Pi host can reach it without exposing it to the LAN.
- If Home Assistant runs on the Pi host, `host.docker.internal` is mapped to the host gateway by Compose. Otherwise use an address reachable from the container.
- If a token is exposed, revoke and replace it immediately; deleting a file does not invalidate a leaked credential.

This is an independent deployment guide, not an official Raspberry Pi, Docker, Home Assistant, Cloudflare, Tailscale, or Poke manual. See the upstream project for the authoritative application configuration: https://github.com/acyounk28/ha-device-mcp .
