# Environment setup guide (beginner-friendly)

This guide walks you through finding each value used by this repository's `.env` file. You do not need to understand Docker internals to fill it in; follow the steps, paste the values into the matching lines, and keep the file private.

## 1. Create your private `.env` file

Open a terminal on the Docker host, change to the `pi-homelab-setup` directory, and run:

```sh
cp .env.example .env && nano .env
```

In nano, move with the arrow keys, replace the placeholder after `=`, then save with Ctrl+O, Enter, and exit with Ctrl+X. Do not add spaces around `=`. Keep `.env` out of Git and do not paste it into chats or public issue reports. Restrict its permissions afterward:

```sh
chmod 600 .env
```

The names in the left column below must match `.env.example`. A few names in older descriptions differ from this repository's actual variable names: Home Assistant uses `HA_URL` (not `HA_BASE_URL`) and `WINDMILL_ENTITY_ID` (not `WINDMILL_FAN_ENTITY_ID`). Use the exact names shown in `.env.example` unless the application repository has since changed its configuration.

## 2. Home Assistant values

### `HA_URL`

Use the address that the Docker host can use to reach Home Assistant, including port `8123`. Common examples are:

- `http://homeassistant.local:8123`
- `http://192.168.1.50:8123` (replace with your Home Assistant machine's actual local IP)

Find the IP from your router's connected-device list or Home Assistant's network/system information. From another device on the same home network, open the address in a browser to check that it reaches Home Assistant. If Docker runs on a different host or network, make sure that host can reach the chosen address. Do not use a made-up IP.

### `HA_LONG_LIVED_ACCESS_TOKEN`

1. Sign in to Home Assistant as the user account the integration should use.
2. Open your user profile by selecting your name/profile in the lower-left corner.
3. Scroll to the bottom of the profile page, or open Profile → Security.
4. Under Long-Lived Access Tokens, choose Create Token, enter a recognizable name, and confirm.
5. Copy the token immediately and paste it as the value for `HA_LONG_LIVED_ACCESS_TOKEN`. Home Assistant may not show it again.

Treat this token like a password. Do not include quote marks unless required by your editor, and never share it publicly.

### Device entity IDs

In Home Assistant, open Developer Tools → States. Search for each device by name and select its entity. Copy the exact entity ID shown (including its domain prefix, such as `fan.` or `switch.`):

- `WINDMILL_ENTITY_ID` — the Windmill fan entity (often starts with `fan.windmill_`). The requested name `WINDMILL_FAN_ENTITY_ID` is not the key used by this repo's `.env.example`.
- `PURA_ENTITY_ID` — the Pura entity (often starts with `switch.`).
- `OASIS_ENTITY_ID` — the Oasis entity (often starts with `switch.`).

Paste each exact ID into its matching line. Do not copy a display name or guess the entity ID; the available entity domain depends on how the device is integrated.

Other Home Assistant entries already in `.env.example`:

- `HA_TIMEOUT_SECONDS` is the request timeout; the provided default is usually fine.
- `HA_VERIFY_SSL` should normally remain `true` for HTTPS. Do not disable certificate checking as a workaround without understanding the security impact.
- `MCP_HOST`, `MCP_PORT`, and `MCP_PATH` are service settings; keep the provided defaults unless you are deliberately changing the deployment.
- `MCP_ALLOWED_HOSTS` is a comma-separated list of hostnames accepted by the HA service. Keep localhost entries and include the public hostname you configure, such as `ha-mcp.yourdomain.com`.

## 3. Flaim (ESPN NFL GM and Sleeper) values

### `ESPN_S2` and `SWID`

These are ESPN sign-in cookies. Handle them as credentials: anyone who gets them may be able to access your ESPN fantasy account. Do not send them to anyone or paste them into an issue.

1. In Chrome or Safari, sign in to ESPN and open `https://www.espn.com/fantasy/football/`.
2. Open browser Developer Tools (F12 on many keyboards; on Mac, use the browser's Developer Tools menu or its keyboard shortcut).
3. Open the Application tab in Chrome, or Storage in Firefox/Safari's Web Inspector.
4. In the left pane, expand Cookies and select `https://www.espn.com` / `espn.com`.
5. Find the cookie named `espn_s2` and copy its complete Value into `ESPN_S2`.
6. Find the cookie named `SWID` and copy its complete Value into `SWID`. Preserve its curly braces, for example `{...}`.

If the cookies are not listed, confirm you are signed in and viewing ESPN's fantasy football site, then refresh the page and inspect the `espn.com` cookie store again. Do not include the cookie-name column in the value.

### `ESPN_LEAGUE_IDS`

Open the ESPN fantasy league in your browser. In its address bar, find `leagueId=XXXXXX`; copy only the digits/value after the equals sign into `ESPN_LEAGUE_IDS`. For more than one league, enter the IDs separated by commas, with no spaces unless the Flaim documentation specifies otherwise.

### `SLEEPER_LEAGUE_IDS`

Open the league in the Sleeper app or website. The league ID appears in a URL like `sleeper.com/leagues/XXXXXX`; copy the segment after `/leagues/`. League Settings may also show league details/ID. For multiple leagues, use comma-separated IDs.

`FLAIM_MCP_AUTH_TOKEN`, `FLAIM_MCP_HOST`, and `FLAIM_MCP_PORT` are separate Flaim service settings. Keep the supplied host/port defaults. Set the Flaim token to a separate strong secret; do not reuse `MCP_AUTH_TOKEN`.

## 4. Generate the Home Assistant MCP bearer token

On the Docker host, run:

```sh
openssl rand -hex 32
```

Copy the full output into `MCP_AUTH_TOKEN`. This creates a random 32-byte secret represented as hexadecimal. Keep it private and do not reuse it for the Flaim service.

When adding the HA MCP server in Poke at `https://poke.com/integrations/new`, use the public MCP endpoint and add this custom header:

```text
Authorization: Bearer <the exact MCP_AUTH_TOKEN value>
```

Replace the angle-bracket placeholder with the token itself; do not include the angle brackets. The word `Bearer` and the space after it are required. Use the corresponding `FLAIM_MCP_AUTH_TOKEN` for Flaim if its server is configured for bearer auth. Keep each service's token matched to that service; verify the current application documentation if its auth behavior differs.

## 5. Cloudflare Tunnel token and public hostnames

### Find `TUNNEL_TOKEN`

1. Sign in to the Cloudflare Zero Trust dashboard for your account.
2. Open Networks → Tunnels.
3. Select an existing tunnel or create one.
4. Choose the Docker or Linux setup instructions.
5. Cloudflare displays a command similar to `cloudflared tunnel run --token <TOKEN>`.
6. Copy only the token after `--token` (not the command text) into `TUNNEL_TOKEN` in `.env`.

The tunnel token grants access to your tunnel. Keep it secret. The exact dashboard labels can vary as Cloudflare updates its interface.

### Add Public Hostnames

In Networks → Tunnels, select the tunnel and open its Public Hostnames / published application routes section. Add these two routes, replacing `yourdomain.com` with a domain managed in your Cloudflare account:

| Hostname | Service type | Service URL |
| --- | --- | --- |
| `ha-mcp.yourdomain.com` | HTTP | `ha-mcp:8000` |
| `flaim.yourdomain.com` | HTTP | `flaim-mcp:8001` |

For Cloudflare's URL field, enter `http://ha-mcp:8000` and `http://flaim-mcp:8001` (the `http://` scheme is required). These Compose service-name origins work when cloudflared runs in the same Compose network, as it does in this repository. If cloudflared runs directly on the Docker host outside that network, use `http://localhost:8000` and `http://localhost:8001` instead. Do not mix the two connection layouts.

The hostname used for HA must also be listed in `MCP_ALLOWED_HOSTS`. Use the same hostname when registering the server in Poke, with `/mcp` appended if that is the configured MCP path, for example `https://ha-mcp.yourdomain.com/mcp`.

## 6. Docker/Compose: what to run

Docker runs the services in containers; Docker Compose reads this repository's `docker-compose.yml` and starts the related containers together. Once `.env` is filled in and the three sibling repositories have been cloned as described in the README, run these commands from the `pi-homelab-setup` directory:

```sh
sudo docker compose config
sudo docker compose up -d --build
sudo docker compose ps
```

The first command checks the Compose configuration. Its output can contain secrets, so do not share it. The second builds and starts services in the background. The third shows whether they are running. To view recent startup logs:

```sh
sudo docker compose logs --tail=100 ha-mcp flaim-mcp cloudflared
```

If a command says Docker is not installed, follow Docker's official Debian installation instructions linked in the README. If a hostname does not connect, check the tunnel route, hostname spelling, service/port, and container status before changing security settings. Do not expose the service ports directly to the public internet.

## 7. Final safety check

- `.env` contains real secrets; `.env.example` contains placeholders and is safe to commit.
- Never commit `.env`, post its contents, or share screenshots showing token/cookie values.
- Use separate strong tokens for HA MCP and Flaim MCP.
- If a token or cookie is exposed, revoke/rotate it at the issuing service and update `.env`.
- Check the application repositories' documentation if a variable name or authentication behavior has changed; the environment variable names in this guide reflect this repository's current `.env.example`.
