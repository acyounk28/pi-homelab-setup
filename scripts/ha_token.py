#!/usr/bin/env python3
"""Create, verify or revoke Home Assistant Long-Lived Access Tokens (LLATs).

Standard library only, so it runs on a bare Raspberry Pi OS python3.

    scripts/ha_token.py create  --name ha-device-mcp [--write-env FILE] [--print]
    scripts/ha_token.py verify  [--token-env HA_LONG_LIVED_ACCESS_TOKEN]
    scripts/ha_token.py list
    scripts/ha_token.py revoke  --name ha-device-mcp

`create` logs in with the HA username/password (prompted, never echoed, never
stored), opens the WebSocket API and calls `auth/long_lived_access_token`.
The token is shown ONCE unless --write-env is given, in which case it is
written to that file as HA_LONG_LIVED_ACCESS_TOKEN=... (mode 600) and not
printed. Accounts with multi-factor auth enabled must create the token in the
UI instead (Profile -> Security -> Long-lived access tokens).

HA_URL defaults to http://127.0.0.1:8123 (host networking on the Pi) or
the value in ./.env / $HA_URL.
"""

from __future__ import annotations

import argparse
import base64
import getpass
import json
import os
import re
import socket
import ssl
import struct
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

CLIENT_ID_PATH = "/"  # HA requires client_id to be a URL on the same origin


def load_dotenv(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        values[k.strip()] = v.strip().strip('"').strip("'")
    return values


def http_json(url: str, data: dict | None = None, token: str | None = None, form: bool = False) -> tuple[int, object]:
    body: bytes | None = None
    headers = {"Accept": "application/json"}
    if data is not None:
        if form:
            body = urllib.parse.urlencode(data).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            body = json.dumps(data).encode()
            headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, data=body, headers=headers, method="POST" if body is not None else "GET")
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as err:
        raw = err.read()
        try:
            return err.code, json.loads(raw)
        except ValueError:
            return err.code, raw.decode(errors="replace")


# --------------------------------------------------------------------------- auth
def login(ha_url: str, username: str, password: str) -> str:
    """Run the HA login flow and exchange the code for a short-lived access token."""
    client_id = ha_url.rstrip("/") + CLIENT_ID_PATH
    status, flow = http_json(f"{ha_url}/auth/login_flow", {"client_id": client_id, "handler": ["homeassistant", None], "redirect_uri": client_id})
    if status != 200 or not isinstance(flow, dict):
        raise SystemExit(f"login_flow init failed ({status}): {flow}")
    flow_id = flow["flow_id"]
    status, result = http_json(f"{ha_url}/auth/login_flow/{flow_id}", {"client_id": client_id, "username": username, "password": password})
    if status != 200 or not isinstance(result, dict):
        raise SystemExit(f"login_flow step failed ({status}): {result}")
    if result.get("type") == "form":
        if result.get("step_id") == "mfa":
            raise SystemExit("this account has MFA enabled; create the token in the HA UI (Profile -> Security) and use `verify`")
        errors = result.get("errors") or {}
        raise SystemExit(f"login rejected: {errors.get('base', result)}")
    if result.get("type") != "create_entry":
        raise SystemExit(f"unexpected login flow result: {result}")
    code = result["result"]
    status, tokens = http_json(f"{ha_url}/auth/token", {"grant_type": "authorization_code", "code": code, "client_id": client_id}, form=True)
    if status != 200 or not isinstance(tokens, dict):
        raise SystemExit(f"token exchange failed ({status}): {tokens}")
    return tokens["access_token"]


