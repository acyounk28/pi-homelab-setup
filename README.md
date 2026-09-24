# Raspberry Pi 5 Home Assistant MCP server for Poke

Deploy `acyounk28/ha-device-mcp` on a Raspberry Pi 5 with Docker Compose, then expose it securely through a Cloudflare Zero Trust Tunnel. The server uses MCP Streamable HTTP at `/mcp` (not legacy SSE `/sse`).

## Current status and tomorrow-night checklist

Based on the current repository files and the requester's update:

Already done / prepared:

- The `acyounk28/pi-homelab-setup` deployment repository exists.
- The `acyounk28/ha-device-mcp` application repository exists; its Dockerfile has a multi-stage build and runs the runtime as non-root UID 10001.
- This repository's `docker-compose.yml` defines `ha-mcp` and `cloudflared`, a healthcheck, and binds the app only to Pi loopback (`127.0.0.1:8000`). It expects the application repository cloned beside this repository.
- `.env.example` documents the Home Assistant, MCP bearer-auth, allowed-host, and tunnel settings; `.gitignore` excludes `.env` and credential files.
- Cloudflare nameservers have reportedly been updated for the domain. That is user-reported; this repository check did not independently verify DNS delegation or Cloudflare activation. Once the domain is active in Cloudflare, a custom hostname such as `mcp.yourdomain.com` or `ha-mcp.yourdomain.com` is the streamlined primary route.

Still to do tomorrow night:

1. Flash Raspberry Pi OS 64-bit to the SD card with Raspberry Pi Imager, boot the Pi 5, and connect it to the network.
2. SSH into the Pi, install Docker Engine and the Compose plugin, and clone both repositories as siblings using the commands below.
3. Create a remotely-managed Cloudflare Tunnel in Zero Trust and configure its public hostname to route to `http://ha-mcp:8000`.
4. Copy the tunnel token into the deployment repo's local `.env` as `TUNNEL_TOKEN`, alongside the Home Assistant URL/token and a separate strong MCP auth token. Set `MCP_ALLOWED_HOSTS` to the exact custom hostname.
5. Start and verify the Compose stack, then register `https://YOUR_HOSTNAME/mcp` at `https://poke.com/integrations/new` with bearer authentication, if supported by the integration form. Verify with a harmless read-only tool.

No Pi boot, tunnel, DNS hostname route, secret provisioning, or Poke integration is claimed as already completed. Nameserver changes alone do not create the tunnel or hostname route.

## 1. Prepare the Pi and Docker

Install Raspberry Pi OS 64-bit using Raspberry Pi Imager. Configure a hostname, user, SSH, and Wi-Fi if needed. Connect by `ssh YOUR_USER@raspberrypi.local` or use the Pi's router-assigned LAN IP. Use a router DHCP reservation for a stable LAN address. Update the OS and reboot:

```sh
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

Install Docker Engine and Compose plugin by following the current official Raspberry Pi OS/Debian instructions: https://docs.docker.com/engine/install/debian/ . Confirm `uname -m` reports `aarch64`, then verify `sudo docker run --rm hello-world` and `sudo docker compose version`. Avoid adding your user to the `docker` group unless you understand its root-equivalent privileges.

## 2. Clone repositories and configure secrets

The Compose build context is `./ha-device-mcp`, so clone both repositories as siblings:

```sh
mkdir -p ~/services && cd ~/services
git clone https://github.com/acyounk28/pi-homelab-setup.git
git clone https://github.com/acyounk28/ha-device-mcp.git
cd pi-homelab-setup
cp .env.example .env
nano .env
chmod 600 .env
```

In `.env`, set:

- `HA_URL`: reachable Home Assistant base URL; if HA runs on the Pi host, use `http://host.docker.internal:8123`.
- `HA_LONG_LIVED_ACCESS_TOKEN`: a Home Assistant long-lived token, preferably created by a dedicated non-admin user.
- `MCP_AUTH_TOKEN`: a separate strong secret for MCP bearer authentication.
- `MCP_ALLOWED_HOSTS`: include the exact public hostname, for example `mcp.yourdomain.com`, as well as any local hostnames needed for testing.
- `TUNNEL_TOKEN`: the Cloudflare Tunnel token created in the next section.

Keep `.env` private; never commit or paste credentials into logs/issues. The example file contains placeholders only. Rotate any exposed credential immediately.

## 3. Create the Cloudflare Zero Trust Tunnel

