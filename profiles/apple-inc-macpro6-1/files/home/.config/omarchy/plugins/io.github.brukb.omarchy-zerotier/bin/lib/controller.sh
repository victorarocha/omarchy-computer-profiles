#!/usr/bin/env bash
# Controller API read helpers (phase 1.5 — list/detail/members).
set -u
set -o pipefail
export LC_ALL=C

controller_api_get() {
  local path="$1"
  local base tmp code body
  base="$(api_base_url)"
  tmp="$(mktemp)"
  chmod 600 "$tmp"
  code="$(zt_api_call "$tmp" GET "$path" 20)"
  body=""
  if ! zt_read_tmp_body "$tmp" body; then
    rm -f "$tmp"
    json_err "response too large" false
    return 1
  fi
  rm -f "$tmp"
  if [[ "$code" == "000" ]]; then
    json_err "cannot reach ZeroTier service at ${base}" false
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
  printf '%s' "$body"
  return 0
}

cmd_controller_networks() {
  if ! require_token; then
    return 1
  fi
  local ids_json
  ids_json="$(controller_api_get "/controller/network")" || {
    unset TOKEN TOKEN_SOURCE 2>/dev/null || true
    return 1
  }
  printf '%s' "$ids_json" | python3 -c "
import json, sys
limit = int('${ZT_MAX_RESPONSE_BYTES}') + 1
raw = sys.stdin.read(limit)
if len(raw) > limit - 1:
    print(json.dumps({'ok': False, 'error': 'response too large'}))
    sys.exit(0)
try:
    ids = json.loads(raw)
except json.JSONDecodeError:
    print(json.dumps({'ok': False, 'error': 'invalid controller network list'}))
    sys.exit(0)
if not isinstance(ids, list):
    print(json.dumps({'ok': False, 'error': 'unexpected controller network list'}))
    sys.exit(0)
print(json.dumps({'ok': True, 'data': ids}))
"
  unset TOKEN TOKEN_SOURCE 2>/dev/null || true
}

cmd_controller_networks_full() {
  if ! require_token; then
    return 1
  fi
  local ids_json base input_tmp rc
  base="$(api_base_url)"
  ids_json="$(controller_api_get "/controller/network")" || {
    unset TOKEN TOKEN_SOURCE 2>/dev/null || true
    return 1
  }
  input_tmp="$(mktemp)"
  chmod 600 "$input_tmp"
  printf '%s' "$ids_json" >"$input_tmp"
  zt_helper_with_token "$TOKEN" networks-full "$base" --input-file "$input_tmp"
  rc=$?
  rm -f "$input_tmp"
  unset ids_json
  unset TOKEN TOKEN_SOURCE 2>/dev/null || true
  return "$rc"
}

controller_api_post() {
  local path="$1"
  local body_file="$2"
  local base tmp code body
  base="$(api_base_url)"
  tmp="$(mktemp)"
  chmod 600 "$tmp"
  code="$(zt_api_call "$tmp" POST "$path" 30 "$body_file")"
  body=""
  if ! zt_read_tmp_body "$tmp" body; then
    rm -f "$tmp"
    json_err "response too large" false
    return 1
  fi
  rm -f "$tmp"
  if [[ "$code" == "000" ]]; then
    json_err "cannot reach ZeroTier service at ${base}" false
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
    printf '%s' "$body" | json_ok
  fi
}

controller_api_delete() {
  local path="$1"
  local base tmp code body
  base="$(api_base_url)"
  tmp="$(mktemp)"
  chmod 600 "$tmp"
  code="$(zt_api_call "$tmp" DELETE "$path" 30)"
  body=""
  if ! zt_read_tmp_body "$tmp" body; then
    rm -f "$tmp"
    json_err "response too large" false
    return 1
  fi
  rm -f "$tmp"
  if [[ "$code" == "000" ]]; then
    json_err "cannot reach ZeroTier service at ${base}" false
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
    printf '%s' "$body" | json_ok
  fi
}