# --------------------------------------------------------------------------- minimal websocket client
class WS:
    def __init__(self, ha_url: str):
        u = urllib.parse.urlsplit(ha_url)
        secure = u.scheme == "https"
        port = u.port or (443 if secure else 80)
        raw = socket.create_connection((u.hostname, port), timeout=20)
        self.sock = ssl.create_default_context().wrap_socket(raw, server_hostname=u.hostname) if secure else raw
        key = base64.b64encode(os.urandom(16)).decode()
        req = (
            f"GET /api/websocket HTTP/1.1\r\nHost: {u.hostname}:{port}\r\nUpgrade: websocket\r\n"
            f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
        )
        self.sock.sendall(req.encode())
        head = b""
        while b"\r\n\r\n" not in head:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise SystemExit("websocket handshake: connection closed")
            head += chunk
        status_line = head.split(b"\r\n", 1)[0].decode()
        if " 101 " not in status_line:
            raise SystemExit(f"websocket handshake failed: {status_line}")
        self.buf = head.split(b"\r\n\r\n", 1)[1]

    def _read(self, n: int) -> bytes:
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise SystemExit("websocket closed")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def send(self, obj: dict) -> None:
        payload = json.dumps(obj).encode()
        mask = os.urandom(4)
        hdr = bytearray([0x81])
        n = len(payload)
        if n < 126:
            hdr.append(0x80 | n)
        elif n < 65536:
            hdr.append(0x80 | 126)
            hdr += struct.pack("!H", n)
        else:
            hdr.append(0x80 | 127)
            hdr += struct.pack("!Q", n)
        hdr += mask
        self.sock.sendall(bytes(hdr) + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))

    def recv(self) -> dict:
        while True:
            b0, b1 = self._read(2)
            opcode, n = b0 & 0x0F, b1 & 0x7F
            if n == 126:
                n = struct.unpack("!H", self._read(2))[0]
            elif n == 127:
                n = struct.unpack("!Q", self._read(8))[0]
            mask = self._read(4) if b1 & 0x80 else b""
            data = self._read(n)
            if mask:
                data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
            if opcode == 0x8:
                raise SystemExit("websocket closed by server")
            if opcode == 0x9:  # ping -> pong
                self.sock.sendall(bytes([0x8A, 0x80]) + b"\0\0\0\0")
                continue
            if opcode == 0x1:
                return json.loads(data)

    def close(self) -> None:
        try:
            self.sock.sendall(bytes([0x88, 0x80]) + b"\0\0\0\0")
        finally:
            self.sock.close()


def ws_session(ha_url: str, access_token: str) -> WS:
    ws = WS(ha_url)
    first = ws.recv()
    if first.get("type") != "auth_required":
        raise SystemExit(f"unexpected websocket greeting: {first}")
    ws.send({"type": "auth", "access_token": access_token})
    reply = ws.recv()
    if reply.get("type") != "auth_ok":
        raise SystemExit(f"websocket auth failed: {reply}")
    return ws


def ws_call(ws: WS, msg: dict, msg_id: int = 1) -> object:
    ws.send({"id": msg_id, **msg})
    while True:
        reply = ws.recv()
        if reply.get("id") == msg_id:
            if not reply.get("success"):
                raise SystemExit(f"{msg['type']} failed: {reply.get('error')}")
            return reply.get("result")


# --------------------------------------------------------------------------- commands
def write_env(path: Path, key: str, value: str) -> None:
    lines = path.read_text().splitlines() if path.is_file() else []
    pattern = re.compile(rf"^\s*#?\s*{re.escape(key)}=")
    replaced = False
    for i, line in enumerate(lines):
        if pattern.match(line):
            lines[i] = f"{key}={value}"
            replaced = True
            break
    if not replaced:
        lines.append(f"{key}={value}")
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text("\n".join(lines) + "\n")
    os.chmod(tmp, 0o600)
    tmp.replace(path)
    os.chmod(path, 0o600)


def credentials(args: argparse.Namespace) -> tuple[str, str]:
    """Username from --username/$HA_USERNAME/prompt; password from $HA_PASSWORD (automation only) or a hidden prompt. Never persisted."""
    user = args.username or os.environ.get("HA_USERNAME") or input("Home Assistant username: ")
    password = os.environ.get("HA_PASSWORD") or getpass.getpass("Home Assistant password (not stored): ")
    return user, password


def cmd_create(args: argparse.Namespace) -> int:
    user, password = credentials(args)
    access = login(args.ha_url, user, password)
    ws = ws_session(args.ha_url, access)
    try:
        existing = ws_call(ws, {"type": "auth/refresh_tokens"}, 1)
        names = {t.get("client_name") for t in existing if t.get("type") == "long_lived_access_token"}
        if args.name in names and not args.replace:
            raise SystemExit(f"a token named {args.name!r} already exists; pass --replace to revoke and recreate, or pick another --name")
        if args.name in names:
            for t in existing:
                if t.get("type") == "long_lived_access_token" and t.get("client_name") == args.name:
                    ws_call(ws, {"type": "auth/delete_refresh_token", "refresh_token_id": t["id"]}, 2)
        token = ws_call(ws, {"type": "auth/long_lived_access_token", "client_name": args.name, "lifespan": args.lifespan_days}, 3)
    finally:
        ws.close()
    if not isinstance(token, str):
        raise SystemExit(f"unexpected token result: {token!r}")
    written = []
    for env_path in args.write_env:
        write_env(Path(env_path), "HA_LONG_LIVED_ACCESS_TOKEN", token)
        written.append(env_path)
    if written:
        print(f"token {args.name!r} created for user {user!r}; written to: {', '.join(written)} (mode 600). Not printed.")
    if args.print:
        print(token)
    elif not written:
        print("token created but neither --print nor --write-env was given; revoke it with `revoke --name` and re-run", file=sys.stderr)
        return 1
    return 0


