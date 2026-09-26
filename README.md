# Raspberry Pi Home Lab MCP services

Deploy Home Assistant's `ha-mcp` and fantasy-sports `flaim-mcp` on a Raspberry Pi (or another Docker host) with Compose, then expose them through a Cloudflare Tunnel. Both services use MCP over HTTP; preserve bearer authentication and the container security settings described below.

## 1. Prepare the host

Install a 64-bit Raspberry Pi OS or compatible Linux, enable SSH, and install Docker Engine and the Compose plugin using Docker's official guide: https://docs.docker.com/engine/install/debian/ . Verify Docker and Compose:

```sh
sudo docker run --rm hello-world
sudo docker compose version
```

## 2. Clone all three repositories as siblings

The Compose file builds from `../ha-device-mcp` and `../flaim`, so keep both application repositories next to the deployment repository (not inside it):

```sh
mkdir -p ~/services && cd ~/services
git clone https://github.com/acyounk28/pi-homelab-setup.git
git clone https://github.com/acyounk28/ha-device-mcp.git
git clone https://github.com/acyounk28/flaim.git
cd pi-homelab-setup
```

The resulting layout should be `~/services/pi-homelab-setup`, `~/services/ha-device-mcp`, and `~/services/flaim`.

## 3. Configure environment variables

Copy the example and edit it privately:

```sh
cp .env.example .env
nano .env
chmod 600 .env
```

For `ha-mcp`, set the Home Assistant base URL (`HA_URL`), a Home Assistant long-lived access token (`HA_LONG_LIVED_ACCESS_TOKEN`), and the exact Home Assistant entity IDs for the Windmill, Pura, and Oasis devices. Set a strong, unique `MCP_AUTH_TOKEN`; configure `MCP_ALLOWED_HOSTS` for the hostname used to reach this service. If Home Assistant runs on the Docker host, `http://host.docker.internal:8123` is often appropriate; otherwise use its reachable LAN URL.

For `flaim-mcp`, set the ESPN `ESPN_S2` and `SWID` cookie values, the relevant comma-separated `ESPN_LEAGUE_IDS` and `SLEEPER_LEAGUE_IDS`, and a strong unique `FLAIM_MCP_AUTH_TOKEN`. Set the Cloudflare tunnel token as `TUNNEL_TOKEN` if using the included token-based tunnel service. Never commit or share `.env`; the example contains placeholders only. Check the Flaim repository's current configuration documentation for exact variable naming and league-ID format before running.

## 4. Configure Cloudflare Tunnel ingress

Create a Cloudflare Tunnel in the Cloudflare Zero Trust dashboard (Networks → Tunnels), and configure public hostnames pointing to these Compose service names and container ports:

- `ha-mcp.yourdomain.com` → `http://ha-mcp:8000`
- `flaim.yourdomain.com` → `http://flaim-mcp:8001`

For the included token-managed `cloudflared` Compose service, put the tunnel token in `.env`. In the Zero Trust dashboard, add both public hostnames to that tunnel with the origins above. The service-name origins work when cloudflared is connected to the same Compose network. Alternatively, if running cloudflared outside this Compose network, use `http://localhost:8000` and `http://localhost:8001` as appropriate.

For a locally managed tunnel, `cloudflared/config.yml` can use ingress rules like:

```yaml
ingress:
  - hostname: ha-mcp.yourdomain.com
    service: http://ha-mcp:8000
  - hostname: flaim.yourdomain.com
    service: http://flaim-mcp:8001
  - service: http_status:404
```

For a cloudflared process outside the Compose network, substitute `http://localhost:8000` and `http://localhost:8001`. Do not expose the MCP ports directly to the public internet; the Compose port bindings are loopback-only.

## 5. Start both services

From `pi-homelab-setup`, validate and launch:

```sh
sudo docker compose config
sudo docker compose up -d --build
sudo docker compose ps
sudo docker compose logs --tail=100 ha-mcp flaim-mcp cloudflared
```

The Compose configuration binds service ports to host loopback: `http://127.0.0.1:8000` and `http://127.0.0.1:8001`. Confirm each application's documented health endpoint or test its MCP endpoint. Do not assume the Flaim health-check path; consult its repository documentation. `docker compose config` may print secrets, so keep its output private.

## 6. Register both MCP endpoints in Poke

Open https://poke.com/integrations/new and register each server separately using its public MCP URL:

- `https://ha-mcp.yourdomain.com/mcp`
- `https://flaim.yourdomain.com/mcp`

Use the authentication method and bearer token configured for the corresponding server (`MCP_AUTH_TOKEN` for Home Assistant and `FLAIM_MCP_AUTH_TOKEN` for Flaim), as required by each server's current documentation and the Poke integration form. Verify each connection with a harmless read-only operation first. If either application uses a different MCP path or auth-header convention, follow that repository's documentation rather than weakening authentication.

## Security hardening

Both application services are configured to run as UID/GID 10001, drop all Linux capabilities, enable `no-new-privileges`, use a read-only container filesystem, and restart unless stopped. The Home Assistant service also has a health check. Keep these controls intact; confirm the application images support the configured non-root UID and read-only filesystem. Use unique, strong MCP tokens, restrict Home Assistant account permissions, keep secrets out of Git, update the host and images, and do not configure public router port forwarding. Cloudflare Access can add another layer only if the MCP client can supply the required Access credentials.

## Troubleshooting

- `sudo docker compose ps` and `sudo docker compose logs --tail=200 ha-mcp flaim-mcp cloudflared` show container status and startup errors; redact secrets before sharing logs.
- A build-context error usually means the three repository directories are not siblings as shown above.
- Check entity IDs, league IDs, and provider credentials against the applications' documentation.
- Confirm each Cloudflare public hostname routes to the correct service and port, and that the cloudflared container shares the Compose network.
- Do not solve connectivity issues by exposing ports publicly or removing authentication/security hardening.

References: https://github.com/acyounk28/ha-device-mcp , https://github.com/acyounk28/flaim , https://docs.docker.com/engine/install/debian/ , https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/ .
