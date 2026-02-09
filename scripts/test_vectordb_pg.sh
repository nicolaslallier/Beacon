#!/usr/bin/env bash
set -euo pipefail

HOST_INPUT="${1:-beacon.famillelallier.net}"
HOST="${HOST_INPUT#*://}"
HOST="${HOST%%/*}"
PORT="${2:-${VECTORDB_PUBLIC_PORT:-5432}}"
DB="${VECTORDB_DB:-vectordb}"
USER="${VECTORDB_USER:-vectordb}"
PASS="${VECTORDB_PASSWORD:-change_me}"

if [[ -z "${PASS}" ]]; then
  read -s -p "Password for ${USER}@${HOST_INPUT}: " PASS
  echo
fi

echo "== Debug: local environment =="
echo "HOST_INPUT=${HOST_INPUT}"
echo "HOST=${HOST}"
echo "PORT=${PORT}"
echo "DB=${DB}"
echo "USER=${USER}"
echo "PASS_SET=$([[ -n "${PASS}" ]] && echo yes || echo no)"
echo

echo "== Debug: DNS resolution =="
if command -v dig >/dev/null 2>&1; then
  dig +short "${HOST}" || true
elif command -v nslookup >/dev/null 2>&1; then
  nslookup "${HOST}" || true
elif command -v host >/dev/null 2>&1; then
  host "${HOST}" || true
else
  echo "No dig/nslookup/host available."
fi
echo

echo "== Debug: TCP connectivity =="
if command -v nc >/dev/null 2>&1; then
  nc -zv "${HOST}" "${PORT}"
else
  echo "nc not found; skipping TCP check."
fi
echo

echo "== Debug: Direct psql (host OS -> beacon.famillelallier.net) =="
PSQL_CMD=(psql -h "beacon.famillelallier.net" -p "5432" -U "${USER}" -d "${DB}" \
  -v ON_ERROR_STOP=1 -c "select version(), now(), 1 as ok;")
echo "+ ${PSQL_CMD[*]}"
if command -v timeout >/dev/null 2>&1; then
  timeout 15s "${PSQL_CMD[@]}" || true
else
  "${PSQL_CMD[@]}" || true
fi
echo

echo "== Debug: Docker psql test (bridge -> host) =="
BRIDGE_HOST="${VECTORDB_BRIDGE_HOST:-host.docker.internal}"
RUN_CMD=(docker run --rm --add-host=host.docker.internal:host-gateway -e PGPASSWORD="${PASS}" -e PGCONNECT_TIMEOUT=5 postgres:18-alpine \
  psql -h "${BRIDGE_HOST}" -p "${PORT}" -U "${USER}" -d "${DB}" \
  -v ON_ERROR_STOP=1 -c "select version(), now(), 1 as ok;")
echo "+ ${RUN_CMD[*]}"
if command -v timeout >/dev/null 2>&1; then
  timeout 15s "${RUN_CMD[@]}" || echo "FAILED (bridge -> host) check host port exposure"
else
  "${RUN_CMD[@]}" || echo "FAILED (bridge -> host) check host port exposure"
fi

echo
echo "== Debug: Docker psql with --network host (recommended) =="
RUN_CMD_NET_HOST=(docker run --rm --network host -e PGPASSWORD="${PASS}" -e PGCONNECT_TIMEOUT=5 postgres:18-alpine \
  psql -h localhost -p "${PORT}" -U "${USER}" -d "${DB}" \
  -v ON_ERROR_STOP=1 -c "select version(), now(), 1 as ok;")
echo "+ ${RUN_CMD_NET_HOST[*]}"
if command -v timeout >/dev/null 2>&1; then
  timeout 15s "${RUN_CMD_NET_HOST[@]}" || true
else
  "${RUN_CMD_NET_HOST[@]}" || true
fi

echo
echo "== Debug: Docker psql via host.docker.internal =="
RUN_CMD_HOST=(docker run --rm -e PGPASSWORD="${PASS}" -e PGCONNECT_TIMEOUT=5 postgres:18-alpine \
  psql -h host.docker.internal -p "${PORT}" -U "${USER}" -d "${DB}" \
  -v ON_ERROR_STOP=1 -c "select version(), now(), 1 as ok;")
echo "+ ${RUN_CMD_HOST[*]}"
if command -v timeout >/dev/null 2>&1; then
  timeout 15s "${RUN_CMD_HOST[@]}" || true
else
  "${RUN_CMD_HOST[@]}" || true
fi

echo
echo "== Debug: Docker psql on nginx network (direct to beacon-vectordb) =="
RUN_CMD_NET=(docker run --rm --network beacon_nginx_net -e PGPASSWORD="${PASS}" -e PGCONNECT_TIMEOUT=5 postgres:18-alpine \
  psql -h beacon-vectordb -p "${PORT}" -U "${USER}" -d "${DB}" \
  -v ON_ERROR_STOP=1 -c "select version(), now(), 1 as ok;")
echo "+ ${RUN_CMD_NET[*]}"
if command -v timeout >/dev/null 2>&1; then
  timeout 15s "${RUN_CMD_NET[@]}" || true
else
  "${RUN_CMD_NET[@]}" || true
fi
