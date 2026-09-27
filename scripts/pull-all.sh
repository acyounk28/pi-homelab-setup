#!/usr/bin/env bash
# Clone or fast-forward all core homelab repositories as siblings of this repo.
#
# Usage:
#   scripts/pull-all.sh [options]
#
# Options:
#   -d, --dir <path>      parent directory holding the repos
#                         (default: $HOMELAB_ROOT, else the parent of this checkout)
#   -p, --protocol <p>    ssh | https  (default: $HOMELAB_GIT_PROTOCOL, else auto:
#                         match the remote style of this checkout, falling back to https)
#   -n, --dry-run         print what would run without touching anything
#   -h, --help            show this help
#
# Existing repos are updated with `git pull --ff-only` on their current branch;
# missing ones are cloned. Repos with local changes or a diverged branch are
# reported and skipped, never rewritten.
set -euo pipefail

REPOS=(
  pi-homelab-setup
  homeassistant-service
  ha-device-mcp
  flaim
  citibike-lookup
)
GITHUB_OWNER="${HOMELAB_GITHUB_OWNER:-acyounk28}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="${HOMELAB_ROOT:-$(dirname "$SELF_REPO")}"
PROTOCOL="${HOMELAB_GIT_PROTOCOL:-auto}"
DRY_RUN=0

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
}
info()  { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()    { printf '  %s[ok]%s   %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '  %s[skip]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
fail()  { printf '  %s[fail]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()   { printf '%serror:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -d|--dir) [ $# -ge 2 ] || die "--dir requires a value"; ROOT="$2"; shift 2 ;;
    --dir=*) ROOT="${1#--dir=}"; shift ;;
    -p|--protocol) [ $# -ge 2 ] || die "--protocol requires a value"; PROTOCOL="$2"; shift 2 ;;
    --protocol=*) PROTOCOL="${1#--protocol=}"; shift ;;
    -n|--dry-run) DRY_RUN=1; shift ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

command -v git >/dev/null 2>&1 || die "git is required"

# Resolve auto protocol from the remote of this checkout (or any sibling).
if [ "$PROTOCOL" = "auto" ]; then
  PROTOCOL=https
  for candidate in "$SELF_REPO" "$ROOT"/*; do
    [ -d "$candidate/.git" ] || continue
    url="$(git -C "$candidate" remote get-url origin 2>/dev/null || true)"
    case "$url" in
      git@github.com:*|ssh://git@github.com/*) PROTOCOL=ssh; break ;;
      https://github.com/*) PROTOCOL=https; break ;;
    esac
  done
fi
case "$PROTOCOL" in
  ssh|https) ;;
  *) die "protocol must be ssh or https (got: $PROTOCOL)" ;;
esac

repo_url() {
  if [ "$PROTOCOL" = "ssh" ]; then
    printf 'git@github.com:%s/%s.git' "$GITHUB_OWNER" "$1"
  else
    printf 'https://github.com/%s/%s.git' "$GITHUB_OWNER" "$1"
  fi
}

run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '  %s$ %s%s\n' "$C_DIM" "$*" "$C_RESET"
  else
    "$@"
  fi
}

mkdir -p "$ROOT"
ROOT="$(cd "$ROOT" && pwd)"
info "Syncing ${#REPOS[@]} repos in ${C_BOLD}${ROOT}${C_RESET} (${PROTOCOL} remotes)"
[ "$DRY_RUN" = 1 ] && warn "dry run: no changes will be made"

updated=0; cloned=0; skipped=0; failed=0
for name in "${REPOS[@]}"; do
  dir="$ROOT/$name"
  url="$(repo_url "$name")"
  printf '%s%s%s\n' "$C_BOLD" "$name" "$C_RESET"

  if [ -d "$dir/.git" ]; then
    if [ -n "$(git -C "$dir" status --porcelain --untracked-files=no)" ]; then
      warn "local changes present; commit or stash them, then re-run"
      skipped=$((skipped + 1)); continue
    fi
    if ! branch="$(git -C "$dir" symbolic-ref --short -q HEAD)"; then
      warn "detached HEAD; check out a branch, then re-run"
      skipped=$((skipped + 1)); continue
    fi
    if ! git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
      warn "branch '$branch' has no upstream; set one with: git branch -u origin/$branch"
      skipped=$((skipped + 1)); continue
    fi
    before="$(git -C "$dir" rev-parse --short HEAD)"
    if run git -C "$dir" pull --ff-only --quiet; then
      after="$(git -C "$dir" rev-parse --short HEAD)"
      if [ "$before" = "$after" ]; then
        ok "$branch already up to date ($after)"
      else
        ok "$branch fast-forwarded $before -> $after"
      fi
      updated=$((updated + 1))
    else
      fail "pull --ff-only failed on '$branch' (diverged from upstream or network error)"
      failed=$((failed + 1))
    fi
  elif [ -e "$dir" ]; then
    warn "$dir exists but is not a git repository"
    skipped=$((skipped + 1))
  else
    if run git clone --quiet "$url" "$dir"; then
      ok "cloned from $url"
      cloned=$((cloned + 1))
    else
      fail "clone failed from $url"
      failed=$((failed + 1))
    fi
  fi
done

echo
info "Done: ${C_GREEN}${updated} updated${C_RESET}, ${C_GREEN}${cloned} cloned${C_RESET}, ${C_YELLOW}${skipped} skipped${C_RESET}, ${C_RED}${failed} failed${C_RESET}"
[ "$failed" -eq 0 ]
