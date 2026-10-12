#!/usr/bin/env bash
# HTTP client for ZeroTier Service API.
set -u
set -o pipefail
export LC_ALL=C

require_token() {
  if ! load_token; then
    json_err "ZeroTier API token unavailable — paste token in panel or run ztnui once" true
    return 1
  fi
  return 0
}

api_request() {
  local method="$1"
  local path="$2"
  local body_file="${3:-}"

  if ! require_token; then
    return 1
  fi

  local tmp code body
  tmp="$(mktemp)"
  chmod 600 "$tmp"
  code="$(zt_api_call "$tmp" "$method" "$path" 20 "$body_file")"
  body=""
  if ! zt_read_tmp_body "$tmp" body; then
    rm -f "$tmp"
    unset TOKEN TOKEN_SOURCE 2>/dev/null || true
    json_err "response too large" false
    return 1
  fi
  rm -f "$tmp"
  unset TOKEN TOKEN_SOURCE 2>/dev/null || true

  local base
  base="$(api_base_url)"

  if [[ "$code" == "000" ]]; then
    json_err "cannot reach ZeroTier service at ${base} (is zerotier-one running?)" false
    return 1
  fi

  if [[ "$code" == "401" || "$code" == "403" ]]; then
    json_err "API rejected auth token (HTTP ${code})" true
    return 1
  fi

  if [[ "$code" -lt 200 || "$code" -ge 300 ]]; then
    local msg
    msg="$(printf '%s' "$body" | tr -d '\0' | head -c 400)"
    [[ -z "$msg" ]] && msg="HTTP ${code}"
    json_err "$msg" false
    return 1
  fi

  if [[ -z "$body" ]]; then
    json_ok_raw 'null'
  else
    if ! printf '%s' "$body" | json_ok; then
      json_err "invalid API response body" false
      return 1
    fi
  fi
}

cmd_status() { api_request GET "/status"; }
cmd_networks() { api_request GET "/network"; }
cmd_network_get() {
  local id="$1"
  is_valid_nwid "$id" || { json_err "invalid network id"; return 1; }
  api_request GET "/network/${id,,}"
}
cmd_network_join() {
  local id="$1"
  is_valid_nwid "$id" || { json_err "invalid network id"; return 1; }
  local body_file
  body_file="$(mktemp)"
  chmod 600 "$body_file"
  printf '{}' >"$body_file"
  api_request POST "/network/${id,,}" "$body_file"
  rm -f "$body_file"
}
cmd_network_leave() {
  local id="$1"
  is_valid_nwid "$id" || { json_err "invalid network id"; return 1; }
  api_request DELETE "/network/${id,,}"
}
cmd_network_set() {
  local id="$1" key="$2" value="$3"
  is_valid_nwid "$id" || { json_err "invalid network id"; return 1; }
  case "$key" in
    allowDNS|allowDefault|allowGlobal|allowManaged) ;;
    *) json_err "unsupported network setting"; return 1 ;;
  esac
  local bool="false"
  case "${value,,}" in
    1|true|yes|on) bool="true" ;;
    0|false|no|off) bool="false" ;;
    *) json_err "expected boolean value"; return 1 ;;
  esac
  local body_file
  body_file="$(mktemp)"
  chmod 600 "$body_file"
  python3 - "$key" "$bool" >"$body_file" <<'PY'
import json, sys
print(json.dumps({sys.argv[1]: sys.argv[2] == "true"}))
PY
  api_request POST "/network/${id,,}" "$body_file"
  rm -f "$body_file"
}
cmd_peers() { api_request GET "/peer"; }
cmd_controller_status() {
  if ! require_token; then
    return 1
  fi
  local tmp code body
  tmp="$(mktemp)"
  chmod 600 "$tmp"
  code="$(zt_api_call "$tmp" GET "/controller" 20)"
  body=""
  if ! zt_read_tmp_body "$tmp" body; then
    rm -f "$tmp"
    unset TOKEN TOKEN_SOURCE 2>/dev/null || true
    json_err "response too large" false
    return 1
  fi
  rm -f "$tmp"
  unset TOKEN TOKEN_SOURCE 2>/dev/null || true

  if [[ "$code" == "401" || "$code" == "403" ]]; then
    json_err "API rejected auth token (HTTP ${code})" true
    return 1
  fi
  if [[ "$code" == "404" || "$code" -lt 200 || "$code" -ge 300 ]]; then
    json_ok_raw '{"controller":false}'
    return 0
  fi
  if [[ -z "$body" ]]; then
    json_ok_raw '{"controller":false}'
    return 0
  fi
  if ! printf '%s' "$body" | json_ok; then
    json_err "invalid API response body" false
    return 1
  fi
}
