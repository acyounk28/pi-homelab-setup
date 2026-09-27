#!/usr/bin/env bash
# Start Home Assistant before the MCP services and tunnel.
# Usage: scripts/start-all.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HA_DIR="$(dirname "$ROOT")/homeassistant-service"
WAIT_SECONDS=300

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v docker >/dev/null 2>&1 || die "Docker is required"
docker compose version >/dev/null 2>&1 || die "Docker Compose is required"
command -v curl >/dev/null 2>&1 || die "curl is required to check Home Assistant readiness"
[ -f "$ROOT/docker-compose.yml" ] || die "missing $ROOT/docker-compose.yml"

cd "$ROOT"
service_list="$(docker compose -f docker-compose.yml config --services)" || die "check the Compose configuration and .env in $ROOT"
[ -n "$service_list" ] || die "no services found in $ROOT/docker-compose.yml"
mapfile -t services <<< "$service_list"

if [ -f "$HA_DIR/docker-compose.yml" ]; then
  echo "Starting Home Assistant from $HA_DIR"
  if ! (cd "$HA_DIR" && docker compose -f docker-compose.yml up -d --wait --wait-timeout "$WAIT_SECONDS"); then
    (cd "$HA_DIR" && docker compose -f docker-compose.yml ps --all) || true
    die "Home Assistant failed to start from $HA_DIR"
  fi
  ha_project="$HA_DIR"
else
  if [ -d "$HA_DIR" ]; then
    printf 'Skipping %s: no docker-compose.yml; using the included Home Assistant service\n' "$HA_DIR" >&2
  fi
  echo "Starting Home Assistant from $ROOT"
  if ! docker compose -f docker-compose.yml up -d --wait --wait-timeout "$WAIT_SECONDS" homeassistant; then
    docker compose -f docker-compose.yml ps --all || true
    die "Home Assistant failed to start from $ROOT"
  fi
  ha_project="$ROOT"
fi

echo "Waiting for Home Assistant on http://127.0.0.1:8123/"
deadline=$((SECONDS + WAIT_SECONDS))
until curl --fail --silent --output /dev/null --max-time 3 http://127.0.0.1:8123/; do
  if (( SECONDS >= deadline )); then
    (cd "$ha_project" && docker compose -f docker-compose.yml ps --all) || true
    die "Home Assistant did not become reachable on port 8123 within ${WAIT_SECONDS}s"
  fi
  sleep 3
done

bridge_services=()
for service in "${services[@]}"; do
  if [ "$service" != homeassistant ]; then
    bridge_services+=("$service")
  fi
done

if [ "${#bridge_services[@]}" -gt 0 ]; then
  echo "Starting homelab services: ${bridge_services[*]}"
  if ! docker compose -f docker-compose.yml up -d --wait --wait-timeout "$WAIT_SECONDS" "${bridge_services[@]}"; then
    docker compose -f docker-compose.yml ps --all || true
    die "homelab services failed to start or become healthy"
  fi
fi

echo "Home Assistant status ($ha_project):"
(cd "$ha_project" && docker compose -f docker-compose.yml ps --all)
if [ "$ha_project" != "$ROOT" ]; then
  echo "Homelab service status ($ROOT):"
  docker compose -f docker-compose.yml ps --all
fi
