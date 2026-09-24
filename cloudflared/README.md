# Cloudflare Tunnel setup

The Compose service uses a remotely-managed tunnel token (`TUNNEL_TOKEN`). Create a tunnel in Cloudflare Zero Trust, copy its token into `.env`, and configure its public hostname route in the Cloudflare dashboard with service `http://ha-mcp:8000`. Ensure the hostname route points to the MCP endpoint path `/mcp` at the client (the tunnel origin routes to the service root; configure the desired path/host appropriately). Keep `MCP_AUTH_TOKEN` enabled; TLS at the tunnel does not replace MCP bearer authentication.

Quick setup:

1. Install `cloudflared` locally and authenticate: `cloudflared tunnel login` (opens browser; saves an account certificate locally).
2. Create a named tunnel: `cloudflared tunnel create ha-device-mcp`.
3. Get its run token: `cloudflared tunnel token ha-device-mcp`; copy the output to `TUNNEL_TOKEN` in the homelab repo's `.env` (never paste it into source control).
4. In Cloudflare Zero Trust, configure the tunnel's public hostname and set the service URL to `http://ha-mcp:8000`. Add the hostname to `MCP_ALLOWED_HOSTS` and restart the stack.
5. Run `docker compose config` (avoid sharing output containing interpolated secrets), then `docker compose up -d --build` and `docker compose logs --tail=100 cloudflared`.

The token-based container uses Cloudflare's remotely managed tunnel configuration; the `config.yml` adjacent to this guide is a local-managed credentials-file example, not loaded by the token-mode Compose service. For local mode, use `cloudflared tunnel run --config /etc/cloudflared/config.yml` and mount both the config and the JSON credentials into the cloudflared container instead of setting a token. Do not configure the two modes simultaneously. The `config.yml` ingress target is the Compose service DNS name `ha-mcp:8000` and includes a final 404 catch-all.

For a one-command login/create/token workflow run these commands on a trusted workstation:

```sh
cloudflared tunnel login
cloudflared tunnel create ha-device-mcp
cloudflared tunnel token ha-device-mcp
```

Then put the token in `.env`; configure the DNS/public hostname and origin in Cloudflare dashboard. Revoke/rotate the token immediately if exposed. Cloudflare route setup may require an owned domain active on Cloudflare.
