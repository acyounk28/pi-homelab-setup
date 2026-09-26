# Cloudflare Tunnel setup and access security

The Compose service uses a remotely-managed tunnel token (`TUNNEL_TOKEN`). Create a tunnel in Cloudflare Zero Trust, copy its token into the Pi's private `.env`, and configure a public hostname route to `http://ha-mcp:8000`. The client endpoint is `https://YOUR_HOSTNAME/mcp` (this app uses Streamable HTTP, not `/sse`). Keep `MCP_AUTH_TOKEN` enabled: tunnel TLS does not authenticate MCP callers.

## Token-mode setup

1. Ensure the domain is active on Cloudflare. Nameserver delegation and tunnel/hostname configuration are separate.
2. In Zero Trust, go to Networks → Tunnels → Add a Tunnel → Cloudflared and create a remotely managed tunnel.
3. Copy its token into `.env` as `TUNNEL_TOKEN=...`; protect the file with `chmod 600 .env`. Never commit or share the token.
4. Add a Public Hostname, such as `mcp.yourdomain.com`, with service/origin `http://ha-mcp:8000`. The hostname is the public address; `/mcp` is the client endpoint path.
5. Include the hostname in `MCP_ALLOWED_HOSTS` and maintain the MCP bearer token. Do not add a router port-forward.
6. Start/verify with `sudo docker compose up -d --build` and inspect `sudo docker compose logs --tail=100 cloudflared ha-mcp`.

## Optional Cloudflare Access for machine clients

A Cloudflare Access Service Auth policy may require Service Token headers `CF-Access-Client-Id` and `CF-Access-Client-Secret`. Configure this only after confirming that Poke's custom integration can send both headers on every MCP request. If Poke cannot provide the headers, Access will block it; do not remove MCP bearer authentication or expose an unprotected alternative. Continue to use `MCP_AUTH_TOKEN` as defense in depth and do not place secrets in a URL.

## Alternative local-managed mode

`config.yml` is a local-managed credentials-file example and is not consumed by the token-mode Compose service. For local mode, use `cloudflared tunnel run --config /etc/cloudflared/config.yml` and mount the config and JSON credentials instead of setting a tunnel token. Do not configure token-mode and local-managed mode simultaneously. The example ingress targets Compose DNS name `ha-mcp:8000` and has a final 404 catch-all.

Revoke/rotate a tunnel token immediately if exposed. Official docs: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/ .
