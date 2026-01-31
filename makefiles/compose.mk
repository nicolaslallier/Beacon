# ------------------------------------------------------------------
# Docker build
# ------------------------------------------------------------------
.PHONY: docker-build

docker-build:
	@echo "Pulling monitoring stack images..."
	$(COMPOSE_MONITORING) pull
	@echo "Pulling auth stack images..."
	$(COMPOSE_AUTH) pull
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
	up-pgadmin down-pgadmin pgadmin-logs pgadmin-status pgadmin-reset \
	infra/pgadmin \
	monitoring-logs monitoring-status auth-logs auth-status \
	reset-grafana reset-keycloak \
	up-toolsuite down-toolsuite toolsuite-logs toolsuite-status \
	toolsuite-spa-sync \
	vectordb-up vectordb-down vectordb-logs vectordb-status vectordb-test

# Start all services (nginx + monitoring + auth)
ifneq (,$(filter infra/pgadmin,$(MAKECMDGOALS)))
INFRA_PGADMIN_MODE := 1
endif

up:
	@if [ -n "$(INFRA_PGADMIN_MODE)" ]; then :; else $(COMPOSE_MONITORING_AUTH) up -d; fi

# Start only core nginx service
up-core:
	$(COMPOSE) up -d

down:
	@if [ -n "$(INFRA_PGADMIN_MODE)" ]; then :; else $(COMPOSE_MONITORING_AUTH) down; fi

restart:
	$(COMPOSE_MONITORING_AUTH) up -d --force-recreate

logs:
	@if [ -n "$(INFRA_PGADMIN_MODE)" ]; then :; else $(COMPOSE_MONITORING_AUTH) logs -f; fi

ps:
	@if [ -n "$(INFRA_PGADMIN_MODE)" ]; then :; else $(COMPOSE_MONITORING_AUTH) ps; fi

# --- Monitoring targets ---
up-monitoring:
	$(COMPOSE_MONITORING) up -d

down-monitoring:
	$(COMPOSE_MONITORING) down

up-monitoring-only:
	$(COMPOSE_MONITORING) up -d $(MONITORING_SERVICES)

down-monitoring-only:
	$(COMPOSE_MONITORING) stop $(MONITORING_SERVICES)

monitoring-logs:
	$(COMPOSE) logs -f $(MONITORING_SERVICES)

monitoring-status:
	$(COMPOSE) ps $(MONITORING_SERVICES)

reset-grafana:
	@echo "Resetting Grafana (this will delete all Grafana data)..."
	$(COMPOSE_MONITORING) stop grafana || true
	$(COMPOSE_MONITORING) rm -f grafana || true
	$(DOCKER) volume rm beacon_grafana-data 2>/dev/null || echo "Volume already removed or doesn't exist"
	@echo "Grafana reset complete. Restart with: make up-monitoring"

# --- Auth (Keycloak) targets ---
up-auth:
	$(COMPOSE_AUTH) up -d

down-auth:
	$(COMPOSE_AUTH) down

up-auth-only:
	$(COMPOSE_AUTH) up -d $(AUTH_SERVICES)

down-auth-only:
	$(COMPOSE_AUTH) stop $(AUTH_SERVICES)

auth-logs:
	$(COMPOSE) logs -f $(AUTH_SERVICES)

auth-status:
	$(COMPOSE) ps $(AUTH_SERVICES)

# --- PgAdmin targets ---
up-pgadmin:
	$(COMPOSE_ADMIN) up -d $(PGADMIN_SERVICES)

down-pgadmin:
	$(COMPOSE_ADMIN) stop $(PGADMIN_SERVICES)

pgadmin-logs:
	$(COMPOSE) logs -f $(PGADMIN_SERVICES)

pgadmin-status:
	$(COMPOSE) ps $(PGADMIN_SERVICES)

# --- PgAdmin test target ---
pgadmin-test:
	$(COMPOSE) exec -T pgadmin wget -O - http://localhost:80/misc/ping

pgadmin-reset:
	@echo "Resetting pgAdmin (this will delete pgAdmin data)..."
	$(COMPOSE_ADMIN) stop $(PGADMIN_SERVICES) || true
	$(COMPOSE_ADMIN) rm -f $(PGADMIN_SERVICES) || true
	$(DOCKER) volume rm beacon-vectordb_pgadmin_data 2>/dev/null || echo "Volume already removed or doesn't exist"
	@echo "pgAdmin reset complete. Restart with: make infra/pgadmin up"

# --- Namespaced targets (make infra/pgadmin up|down|logs|log|status|test) ---
ifneq (,$(filter infra/pgadmin,$(MAKECMDGOALS)))
infra/pgadmin:
	@case "$(word 2,$(MAKECMDGOALS))" in \
	  up) $(MAKE) up-pgadmin ;; \
	  down) $(MAKE) down-pgadmin ;; \
	  logs) $(MAKE) pgadmin-logs ;; \
	  log) $(MAKE) pgadmin-logs ;; \
	  status) $(MAKE) pgadmin-status ;; \
	  test) $(MAKE) pgadmin-test ;; \
	  reset) $(MAKE) pgadmin-reset ;; \
	  *) echo "Usage: make infra/pgadmin {up|down|logs|log|status|test|reset}"; exit 2 ;; \
	esac

status:
	@:

log:
	@:

test:
	@:

reset:
	@:
endif

reset-keycloak:
	@echo "Resetting Keycloak (this will delete all Keycloak data)..."
	$(COMPOSE_AUTH) stop $(AUTH_SERVICES) || true
	$(COMPOSE_AUTH) rm -f $(AUTH_SERVICES) || true
	$(DOCKER) volume rm beacon_keycloak-db-data 2>/dev/null || echo "Volume already removed or doesn't exist"
	@echo "Keycloak reset complete. Restart with: make up-auth"

# --- Toolsuite targets ---
toolsuite-spa-sync:
	@if [ ! -d "$(TOOLSUITE_SPA_DIST)" ]; then \
	  echo "Toolsuite SPA build output not found: $(TOOLSUITE_SPA_DIST)"; \
	  echo "Build the SPA first, then re-run: make toolsuite-spa-sync"; \
	  exit 1; \
	fi
	@mkdir -p "$(TOOLSUITE_SPA_TARGET)"
	@rm -rf "$(TOOLSUITE_SPA_TARGET)"/*
	@cp -R "$(TOOLSUITE_SPA_DIST)"/. "$(TOOLSUITE_SPA_TARGET)"
	@echo "Toolsuite SPA synced to $(TOOLSUITE_SPA_TARGET)"

up-toolsuite:
	$(COMPOSE_TOOLSUITE) up -d --build

down-toolsuite:
	$(COMPOSE_TOOLSUITE) down

toolsuite-logs:
	$(COMPOSE_TOOLSUITE) logs -f

toolsuite-status:
	$(COMPOSE_TOOLSUITE) ps

# --- VectorDB targets ---
vectordb-up:
	$(COMPOSE_VECTORDB) up -d

vectordb-down:
	$(COMPOSE_VECTORDB) down

vectordb-logs:
	$(COMPOSE_VECTORDB) logs -f

vectordb-status:
	$(COMPOSE_VECTORDB) ps

vectordb-test:
	@set -a; \
	  . $(VECTORDB_DIR)/.env; \
	  set +a; \
	  PGPASSWORD=$$VECTORDB_PASSWORD psql -h $(VECTORDB_HOST) -p $${VECTORDB_PORT:-5432} -U $$VECTORDB_USER -d $$VECTORDB_DB -c "$(VECTORDB_QUERY)"
