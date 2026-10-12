#!/usr/bin/env python3
"""Read one JSON value from stdin without waiting for EOF.

Quickshell Process write() leaves the write channel open. Python
sys.stdin.read(n) blocks until n bytes or EOF, so create/update hangs
until the panel process dies.

os.read() returns as soon as the pipe has data. Stop at the first
complete JSON value (JSONDecoder.raw_decode).
"""

from __future__ import annotations

import json
import os
import sys

DEFAULT_LIMIT = 8 * 1024 * 1024


def _limit_from_argv(argv: list[str]) -> int:
    if len(argv) > 1:
        return int(argv[1])
    return int(os.environ.get("ZT_MAX_RESPONSE_BYTES", str(DEFAULT_LIMIT)))


def read_one_json(fd: int, limit: int) -> tuple[int, str]:
    """Return (exit_code, payload). 0=ok, 1=missing/invalid, 2=too large."""
    buf = bytearray()
    decoder = json.JSONDecoder()
    while True:
        if len(buf) > limit:
            return 2, ""
        want = min(4096, limit + 1 - len(buf))
        if want <= 0:
            return 2, ""
        chunk = os.read(fd, want)
        if not chunk:
            break
        buf.extend(chunk)
        if len(buf) > limit:
            return 2, ""
        try:
            text = buf.decode("utf-8")
        except UnicodeDecodeError:
            continue
        stripped = text.lstrip(" \t\r\n")
        if not stripped:
            continue
        try:
            obj, _end = decoder.raw_decode(stripped)
        except json.JSONDecodeError:
            if len(buf) > limit:
                return 2, ""
            continue
        return 0, json.dumps(obj, separators=(",", ":"), ensure_ascii=False)

    if len(buf) > limit:
        return 2, ""
    text = buf.decode("utf-8", errors="strict").strip() if buf else ""
    if not text:
        return 1, ""
    try:
        obj = json.loads(text)
    except (json.JSONDecodeError, UnicodeDecodeError, ValueError):
        return 1, ""
    if not isinstance(obj, (dict, list)):
        return 1, ""
    return 0, json.dumps(obj, separators=(",", ":"), ensure_ascii=False)


def main() -> None:
    try:
        limit = _limit_from_argv(sys.argv)
    except ValueError:
        raise SystemExit(1)
    code, payload = read_one_json(sys.stdin.fileno(), limit)
    if code != 0:
        raise SystemExit(code)
    sys.stdout.write(payload)


if __name__ == "__main__":
    main()
