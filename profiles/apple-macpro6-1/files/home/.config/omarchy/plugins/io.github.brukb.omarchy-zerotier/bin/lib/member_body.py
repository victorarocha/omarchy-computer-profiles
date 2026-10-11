import json
import sys

MAX_NAME_LEN = 128
MAX_IP_ASSIGNMENTS = 64
MAX_IP_LEN = 64


def build_member(payload: dict) -> dict:
    if not isinstance(payload, dict):
        raise ValueError("expected object")

    out: dict = {}
    for key in ("authorized", "activeBridge", "noAutoAssignIps"):
        if key in payload:
            out[key] = bool(payload[key])

    if "name" in payload:
        name = str(payload["name"]).strip()
        if len(name) > MAX_NAME_LEN:
            raise ValueError("name too long")
        out["name"] = name

    if "ipAssignments" in payload:
        ips = payload["ipAssignments"]
        if not isinstance(ips, list):
            raise ValueError("ipAssignments must be a list")
        if len(ips) > MAX_IP_ASSIGNMENTS:
            raise ValueError("too many ip assignments")
        norm: list[str] = []
        for ip in ips:
            value = str(ip).strip()
            if not value or len(value) > MAX_IP_LEN:
                raise ValueError("invalid ip assignment")
            norm.append(value)
        out["ipAssignments"] = norm

    if not out:
        raise ValueError("empty member payload")
    return out


def main() -> None:
    try:
        limit = 8 * 1024 * 1024 + 1
        raw = sys.stdin.read(limit)
        if len(raw) > 8 * 1024 * 1024:
            sys.exit(1)
        payload = json.loads(raw)
        json.dump(build_member(payload), sys.stdout)
    except (json.JSONDecodeError, ValueError, TypeError):
        sys.exit(1)


if __name__ == "__main__":
    main()
