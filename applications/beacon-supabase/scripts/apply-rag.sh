#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/../docker-compose.yml"

echo "Applying Supabase RAG SQL scripts..."

docker compose -f "${COMPOSE_FILE}" exec -T db \
  psql -U postgres -d postgres \
  -f /docker-entrypoint-initdb.d/02_extensions.sql \
  -f /docker-entrypoint-initdb.d/03_embeddings.sql \
  -f /docker-entrypoint-initdb.d/04_match_embeddings.sql

echo "Done."
