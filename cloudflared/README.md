# Cloudflare Tunnel setup and access security

The Compose service uses a remotely-managed tunnel token (`TUNNEL_TOKEN`). Create a tunnel in Cloudflare Zero Trust, copy its token into the Pi's private `.env`, and configure one public hostname per MCP server:

| Hostname (example) | Origin (Compose DNS name + container port) | Client endpoint |
|---|---|---|
| `ha.yourdomain.com` | `http://ha-mcp:8000` | `https://ha.yourdomain.com/mcp` (Streamable HTTP) |
| `nfl.yourdomain.com` | `http://flaim-mcp:8800` | `https://nfl.yourdomain.com/sse` (SSE; `/mcp` if `NFL_MCP_TRANSPORT=streamable-http`) |

Keep the bearer tokens (`MCP_AUTH_TOKEN`, `NFL_MCP_TOKEN`) enabled: tunnel TLS does not authenticate MCP callers. A single hostname with path rules works only while `flaim-mcp` uses SSE (`/mcp` → `ha-mcp:8000`; `/sse`, `/messages*` → `flaim-mcp:8800`); Tunnel does not rewrite paths, so prefix routing such as `/nfl/mcp` is not possible.

## Token-mode setup

1. Ensure the domain is active on Cloudflare. Nameserver delegation and tunnel/hostname configuration are separate.
2. In Zero Trust, go to Networks → Tunnels → Add a Tunnel → Cloudflared and create a remotely managed tunnel.
3. Copy its token into `.env` as `TUNNEL_TOKEN=...`; protect the file with `chmod 600 .env`. Never commit or share the token.
4. Add the Public Hostnames from the table above. For the SSE hostname raise **Connection timeout** / keep-alive under HTTP settings.
5. Include the HA hostname in `MCP_ALLOWED_HOSTS` and maintain both MCP bearer tokens. Do not add a router port-forward.
6. Start/verify with `sudo docker compose up -d --build` and inspect `sudo docker compose logs --tail=100 cloudflared ha-mcp flaim-mcp`.

## Optional Cloudflare Access for machine clients

A Cloudflare Access Service Auth policy may require Service Token headers `CF-Access-Client-Id` and `CF-Access-Client-Secret`. Configure this only after confirming that Poke's custom integration can send both headers on every MCP request. If Poke cannot provide the headers, Access will block it; do not remove MCP bearer authentication or expose an unprotected alternative. Continue to use `MCP_AUTH_TOKEN` as defense in depth and do not place secrets in a URL.

## Alternative local-managed mode

`config.yml` is a local-managed credentials-file example and is not consumed by the token-mode Compose service. For local mode, use `cloudflared tunnel run --config /etc/cloudflared/config.yml` and mount the config and JSON credentials instead of setting a tunnel token. Do not configure token-mode and local-managed mode simultaneously. The example ingress targets Compose DNS names `ha-mcp:8000` and `flaim-mcp:8800` per hostname and has a final 404 catch-all.

Revoke/rotate a tunnel token immediately if exposed. Official docs: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/ .
