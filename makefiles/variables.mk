# ------------------------------------------------------------------
# Variables (override as needed)
# ------------------------------------------------------------------
ENV ?= local
PROJECT ?= beacon
LIBRARY_DIR ?= applications/Library
TOOLSUITE_DIR ?= applications/toolsuite
TOOLSUITE_SPA_DIST ?= $(TOOLSUITE_DIR)/frontend/dist
TOOLSUITE_SPA_TARGET ?= infra/html/toolsuite
VERSION ?= $(shell git describe --tags --always 2>/dev/null || echo "0.0.0-dev")
IMAGE ?= $(PROJECT)/nginx
REGISTRY ?= ghcr.io/nicolaslallier
FULL_IMAGE ?= $(REGISTRY)/$(IMAGE)
COMPOSE_FILE ?= infra/docker-compose.yml
LIBRARY_COMPOSE_FILE ?= $(LIBRARY_DIR)/docker-compose.yml
TOOLSUITE_COMPOSE_FILE ?= $(TOOLSUITE_DIR)/docker-compose.yml
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
COMPOSE_LIBRARY := $(COMPOSE_LIBRARY_BASE) --profile library
COMPOSE_LIBRARY_OBS := $(COMPOSE_LIBRARY_BASE) --profile observability --profile library
COMPOSE_ADMIN_LIBRARY := $(COMPOSE_LIBRARY_BASE) --profile admin --profile library
COMPOSE_OBSERVABILITY := $(COMPOSE) --profile observability
COMPOSE_TOOLSUITE := docker compose -f $(TOOLSUITE_COMPOSE_FILE)

MONITORING_SERVICES := grafana prometheus loki tempo promtail cadvisor node-exporter minio1 minio2 minio3
AUTH_SERVICES := keycloak keycloak-db
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
