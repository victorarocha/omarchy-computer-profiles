#!/usr/bin/env python3
"""Authenticated ZeroTier Service API client — token on stdin, bounded I/O.

Token is never on argv. HTTP bodies use --body-file / --input-file so stdin
is free for the token. (fd 3 / memfd does not survive Quickshell Process.)
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

MAX_RESPONSE_BYTES = 8 * 1024 * 1024
MAX_BATCH_BYTES = MAX_RESPONSE_BYTES
MAX_BATCH_ITEMS = 32
MAX_TOKEN_BYTES = 64
CONNECT_TIMEOUT = 3.0
_BATCH_ENVELOPE_BYTES = 64


def read_token() -> str:
    token = sys.stdin.read(MAX_TOKEN_BYTES + 1).strip()
    if not token or len(token) > MAX_TOKEN_BYTES:
        _fail("missing API token")
    if not token.isalnum():
        _fail("invalid API token")
    return token


def read_stdin_bounded() -> str:
    data = sys.stdin.read(MAX_RESPONSE_BYTES + 1)
    if len(data) > MAX_RESPONSE_BYTES:
        _fail("input too large")
    return data


def read_input_file(path: str) -> str:
    size = os.path.getsize(path)
    if size > MAX_RESPONSE_BYTES:
        _fail("input too large")
    with open(path, encoding="utf-8") as handle:
        data = handle.read(MAX_RESPONSE_BYTES + 1)
    if len(data) > MAX_RESPONSE_BYTES:
        _fail("input too large")
    return data


def input_from_args(argv: list[str], flag: str = "--input-file") -> tuple[str, list[str]]:
    if flag not in argv:
        return read_stdin_bounded(), argv
    idx = argv.index(flag)
    if idx + 1 >= len(argv):
        _fail(f"missing {flag} path")
    path = argv[idx + 1]
    trimmed = argv[:idx] + argv[idx + 2:]
    return read_input_file(path), trimmed


def _fail(message: str) -> None:
    print(json.dumps({"ok": False, "error": message}))
    raise SystemExit(0)


def _item_serialized_bytes(item: dict) -> int:
    text = json.dumps(item, separators=(",", ":"), ensure_ascii=False)
    return len(text.encode("utf-8"))


def _item_budget_cost(item: dict, raw_len: int) -> int:
    return max(raw_len, _item_serialized_bytes(item))


class _BatchBudget:
    def __init__(self) -> None:
        self.used = _BATCH_ENVELOPE_BYTES

    def charge(self, item: dict, raw_len: int) -> None:
        cost = _item_budget_cost(item, raw_len)
        if self.used + cost > MAX_BATCH_BYTES:
            _fail("batch budget exceeded")
        self.used += cost


def _emit_batch(items: list[dict], errors: list[str]) -> None:
    if errors and not items:
        _fail(errors[0])
    out: dict = {"ok": True, "data": items}
    text = json.dumps(out, separators=(",", ":"), ensure_ascii=False)
    if len(text.encode("utf-8")) > MAX_BATCH_BYTES:
        _fail("batch budget exceeded")
    print(text)


def _request(
    method: str,
    url: str,
    token: str,
    body: bytes | None = None,
    timeout: float = 20.0,
) -> tuple[int, bytes]:
    headers = {"X-ZT1-Auth": token}
    if body is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            code = int(resp.status)
            raw = resp.read(MAX_RESPONSE_BYTES + 1)
    except urllib.error.HTTPError as exc:
        code = int(exc.code)
        raw = exc.read(MAX_RESPONSE_BYTES + 1)
    except Exception:
        return 0, b""
    if len(raw) > MAX_RESPONSE_BYTES:
        return code, b""
    return code, raw


def _api_get(base: str, token: str, path: str, timeout: float = 20.0) -> tuple[dict, int]:
    url = f"{base.rstrip('/')}{path}"
    code, raw = _request("GET", url, token, timeout=timeout)
    if code == 0:
        raise RuntimeError("connection failed")
    if code == 401 or code == 403:
        raise RuntimeError(f"HTTP {code}")
    if code < 200 or code >= 300:
        msg = raw.decode("utf-8", errors="replace")[:400]
        raise RuntimeError(msg or f"HTTP {code}")
    try:
        data = json.loads(raw.decode("utf-8", errors="replace"))
    except json.JSONDecodeError as exc:
        raise RuntimeError("invalid JSON response") from exc
    if not isinstance(data, dict):
        raise RuntimeError("unexpected response shape")
    return data, len(raw)


def cmd_request(token: str, argv: list[str]) -> None:
    # request METHOD URL TIMEOUT -o OUTFILE [--body-file PATH]
    if len(argv) < 4:
        print("000", end="")
        raise SystemExit(1)
    method = argv[0].upper()
    url = argv[1]
    timeout = float(argv[2])
    outfile = ""
    body_file = ""
    idx = 3
    while idx < len(argv):
        arg = argv[idx]
        if arg == "-o" and idx + 1 < len(argv):
            outfile = argv[idx + 1]
            idx += 2
            continue
        if arg == "--body-file" and idx + 1 < len(argv):
            body_file = argv[idx + 1]
            idx += 2
            continue
        idx += 1
    if not outfile:
        print("000", end="")
        raise SystemExit(1)

    body: bytes | None = None
    if body_file:
        size = os.path.getsize(body_file)
        if size > MAX_RESPONSE_BYTES:
            print("000", end="")
            raise SystemExit(1)
        with open(body_file, "rb") as handle:
            body = handle.read(MAX_RESPONSE_BYTES + 1)
        if len(body) > MAX_RESPONSE_BYTES:
            print("000", end="")
            raise SystemExit(1)

    code, raw = _request(method, url, token, body=body, timeout=timeout)
    with open(outfile, "wb") as handle:
        handle.write(raw)
    print(code, end="")


def networks_full(base: str, token: str, ids_raw: str) -> None:
    try:
        ids = json.loads(ids_raw)
    except json.JSONDecodeError:
        _fail("invalid controller network list")
    if not isinstance(ids, list):
        _fail("unexpected controller network list")

    networks: list[dict] = []
    errors: list[str] = []
    budget = _BatchBudget()
    for item in ids:
        if len(networks) >= MAX_BATCH_ITEMS:
            _fail("batch limit exceeded")
        if isinstance(item, dict):
            raw_len = _item_serialized_bytes(item)
            budget.charge(item, raw_len)
            networks.append(item)
            continue
        nwid = str(item).strip().lower()
        if len(nwid) != 16:
            continue
        try:
            net, raw_len = _api_get(base, token, f"/controller/network/{nwid}")
            budget.charge(net, raw_len)
            networks.append(net)
        except Exception as exc:
            errors.append(f"{nwid}: {exc}")

    _emit_batch(networks, errors)


def members(base: str, token: str, nwid: str, map_raw: str) -> None:
    nwid = nwid.strip().lower()
    try:
        member_map = json.loads(map_raw)
    except json.JSONDecodeError:
        _fail("invalid member map")
    if not isinstance(member_map, dict):
        _fail("unexpected member map")

    members_out: list[dict] = []
    errors: list[str] = []
    budget = _BatchBudget()
    for node_id in sorted(member_map.keys()):
        if len(members_out) >= MAX_BATCH_ITEMS:
            _fail("batch limit exceeded")
        node_id = str(node_id).strip().lower()
        if len(node_id) != 10:
            continue
        try:
            mem, raw_len = _api_get(base, token, f"/controller/network/{nwid}/member/{node_id}")
            budget.charge(mem, raw_len)
            members_out.append(mem)
        except Exception as exc:
            errors.append(f"{node_id}: {exc}")

    _emit_batch(members_out, errors)


def node_id_from_status(status_raw: str) -> None:
    try:
        data = json.loads(status_raw)
    except json.JSONDecodeError:
        raise SystemExit(1)
    if not isinstance(data, dict):
        raise SystemExit(1)
    addr = str(data.get("address") or "").strip().lower()
    if len(addr) != 10:
        raise SystemExit(1)
    print(addr)


def main() -> None:
    if len(sys.argv) < 2:
        _fail("usage: zt_helper.py <command> [args…]")

    subcmd = sys.argv[1]
    token = read_token()

    if subcmd == "request":
        cmd_request(token, sys.argv[2:])
        return

    if subcmd == "networks-full":
        args = sys.argv[2:]
        payload, args = input_from_args(args)
        if len(args) != 1:
            _fail("usage: zt_helper.py networks-full <base-url> [--input-file PATH]")
        networks_full(args[0], token, payload)
        return

    if subcmd == "members":
        args = sys.argv[2:]
        payload, args = input_from_args(args)
        if len(args) != 2:
            _fail("usage: zt_helper.py members <base-url> <nwid> [--input-file PATH]")
        members(args[0], token, args[1], payload)
        return

    if subcmd == "node-id":
        payload, _ = input_from_args(sys.argv[2:])
        node_id_from_status(payload)
        return

    _fail(f"unknown command: {subcmd}")


if __name__ == "__main__":
    main()