def resolve_token(args: argparse.Namespace) -> str:
    token = os.environ.get(args.token_env) or load_dotenv(Path(args.env_file)).get(args.token_env, "")
    if not token or token.startswith("replace-with"):
        raise SystemExit(f"{args.token_env} not set (env or {args.env_file})")
    return token


def cmd_verify(args: argparse.Namespace) -> int:
    token = resolve_token(args)
    status, body = http_json(f"{args.ha_url}/api/", token=token)
    if status != 200:
        print(f"FAIL {args.ha_url}/api/ -> {status}: {body}")
        return 1
    status, cfg = http_json(f"{args.ha_url}/api/config", token=token)
    if isinstance(cfg, dict):
        print(f"OK   HA {cfg.get('version')} at {args.ha_url} (location: {cfg.get('location_name')}, tz: {cfg.get('time_zone')})")
    else:
        print(f"OK   {args.ha_url}/api/ reachable with token")
    return 0


def _list_tokens(args: argparse.Namespace) -> list[dict]:
    user, password = credentials(args)
    ws = ws_session(args.ha_url, login(args.ha_url, user, password))
    try:
        return [t for t in ws_call(ws, {"type": "auth/refresh_tokens"}, 1) if t.get("type") == "long_lived_access_token"]
    finally:
        ws.close()


def cmd_list(args: argparse.Namespace) -> int:
    for t in _list_tokens(args):
        print(f"{t.get('client_name'):<30} created {t.get('created_at')}  last used {t.get('last_used_at') or 'never'} from {t.get('last_used_ip') or '-'}")
    return 0


def cmd_revoke(args: argparse.Namespace) -> int:
    user, password = credentials(args)
    ws = ws_session(args.ha_url, login(args.ha_url, user, password))
    try:
        tokens = [t for t in ws_call(ws, {"type": "auth/refresh_tokens"}, 1) if t.get("type") == "long_lived_access_token" and t.get("client_name") == args.name]
        if not tokens:
            print(f"no token named {args.name!r}")
            return 1
        for i, t in enumerate(tokens, start=2):
            ws_call(ws, {"type": "auth/delete_refresh_token", "refresh_token_id": t["id"]}, i)
        print(f"revoked {len(tokens)} token(s) named {args.name!r}")
    finally:
        ws.close()
    return 0


def main(argv: list[str] | None = None) -> int:
    root = Path(__file__).resolve().parent.parent
    dotenv = load_dotenv(root / ".env")
    default_url = os.environ.get("HA_URL") or dotenv.get("HA_URL") or "http://127.0.0.1:8123"

    defaults = {"ha_url": default_url, "username": None, "env_file": str(root / ".env"), "token_env": "HA_LONG_LIVED_ACCESS_TOKEN"}
    # Accepted both before and after the sub-command; SUPPRESS so a sub-parser
    # default never clobbers a value given at the top level.
    common = argparse.ArgumentParser(add_help=False, argument_default=argparse.SUPPRESS)
    common.add_argument("--ha-url", help=f"Home Assistant base URL (default {default_url})")
    common.add_argument("--username", help="HA username (prompted if omitted)")
    common.add_argument("--env-file", help="dotenv holding the token (default ./.env)")
    common.add_argument("--token-env", help="variable name (default HA_LONG_LIVED_ACCESS_TOKEN)")

    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter, parents=[common])
    sub = p.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("create", help="create an LLAT via the HA login flow", parents=[common])
    c.add_argument("--name", default="ha-device-mcp", help="token name shown in the HA UI")
    c.add_argument("--lifespan-days", type=int, default=3650, help="token lifetime in days (default 3650, the HA UI default)")
    c.add_argument("--write-env", action="append", default=[], metavar="FILE", help="write HA_LONG_LIVED_ACCESS_TOKEN= into FILE (repeatable; ./.env is the usual target)")
    c.add_argument("--print", action="store_true", help="print the token to stdout (avoid in shared terminals)")
    c.add_argument("--replace", action="store_true", help="revoke an existing token of the same name first")
    c.set_defaults(fn=cmd_create)

    v = sub.add_parser("verify", help="check the token in env/.env against /api/", parents=[common])
    v.set_defaults(fn=cmd_verify)
    sub.add_parser("list", help="list LLATs of the logging-in user", parents=[common]).set_defaults(fn=cmd_list)
    r = sub.add_parser("revoke", help="revoke LLAT(s) by name", parents=[common])
    r.add_argument("--name", required=True)
    r.set_defaults(fn=cmd_revoke)

    args = p.parse_args(argv)
    for k, v in defaults.items():
        if not hasattr(args, k):
            setattr(args, k, v)
    args.ha_url = args.ha_url.rstrip("/")
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
