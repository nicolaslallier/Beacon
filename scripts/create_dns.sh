#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/config/.env"

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "${ENV_FILE}"
  set +a
fi

: "${TECHNITIUM_API_KEY:?TECHNITIUM_API_KEY is required in config/.env}"

TECHNITIUM_API_URL="${TECHNITIUM_API_URL:-http://localhost:5380}"
ZONE_NAME="${TECHNITIUM_ZONE_NAME:-famillelallier.net}"
BEACON_HOST="${TECHNITIUM_BEACON_HOST:-beacon.famillelallier.net}"
N8N_HOST="${TECHNITIUM_N8N_HOST:-n8n.beacon.famillelallier.net}"
PGADMIN_HOST="${TECHNITIUM_PGADMIN_HOST:-pgadmin.beacon.famillelallier.net}"
GRAFANA_HOST="${TECHNITIUM_GRAFANA_HOST:-grafana.beacon.famillelallier.net}"
KEYCLOAK_HOST="${TECHNITIUM_KEYCLOAK_HOST:-keycloak.beacon.famillelallier.net}"
DNS_HOST="${TECHNITIUM_DNS_HOST:-dns.beacon.famillelallier.net}"
MINIO_HOST="${TECHNITIUM_MINIO_HOST:-minio.beacon.famillelallier.net}"
BEACON_OLLAMA_HOST="${TECHNITIUM_BEACON_OLLAMA_HOST:-beacon-ollama.beacon.famillelallier.net}"
BEACON_OLLAMA_WEBUI_HOST="${TECHNITIUM_BEACON_OLLAMA_WEBUI_HOST:-beacon-ollama-webui.beacon.famillelallier.net}"
OLLAMA_HOST="${TECHNITIUM_OLLAMA_HOST:-ollama.beacon.famillelallier.net}"
LMSTUDIO_HOST="${TECHNITIUM_LMSTUDIO_HOST:-lmstudio.beacon.famillelallier.net}"
POSTGRESQL_HOST="${TECHNITIUM_POSTGRESQL_HOST:-postgresql.beacon.famillelallier.net}"
REDIS_HOST="${TECHNITIUM_REDIS_HOST:-redis.beacon.famillelallier.net}"
SUPABASE_HOST="${TECHNITIUM_SUPABASE_HOST:-supabase.beacon.famillelallier.net}"
CHROMADB_HOST="${TECHNITIUM_CHROMADB_HOST:-chromadb.beacon.famillelallier.net}"
TARGET_IP="${TECHNITIUM_TARGET_IP:-192.168.2.35}"

ALLOW_RECURSION="${TECHNITIUM_ALLOW_RECURSION:-true}"
ALLOW_RECURSION_PRIVATE="${TECHNITIUM_ALLOW_RECURSION_PRIVATE:-true}"
FORWARDERS="${TECHNITIUM_FORWARDERS:-8.8.8.8,8.8.4.4}"
FORWARDER_PROTOCOL="${TECHNITIUM_FORWARDER_PROTOCOL:-Udp}"
PROXY_TYPE="${TECHNITIUM_PROXY_TYPE:-None}"
PROXY_ADDRESS="${TECHNITIUM_PROXY_ADDRESS:-}"
PROXY_PORT="${TECHNITIUM_PROXY_PORT:-}"
PROXY_BYPASS="${TECHNITIUM_PROXY_BYPASS:-127.0.0.0/8,169.254.0.0/16,fe80::/10,::1,localhost}"

api_call() {
  local endpoint="$1"
  shift
  curl -sS --get \
    --data-urlencode "token=${TECHNITIUM_API_KEY}" \
    "${TECHNITIUM_API_URL}${endpoint}" \
    "$@"
}

is_ok() {
  grep -q '"status"[[:space:]]*:[[:space:]]*"ok"' <<<"$1"
}

settings_args=(
  --data-urlencode "allowRecursion=${ALLOW_RECURSION}"
  --data-urlencode "allowRecursionOnlyForPrivateNetworks=${ALLOW_RECURSION_PRIVATE}"
  --data-urlencode "forwarders=${FORWARDERS}"
  --data-urlencode "forwarderProtocol=${FORWARDER_PROTOCOL}"
  --data-urlencode "proxyType=${PROXY_TYPE}"
)

if [[ "${PROXY_TYPE}" != "None" ]]; then
  if [[ -z "${PROXY_ADDRESS}" || -z "${PROXY_PORT}" ]]; then
    echo "proxyType=${PROXY_TYPE} requires TECHNITIUM_PROXY_ADDRESS and TECHNITIUM_PROXY_PORT" >&2
    exit 1
  fi
  settings_args+=(
    --data-urlencode "proxyAddress=${PROXY_ADDRESS}"
    --data-urlencode "proxyPort=${PROXY_PORT}"
  )
fi

if [[ -n "${PROXY_BYPASS}" ]]; then
  settings_args+=(--data-urlencode "proxyBypass=${PROXY_BYPASS}")
fi

settings_resp="$(api_call "/api/settings/set" "${settings_args[@]}")"
if ! is_ok "${settings_resp}"; then
  echo "Failed to update DNS settings: ${settings_resp}" >&2
  exit 1
fi

zone_resp="$(api_call "/api/zones/create" \
  --data-urlencode "zone=${ZONE_NAME}" \
  --data-urlencode "type=Primary")"
if ! is_ok "${zone_resp}"; then
  if ! grep -qi "already exists" <<<"${zone_resp}"; then
    echo "Failed to create zone ${ZONE_NAME}: ${zone_resp}" >&2
    exit 1
  fi
fi

add_record() {
  local domain="$1"
  local record_resp
  record_resp="$(api_call "/api/zones/records/add" \
    --data-urlencode "zone=${ZONE_NAME}" \
    --data-urlencode "domain=${domain}" \
    --data-urlencode "type=A" \
    --data-urlencode "ipAddress=${TARGET_IP}" \
    --data-urlencode "overwrite=true")"
  if ! is_ok "${record_resp}"; then
    echo "Failed to add record ${domain}: ${record_resp}" >&2
    exit 1
  fi
}

add_record "${ZONE_NAME}"
add_record "${BEACON_HOST}"
add_record "${N8N_HOST}"
add_record "${PGADMIN_HOST}"
add_record "${GRAFANA_HOST}"
add_record "${KEYCLOAK_HOST}"
add_record "${DNS_HOST}"
add_record "${MINIO_HOST}"
add_record "${BEACON_OLLAMA_HOST}"
add_record "${BEACON_OLLAMA_WEBUI_HOST}"
add_record "${OLLAMA_HOST}"
add_record "${LMSTUDIO_HOST}"
add_record "${POSTGRESQL_HOST}"
add_record "${REDIS_HOST}"
add_record "${SUPABASE_HOST}"
add_record "${CHROMADB_HOST}"

echo "DNS configuration applied for ${ZONE_NAME}, ${BEACON_HOST}, ${N8N_HOST}, ${PGADMIN_HOST}, ${GRAFANA_HOST}, ${KEYCLOAK_HOST}, ${DNS_HOST}, ${MINIO_HOST}, ${BEACON_OLLAMA_HOST}, ${BEACON_OLLAMA_WEBUI_HOST}, ${OLLAMA_HOST}, ${LMSTUDIO_HOST}, ${POSTGRESQL_HOST}, ${REDIS_HOST}, ${SUPABASE_HOST}, ${CHROMADB_HOST} -> ${TARGET_IP}"
