#!/usr/bin/env bash
# Secure ZeroTier API token resolution and storage.
set -u
set -o pipefail
export LC_ALL=C

PLUGIN_KEYRING_SERVICE="io.github.brukb.omarchy-zerotier"
LEGACY_KEYRING_SERVICE="io.github.brukberhane.ztnodes"
PLUGIN_KEYRING_USER="auth-token"
ZTNUI_KEYRING_SERVICE="ztnui"
ZTNUI_KEYRING_USER="zerotier-auth-token"
ZT_TOKEN_FILE="${ZT_HOME:-/var/lib/zerotier-one}/authtoken.secret"

# Test hook only — never set in production shell profiles.
allow_env_token() {
  [[ -n "${ZTNODES_ALLOW_ENV_TOKEN:-}" && -n "${ZTNODES_AUTH_TOKEN:-}" ]]
}

lookup_secret() {
  local service="$1" user="$2"
  if ! command -v secret-tool >/dev/null 2>&1; then
    return 1
  fi
  secret-tool lookup service "$service" username "$user" 2>/dev/null
}

store_secret() {
  local service="$1" user="$2" label="$3" token="$4"
  if ! command -v secret-tool >/dev/null 2>&1; then
    return 1
  fi
  printf '%s' "$token" | secret-tool store --label="$label" service "$service" username "$user"
}

clear_secret() {
  local service="$1" user="$2"
  if ! command -v secret-tool >/dev/null 2>&1; then
    return 1
  fi
  secret-tool clear service "$service" username "$user" >/dev/null 2>&1 || true
}

# Sets TOKEN and TOKEN_SOURCE (global in caller). Returns 0 on success.
load_token() {
  TOKEN=""
  TOKEN_SOURCE=""

  if allow_env_token; then
    TOKEN="$(printf '%s' "$ZTNODES_AUTH_TOKEN" | tr -d '\r\n')"
    TOKEN_SOURCE="env"
    [[ -n "$TOKEN" ]]
    return
  fi

  local t
  t="$(lookup_secret "$PLUGIN_KEYRING_SERVICE" "$PLUGIN_KEYRING_USER" || true)"
  if [[ -n "$t" ]]; then
    TOKEN="$(printf '%s' "$t" | tr -d '\r\n')"
    TOKEN_SOURCE="keyring"
    unset t
    [[ -n "$TOKEN" ]]
    return
  fi

  t="$(lookup_secret "$LEGACY_KEYRING_SERVICE" "$PLUGIN_KEYRING_USER" || true)"
  if [[ -n "$t" ]]; then
    TOKEN="$(printf '%s' "$t" | tr -d '\r\n')"
    TOKEN_SOURCE="keyring"
    unset t
    [[ -n "$TOKEN" ]]
    return
  fi

  t="$(lookup_secret "$ZTNUI_KEYRING_SERVICE" "$ZTNUI_KEYRING_USER" || true)"
  if [[ -n "$t" ]]; then
    TOKEN="$(printf '%s' "$t" | tr -d '\r\n')"
    TOKEN_SOURCE="ztnui-keyring"
    unset t
    [[ -n "$TOKEN" ]]
    return
  fi

  if [[ -r "$ZT_TOKEN_FILE" ]]; then
    t="$(<"$ZT_TOKEN_FILE")"
    TOKEN="$(printf '%s' "$t" | tr -d '\r\n')"
    TOKEN_SOURCE="os-file"
    unset t
    is_valid_token_chars "$TOKEN"
    return
  fi

  return 1
}

auth_status_json() {
  local has=false source="" reachable=false
  if load_token; then
    has=true
    source="$TOKEN_SOURCE"
  fi
  if service_reachable; then
    reachable=true
  fi
  unset TOKEN TOKEN_SOURCE 2>/dev/null || true
  python3 - "$has" "$source" "$reachable" <<'PY'
import json, sys

def as_bool(value):
    return str(value).lower() in ("1", "true", "yes")

has, source, reachable = sys.argv[1], sys.argv[2], sys.argv[3]
data = {
    "hasToken": as_bool(has),
    "source": source,
    "serviceReachable": as_bool(reachable),
}
json.dump({"ok": True, "data": data}, sys.stdout)
PY
}

auth_store_stdin() {
  local token
  IFS= read -r token || token=""
  token="$(printf '%s' "$token" | tr -d '\r\n')"
  if [[ ${#token} -lt 16 || ${#token} -gt 64 ]]; then
    json_err "invalid token length (expected ~24 characters)" false
    return 1
  fi
  if [[ ! "$token" =~ ^[A-Za-z0-9]+$ ]]; then
    json_err "invalid token characters (paste only the authtoken.secret contents)" false
    return 1
  fi
  if ! store_secret "$PLUGIN_KEYRING_SERVICE" "$PLUGIN_KEYRING_USER" \
      "Omarchy ZeroTier API token" "$token"; then
    json_err "failed to store token (is secret-service / gnome-keyring running?)" false
    return 1
  fi
  if ! verify_token_with_api "$token"; then
    clear_secret "$PLUGIN_KEYRING_SERVICE" "$PLUGIN_KEYRING_USER"
    json_err "token saved but rejected by zerotier-one — paste the exact authtoken.secret value" false
    return 1
  fi
  unset token
  auth_status_json
}

verify_token_with_api() {
  local token="$1"
  local tmp code
  tmp="$(mktemp)"
  chmod 600 "$tmp"
  TOKEN="$token"
  code="$(zt_api_call "$tmp" GET "/status" 10)"
  rm -f "$tmp"
  unset TOKEN
  [[ "$code" == "200" ]]
}

auth_clear() {
  clear_secret "$PLUGIN_KEYRING_SERVICE" "$PLUGIN_KEYRING_USER"
  clear_secret "$LEGACY_KEYRING_SERVICE" "$PLUGIN_KEYRING_USER"
  clear_secret "$ZTNUI_KEYRING_SERVICE" "$ZTNUI_KEYRING_USER"
  auth_status_json
}
