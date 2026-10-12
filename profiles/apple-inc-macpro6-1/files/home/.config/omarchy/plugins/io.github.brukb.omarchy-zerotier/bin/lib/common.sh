#!/usr/bin/env bash
# Shared paths and config for Ztnodes backend.
set -u
set -o pipefail
export LC_ALL=C

PLUGIN_ID="io.github.brukb.omarchy-zerotier"
ZT_HOME="${ZT_HOME:-/var/lib/zerotier-one}"
ZT_PORT_FILE="$ZT_HOME/zerotier-one.port"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/$PLUGIN_ID"
CONFIG_FILE="$CONFIG_DIR/config.json"
ZT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZT_MAX_RESPONSE_BYTES=8388608
ZT_LAUNCHER="${ZT_LIB_DIR}/zt_launcher.py"
ZT_HELPER="${ZT_LIB_DIR}/zt_helper.py"

zt_helper_with_token() {
  local token="$1"
  shift
  printf '%s' "$token" | python3 "$ZT_LAUNCHER" "$ZT_HELPER" "$@"
}

zt_api_call() {
  local outfile="$1"
  local method="$2"
  local path="$3"
  local timeout="${4:-20}"
  local body_file="${5:-}"
  local base url code
  base="$(api_base_url)"
  url="${base}${path}"
  local -a args=(request "$method" "$url" "$timeout" -o "$outfile")
  if [[ -n "$body_file" && -f "$body_file" ]]; then
    args+=(--body-file "$body_file")
  fi
  code="$(zt_helper_with_token "$TOKEN" "${args[@]}" 2>/dev/null || printf '000')"
  printf '%s' "$code"
}

zt_read_tmp_body() {
  local tmp="$1"
  local __var="$2"
  printf -v "$__var" ''
  if [[ ! -f "$tmp" ]]; then
    return 0
  fi
  local size
  size="$(stat -c%s "$tmp" 2>/dev/null || echo 0)"
  if (( size > ZT_MAX_RESPONSE_BYTES )); then
    return 2
  fi
  # shellcheck disable=SC2154
  printf -v "$__var" '%s' "$(<"$tmp")"
  return 0
}

json_ok() {
  python3 -c "
import json, sys
limit = int('${ZT_MAX_RESPONSE_BYTES}') + 1
raw = sys.stdin.read(limit)
if len(raw) > limit - 1:
    raise SystemExit(1)
json.dump({'ok': True, 'data': json.loads(raw)}, sys.stdout)
"
}

json_ok_raw() {
  python3 - "$1" <<'PY'
import json, sys
json.dump({"ok": True, "data": json.loads(sys.argv[1])}, sys.stdout)
PY
}

json_err() {
  local msg="$1"
  local needs="${2:-false}"
  python3 - "$msg" "$needs" <<'PY'
import json, sys
out = {"ok": False, "error": sys.argv[1]}
if sys.argv[2].lower() in ("1", "true", "yes"):
    out["needsAuth"] = True
json.dump(out, sys.stdout)
PY
}

read_config_host() {
  python3 - "$CONFIG_FILE" <<'PY'
import ipaddress
import json
import os
import re
import sys

DEFAULT = "127.0.0.1"
path = sys.argv[1]
raw = DEFAULT
if os.path.isfile(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        if isinstance(data, dict) and data.get("host"):
            raw = str(data["host"]).strip() or DEFAULT
    except Exception:
        raw = DEFAULT

def allowed_host(host: str) -> str:
    if not host:
        return DEFAULT
    if re.search(r"[@/\\#\s]", host):
        return DEFAULT
    lower = host.lower()
    if lower == "localhost":
        return "127.0.0.1"
    try:
        ip = ipaddress.ip_address(host)
        if ip.is_loopback or ip.is_private:
            return host
        return DEFAULT
    except ValueError:
        return DEFAULT

print(allowed_host(raw))
PY
}

read_config_port() {
  python3 - "$CONFIG_FILE" "$ZT_PORT_FILE" <<'PY'
import json
import os
import sys

cfg, port_file = sys.argv[1], sys.argv[2]
port = 0
if os.path.isfile(cfg):
    try:
        with open(cfg, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        if isinstance(data, dict):
            port = int(data.get("port") or 0)
    except Exception:
        port = 0
if port <= 0 and os.path.isfile(port_file):
    try:
        with open(port_file, "r", encoding="utf-8") as handle:
            port = int(str(handle.read()).strip())
    except Exception:
        port = 9993
if port <= 0:
    port = 9993
if port < 1 or port > 65535:
    port = 9993
print(port)
PY
}

api_base_url() {
  local host port
  host="$(read_config_host)"
  port="$(read_config_port)"
  printf 'http://%s:%s' "$host" "$port"
}

is_valid_nwid() {
  [[ "$1" =~ ^[0-9a-fA-F]{16}$ ]]
}

is_valid_node_id() {
  [[ "$1" =~ ^[0-9a-fA-F]{10}$ ]]
}

is_valid_token_chars() {
  [[ "$1" =~ ^[A-Za-z0-9]+$ && ${#1} -ge 16 && ${#1} -le 64 ]]
}

service_reachable() {
  local base code
  base="$(api_base_url)"
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 4 "$base/status" 2>/dev/null || printf '000')"
  # 401/403 still means zerotier-one is listening.
  [[ "$code" != "000" ]]
}

read_stdin_json() {
  local data rc=0
  # First complete JSON value. Do not wait for EOF — Quickshell leaves stdin open.
  data="$(python3 "${ZT_LIB_DIR}/stdin_json.py" "${ZT_MAX_RESPONSE_BYTES}" 2>/dev/null)" || rc=$?
  if [[ "${rc:-0}" -eq 2 ]]; then
    json_err "input too large" false
    return 1
  fi
  if [[ -z "$data" ]]; then
    json_err "expected JSON body on stdin" false
    return 1
  fi
  data="$(printf '%s' "$data" | tr -d '\r')"
  if [[ -z "$data" ]]; then
    json_err "expected JSON body on stdin" false
    return 1
  fi
  printf '%s' "$data"
  return 0
}
