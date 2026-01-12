# ------------------------------------------------------------------
# Variables (surchargables)
# ------------------------------------------------------------------
ENV ?= local
PROJECT ?= beacon
VERSION ?= $(shell git describe --tags --always 2>/dev/null || echo "0.0.0-dev")
IMAGE ?= $(PROJECT)/nginx
REGISTRY ?= ghcr.io/nicolaslallier
FULL_IMAGE ?= $(REGISTRY)/$(IMAGE)
COMPOSE ?= docker compose
DOCKER ?= docker
PLATFORM ?= linux/amd64
VERBOSE ?= 0

# ------------------------------------------------------------------
# Helpers (help, version, info)
# ------------------------------------------------------------------
.PHONY: help version info
help:
	@printf "\n=== CI/CD Makefile (Beacon) ===\n\n"
	@printf "## Dev/Build\n"
	@printf "  make docker-build     # Construit l'image Docker\n"
	@printf "\n## Quality\n"
	@printf "  make lint            # Lint global (Dockerfile, shell, nginx)\n"
	@printf "  make lint-docker     # Lint du Dockerfile (hadolint)\n"
	@printf "  make lint-shell      # Lint des scripts shell (shellcheck)\n"
	@printf "  make lint-nginx      # Test la conf NGINX\n"
	@printf "\n## Docker Compose\n"
	@printf "  make up              # Démarre tous les services (nginx + monitoring + auth)\n"
	@printf "  make up-core         # Démarre uniquement nginx\n"
	@printf "  make up-monitoring   # Démarre nginx + monitoring\n"
	@printf "  make up-auth         # Démarre nginx + auth (Keycloak)\n"
	@printf "  make up-monitoring-only   # Seulement la stack monitoring\n"
	@printf "  make up-auth-only    # Seulement Keycloak + DB\n"
	@printf "  make down            # Stoppe tous les services\n"
	@printf "  make down-monitoring # Arrête tout avec monitoring\n"
	@printf "  make down-auth       # Arrête tout avec auth\n"
	@printf "  make down-monitoring-only # Stoppe uniquement la stack monitoring\n"
	@printf "  make down-auth-only  # Stoppe uniquement Keycloak + DB\n"
	@printf "  make restart         # Redémarre les services\n"
	@printf "  make logs            # Affiche les logs\n"
	@printf "  make monitoring-logs    # Logs only monitoring services\n"
	@printf "  make auth-logs       # Logs only auth services (Keycloak)\n"
	@printf "  make ps              # Montre le statut des services\n"
	@printf "  make monitoring-status # Statut health monitoring\n"
	@printf "  make auth-status     # Statut health auth (Keycloak)\n"
	@printf "  make reset-grafana   # Reset Grafana (delete data, use new password)\n"
	@printf "  make reset-keycloak  # Reset Keycloak (delete data)\n"
	@printf "\n## SSL / Private CA\n"
	@printf "  make ssl-init        # Create private CA and certificates\n"
	@printf "  make ssl-renew       # Renew server certificate\n"
	@printf "  make ssl-status      # Show certificate info and expiry\n"
	@printf "  make ssl-install-ca-macos # Install CA on macOS\n"
	@printf "  make ssl-show-ca-path # Show path for NODE_EXTRA_CA_CERTS\n"
	@printf "\n## CI Pipeline\n"
	@printf "  make ci              # Pipeline CI complet (lint + build)\n"
	@printf "\n## Release/Deploy\n"
	@printf "  make push            # Push l'image vers le registry\n"
	@printf "\n## Info\n"
	@printf "  make version         # Affiche la version\n"
	@printf "  make info            # Affiche project/env/image\n"
	@printf "  make env-check       # Vérifie les variables d'environnement\n"

version:
	@echo "$(VERSION)"

info:
	@printf "Project : $(PROJECT)\n"
	@printf "Env     : $(ENV)\n"
	@printf "Image   : $(FULL_IMAGE):$(VERSION)\n"

env-check:
	@echo "Checking environment variables..."
	@echo "NGINX_HTTP_PORT: ${NGINX_HTTP_PORT:-80}"
	@echo "GRAFANA_PORT: ${GRAFANA_PORT:-3000}"
	@echo "GF_SECURITY_ADMIN_PASSWORD: $${GF_SECURITY_ADMIN_PASSWORD:-not set}"
	@if [ -f .env ]; then \
	  echo "\n.env file exists. Contents:"; \
	  grep -v "^#" .env | grep -v "^$$" || echo "  (empty or only comments)"; \
	else \
	  echo "\nWARNING: .env file not found!"; \
	fi