1. Sign in to Cloudflare and confirm the domain is active in the account after the nameserver change. If Cloudflare still reports pending nameserver/delegation status, wait for activation before proceeding.
2. Open Cloudflare Zero Trust → Networks → Tunnels → Add a Tunnel → Cloudflared. Follow the dashboard flow to create a remotely-managed tunnel.
3. Copy the tunnel token from the dashboard into the local `.env` as `TUNNEL_TOKEN=...`. Do not commit it. The Compose service runs `cloudflared tunnel --no-autoupdate run --token ...` using this value.
4. In the tunnel's Public Hostnames configuration, choose the domain and a hostname such as `mcp.yourdomain.com` (or `ha-mcp.yourdomain.com`) and set the service/origin to `http://ha-mcp:8000`. `ha-mcp` is the Compose service name, resolvable by `cloudflared` on the Compose network. Do not add a router port-forward.
5. Save the route. The app endpoint path is `/mcp`; the client URL will be `https://YOUR_HOSTNAME/mcp`. The origin should be the service root `http://ha-mcp:8000`, not a guessed `/sse` endpoint. Add the chosen hostname to `MCP_ALLOWED_HOSTS` in `.env` and restart the stack after configuration.

Official documentation: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/ . Nameserver delegation, tunnel creation, public hostname routing, and app authentication are separate setup steps.

## 4. Start and verify

From `~/services/pi-homelab-setup` after both clones and `.env` are ready:

```sh
sudo docker compose config
sudo docker compose up -d --build
sudo docker compose ps
sudo docker compose logs --tail=100 ha-mcp cloudflared
curl -i http://127.0.0.1:8000/healthz
```

`docker compose config` may display interpolated secrets; do not share its output. Confirm both services are running/healthy and check logs for errors. For a public test, use the proper MCP client/Poke integration rather than expecting a browser page at `/mcp`; the protocol is Streamable HTTP, not legacy SSE. Never expose port 8000 directly to the internet.

## 5. Register with Poke

1. Open https://poke.com/integrations/new.
2. Add the server URL `https://YOUR_HOSTNAME/mcp` (replace with the exact hostname created in Cloudflare).
3. Configure bearer authorization using the `MCP_AUTH_TOKEN` value if the form supports the required Authorization header.
4. Save and run the integration verification. Start with a harmless read-only tool such as `ha_status` or `get_device_states`.

If Poke's integration form does not support the required Streamable HTTP transport or bearer header, stop and resolve compatibility before weakening/removing authentication. Cloudflare HTTPS encryption is not a substitute for application authentication. The MCP service uses `MCP_AUTH_TOKEN`; do not assume Cloudflare Tunnel alone authenticates callers.

## Configuration checked in this repository

- `docker-compose.yml`: app build context `./ha-device-mcp`, loopback-only host port, healthcheck, non-new-privileges security option, and `cloudflared` token-mode service. Clone the app repository alongside this repository as instructed.
- `.env.example`: matches the app's documented names (`HA_URL`, `HA_LONG_LIVED_ACCESS_TOKEN`, `MCP_HOST`, `MCP_PORT`, `MCP_PATH`, `MCP_AUTH_TOKEN`, `MCP_ALLOWED_HOSTS`) and adds `TUNNEL_TOKEN` for tunnel mode.
- `cloudflared/README.md`: tunnel-token setup and service origin guidance. The `cloudflared/config.yml` file is a local-managed alternative and is not consumed by the token-mode Compose service; do not mix the two modes.
- `ha-device-mcp/Dockerfile` upstream: multi-stage Python build, non-root runtime user, port 8000, and `/healthz` healthcheck. Its README confirms Streamable HTTP at `/mcp`, bearer auth, and `MCP_ALLOWED_HOSTS`.

This is prepared for deployment but cannot be called fully live/turnkey until the Pi is booted, credentials are entered privately, the tunnel/public hostname is created, and Poke accepts and verifies the endpoint. Do not treat DNS nameserver changes as proof those steps are complete.

## Troubleshooting

- `uname -m`: expected `aarch64`.
- `sudo docker compose ps` and `sudo docker compose logs --tail=200 ha-mcp cloudflared`: inspect health/startup failures; redact secrets before sharing.
- `curl -i http://127.0.0.1:8000/healthz`: local application health check.
- `421 Misdirected Request`: check `MCP_ALLOWED_HOSTS` for the exact Host value.
- `unauthorized`: verify the MCP bearer token configured in Poke, not the Home Assistant token.
- Tunnel online but origin fails: verify Compose service is healthy and the public hostname service is exactly `http://ha-mcp:8000`.
- Home Assistant unreachable: check `HA_URL`, routing, and firewall; use `host.docker.internal` when HA is on the Pi host.
- Never fix a failure by forwarding port 8000 or removing authentication.

References: https://github.com/acyounk28/ha-device-mcp , https://docs.docker.com/engine/install/debian/ , https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/ .
