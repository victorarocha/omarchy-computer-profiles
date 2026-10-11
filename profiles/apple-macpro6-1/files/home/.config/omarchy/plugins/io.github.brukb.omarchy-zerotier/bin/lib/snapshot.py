#!/usr/bin/env python3
"""Assemble ztn-api snapshot envelope from HTTP response files."""

from __future__ import annotations

import json
import os
import sys

MAX_BYTES = int(os.environ.get("ZT_MAX_RESPONSE_BYTES", str(8 * 1024 * 1024)))


def dump(obj) -> None:
    json.dump(obj, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    sys.stdout.flush()


def read_body(path: str) -> str:
    if not path or not os.path.isfile(path):
        return ""
    if os.path.getsize(path) > MAX_BYTES:
        raise ValueError("response too large")
    with open(path, encoding="utf-8", errors="replace") as handle:
        return handle.read(MAX_BYTES + 1)


def parse_json_body(raw: str):
    if not raw or not raw.strip():
        return None
    return json.loads(raw)


def slim_status(status):
    if not isinstance(status, dict):
        return None
    return {
        "address": status.get("address"),
        "online": status.get("online"),
        "version": status.get("version"),
    }


def slim_networks(networks):
    if not isinstance(networks, list):
        return []
    out = []
    for n in networks:
        if not isinstance(n, dict):
            continue
        out.append({
            "id": n.get("id") or n.get("nwid"),
            "name": n.get("name"),
            "status": n.get("status"),
            "type": n.get("type"),
            "mac": n.get("mac"),
            "assignedAddresses": n.get("assignedAddresses") or [],
            "portDeviceName": n.get("portDeviceName"),
            "allowDNS": n.get("allowDNS"),
            "allowDefault": n.get("allowDefault"),
            "allowGlobal": n.get("allowGlobal"),
            "allowManaged": n.get("allowManaged"),
        })
    return out


def slim_controller(parsed):
    if not isinstance(parsed, dict):
        return {"controller": False}
    return {
        "controller": parsed.get("controller") is True,
        "apiVersion": parsed.get("apiVersion"),
    }


def slim_peers(peers):
    if not isinstance(peers, list):
        return []
    out = []
    for p in peers:
        if not isinstance(p, dict):
            continue
        out.append({
            "address": p.get("address"),
            "role": p.get("role"),
            "latency": p.get("latency"),
            "version": p.get("version"),
            "versionMajor": p.get("versionMajor"),
            "versionMinor": p.get("versionMinor"),
        })
    return out


def main() -> None:
    if len(sys.argv) != 12:
        dump({"ok": False, "error": "snapshot internal error"})
        return

    has = sys.argv[1].lower() in ("1", "true", "yes")
    source = sys.argv[2]
    reachable = sys.argv[3].lower() in ("1", "true", "yes")
    status_code = sys.argv[4]
    status_file = sys.argv[5]
    networks_code = sys.argv[6]
    networks_file = sys.argv[7]
    controller_code = sys.argv[8]
    controller_file = sys.argv[9]
    peers_code = sys.argv[10]
    peers_file = sys.argv[11]

    auth = {
        "hasToken": has,
        "source": source if has else "",
        "serviceReachable": reachable,
    }

    if not has:
        dump({
            "ok": True,
            "data": {
                "auth": auth,
                "status": None,
                "networks": [],
                "controller": {"controller": False},
                "peers": [],
            },
        })
        return

    if any(c in ("401", "403") for c in (status_code, networks_code, controller_code, peers_code)):
        dump({"ok": False, "error": "API rejected auth token", "needsAuth": True})
        return

    try:
        status = parse_json_body(read_body(status_file)) if status_code == "200" else None
        networks = parse_json_body(read_body(networks_file)) if networks_code == "200" else []
        controller_raw = read_body(controller_file)
        controller = {"controller": False}
        if controller_code == "200" and controller_raw.strip():
            controller = slim_controller(parse_json_body(controller_raw))
        peers = parse_json_body(read_body(peers_file)) if peers_code == "200" else []

        if status_code == "000" or networks_code == "000":
            dump({
                "ok": False,
                "error": "cannot reach ZeroTier service (is zerotier-one running?)",
            })
            return

        dump({
            "ok": True,
            "data": {
                "auth": auth,
                "status": slim_status(status),
                "networks": slim_networks(networks),
                "controller": controller,
                "peers": slim_peers(peers),
            },
        })
    except (json.JSONDecodeError, ValueError, OSError) as exc:
        dump({"ok": False, "error": str(exc) or "invalid snapshot data"})


if __name__ == "__main__":
    main()
