#!/usr/bin/env bash
# Single-call panel snapshot for ztn-api.
set -u
set -o pipefail
export LC_ALL=C

cmd_snapshot() {
  local reachable=false has=false source=""
  local status_code=000 networks_code=000 controller_code=000 peers_code=000
  local status_tmp="" networks_tmp="" controller_tmp="" peers_tmp=""

  if service_reachable; then
    reachable=true
  fi

  if load_token; then
    has=true
    source="$TOKEN_SOURCE"

    status_tmp="$(mktemp)"
    networks_tmp="$(mktemp)"
    controller_tmp="$(mktemp)"
    peers_tmp="$(mktemp)"
    chmod 600 "$status_tmp" "$networks_tmp" "$controller_tmp" "$peers_tmp"

    status_code="$(zt_api_call "$status_tmp" GET "/status" 20)"
    networks_code="$(zt_api_call "$networks_tmp" GET "/network" 20)"
    controller_code="$(zt_api_call "$controller_tmp" GET "/controller" 20)"
    peers_code="$(zt_api_call "$peers_tmp" GET "/peer" 20)"

    unset TOKEN TOKEN_SOURCE 2>/dev/null || true
  fi

  export ZT_MAX_RESPONSE_BYTES
  python3 "${ZT_LIB_DIR}/snapshot.py" \
    "$has" "$source" "$reachable" \
    "$status_code" "${status_tmp:-}" \
    "$networks_code" "${networks_tmp:-}" \
    "$controller_code" "${controller_tmp:-}" \
    "$peers_code" "${peers_tmp:-}"

  rm -f "$status_tmp" "$networks_tmp" "$controller_tmp" "$peers_tmp"
}
