import json
import os
import subprocess
import sys
import tempfile

MAX_INPUT_BYTES = 8 * 1024 * 1024


def split_csv(value):
    return [part.strip() for part in str(value or "").split(",") if part.strip()]


def parse_routes(routes_text, default_cidr):
    text = str(routes_text or "").strip()
    if not text:
        text = str(default_cidr or "").strip()
    routes = []
    for part in text.split(","):
        part = part.strip()
        if not part:
            continue
        fields = part.split(";", 1)
        target = fields[0].strip()
        if not target:
            continue
        route = {"target": target}
        if len(fields) == 2 and fields[1].strip():
            route["via"] = fields[1].strip()
        routes.append(route)
    if not routes and text:
        routes.append({"target": text})
    return routes


def parse_rules(rules_text):
    text = str(rules_text or "").strip()
    if not text:
        return [{"type": "ACTION_ACCEPT"}]
    if text.startswith("["):
        return json.loads(text)
    return compile_rdl_rules(text)


def compile_rdl_rules(text):
    script_dir = os.path.dirname(os.path.abspath(__file__))
    compiler = os.path.join(os.path.dirname(script_dir), "rule-compiler", "cli.js")
    if not os.path.isfile(compiler):
        raise ValueError("rule compiler missing; install node or restore bin/rule-compiler")
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".rules", delete=False, encoding="utf-8"
        ) as tmp:
            tmp.write(text)
            if not text.endswith("\n"):
                tmp.write("\n")
            tmp_path = tmp.name
        proc = subprocess.run(
            ["node", compiler, tmp_path],
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode != 0:
            err = (proc.stderr or proc.stdout or "compile failed").strip()
            raise ValueError(err)
        payload = json.loads(proc.stdout)
        rules = payload.get("config", {}).get("rules")
        if not rules:
            return [{"type": "ACTION_ACCEPT"}]
        return rules
    finally:
        if tmp_path:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass


def build_network(payload):
    payload = payload or {}
    name = str(payload.get("name") or "network").strip() or "network"
    pool_start = str(payload.get("poolStart") or "10.147.20.1").strip()
    pool_end = str(payload.get("poolEnd") or "10.147.20.254").strip()
    cidr = str(payload.get("cidr") or "10.147.20.0/24").strip()
    mtu = int(payload.get("mtu") or 2800)
    multicast_limit = int(payload.get("multicastLimit") or 32)
    return {
        "name": name,
        "private": bool(payload.get("private", True)),
        "enableBroadcast": bool(payload.get("enableBroadcast", True)),
        "mtu": mtu,
        "multicastLimit": multicast_limit,
        "v4AssignMode": {"zt": bool(payload.get("v4ZT", True))},
        "v6AssignMode": {
            "6plane": bool(payload.get("v6SixPlane", False)),
            "rfc4193": bool(payload.get("v6RFC4193", False)),
            "zt": bool(payload.get("v6ZT", False)),
        },
        "ipAssignmentPools": [
            {"ipRangeStart": pool_start, "ipRangeEnd": pool_end}
        ],
        "routes": parse_routes(payload.get("routes"), cidr),
        "dns": {
            "domain": str(payload.get("dnsDomain") or "").strip(),
            "servers": split_csv(payload.get("dnsServers")),
        },
        "rules": parse_rules(payload.get("rules")),
    }


def read_payload() -> dict:
    raw = sys.stdin.read(MAX_INPUT_BYTES + 1)
    if len(raw) > MAX_INPUT_BYTES:
        raise ValueError("input too large")
    payload = json.loads(raw)
    if not isinstance(payload, dict):
        raise ValueError("expected object")
    return payload


def main() -> None:
    mode = sys.argv[1] if len(sys.argv) > 1 else "update"
    payload = read_payload()
    net = build_network(payload)

    if mode == "create":
        node_id = sys.argv[2] if len(sys.argv) > 2 else ""
        node_id = str(node_id).strip().lower()
        if len(node_id) != 10:
            sys.exit(1)
        print(json.dumps({"path": f"/controller/network/{node_id}______", "body": net}))
        return

    json.dump(net, sys.stdout)


if __name__ == "__main__":
    main()
