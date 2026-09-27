#!/usr/bin/env python3
"""Discover the Home Assistant entities ha-device-mcp needs and emit its env fragment.

Standard library only. Talks to HA's REST API with the LLAT from $HA_LONG_LIVED_ACCESS_TOKEN
or ./.env, mirrors the discovery rules in acyounk28/ha-device-mcp (entities.py) and writes:

  * ha-device-mcp.entities.env  -- paste/append into ./.env
  * entities.json               -- full candidate list per role (with --json)

    scripts/export_entities.py                     # print report + write ha-device-mcp.entities.env
    scripts/export_entities.py --json entities.json
    scripts/export_entities.py --merge-into .env   # update *_ENTITY_ID keys in place
    scripts/export_entities.py --windmill fan.windmill_ac               # pin a fan entity explicitly

Roles and how they are resolved (identical to ha-device-mcp, except oasis_light):

  role                integration        domain         suffix        env var
  oasis_light         oasis              light.         (none)        OASIS_LIGHT_ENTITY_ID
                      (Oasis Lighting via longweekendprojects/oasis-lights. ha-device-mcp itself
                       still auto-discovers integration_entities('oasis_mini') light.*_led -- the
                       Oasis Mini sand table -- so OASIS_LIGHT_ENTITY_ID must always be pinned;
                       this script does that when exactly one Oasis light exists.)
  pura_nightlight     pura               light.         _nightlight   PURA_NIGHTLIGHT_ENTITY_ID
  pura_fragrance      pura               select.        _fragrance    PURA_FRAGRANCE_SELECT_ENTITY_ID
  pura_intensity      pura               select.       _intensity    PURA_INTENSITY_SELECT_ENTITY_ID
  hatch_light         ha_hatch           light.         _light        HATCH_LIGHT_ENTITY_ID
  hatch_media_player  ha_hatch           media_player.  _media_player HATCH_MEDIA_PLAYER_ENTITY_ID
  hatch_power_switch  ha_hatch           switch.        _power_switch HATCH_POWER_SWITCH_ENTITY_ID
  windmill_fan        (no auto-discovery in ha-device-mcp; this script looks at fan.* from
                       homekit_controller / tuya / tuya_local / template)         WINDMILL_FAN_ENTITY_ID

Exactly one candidate -> the env var is set. Zero -> commented hint. Several -> all listed,
commented, for you to pick (ha-device-mcp raises entity_ambiguous otherwise).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


@dataclass(frozen=True)
class Role:
    name: str
    env: str
    integrations: tuple[str, ...]
    domain: str
    suffix: str
    device_doc: str


ROLES: tuple[Role, ...] = (
    Role("oasis_light", "OASIS_LIGHT_ENTITY_ID", ("oasis",), "light.", "", "docs/devices/oasis-lighting.md"),
    Role("pura_nightlight", "PURA_NIGHTLIGHT_ENTITY_ID", ("pura",), "light.", "_nightlight", "docs/devices/pura.md"),
    Role("pura_fragrance", "PURA_FRAGRANCE_SELECT_ENTITY_ID", ("pura",), "select.", "_fragrance", "docs/devices/pura.md"),
    Role("pura_intensity", "PURA_INTENSITY_SELECT_ENTITY_ID", ("pura",), "select.", "_intensity", "docs/devices/pura.md"),
    Role("hatch_light", "HATCH_LIGHT_ENTITY_ID", ("ha_hatch",), "light.", "_light", "docs/devices/hatch.md"),
    Role("hatch_media_player", "HATCH_MEDIA_PLAYER_ENTITY_ID", ("ha_hatch",), "media_player.", "_media_player", "docs/devices/hatch.md"),
    Role("hatch_power_switch", "HATCH_POWER_SWITCH_ENTITY_ID", ("ha_hatch",), "switch.", "_power_switch", "docs/devices/hatch.md"),
    Role("windmill_fan", "WINDMILL_FAN_ENTITY_ID", ("homekit_controller", "tuya", "tuya_local", "template"), "fan.", "", "docs/devices/windmill.md"),
)


def load_dotenv(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if path.is_file():
        for line in path.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                values[k.strip()] = v.strip().strip('"').strip("'")
    return values


class HA:
    def __init__(self, url: str, token: str):
        self.url = url.rstrip("/")
        self.token = token

    def _req(self, path: str, data: dict | None = None) -> object:
        body = json.dumps(data).encode() if data is not None else None
        req = urllib.request.Request(
            self.url + path,
            data=body,
            headers={"Authorization": f"Bearer {self.token}", "Content-Type": "application/json"},
            method="POST" if body else "GET",
        )
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                raw = resp.read().decode()
        except urllib.error.HTTPError as err:
            detail = err.read().decode(errors="replace")[:300]
            if err.code == 401:
                raise SystemExit("401 from Home Assistant: HA_LONG_LIVED_ACCESS_TOKEN is missing/invalid. Run scripts/ha_token.py verify")
            raise SystemExit(f"{path} -> HTTP {err.code}: {detail}")
        except urllib.error.URLError as err:
            raise SystemExit(f"cannot reach {self.url}: {err.reason}")
        try:
            return json.loads(raw)
        except ValueError:
            return raw

    def template(self, tpl: str) -> object:
        out = self._req("/api/template", {"template": tpl})
        if isinstance(out, str):
            try:
                return json.loads(out)
            except ValueError:
                return out
        return out

    def integration_entities(self, integration: str) -> list[str]:
        out = self.template(f"{{{{ integration_entities('{integration}') | to_json }}}}")
        return sorted(out) if isinstance(out, list) else []

    def states(self) -> dict[str, dict]:
        return {s["entity_id"]: s for s in self._req("/api/states")}

    def config(self) -> dict:
        cfg = self._req("/api/config")
        return cfg if isinstance(cfg, dict) else {}


def discover(ha: HA, states: dict[str, dict], overrides: dict[str, str]) -> dict[str, dict]:
    result: dict[str, dict] = {}
    cache: dict[str, list[str]] = {}
    for role in ROLES:
        if role.name in overrides:
            cands = [overrides[role.name]]
        else:
            cands = []
            for integ in role.integrations:
                if integ not in cache:
                    cache[integ] = ha.integration_entities(integ)
                cands += [e for e in cache[integ] if e.startswith(role.domain) and (not role.suffix or e.endswith(role.suffix))]
            cands = sorted(set(cands))
        result[role.name] = {
            "env": role.env,
            "integrations": list(role.integrations),
            "candidates": cands,
            "states": {e: {"state": states.get(e, {}).get("state", "missing"), "friendly_name": states.get(e, {}).get("attributes", {}).get("friendly_name")} for e in cands},
            "loaded": {integ: bool(cache.get(integ)) for integ in role.integrations} if role.name not in overrides else {},
            "doc": role.device_doc,
        }
    return result


def render_env(found: dict[str, dict]) -> str:
    lines = ["# Generated by pi-homelab-setup/scripts/export_entities.py -- entity IDs for acyounk28/ha-device-mcp.",
             "# Set/omitted keys follow ha-device-mcp discovery rules; commented keys need a manual choice.", ""]
    for role in ROLES:
        info = found[role.name]
        cands = info["candidates"]
        if len(cands) == 1:
            lines.append(f"{role.env}={cands[0]}")
        elif not cands:
            integ = "/".join(role.integrations)
            lines.append(f"# {role.env}=   # no {role.domain}*{role.suffix} entity from {integ}; see {info['doc']}")
        else:
            lines.append(f"# {role.env}=   # AMBIGUOUS, pick one:")
            for c in cands:
                lines.append(f"#   {role.env}={c}   # {info['states'][c]['friendly_name']} ({info['states'][c]['state']})")
    return "\n".join(lines) + "\n"


def merge_env(path: Path, found: dict[str, dict]) -> list[str]:
    lines = path.read_text().splitlines() if path.is_file() else []
    changed: list[str] = []
    for role in ROLES:
        cands = found[role.name]["candidates"]
        if len(cands) != 1:
            continue
        new = f"{role.env}={cands[0]}"
        pat = re.compile(rf"^\s*#?\s*{re.escape(role.env)}=")
        for i, line in enumerate(lines):
            if pat.match(line):
                if line.strip() != new:
                    lines[i] = new
                    changed.append(role.env)
                break
        else:
            lines.append(new)
            changed.append(role.env)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text("\n".join(lines) + "\n")
    os.chmod(tmp, 0o600)
    tmp.replace(path)
    return changed


def main(argv: list[str] | None = None) -> int:
    dotenv = load_dotenv(ROOT / ".env")
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--ha-url", default=os.environ.get("HA_URL") or dotenv.get("HA_URL") or "http://127.0.0.1:8123")
    p.add_argument("--token", default=None, help="LLAT (default: $HA_LONG_LIVED_ACCESS_TOKEN or ./.env)")
    p.add_argument("--out", default=str(ROOT / "ha-device-mcp.entities.env"), help="env fragment path ('-' for stdout only)")
    p.add_argument("--json", metavar="FILE", help="also dump the full discovery result as JSON")
    p.add_argument("--merge-into", metavar="ENV_FILE", help="update *_ENTITY_ID keys in an existing .env (e.g. ./.env)")
    for role in ROLES:
        p.add_argument(f"--{role.name.replace('_', '-')}", dest=role.name, metavar="ENTITY_ID", help=f"override {role.env}")
    p.add_argument("--windmill", dest="windmill_fan", metavar="ENTITY_ID", help="alias for --windmill-fan")
    args = p.parse_args(argv)

    token = args.token or os.environ.get("HA_LONG_LIVED_ACCESS_TOKEN") or dotenv.get("HA_LONG_LIVED_ACCESS_TOKEN", "")
    if not token or token.startswith("replace-with"):
        raise SystemExit("no HA_LONG_LIVED_ACCESS_TOKEN; run scripts/ha_token.py create --write-env .env first")
    overrides = {}
    for role in ROLES:
        val = getattr(args, role.name)
        if val:
            if not re.fullmatch(r"[a-z0-9_]+\.[a-z0-9_]+", val) or not val.startswith(role.domain):
                raise SystemExit(f"--{role.name.replace('_', '-')} must look like {role.domain}<lowercase_name>")
            overrides[role.name] = val

    ha = HA(args.ha_url, token)
    cfg = ha.config()
    states = ha.states()
    found = discover(ha, states, overrides)

    print(f"Home Assistant {cfg.get('version', '?')} at {ha.url}  ({len(states)} entities)\n")
    print(f"{'role':<20} {'result':<45} note")
    for role in ROLES:
        info = found[role.name]
        cands = info["candidates"]
        if len(cands) == 1:
            st = info["states"][cands[0]]
            note = f"state={st['state']}" + (" (entity missing from /api/states!)" if st["state"] == "missing" else "")
            print(f"{role.name:<20} {cands[0]:<45} {note}")
        elif not cands:
            unloaded = [i for i, ok in info["loaded"].items() if not ok]
            note = "integration not set up: " + ", ".join(unloaded) if unloaded and len(unloaded) == len(role.integrations) else f"no {role.domain}*{role.suffix} entity"
            print(f"{role.name:<20} {'-':<45} {note} -> {info['doc']}")
        else:
            print(f"{role.name:<20} {'AMBIGUOUS':<45} {', '.join(cands)}")
    missing_state = [e for r in found.values() for e in r["candidates"] if r["states"][e]["state"] == "missing"]
    if missing_state:
        print(f"\nwarning: configured/overridden entities not present in HA: {', '.join(missing_state)}")

    env_text = render_env(found)
    if args.out == "-":
        print("\n" + env_text)
    else:
        out = Path(args.out)
        out.write_text(env_text)
        os.chmod(out, 0o600)
        print(f"\nwrote {out}")
    if args.json:
        Path(args.json).write_text(json.dumps(found, indent=2) + "\n")
        print(f"wrote {args.json}")
    if args.merge_into:
        changed = merge_env(Path(args.merge_into), found)
        print(f"updated {args.merge_into}: {', '.join(changed) if changed else 'no changes'}")
        print("restart the bridge: docker compose up -d ha-mcp")
    return 0


if __name__ == "__main__":
    sys.exit(main())