controller_node_id() {
  local status_json status_tmp node_id
  status_json="$(controller_api_get "/status")" || return 1
  status_tmp="$(mktemp)"
  chmod 600 "$status_tmp"
  printf '%s' "$status_json" >"$status_tmp"
  node_id="$(zt_helper_with_token "$TOKEN" node-id --input-file "$status_tmp" 2>/dev/null)" || {
    rm -f "$status_tmp"
    return 1
  }
  rm -f "$status_tmp"
  [[ -n "$node_id" ]]
  printf '%s' "$node_id"
}

cmd_controller_network_create_stdin() {
  local payload body_file node_id create_meta meta_file path
  payload="$(read_stdin_json)" || return 1
  if ! require_token; then
    return 1
  fi
  node_id="$(controller_node_id)" || {
    unset TOKEN TOKEN_SOURCE 2>/dev/null || true
    json_err "could not read controller node id from /status" false
    return 1
  }
  payload_tmp="$(mktemp)"
  meta_file="$(mktemp)"
  body_file="$(mktemp)"
  chmod 600 "$payload_tmp" "$meta_file" "$body_file"
  printf '%s' "$payload" >"$payload_tmp"
  if ! python3 "${ZT_LIB_DIR}/network_body.py" create "$node_id" <"$payload_tmp" >"$meta_file"; then
    rm -f "$payload_tmp" "$meta_file" "$body_file"
    unset TOKEN TOKEN_SOURCE 2>/dev/null || true
    json_err "invalid create payload" false
    return 1
  fi
  path="$(python3 - "$meta_file" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle)["path"])
PY
)"
  python3 - "$meta_file" <<'PY' >"$body_file"
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    json.dump(json.load(handle)["body"], sys.stdout)
PY
  local ok=1
  if controller_api_post "$path" "$body_file"; then
    ok=0
  elif controller_api_post "/controller/network/${node_id}" "$body_file"; then
    ok=0
  fi
  rm -f "$payload_tmp" "$meta_file" "$body_file"
  unset TOKEN TOKEN_SOURCE 2>/dev/null || true
  return "$ok"
}

cmd_controller_network_create_blank() {
  local body_file node_id path
  if ! require_token; then
    return 1
  fi
  node_id="$(controller_node_id)" || {
    unset TOKEN TOKEN_SOURCE 2>/dev/null || true
    json_err "could not read controller node id from /status" false
    return 1
  }
  body_file="$(mktemp)"
  chmod 600 "$body_file"
  printf '{"name":"network","private":true,"enableBroadcast":true,"v4AssignMode":{"zt":true},"rules":[{"type":"ACTION_ACCEPT"}]}' >"$body_file"
  path="/controller/network/${node_id}______"
  local ok=1
  if controller_api_post "$path" "$body_file"; then
    ok=0
  elif controller_api_post "/controller/network/${node_id}" "$body_file"; then
    ok=0
  fi
  rm -f "$body_file"
  unset TOKEN TOKEN_SOURCE 2>/dev/null || true
  return "$ok"
}

cmd_controller_network_update_stdin() {
  local id="$1"
  local payload body_file payload_tmp
  is_valid_nwid "$id" || { json_err "invalid network id"; return 1; }
  payload="$(read_stdin_json)" || return 1
  if ! require_token; then
    return 1
  fi
  payload_tmp="$(mktemp)"
  body_file="$(mktemp)"
  chmod 600 "$payload_tmp" "$body_file"
  printf '%s' "$payload" >"$payload_tmp"
  if ! python3 "${ZT_LIB_DIR}/network_body.py" update <"$payload_tmp" >"$body_file"; then
    rm -f "$payload_tmp" "$body_file"
    unset TOKEN TOKEN_SOURCE 2>/dev/null || true
    json_err "invalid update payload" false
    return 1
  fi
  controller_api_post "/controller/network/${id,,}" "$body_file"
  local rc=$?
  rm -f "$payload_tmp" "$body_file"
  unset TOKEN TOKEN_SOURCE 2>/dev/null || true
  return "$rc"
}

