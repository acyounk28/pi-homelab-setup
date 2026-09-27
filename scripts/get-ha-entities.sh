#!/usr/bin/env bash
# List Home Assistant entity IDs (climate, fan, light, switch, sensor) via the
# REST API, so they can be copied into .env for ha-device-mcp.
#
# Usage:
#   scripts/get-ha-entities.sh <long-lived-access-token> [ha-url]
#   HA_LONG_LIVED_ACCESS_TOKEN=... scripts/get-ha-entities.sh [ha-url]
#
#   ha-url defaults to $HA_URL if set, otherwise http://localhost:8123.
#
# Options:
#   -d, --domains a,b,c   comma-separated domains to include
#                         (default: climate,fan,light,switch,sensor)
#   -h, --help            show this help
#
# The token is only ever sent in the Authorization header; it is never echoed.
set -euo pipefail

DEFAULT_DOMAINS="climate,fan,light,switch,sensor"
DOMAINS="$DEFAULT_DOMAINS"

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
}

die() {
  echo "error: $*" >&2
  exit 1
}

POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -d|--domains)
      [ $# -ge 2 ] || die "--domains requires a value"
      DOMAINS="$2"; shift 2 ;;
    --domains=*) DOMAINS="${1#--domains=}"; shift ;;
    -*) die "unknown option: $1 (see --help)" ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done

TOKEN=""
URL=""
case "${#POSITIONAL[@]}" in
  0) TOKEN="${HA_LONG_LIVED_ACCESS_TOKEN:-}" ;;
  1)
    # Single arg: a URL if it looks like one, otherwise the token.
    if [[ "${POSITIONAL[0]}" =~ ^https?:// ]]; then
      URL="${POSITIONAL[0]}"; TOKEN="${HA_LONG_LIVED_ACCESS_TOKEN:-}"
    else
      TOKEN="${POSITIONAL[0]}"
    fi ;;
  2) TOKEN="${POSITIONAL[0]}"; URL="${POSITIONAL[1]}" ;;
  *) die "too many arguments (see --help)" ;;
esac

[ -n "$TOKEN" ] || die "missing Home Assistant Long-Lived Access Token (pass it as the first argument or set HA_LONG_LIVED_ACCESS_TOKEN)"
URL="${URL:-${HA_URL:-http://localhost:8123}}"
URL="${URL%/}"
[[ "$URL" =~ ^https?:// ]] || die "HA URL must start with http:// or https:// (got: $URL)"

command -v curl >/dev/null 2>&1 || die "curl is required"
if command -v jq >/dev/null 2>&1; then
  PARSER=jq
elif command -v python3 >/dev/null 2>&1; then
  PARSER=python3
else
  die "jq or python3 is required to parse the API response"
fi

# Pass the token via a header file so it never appears in the process list.
HEADER_FILE="$(mktemp)"
trap 'rm -f "$HEADER_FILE"' EXIT
chmod 600 "$HEADER_FILE"
printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" > "$HEADER_FILE"

BODY="$(mktemp)"
trap 'rm -f "$HEADER_FILE" "$BODY"' EXIT

set +e
STATUS="$(curl -sS --max-time 15 -K "$HEADER_FILE" -H 'Accept: application/json' \
  -o "$BODY" -w '%{http_code}' "$URL/api/states")"
CURL_RC=$?
set -e

if [ "$CURL_RC" -ne 0 ]; then
  die "could not reach $URL (curl exit $CURL_RC). Is Home Assistant running and is the URL correct?"
fi
case "$STATUS" in
  200) ;;
  401|403) die "Home Assistant rejected the token (HTTP $STATUS). Create a new Long-Lived Access Token from your HA profile -> Security." ;;
  404) die "HTTP 404 from $URL/api/states - is this really a Home Assistant URL?" ;;
  *) die "unexpected HTTP $STATUS from $URL/api/states" ;;
esac

if [ "$PARSER" = jq ]; then
  jq -r --arg domains "$DOMAINS" '
    ($domains | split(",") | map(select(length > 0))) as $wanted
    | map(select((.entity_id | split(".")[0]) as $d | $wanted | index($d)))
    | sort_by(.entity_id)
    | .[]
    | [.entity_id, (.state // "unknown"), (.attributes.friendly_name // "")]
    | @tsv' "$BODY"
else
  python3 - "$DOMAINS" "$BODY" <<'PY'
import json, sys
wanted = [d for d in sys.argv[1].split(",") if d]
with open(sys.argv[2], encoding="utf-8") as fh:
    states = json.load(fh)
rows = [s for s in states if s.get("entity_id", "").split(".")[0] in wanted]
for s in sorted(rows, key=lambda s: s["entity_id"]):
    name = (s.get("attributes") or {}).get("friendly_name", "")
    print(f"{s['entity_id']}\t{s.get('state', 'unknown')}\t{name}")
PY
fi | awk -F '\t' -v domains="$DOMAINS" '
  BEGIN { n = 0 }
  {
    split($1, parts, ".")
    domain = parts[1]
    if (domain != last) {
      if (n > 0) print ""
      printf "== %s ==\n", domain
      last = domain
    }
    printf "  %-45s  state=%-12s  %s\n", $1, $2, $3
    n++
  }
  END {
    if (n == 0) {
      printf "No entities found for domains: %s\n", domains
      printf "Add integrations in Home Assistant (Settings -> Devices & services) and re-run.\n"
    } else {
      printf "\n%d entities (domains: %s)\n", n, domains
    }
  }'
