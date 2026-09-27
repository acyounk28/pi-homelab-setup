# Networking: host mode, Docker bridges and the Cloudflare tunnel

```
                     Internet
                        │  (outbound-only tunnel; no inbound ports)
                 ┌──────▼──────┐
                 │  cloudflared│  bridge net "pi-homelab" (172.16.0.0/12)
                 └──┬───────┬──┘
   ha-mcp.<domain>  │       │ (optional) ha.<domain>
                    ▼       ▼
              ┌─────────┐  host.docker.internal:8123
              │  ha-mcp │──────────────┐
              │  :8000  │              │
              └─────────┘              ▼
  LAN ◄────── network_mode: host ── homeassistant :8123
  (mDNS/SSDP/HomeKit multicast)     (+ every port HA opens)
```

## Why Home Assistant runs with `network_mode: host`

Discovery protocols used by the devices in this stack are link-local multicast or broadcast:

| Protocol | Used by | Needs |
| --- | --- | --- |
| mDNS / Zeroconf (`224.0.0.251:5353`) | HomeKit Controller (Windmill AC), HA's own discovery cards | HA on the LAN interface, receiving multicast |
| Outbound HTTPS only | Oasis Lighting (cloud-only; the lamps/bulbs expose no LAN service, see [devices/oasis-lighting.md](devices/oasis-lighting.md)) | Pi has internet access; nothing LAN-specific |
| SSDP / UPnP (`239.255.255.250:1900`) | many TVs, speakers, routers | same |
| HomeKit pairing (HAP over TCP) | Windmill AC | the accessory must be able to reach HA back on the address it advertised |
| Bluetooth (optional) | — | `/run/dbus` + host network |

A Docker bridge network NATs the container behind the Pi's IP and does **not** forward multicast, so none of the above work. Host networking puts HA directly on `eth0`/`wlan0`, exactly like a bare-metal install.

## Consequences you must plan for

1. **No `ports:` / `networks:` on the HA service.** Compose rejects them together with `network_mode: host`. HA listens on `0.0.0.0:8123` — every host interface. Restrict with the host firewall, not Docker:

   ```sh
   sudo ufw allow from 192.168.1.0/24 to any port 8123 proto tcp   # your LAN CIDR
   sudo ufw deny 8123/tcp
   ```

   Docker bypasses UFW for *published* ports of bridge containers, but a host-networked process is an ordinary listener, so UFW rules **do** apply to HA.

2. **The Compose DNS name `homeassistant` no longer resolves to HA** for containers on the `pi-homelab` bridge (ha-mcp, cloudflared). They must use the host gateway:

   ```yaml
   extra_hosts:
     - "host.docker.internal:host-gateway"
   environment:
     HA_URL: http://host.docker.internal:8123
   ```

   `docker-compose.yml` does exactly this for `ha-mcp` (and `cloudflared`). `host-gateway` resolves to the bridge's gateway IP (typically `172.17.0.1`–`172.31.x.1`), which is the Pi itself, so traffic never leaves the machine.

3. **HA sees Docker-bridge source IPs.** Requests from ha-mcp/cloudflared arrive from `172.x.x.x`. Two effects:
   - HA's `http.ip_ban_enabled` would ban *the whole bridge* after a few bad tokens; `configuration.yaml` therefore trusts `172.16.0.0/12` as proxies so `X-Forwarded-For` is honoured and bans apply to the real client.
   - Requests proxied by cloudflared without `trusted_proxies` get `400 Bad Request`. `scripts/install-homeassistant.sh` writes the block; if you kept an older `configuration.yaml`, add it manually (see `homeassistant/configuration.yaml`).

4. **Port collisions are real.** HA also opens `1900/udp` (SSDP), `5353/udp` (mDNS), `21063/tcp`/`21064/tcp` (HomeKit Bridge if enabled), `40000+` ephemeral. Do not run `avahi-daemon` on the Pi (Raspberry Pi OS Lite doesn't by default) and don't run a second mDNS responder container in host mode.

5. **Bluetooth** needs `/run/dbus:/run/dbus:ro` (already mounted) and BlueZ on the host (`sudo apt install bluez`).

## Cloudflare tunnel: what is and isn't exposed

The tunnel is **outbound only**: `cloudflared` opens a connection to Cloudflare's edge and receives requests through it. Nothing on the router is forwarded; the Pi has zero inbound ports. Public hostnames are mapped to *origins* that cloudflared can reach from inside its container:

| Public hostname (Zero Trust → Networks → Tunnels → Public Hostname) | Origin | Notes |
| --- | --- | --- |
| `ha-mcp.<domain>` | `http://ha-mcp:8000` | bridge DNS works |
| `flaim.<domain>` / `bike.<domain>` | `http://flaim-mcp:8790` / `http://citibike-mcp:8002` | `flaim-mcp` is the container name and a network alias of the `flaim` service |
| `ha.<domain>` *(optional, off by default)* | `http://host.docker.internal:8123` | **not** `http://homeassistant:8123` once HA is host-networked |

### Should HA itself be published through the tunnel?

Default here: **no**. The MCP bridge is what remote clients (Poke, Claude, ChatGPT) talk to, and it reaches HA locally. Use a VPN (Tailscale/WireGuard) or the LAN for the HA UI.

If you do publish `ha.<domain>`:

- Put a **Cloudflare Access** policy (email OTP / IdP) in front of it. The HA Companion app and many integrations cannot pass an Access login page — for those, prefer a VPN, or add an Access *service token* bypass only for specific paths you understand.
- Cloudflare proxies WebSockets (the HA frontend needs them); keep *WebSockets* enabled in the zone.
- Free-plan request body limit is 100 MB: backup downloads and large media uploads through the tunnel fail. Use the LAN for those.
- HA must trust the proxy (already configured) and you should enable MFA on every HA user (*Profile → Security*).
- The `http.trusted_proxies` list must include the bridge range cloudflared lives on. If you move cloudflared to host networking too, add `127.0.0.1` (already present) and `::1`.

### Host networking does **not** make HA public

A common worry: "host networking exposes HA to the internet". It doesn't. Host networking binds HA to the Pi's interfaces; the Pi has no inbound port forwarding, and the tunnel only forwards hostnames you configure. Exposure is decided by (a) your router (no forwards), (b) the tunnel's public-hostname list, (c) UFW on the Pi. Keep all three tight and HA is LAN/VPN-only despite `network_mode: host`.

## Quick checks

```sh
docker inspect homeassistant --format '{{.HostConfig.NetworkMode}}'      # host
ss -ltnp | grep 8123                                                       # python3 listening on *:8123
docker compose exec ha-mcp \
  python -c "import urllib.request;print(urllib.request.urlopen('http://host.docker.internal:8123/').status)"   # 200/302
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8123/api/        # 401 (needs token) = HTTP up
avahi-browse -art 2>/dev/null | head    # optional: see mDNS traffic HA sees (apt install avahi-utils)
```
