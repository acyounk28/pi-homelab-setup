# Raspberry Pi 5 Home Assistant MCP server for Poke

Deploy `acyounk28/ha-device-mcp` on a Raspberry Pi 5 with Docker Compose, then expose it through a Cloudflare Zero Trust Tunnel. The server uses MCP Streamable HTTP at `/mcp` (not legacy SSE `/sse`).

## Current status

Prepared in the repositories: the deployment repo, the upstream application repo with multi-stage Dockerfile and non-root runtime user, a Compose stack for `ha-mcp` plus `cloudflared`, and example configuration. Cloudflare nameserver changes were reported by Alex but have not been independently verified here. Nameservers alone do not create a tunnel or public hostname route. Still required on the Pi: flash/boot OS, install Docker, clone both repositories, privately set `.env`, create the Cloudflare tunnel and custom hostname, then register and verify the endpoint in Poke.

## Prepare the Pi

Install Raspberry Pi OS 64-bit using Raspberry Pi Imager and configure a user, SSH, and network. Connect with `ssh YOUR_USER@raspberrypi.local` or the router-assigned LAN IP; use a DHCP reservation for a stable address. Update and reboot:

```sh
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

Install Docker Engine and Compose plugin following the current official Debian/Raspberry Pi OS guide: https://docs.docker.com/engine/install/debian/ . Confirm `uname -m` is `aarch64`, then run `sudo docker run --rm hello-world` and `sudo docker compose version`.

## Clone and configure

Compose expects the application repository as a sibling directory:

```sh
mkdir -p ~/services && cd ~/services
git clone https://github.com/acyounk28/pi-homelab-setup.git
git clone https://github.com/acyounk28/ha-device-mcp.git
cd pi-homelab-setup
cp .env.example .env
nano .env
chmod 600 .env
```

Set `HA_URL` (use `http://host.docker.internal:8123` if Home Assistant runs on the Pi host), `HA_LONG_LIVED_ACCESS_TOKEN`, a separate strong `MCP_AUTH_TOKEN`, the chosen exact hostname in `MCP_ALLOWED_HOSTS`, and the Cloudflare tunnel's `TUNNEL_TOKEN`. Use a dedicated non-admin Home Assistant account where feasible. Never commit `.env` or share tokens.

## Create the Cloudflare Tunnel

1. Confirm the domain is active in Cloudflare.
2. In Cloudflare Zero Trust, open Networks → Tunnels → Add a Tunnel → Cloudflared and create a remotely-managed tunnel.
3. Copy its token into `.env` as `TUNNEL_TOKEN=...`.
4. Add a public hostname such as `mcp.yourdomain.com`; set the service/origin to `http://ha-mcp:8000`.
5. Put the exact hostname in `MCP_ALLOWED_HOSTS`. The Poke endpoint is `https://YOUR_HOSTNAME/mcp`.

No router port-forward is required or recommended. See `cloudflared/README.md` for Access Service Token considerations and token-mode details.

## Start and connect

```sh
sudo docker compose config
sudo docker compose up -d --build
sudo docker compose ps
sudo docker compose logs --tail=100 ha-mcp cloudflared
curl -i http://127.0.0.1:8000/healthz
```

`docker compose config` can render secrets; do not share its output. In https://poke.com/integrations/new, configure `https://YOUR_HOSTNAME/mcp` and the bearer authorization header using `MCP_AUTH_TOKEN` if supported. Test a harmless read-only tool first. If Poke cannot send the required auth headers, resolve compatibility before weakening authentication.

## Security Hardening

See [SECURITY.md](SECURITY.md) for the full checklist and commands. In brief: require MCP bearer-token authentication; optionally use Cloudflare Access Service Tokens only if Poke can send `CF-Access-Client-Id` and `CF-Access-Client-Secret`; allow no inbound router ports; firewall the Pi to deny incoming traffic except trusted LAN/Tailscale SSH; disable SSH root/password login and use Ed25519 keys; run the app as non-root with a read-only filesystem, all Linux capabilities dropped, and `no-new-privileges`.

These controls reduce exposure but cannot guarantee that a system cannot be compromised. Keep OS, Docker, and images updated, protect and rotate secrets, and retain a local recovery path before changing SSH/firewall settings.

## Troubleshooting

- `sudo docker compose ps` and `sudo docker compose logs --tail=200 ha-mcp cloudflared`: inspect health and startup errors; redact secrets.
- `curl -i http://127.0.0.1:8000/healthz`: local app health check.
- `421 Misdirected Request`: check `MCP_ALLOWED_HOSTS` exactly.
- `unauthorized`: check MCP bearer credential, not the Home Assistant token.
- Tunnel cannot reach origin: verify `ha-mcp` health and origin `http://ha-mcp:8000`.
- Never fix problems by forwarding port 8000 or removing authentication.

References: https://github.com/acyounk28/ha-device-mcp , https://docs.docker.com/engine/install/debian/ , https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/ .