# ------------------------------------------------------------------
# Quality/Lint (Docker/Shell/NGINX)
# ------------------------------------------------------------------
.PHONY: lint lint-docker lint-shell lint-nginx
lint: lint-docker lint-shell lint-nginx

lint-docker:
	@if which hadolint >/dev/null 2>&1; then \
	  hadolint Dockerfile ; \
	else \
	  docker run --rm -i hadolint/hadolint < Dockerfile ; \
	fi

lint-shell:
	@if which shellcheck >/dev/null 2>&1; then \
	  set -- scripts/*.sh; \
	  if [ "$$1" != "scripts/*.sh" ]; then shellcheck "$$@"; else echo "No scripts/*.sh to lint"; fi \
	else \
	  files=$$(find scripts -name '*.sh' -type f 2>/dev/null); \
	  if [ -n "$$files" ]; then \
	    for f in $$files; do \
	      docker run --rm -v "$(PWD)/scripts:/code" koalaman/shellcheck:stable "/code/$$(basename $$f)"; \
	    done; \
	  else \
	    echo "No scripts/*.sh to lint"; \
	  fi \
	fi

lint-nginx:
	@$(DOCKER) run --rm \
	  -v "$(PWD)/templates:/templates:ro" \
	  -e UPSTREAM_API_HOST=127.0.0.1 \
	  -e UPSTREAM_API_PORT=8080 \
	  -e UPSTREAM_WEB_HOST=127.0.0.1 \
	  -e UPSTREAM_WEB_PORT=3000 \
	  -e GZIP_ENABLED=on \
	  -e MAX_BODY_SIZE=1m \
	  -e DOLLAR='$$' \
	  alpine:latest sh -c "apk add --no-cache gettext >/dev/null 2>&1 && \
	    envsubst '\$${UPSTREAM_WEB_HOST} \$${UPSTREAM_WEB_PORT} \$${UPSTREAM_API_HOST} \$${UPSTREAM_API_PORT} \$${MAX_BODY_SIZE} \$${GZIP_ENABLED} \$${DOLLAR}' \
	    < /templates/nginx.conf.template" | \
	  $(DOCKER) run --rm -i nginx:1.27-alpine nginx -t || true

# ------------------------------------------------------------------
# Docker build
# ------------------------------------------------------------------
.PHONY: docker-build
docker-build:
	@echo "Pulling monitoring stack images..."
	$(COMPOSE) --profile monitoring pull
	@echo "Pulling auth stack images..."
	$(COMPOSE) --profile auth pull
	@echo "Building all containers..."
	$(COMPOSE) build
	@echo "Tagging NGINX image as $(FULL_IMAGE):$(VERSION)..."
	@NGINX_IMAGE=$$($(DOCKER) images --format "{{.Repository}}:{{.Tag}}" | grep -E "^beacon_nginx|^$(PROJECT)_nginx" | head -1); \
	if [ -z "$$NGINX_IMAGE" ]; then \
	  NGINX_IMAGE="beacon_nginx:latest"; \
	fi; \
	if $(DOCKER) images -q "$$NGINX_IMAGE" >/dev/null 2>&1; then \
	  $(DOCKER) tag "$$NGINX_IMAGE" "$(FULL_IMAGE):$(VERSION)"; \
	  $(DOCKER) tag "$(FULL_IMAGE):$(VERSION)" "$(FULL_IMAGE):latest"; \
	  echo "Tagged $$NGINX_IMAGE as $(FULL_IMAGE):$(VERSION)"; \
	else \
	  echo "Error: NGINX image '$$NGINX_IMAGE' not found."; \
	  echo "Available images:"; \
	  $(DOCKER) images --format "table {{.Repository}}\t{{.Tag}}" | grep -E "(nginx|beacon|$(PROJECT))" || echo "  (none found)"; \
	fi

# ------------------------------------------------------------------
# Docker Compose lifecycle
# ------------------------------------------------------------------
.PHONY: up up-core down restart logs ps \
	up-monitoring down-monitoring up-monitoring-only down-monitoring-only \
	up-auth down-auth up-auth-only down-auth-only \
	monitoring-logs monitoring-status auth-logs auth-status \
	reset-grafana reset-keycloak

# Start all services (nginx + monitoring + auth)
up:
	$(COMPOSE) --profile monitoring --profile auth up -d

# Start only core nginx service
up-core:
	$(COMPOSE) up -d

down:
	$(COMPOSE) --profile monitoring --profile auth down

restart:
	$(COMPOSE) --profile monitoring --profile auth up -d --force-recreate

logs:
	$(COMPOSE) --profile monitoring --profile auth logs -f

ps:
	$(COMPOSE) --profile monitoring --profile auth ps

# --- Monitoring targets ---
up-monitoring:
	$(COMPOSE) --profile monitoring up -d

down-monitoring:
	$(COMPOSE) --profile monitoring down

up-monitoring-only:
	$(COMPOSE) --profile monitoring up -d grafana prometheus loki tempo promtail cadvisor node-exporter minio1 minio2 minio3

down-monitoring-only:
	$(COMPOSE) --profile monitoring stop grafana prometheus loki tempo promtail cadvisor node-exporter minio1 minio2 minio3

monitoring-logs:
	$(COMPOSE) logs -f grafana prometheus loki tempo promtail cadvisor node-exporter minio1 minio2 minio3

monitoring-status:
	$(COMPOSE) ps grafana prometheus loki tempo promtail cadvisor node-exporter minio1 minio2 minio3

reset-grafana:
	@echo "Resetting Grafana (this will delete all Grafana data)..."
	$(COMPOSE) --profile monitoring stop grafana || true
	$(COMPOSE) --profile monitoring rm -f grafana || true
	$(DOCKER) volume rm beacon_grafana-data 2>/dev/null || echo "Volume already removed or doesn't exist"
	@echo "Grafana reset complete. Restart with: make up-monitoring"

# --- Auth (Keycloak) targets ---
up-auth:
	$(COMPOSE) --profile auth up -d

down-auth:
	$(COMPOSE) --profile auth down

up-auth-only:
	$(COMPOSE) --profile auth up -d keycloak keycloak-db

down-auth-only:
	$(COMPOSE) --profile auth stop keycloak keycloak-db

auth-logs:
	$(COMPOSE) logs -f keycloak keycloak-db

auth-status:
	$(COMPOSE) ps keycloak keycloak-db

reset-keycloak:
	@echo "Resetting Keycloak (this will delete all Keycloak data)..."
	$(COMPOSE) --profile auth stop keycloak keycloak-db || true
	$(COMPOSE) --profile auth rm -f keycloak keycloak-db || true
	$(DOCKER) volume rm beacon_keycloak-db-data 2>/dev/null || echo "Volume already removed or doesn't exist"
	@echo "Keycloak reset complete. Restart with: make up-auth"

# --- SSL / Private CA targets ---
ssl-init:
	@echo "Setting up Private CA and certificates..."
	@./scripts/setup-private-ca.sh

ssl-renew:
	@echo "Renewing server certificate..."
	@./scripts/renew-private-cert.sh

ssl-status:
	@echo "=== Certificate Status ==="
	@if [ -f certs/fullchain.pem ]; then \
		echo "Server Certificate:"; \
		openssl x509 -in certs/fullchain.pem -noout -subject -dates 2>/dev/null || echo "Could not read certificate"; \
		echo ""; \
		echo "Subject Alternative Names:"; \
		openssl x509 -in certs/fullchain.pem -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 || true; \
	else \
		echo "No certificate found at certs/fullchain.pem"; \
		echo "Run 'make ssl-init' to create certificates"; \
	fi
	@echo ""
	@if [ -f ca/beacon-ca.crt ]; then \
		echo "CA Certificate:"; \
		openssl x509 -in ca/beacon-ca.crt -noout -subject -dates 2>/dev/null || echo "Could not read CA certificate"; \
	fi

ssl-install-ca-macos:
	@echo "Installing CA certificate on macOS..."
	@if [ -f ca/beacon-ca.crt ]; then \
		sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ca/beacon-ca.crt; \
		echo "✅ CA installed. You may need to restart browsers."; \
	else \
		echo "❌ CA not found. Run 'make ssl-init' first."; \
	fi

ssl-show-ca-path:
	@echo "CA certificate path for NODE_EXTRA_CA_CERTS:"
	@echo "export NODE_EXTRA_CA_CERTS=$(PWD)/ca/beacon-ca.crt"

# ------------------------------------------------------------------
# CI pipeline
# ------------------------------------------------------------------
.PHONY: ci
ci: lint docker-build
	@echo "CI pipeline completed successfully"

# ------------------------------------------------------------------
# Release/Deploy
# ------------------------------------------------------------------
.PHONY: push
push:
	@echo "Pushing $(FULL_IMAGE):$(VERSION)..."
	$(DOCKER) push "$(FULL_IMAGE):$(VERSION)"
	$(DOCKER) push "$(FULL_IMAGE):latest"
