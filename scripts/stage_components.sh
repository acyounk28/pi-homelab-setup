#!/usr/bin/env bash
# Pre-stage HACS and the custom components listed in homeassistant/custom_components.txt
# into <HA_CONFIG_DIR>/custom_components/. Idempotent; existing folders are
# replaced only with --force (HACS-managed upgrades are otherwise left alone).
#
# Usage: scripts/stage_components.sh [--force] [--no-hacs] [--only <domain>]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_CONFIG_DIR="${HA_CONFIG_DIR:-}"   # explicit env wins over .env
# shellcheck disable=SC1091
[ -f "$REPO_ROOT/.env" ] && set -a && . "$REPO_ROOT/.env" && set +a
HA_CONFIG_DIR="${ENV_CONFIG_DIR:-${HA_CONFIG_DIR:-$REPO_ROOT/config/homeassistant}}"
case "$HA_CONFIG_DIR" in /*) ;; *) HA_CONFIG_DIR="$REPO_ROOT/$HA_CONFIG_DIR" ;; esac
MANIFEST="${COMPONENTS_MANIFEST:-$REPO_ROOT/homeassistant/custom_components.txt}"
CC_DIR="$HA_CONFIG_DIR/custom_components"
CACHE="$REPO_ROOT/.cache"
FORCE=0; WITH_HACS=1; ONLY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1 ;;
    --no-hacs) WITH_HACS=0 ;;
    --only) ONLY="$2"; shift ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

log() { printf '\033[1;34m[stage]\033[0m %s\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
need curl; need tar; need unzip

mkdir -p "$CC_DIR" "$CACHE"

# GitHub API helper. Unauthenticated limit is 60 req/h; export GITHUB_TOKEN to raise it.
gh_api() {
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "$@"
  else
    curl -fsSL -H "Accept: application/vnd.github+json" "$@"
  fi
}

latest_ref() { # owner/repo -> release tag, else default branch
  local repo="$1" tag=""
  # The /releases/latest redirect needs no API quota (the API allows only 60
  # anonymous requests/hour, which a shared IP exhausts quickly).
  tag="$(curl -fsSI -o /dev/null -w '%{redirect_url}' "https://github.com/$repo/releases/latest" 2>/dev/null | sed -n 's#.*/releases/tag/\([^/?]*\).*#\1#p')"
  if [ -z "$tag" ]; then
    tag="$(gh_api "https://api.github.com/repos/$repo" 2>/dev/null | sed -n 's/.*"default_branch": *"\([^"]*\)".*/\1/p' | head -1 || true)"
  fi
  if [ -z "$tag" ] && command -v git >/dev/null; then
    tag="$(git ls-remote --symref "https://github.com/$repo.git" HEAD 2>/dev/null | sed -n 's#^ref: refs/heads/\([^[:space:]]*\).*#\1#p' | head -1)"
  fi
  [ -n "$tag" ] || { echo "could not resolve ref for $repo (no release, and default branch lookup failed)" >&2; return 1; }
  printf '%s' "$tag"
}

install_hacs() {
  local dest="$CC_DIR/hacs"
  if [ -d "$dest" ] && [ "$FORCE" -eq 0 ]; then log "hacs already present (use --force to replace)"; return; fi
  log "downloading HACS (hacs/integration latest release)"
  curl -fsSL -o "$CACHE/hacs.zip" "https://github.com/hacs/integration/releases/latest/download/hacs.zip"
  rm -rf "$dest.tmp" "$dest"; mkdir -p "$dest.tmp"
  unzip -q -o "$CACHE/hacs.zip" -d "$dest.tmp"
  mv "$dest.tmp" "$dest"
  log "hacs -> $dest ($(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$dest/manifest.json" | head -1))"
}

install_component() { # owner/repo domain ref
  local repo="$1" domain="$2" ref="$3" dest="$CC_DIR/$2" tmp
  if [ -n "$ONLY" ] && [ "$ONLY" != "$domain" ]; then return; fi
  if [ -d "$dest" ] && [ "$FORCE" -eq 0 ]; then log "$domain already present (use --force to replace)"; return; fi
  [ "$ref" = "latest" ] && ref="$(latest_ref "$repo")"
  log "downloading $repo@$ref"
  tmp="$(mktemp -d "$CACHE/${domain}.XXXX")"
  local src=""
  # Prefer the HACS-style release asset <domain>.zip (carries the real version
  # in manifest.json); fall back to the source tarball.
  if curl -fsSL -o "$tmp/$domain.zip" "https://github.com/$repo/releases/download/$ref/$domain.zip" 2>/dev/null; then
    mkdir -p "$tmp/custom_components/$domain"
    unzip -q -o "$tmp/$domain.zip" -d "$tmp/custom_components/$domain"
    src="$tmp/custom_components/$domain"
  else
    curl -fsSL "https://github.com/$repo/archive/$ref.tar.gz" | tar -xz -C "$tmp"
    src="$(find "$tmp" -maxdepth 3 -type d -path "*/custom_components/$domain" | head -1)"
  fi
  [ -n "$src" ] || { echo "custom_components/$domain not found in $repo@$ref" >&2; rm -rf "$tmp"; exit 1; }
  rm -rf "$dest"; mv "$src" "$dest"; rm -rf "$tmp"
  log "$domain -> $dest ($(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$dest/manifest.json" | head -1))"
}

[ "$WITH_HACS" -eq 1 ] && [ -z "$ONLY" ] && install_hacs

while read -r repo domain ref _; do
  case "$repo" in ''|\#*) continue ;; esac
  install_component "$repo" "$domain" "${ref:-latest}"
done < "$MANIFEST"

# HA runs as root in the container; make sure the host user can still edit.
if [ "$(id -u)" -ne 0 ] && [ ! -w "$CC_DIR" ]; then
  echo "note: $CC_DIR is not writable by $(id -un); run with sudo or chown it" >&2
fi
log "done. Restart Home Assistant to load new components: docker compose restart homeassistant"
