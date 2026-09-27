#!/usr/bin/env bash
# One-shot bootstrap for Home Assistant on the Pi:
#   1. checks Docker / Compose / architecture
#   2. creates .env from .env.example if missing
#   3. initialises the config volume (configuration.yaml, packages/, empty
#      automations/scripts/scenes, trusted proxies)
#   4. downloads HACS and pre-stages the custom components in
#      homeassistant/custom_components.txt
#   5. pulls the image and (unless --no-start) starts the container
#
# Safe to re-run: never overwrites an existing configuration.yaml or .env.
#
# Usage: scripts/install-homeassistant.sh [--no-start] [--no-components] [--force-components]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
START=1; COMPONENTS=1; STAGE_ARGS=()
for a in "$@"; do
  case "$a" in
    --no-start) START=0 ;;
    --no-components) COMPONENTS=0 ;;
    --force-components) STAGE_ARGS+=(--force) ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown arg: $a" >&2; exit 2 ;;
  esac
done

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[install]\033[0m %s\n' "$*" >&2; exit 1; }

# --- 1. prerequisites -------------------------------------------------------
command -v docker >/dev/null || die "docker not installed: https://docs.docker.com/engine/install/debian/"
docker compose version >/dev/null 2>&1 || die "docker compose plugin missing (apt install docker-compose-plugin)"
if ! docker info >/dev/null 2>&1; then
  die "cannot talk to the Docker daemon; add yourself to the docker group (sudo usermod -aG docker \$USER; re-login) or run with sudo"
fi
ARCH="$(uname -m)"
case "$ARCH" in
  aarch64|arm64) ;;
  *) warn "architecture is $ARCH, not arm64; the image is multi-arch so this still works, but the Pi 5 target is arm64" ;;
esac
if [ -r /proc/device-tree/model ]; then log "host: $(tr -d '\0' </proc/device-tree/model)"; fi

# --- 2. .env ---------------------------------------------------------------
if [ ! -f .env ]; then
  cp .env.example .env && chmod 600 .env
  log "created .env from .env.example (edit TZ if not America/New_York)"
else
  chmod 600 .env 2>/dev/null || true
fi
ENV_CONFIG_DIR="${HA_CONFIG_DIR:-}"
set -a; . ./.env; set +a
HA_CONFIG_DIR="${ENV_CONFIG_DIR:-${HA_CONFIG_DIR:-./config/homeassistant}}"
case "$HA_CONFIG_DIR" in /*) ;; *) HA_CONFIG_DIR="$REPO_ROOT/${HA_CONFIG_DIR#./}" ;; esac
TZ_VALUE="${TZ:-America/New_York}"
if [ ! -f "/usr/share/zoneinfo/$TZ_VALUE" ]; then warn "TZ=$TZ_VALUE is not a known zoneinfo name"; fi

# --- 3. config volume -------------------------------------------------------
mkdir -p "$HA_CONFIG_DIR/packages" "$HA_CONFIG_DIR/custom_components"
for f in automations.yaml scripts.yaml scenes.yaml; do
  [ -f "$HA_CONFIG_DIR/$f" ] || echo "[]" > "$HA_CONFIG_DIR/$f"
done
if [ ! -f "$HA_CONFIG_DIR/configuration.yaml" ]; then
  proxies=""
  IFS=',' read -ra cidrs <<< "${HA_TRUSTED_PROXIES:-172.16.0.0/12,127.0.0.1}"
  for c in "${cidrs[@]}"; do
    c="$(echo "$c" | xargs)"; [ -n "$c" ] && proxies+="    - $c"$'\n'
  done
  # Replace the placeholder line with the generated list.
  awk -v repl="${proxies%$'\n'}" '$0=="__TRUSTED_PROXIES__"{print repl; next}{print}' \
    homeassistant/configuration.yaml > "$HA_CONFIG_DIR/configuration.yaml"
  log "wrote $HA_CONFIG_DIR/configuration.yaml (trusted_proxies: ${HA_TRUSTED_PROXIES:-172.16.0.0/12,127.0.0.1})"
else
  log "keeping existing $HA_CONFIG_DIR/configuration.yaml"
  if ! grep -q "trusted_proxies" "$HA_CONFIG_DIR/configuration.yaml"; then
    warn "existing configuration.yaml has no http.trusted_proxies; add the block from homeassistant/configuration.yaml if HA will sit behind cloudflared"
  fi
fi
[ -f "$HA_CONFIG_DIR/.gitkeep" ] || : > "$HA_CONFIG_DIR/.gitkeep"

# --- 4. HACS + custom components ------------------------------------------
if [ "$COMPONENTS" -eq 1 ]; then
  HA_CONFIG_DIR="$HA_CONFIG_DIR" bash scripts/stage_components.sh "${STAGE_ARGS[@]}"
fi

# --- 5. image + start -------------------------------------------------------
log "validating compose file"
docker compose config -q
log "pulling ${HA_IMAGE:-ghcr.io/home-assistant/home-assistant}:${HA_VERSION:-stable}"
docker compose pull -q homeassistant
if [ "$START" -eq 1 ]; then
  docker compose up -d homeassistant
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  log "Home Assistant starting (first boot on a Pi takes 2-5 min). Follow with: docker compose logs -f homeassistant"
  log "Onboard at http://${ip:-<pi-ip>}:8123 from a device on the same LAN, then run scripts/ha_token.py"
else
  log "skipped start (--no-start). Run: docker compose up -d"
fi
