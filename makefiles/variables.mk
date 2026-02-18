# ------------------------------------------------------------------
# Variables (override as needed)
# ------------------------------------------------------------------
ENV ?= local
PROJECT ?= beacon
LIBRARY_DIR ?= applications/Library
TOOLSUITE_DIR ?= applications/toolsuite
BEACON_VECTORDB_DIR ?= applications/beacon-vectordb
VECTORDB_DIR ?= $(BEACON_VECTORDB_DIR)
QA_DIR ?= applications/beacon-qa
THOR_DIR ?= ../Thor
BEACON_TOOLS_DIR ?= $(THOR_DIR)
FREY_DIR ?= ../Frey
BEACON_OLLAMA_DIR ?= applications/beacon-ollama
GOTENBERG_DIR ?= applications/beacon-gotenberg
N8N_DIR ?= applications/beacon-n8n
MONITORING_DIR ?= applications/beacon-monitoring
MINIO_DIR ?= applications/beacon-minio
POSTGRESQL_DIR ?= applications/beacon-postgresql
REDIS_DIR ?= applications/beacon-redis
MAILHOG_DIR ?= applications/beacon-mailhog
SUPABASE_DIR ?= applications/beacon-supabase
CHROMADB_DIR ?= applications/beacon-chromadb
TOOLSUITE_SPA_DIST ?= $(TOOLSUITE_DIR)/frontend/dist
TOOLSUITE_SPA_TARGET ?= infra/html/toolsuite
VERSION ?= $(shell git describe --tags --always 2>/dev/null || echo "0.0.0-dev")
IMAGE ?= $(PROJECT)/nginx
REGISTRY ?= ghcr.io/nicolaslallier
FULL_IMAGE ?= $(REGISTRY)/$(IMAGE)
COMPOSE_FILE ?= infra/docker-compose.yml
LIBRARY_COMPOSE_FILE ?= $(LIBRARY_DIR)/docker-compose.yml
TOOLSUITE_COMPOSE_FILE ?= $(TOOLSUITE_DIR)/docker-compose.yml
BEACON_VECTORDB_COMPOSE_FILE ?= $(BEACON_VECTORDB_DIR)/docker-compose.yml
VECTORDB_COMPOSE_FILE ?= $(BEACON_VECTORDB_COMPOSE_FILE)
QA_COMPOSE_FILE ?= $(QA_DIR)/docker-compose.yml
BEACON_TOOLS_COMPOSE_FILE ?= $(BEACON_TOOLS_DIR)/docker-compose.beacon-tools.yml
FREY_COMPOSE_FILE ?= $(FREY_DIR)/docker-compose.yml
BEACON_OLLAMA_COMPOSE_FILE ?= $(BEACON_OLLAMA_DIR)/docker-compose.yml
GOTENBERG_COMPOSE_FILE ?= $(GOTENBERG_DIR)/docker-compose.yml
N8N_COMPOSE_FILE ?= $(N8N_DIR)/docker-compose.yml
MONITORING_COMPOSE_FILE ?= $(MONITORING_DIR)/docker-compose.yml
MINIO_COMPOSE_FILE ?= $(MINIO_DIR)/docker-compose.yml
POSTGRESQL_COMPOSE_FILE ?= $(POSTGRESQL_DIR)/docker-compose.yml
REDIS_COMPOSE_FILE ?= $(REDIS_DIR)/docker-compose.yml
MAILHOG_COMPOSE_FILE ?= $(MAILHOG_DIR)/docker-compose.yml
SUPABASE_COMPOSE_FILE ?= $(SUPABASE_DIR)/docker-compose.yml
CHROMADB_COMPOSE_FILE ?= $(CHROMADB_DIR)/docker-compose.yml
COMPOSE_ENV_FILE ?= config/.env
COMPOSE ?= docker compose --env-file $(COMPOSE_ENV_FILE) -f $(COMPOSE_FILE)
COMPOSE_LIBRARY_BASE ?= docker compose --env-file $(COMPOSE_ENV_FILE) -f $(LIBRARY_COMPOSE_FILE)
DOCKER ?= docker
PLATFORM ?= linux/amd64
VERBOSE ?= 0

