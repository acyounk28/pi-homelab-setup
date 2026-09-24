# Raspberry Pi 5 Home Assistant FastMCP server for Poke

A beginner-friendly deployment guide for a Raspberry Pi 5 running the `acyounk28/ha-device-mcp` FastMCP server in Docker, then exposing it securely to Poke without opening router ports.

> Important compatibility check: this guide assumes your server project provides the SSE transport on port 8000 and documents its environment variables and startup command. Verify those details in the upstream repository before deployment. Never publish a Home Assistant token, tunnel token, or `.env` file.

## What you will build

Your Pi runs the MCP container on the LAN. A Cloudflare Tunnel or Tailscale Funnel provides an HTTPS endpoint without router port-forwarding. Poke connects to that endpoint using the SSE URL and the authentication method supported by your server and Poke's integration form.

## 1. Unbox and prepare the Pi

1. Connect the Pi 5 to a monitor, keyboard, network (Ethernet is simplest), and reliable Pi 5 power supply. Insert a microSD card suitable for Raspberry Pi OS.
2. On another computer, install Raspberry Pi Imager from the official Raspberry Pi website and open it.
3. Choose Device: Raspberry Pi 5; Operating System: Raspberry Pi OS (64-bit); Storage: your microSD card. Confirm the storage selection carefully because imaging erases it.
4. Open the Imager customization/settings screen. Set a hostname such as `raspberrypi`, create a non-default username and strong password, enable SSH (password or public-key authentication), and configure Wi-Fi country, SSID, and password if using Wi-Fi. Keep credentials private.
5. Write the image, safely eject the card, insert it in the Pi, and power it on. Allow a few minutes for first boot.
6. From a computer on the same network, connect with `ssh YOUR_USER@raspberrypi.local`. If mDNS does not resolve, find the Pi's address in your router's connected-device list and use `ssh YOUR_USER@PI_LAN_IP`.
7. Accept the host key only if you expect this first connection. Update the OS:

```sh
sudo apt update
sudo apt full-upgrade -y
sudo reboot
```

Reconnect after reboot. Confirm 64-bit ARM with `uname -m` (expected `aarch64`).

### Stable LAN address

Prefer a DHCP reservation in your router: reserve the Pi's current address for its MAC address. This is generally safer and simpler than manually assigning an address on the Pi. Alternatively use `raspberrypi.local` on a LAN where mDNS is supported. A LAN address is not a public address; do not configure router port forwarding.

## 2. Install Docker Engine and Compose plugin

Use Docker's official Debian instructions for the current Raspberry Pi OS release. The following is the official-repository method for Debian-based 64-bit Raspberry Pi OS; review Docker's current documentation if the release has changed:

```sh
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
 echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker run --rm hello-world
sudo docker compose version
```

The official Docker documentation is at https://docs.docker.com/engine/install/debian/ . Avoid adding your login to the `docker` group unless you understand that membership effectively grants root-level control.

## 3. Check the MCP server's actual configuration

On the Pi, install Git and clone the upstream project so you can inspect its maintained instructions and configuration:

```sh
sudo apt install -y git
mkdir -p ~/services && cd ~/services
git clone https://github.com/acyounk28/ha-device-mcp.git
cd ha-device-mcp
git status --short
```

Read the upstream README and Dockerfile/Compose files, if present. Confirm the exact image/build context, startup command, required environment variable names, Home Assistant URL/token format, SSE path, and whether authentication is supported. Do not guess these settings. Make sure the project works on ARM64; if building locally, Docker can build for the Pi's native architecture. If it uses a prebuilt image, confirm the image supports `linux/arm64`.

Create a strong, least-privilege Home Assistant long-lived access token using Home Assistant's profile page. Treat it like a password. The token grants whatever access the integration permits; use a dedicated account if appropriate and limit access as much as Home Assistant allows.

## 4. Compose starter template and secrets

This repository's `docker-compose.yml` is a template, not a guaranteed drop-in: replace the image/build and command placeholders with the exact values verified in the upstream project. Keep port 8000 bound to loopback on the Pi. The tunnel runs on the same host and can reach it locally.

Copy `.env.example` to `.env` and use the variable names required by the upstream application. Protect it:

```sh
cp .env.example .env
nano .env
chmod 600 .env
```

Never commit `.env`. The provided `.gitignore` excludes it. Do not put secrets directly in the Compose file, shell history, screenshots, or public issue reports. For stronger isolation use Docker secrets if the upstream application supports reading secrets from files.

Once Compose is configured from upstream's real settings:

```sh
docker compose config
docker compose up -d
docker compose ps
docker compose logs --tail=100 -f
```

Run as a non-root container user when the upstream image supports it; do not add `privileged: true`. Ensure the container only has the devices and permissions it needs.

## 5. Verify locally before tunneling

Check logs and local listening port:

```sh
docker compose ps
docker compose logs --tail=100 mcp
ss -ltn | grep ':8000'
```

Test the SSE endpoint path documented by the upstream server. Typical older SSE servers use `/sse`, but do not assume this path; substitute the confirmed route:

```sh
curl -i -N http://127.0.0.1:8000/CONFIRMED_SSE_PATH
```

An SSE response normally stays open and has `text/event-stream` content type. A timeout or open connection can be normal. A 404 means check the path; connection refused means check container health, port mapping, and logs. Do not expose this unauthenticated endpoint publicly.

## 6. Secure public access with a tunnel (choose one)

A tunnel avoids router port-forwarding, but it does not by itself authenticate MCP requests. Require token/authentication at the MCP service or a trusted access proxy, use HTTPS, and share credentials only through the integration's supported secure mechanism. Confirm that Poke can send the required authorization header or Cloudflare Access service-token headers before relying on that protection. Do not put secrets in the URL.

### Option A: Cloudflare Tunnel

1. Own or control a domain managed by Cloudflare and sign in to the Cloudflare dashboard.
2. Create a remotely managed tunnel and follow Cloudflare's current Linux connector instructions for ARM64. Install `cloudflared` from Cloudflare's official package/repository instructions; do not download binaries from untrusted sources.
3. Create a tunnel token in the dashboard. On the Pi, store it in a root-readable file or secret store, never in this repository. If using a file, restrict it: `sudo chmod 600 /etc/cloudflared/credentials` and ensure it is owned by root.
4. Configure a published hostname (for example, a dedicated subdomain) to route to `http://127.0.0.1:8000`. Set the upstream path to the verified SSE path if supported by the dashboard configuration.
5. Add Cloudflare Access protection where compatible, or enforce authentication in the MCP server itself. If Poke cannot present Cloudflare Access credentials, Access will block it; verify compatibility before enabling it. Keep server-level authentication enabled regardless.
6. Start the tunnel as a service and confirm its status in the dashboard. Test the public HTTPS endpoint with `curl -i -N https://YOUR_HOSTNAME/CONFIRMED_SSE_PATH` from outside your home network. Do not proceed if it returns an authentication failure or exposes the service without the intended access control.

Cloudflare's authoritative tunnel setup documentation: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/ .

### Option B: Tailscale Funnel

1. Install Tailscale on the Pi using the official Linux installation instructions: https://tailscale.com/kb/1031/install-linux/ . Authenticate the Pi to your tailnet.
2. Confirm your tailnet policy permits Funnel, then follow the current official Funnel instructions: https://tailscale.com/kb/1223/funnel/ . Funnel availability and command syntax can change; use the documented syntax for your installed version.
3. Publish only the local MCP port over HTTPS using Funnel. Never enable a plain router port-forward. Use the server's own authentication because public Funnel access should be treated as internet-reachable.
4. Verify the HTTPS endpoint from a device outside the tailnet. Ensure authentication is required and the SSE route responds as expected.

Use only one tunnel at a time. Rotate the tunnel token and Home Assistant token immediately if either is exposed. An SSE transport may not automatically provide the authorization behavior Poke expects; verify Poke's requirements before choosing a tunnel/auth design.

## 7. Register with Poke

1. Open https://poke.com/integrations/new while signed in.
2. Add a custom MCP integration using the exact public HTTPS SSE endpoint, including the confirmed SSE path, as required by the form.
3. Configure the server's authentication using the form's supported credential/header mechanism. Do not paste secrets into a URL or share them in repository files.
4. Save the integration and use its verification/test action. Confirm the expected Home Assistant tools appear and try a harmless read-only tool first. Only then test an action you understand and intend to perform.
5. If the registration form does not support the server's authentication mechanism or SSE transport, stop and resolve the compatibility gap before making the endpoint public. Never disable authentication merely to make a test pass.

## 8. Troubleshooting checklist

- `uname -m`: should report `aarch64`.
- `docker compose ps`: look for restarting or unhealthy containers.
- `docker compose logs --tail=200 mcp`: inspect startup/configuration errors; redact secrets before sharing logs.
- `docker compose config`: validate YAML and resolved environment (be careful not to publish its output if it contains secrets).
- `curl -i -N http://127.0.0.1:8000/CONFIRMED_SSE_PATH`: check local SSE response.
- `curl -i -N https://YOUR_HOSTNAME/CONFIRMED_SSE_PATH`: check tunnel and HTTPS from outside your LAN.
- `getent hosts raspberrypi.local`: check mDNS resolution; otherwise use router DHCP reservation/IP.
- If the tunnel works but Poke fails, check SSE path, transport compatibility, auth headers, Access policy, and server logs. Never solve this by exposing port 8000 directly or removing authentication.
- If a token was committed: revoke it immediately, remove it from history as appropriate, and issue a new token. Deleting the visible file alone does not invalidate a leaked credential.

## Files in this starter

- `docker-compose.yml`: explicitly marked template with safe loopback binding; customize against upstream documentation.
- `.env.example`: placeholders only, never real credentials.
- `.gitignore`: blocks local secret/config artifacts.

This project is an independent deployment guide and is not an official Raspberry Pi, Docker, Cloudflare, Tailscale, Home Assistant, or Poke manual. Follow each vendor's current docs where installation syntax or product behavior changes.