cmd_controller_network_delete() {
  local id="$1"
  is_valid_nwid "$id" || { json_err "invalid network id"; return 1; }
  if ! require_token; then
    return 1
  fi
  controller_api_delete "/controller/network/${id,,}"
  local rc=$?
  unset TOKEN TOKEN_SOURCE 2>/dev/null || true
  return "$rc"
}

cmd_controller_member_update_stdin() {
  local nwid="$1" node="$2"
  local payload body_file payload_tmp
  is_valid_nwid "$nwid" || { json_err "invalid network id"; return 1; }
  is_valid_node_id "$node" || { json_err "invalid node id"; return 1; }
  payload="$(read_stdin_json)" || return 1
  if ! require_token; then
    return 1
  fi
  payload_tmp="$(mktemp)"
  body_file="$(mktemp)"
  chmod 600 "$payload_tmp" "$body_file"
  printf '%s' "$payload" >"$payload_tmp"
  if ! python3 "${ZT_LIB_DIR}/member_body.py" <"$payload_tmp" >"$body_file"; then
    rm -f "$payload_tmp" "$body_file"
    unset TOKEN TOKEN_SOURCE 2>/dev/null || true
    json_err "invalid member payload" false
    return 1
  fi
  controller_api_post "/controller/network/${nwid,,}/member/${node,,}" "$body_file"
  local rc=$?
  rm -f "$payload_tmp" "$body_file"
  unset TOKEN TOKEN_SOURCE 2>/dev/null || true
  return "$rc"
}

cmd_controller_member_delete() {
  local nwid="$1" node="$2"
  is_valid_nwid "$nwid" || { json_err "invalid network id"; return 1; }
  is_valid_node_id "$node" || { json_err "invalid node id"; return 1; }
  if ! require_token; then
    return 1
  fi
  local body_file
  body_file="$(mktemp)"
  chmod 600 "$body_file"
  printf '{"authorized":false,"ipAssignments":[]}' >"$body_file"
  controller_api_post "/controller/network/${nwid,,}/member/${node,,}" "$body_file" >/dev/null 2>&1 || true
  rm -f "$body_file"
  controller_api_delete "/controller/network/${nwid,,}/member/${node,,}"
  local rc=$?
  unset TOKEN TOKEN_SOURCE 2>/dev/null || true
  return "$rc"
}

cmd_controller_network_get() {
  local id="$1"
  is_valid_nwid "$id" || { json_err "invalid network id"; return 1; }
  if ! require_token; then
    return 1
  fi
  local body
  body="$(controller_api_get "/controller/network/${id,,}")" || {
    unset TOKEN TOKEN_SOURCE 2>/dev/null || true
    return 1
  }
  unset TOKEN TOKEN_SOURCE 2>/dev/null || true
  printf '%s' "$body" | json_ok
}

cmd_controller_members() {
  local nwid="$1"
  is_valid_nwid "$nwid" || { json_err "invalid network id"; return 1; }
  if ! require_token; then
    return 1
  fi
  local map_json base input_tmp rc
  base="$(api_base_url)"
  map_json="$(controller_api_get "/controller/network/${nwid,,}/member")" || {
    unset TOKEN TOKEN_SOURCE 2>/dev/null || true
    return 1
  }
  input_tmp="$(mktemp)"
  chmod 600 "$input_tmp"
  printf '%s' "$map_json" >"$input_tmp"
  zt_helper_with_token "$TOKEN" members "$base" "${nwid,,}" --input-file "$input_tmp"
  rc=$?
  rm -f "$input_tmp"
  unset map_json
  unset TOKEN TOKEN_SOURCE 2>/dev/null || true
  return "$rc"
}