# ------------------------------------------------------------------
# Compose helpers and service lists
# ------------------------------------------------------------------
COMPOSE_MONITORING := $(COMPOSE) --profile monitoring
COMPOSE_AUTH := $(COMPOSE) --profile auth
COMPOSE_MONITORING_AUTH := $(COMPOSE) --profile monitoring --profile auth
COMPOSE_ADMIN := $(COMPOSE) --profile admin
COMPOSE_LIBRARY := $(COMPOSE_LIBRARY_BASE) --profile library
COMPOSE_LIBRARY_OBS := $(COMPOSE_LIBRARY_BASE) --profile observability --profile library
COMPOSE_ADMIN_LIBRARY := $(COMPOSE_LIBRARY_BASE) --profile admin --profile library
COMPOSE_OBSERVABILITY := $(COMPOSE) --profile observability
COMPOSE_TOOLSUITE := docker compose -f $(TOOLSUITE_COMPOSE_FILE)
COMPOSE_BEACON_VECTORDB := docker compose --env-file $(BEACON_VECTORDB_DIR)/.env -f $(BEACON_VECTORDB_COMPOSE_FILE)
COMPOSE_VECTORDB := $(COMPOSE_BEACON_VECTORDB)
COMPOSE_QA := docker compose -f $(QA_COMPOSE_FILE)
COMPOSE_BEACON_TOOLS := docker compose --env-file $(BEACON_TOOLS_DIR)/.env -f $(BEACON_TOOLS_COMPOSE_FILE)
COMPOSE_FREY := docker compose --env-file $(BEACON_TOOLS_DIR)/.env -f $(FREY_COMPOSE_FILE)
COMPOSE_BEACON_OLLAMA := docker compose -f $(BEACON_OLLAMA_COMPOSE_FILE)
COMPOSE_GOTENBERG := docker compose -f $(GOTENBERG_COMPOSE_FILE)
COMPOSE_N8N := docker compose -f $(N8N_COMPOSE_FILE)
COMPOSE_MONITORING_APP := docker compose -f $(MONITORING_COMPOSE_FILE)
COMPOSE_MINIO := docker compose -f $(MINIO_COMPOSE_FILE)
COMPOSE_POSTGRESQL := docker compose -f $(POSTGRESQL_COMPOSE_FILE)
COMPOSE_REDIS := docker compose -f $(REDIS_COMPOSE_FILE)
COMPOSE_MAILHOG := docker compose -f $(MAILHOG_COMPOSE_FILE)
COMPOSE_SUPABASE := docker compose -f $(SUPABASE_COMPOSE_FILE)
COMPOSE_CHROMADB := docker compose -f $(CHROMADB_COMPOSE_FILE)

BEACON_VECTORDB_PSQL_IMAGE ?= postgres:18-alpine
BEACON_VECTORDB_HOST ?= vectordb.beacon.famillelallier.net
BEACON_VECTORDB_PUBLIC_PORT ?= 5433
BEACON_VECTORDB_QUERY ?= SELECT 1;
VECTORDB_PSQL_IMAGE ?= $(BEACON_VECTORDB_PSQL_IMAGE)
VECTORDB_HOST ?= $(BEACON_VECTORDB_HOST)
VECTORDB_PUBLIC_PORT ?= $(BEACON_VECTORDB_PUBLIC_PORT)
VECTORDB_QUERY ?= $(BEACON_VECTORDB_QUERY)

MONITORING_SERVICES := promtail cadvisor node-exporter
AUTH_SERVICES := infra-keycloak infra-keycloak-db
PGADMIN_SERVICES := pgadmin
DNS_SERVICES := infra-technitium-dns
EDGE_SERVICES := infra-traefik infra-static
LIBRARY_OBSERVABILITY_SERVICES := beacon-library-promtail beacon-library-alloy beacon-library-cadvisor
LIBRARY_BASE_SERVICES := postgres chromadb ollama gotenberg mailhog mcp-vector
LIBRARY_APP_SERVICES := backend frontend

# ------------------------------------------------------------------
# Library observability test vars
# ------------------------------------------------------------------
LIBRARY_OBSERVABILITY_TEST_IMAGE := curlimages/curl:8.5.0
LIBRARY_OBSERVABILITY_TEST_NETWORK := beacon_monitoring_net

# ------------------------------------------------------------------
# MinIO test vars
# ------------------------------------------------------------------
LIBRARY_MINIO_TEST_IMAGE := minio/mc:latest
LIBRARY_MINIO_TEST_NETWORK := beacon_monitoring_net
LIBRARY_MINIO_ENDPOINT ?= beacon-minio1:9000
LIBRARY_MINIO_ACCESS_KEY ?= minioadmin
LIBRARY_MINIO_SECRET_KEY ?= minioadmin
LIBRARY_MINIO_BUCKET ?= beacon-lib-test
