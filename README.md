# Raspberry Pi 5 Home Assistant MCP server for Poke

Deploy `acyounk28/ha-device-mcp` on a Raspberry Pi 5 with Docker Compose and optionally expose it securely through Cloudflare Tunnel. The server provides MCP Streamable HTTP at `/mcp` (not legacy SSE `/sse`).

## Prepare and start

Install Raspberry Pi OS 64-bit and Docker Engine plus Compose plugin using Docker's official instructions: https://docs.docker.com/engine/install/debian/ . Confirm `uname -m` reports `aarch64`.

Clone both repositories as siblings:

```sh
mkdir -p ~/services && cd ~/services
git clone https://github.com/acyounk28/pi-homelab-setup.git
git clone https://github.com/acyounk28/ha-device-mcp.git
cd pi-homelab-setup
cp .env.example .env
nano .env
chmod 600 .env
```

Set `HA_URL`, `HA_LONG_LIVED_ACCESS_TOKEN`, a separate strong `MCP_AUTH_TOKEN`, and a Cloudflare `TUNNEL_TOKEN` if enabling the tunnel. `.env` is ignored by Git; never commit credentials. Add the public tunnel hostname to `MCP_ALLOWED_HOSTS`.

The Compose file builds the sibling app, binds its port only to Pi loopback, and starts Cloudflare Tunnel with token-based remotely managed configuration. Create and configure the named tunnel as described in `cloudflared/README.md`; its Cloudflare public hostname origin should be `http://ha-mcp:8000`. Keep bearer authentication enabled.

```sh
docker compose config
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 ha-mcp cloudflared
curl -i http://127.0.0.1:8000/healthz
```

Configure clients for Streamable HTTP at `https://YOUR_HOSTNAME/mcp` and bearer authorization using `MCP_AUTH_TOKEN`. Do not forward port 8000 from your router. Tunnel encryption does not replace authentication.

## Cloudflare tunnel details

`cloudflared/config.yml` is an alternative local-managed tunnel template with ingress to `http://ha-mcp:8000` and a final 404 catch-all. It is not consumed by the token-mode Compose service. Follow `cloudflared/README.md` for Cloudflare login, tunnel creation, token retrieval, hostname setup, and the alternative local credentials mode. Do not commit tunnel tokens or credential JSON files.

## Troubleshooting

Use `docker compose logs --tail=200 ha-mcp cloudflared` (redact secrets before sharing), and verify the local health endpoint. `MCP_PATH` defaults to `/mcp`; this service uses Streamable HTTP, not `/sse`. If Home Assistant is hosted on the Pi, `host.docker.internal` resolves to the host gateway; otherwise set `HA_URL` to a reachable address. Revoke and replace any exposed token.

References: application configuration at https://github.com/acyounk28/ha-device-mcp and Docker installation at https://docs.docker.com/engine/install/debian/.
