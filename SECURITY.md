# Security hardening for the Raspberry Pi MCP deployment

This setup exposes an internet-reachable MCP service through Cloudflare Tunnel. The tunnel avoids inbound home-router ports, but does not by itself authenticate Poke or protect MCP tools. Keep application authentication enabled and use layered controls. Security reduces risk; no configuration can guarantee that a server cannot be compromised.

## Application and MCP authentication

- Set a long, random `MCP_AUTH_TOKEN` in the Pi's local `.env`. The server validates a Bearer token at the HTTP/MCP layer; unauthenticated requests should receive HTTP 401 before tools are exposed. Never leave this unset or use the example placeholder. Store `.env` with `chmod 600 .env`; do not commit it.
- In Poke at https://poke.com/integrations/new, configure the integration with `https://YOUR_HOSTNAME/mcp` and set the custom headers supported by the form: normally `Authorization: Bearer YOUR_MCP_AUTH_TOKEN`, or the exact custom token header only if both server and client are configured for it. Do not put credentials in the URL. Confirm the form actually transmits the header and verify with a read-only tool.
- `MCP_AUTH_TOKEN` is the application credential. A Cloudflare tunnel token (`TUNNEL_TOKEN`) is a separate connector credential and must never be substituted for the MCP token.
- Cloudflare Access can add machine-to-machine protection using a Service Auth policy and service token headers `CF-Access-Client-Id` and `CF-Access-Client-Secret`. Poke must be able to send both headers on every request for this to work; confirm custom-header support in Poke before enforcing Access. Access can reject clients before they reach MCP, so test safely. Retain MCP bearer authentication as defense in depth. Never make Access optional by exposing an unauthenticated origin.
- If custom headers are not supported by the client for either auth layer, do not disable server authentication as a workaround. Resolve client/auth compatibility first.

## Pi network and operating-system controls

### No inbound router ports

Do not create router port-forwarding rules for SSH, 8000, or any container. `cloudflared` initiates an outbound tunnel connection; publish the application only on Pi loopback as the Compose file does. Keep router UPnP/automatic port mappings disabled if feasible and review router rules periodically.

### UFW firewall

Use the actual trusted LAN CIDR for your network; `192.168.1.0/24` below is only an example. Ensure you have a working SSH key and verify the correct LAN range before enabling the firewall, or you can lock yourself out. If administering over Tailscale, allow SSH via the Tailscale interface/address policy instead of opening it to the whole internet.

```sh
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp
sudo ufw enable
sudo ufw status verbose
```

Do not add an allow rule for port 8000. If using Tailscale, configure its ACLs and narrowly allow SSH from the tailnet as appropriate for your setup.

### SSH with Ed25519 keys only

On your trusted client, create a key if needed:

```sh
ssh-keygen -t ed25519 -a 64
ssh-copy-id YOUR_USER@raspberrypi.local
ssh YOUR_USER@raspberrypi.local
```

Before disabling passwords, open a second terminal and confirm key-based login succeeds. Keep a recovery path (local console) available. Then create `/etc/ssh/sshd_config.d/ hardened.conf` without the space (actual path `/etc/ssh/sshd_config.d/hardened.conf`) containing:

```text
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
```

Validate and reload (service name can differ by OS):

```sh
sudo sshd -t
sudo systemctl reload ssh
```

Do not close the verified session until a new key-based SSH login succeeds. Use only Ed25519 keys for this deployment; protect the private key and never copy it onto the Pi.

## Container hardening

The upstream `ha-device-mcp` Dockerfile creates `appuser` with UID 10001 and runs the application as that non-root user. The deployment Compose configuration adds `read_only: true`, `cap_drop: [ALL]`, and `no-new-privileges:true` for `ha-mcp`; it binds port 8000 only to host loopback. Do not add `privileged: true`, host networking, or extra capabilities. If a future application change genuinely requires a writable directory, mount only that specific directory as a bounded writable volume/tmpfs rather than disabling the read-only root filesystem.

Validate and apply the hardened Compose configuration:

```sh
sudo docker compose config
sudo docker compose up -d --build
sudo docker compose ps
sudo docker compose logs --tail=100 ha-mcp cloudflared
```

Do not share rendered Compose output or logs without checking for secrets. Keep Docker and Raspberry Pi OS updated, use a unique Home Assistant token from a dedicated non-admin account when feasible, rotate leaked tokens immediately, and back up configuration securely.
