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
	up-keycloak down-keycloak keycloak-logs keycloak-status \
	up-pgadmin down-pgadmin pgadmin-logs pgadmin-status pgadmin-reset \
	infra/pgadmin \
	up-dns down-dns dns-logs dns-status dns-test dns-build \
	create_dns \
	infra/dns \
	up-edge down-edge edge-logs edge-status build-edge test-edge \
	infra/edge \
	infra/keycloak \
	monitoring-logs monitoring-status auth-logs auth-status \
	reset-grafana reset-monitoring reset-keycloak \
	up-toolsuite down-toolsuite toolsuite-logs toolsuite-status \
	qa-up qa-down qa-logs qa-status qa-build qa \
	tools-up tools-down tools-logs tools-status tools-build tools \
	toolsuite-spa-sync \
	vectordb-up vectordb-down vectordb-logs vectordb-status vectordb-test \
	pgadmin-up pgadmin-down pgadmin-logs pgadmin-status pgadmin \
	monitoring-up monitoring-down monitoring-logs-app monitoring-status-app monitoring \
	grafana-up grafana-down grafana-logs grafana-status grafana \
	n8n-up n8n-down n8n-logs n8n-status n8n \
	minio-up minio-down minio-logs minio-status minio-test minio \
	postgresql-up postgresql-down postgresql-logs postgresql-status postgresql-test postgresql \
	redis-up redis-down redis-logs redis-status redis-test redis \
	mailhog-up mailhog-down mailhog-logs mailhog-status mailhog-test mailhog \
	supabase-up supabase-down supabase-logs supabase-status supabase-test supabase \
	chromadb-up chromadb-down chromadb-logs chromadb-status chromadb-test chromadb \
	gotenberg-up gotenberg-down gotenberg-logs gotenberg-status gotenberg \
	beacon-ollama-up beacon-ollama-down beacon-ollama-logs beacon-ollama-status beacon-ollama-build beacon-ollama-test \
	beacon-ollama

# ------------------------------------------------------------------
# Standalone app compose files
# ------------------------------------------------------------------
PGADMIN_APP_COMPOSE_FILE ?= applications/beacon-pgadmin/docker-compose.yml
COMPOSE_PGADMIN_APP := docker compose -f $(PGADMIN_APP_COMPOSE_FILE)

# Start all services (edge + monitoring + auth)
ifneq (,$(filter infra/pgadmin,$(MAKECMDGOALS)))
INFRA_PGADMIN_MODE := 1
endif
ifneq (,$(filter infra/dns,$(MAKECMDGOALS)))
INFRA_DNS_MODE := 1
endif
ifneq (,$(filter infra/keycloak,$(MAKECMDGOALS)))
INFRA_KEYCLOAK_MODE := 1
endif
ifneq (,$(filter infra/edge,$(MAKECMDGOALS)))
INFRA_EDGE_MODE := 1
endif
ifneq (,$(filter pgadmin,$(MAKECMDGOALS)))
PGADMIN_APP_MODE := 1
endif
ifneq (,$(filter n8n,$(MAKECMDGOALS)))
N8N_MODE := 1
endif
ifneq (,$(filter qa,$(MAKECMDGOALS)))
QA_MODE := 1
endif
ifneq (,$(filter tools,$(MAKECMDGOALS)))
TOOLS_MODE := 1
endif
ifneq (,$(filter minio,$(MAKECMDGOALS)))
MINIO_MODE := 1
endif
ifneq (,$(filter postgresql,$(MAKECMDGOALS)))
POSTGRESQL_MODE := 1
endif
ifneq (,$(filter redis,$(MAKECMDGOALS)))
REDIS_MODE := 1
endif
ifneq (,$(filter mailhog,$(MAKECMDGOALS)))
MAILHOG_MODE := 1
endif
ifneq (,$(filter supabase,$(MAKECMDGOALS)))
SUPABASE_MODE := 1
endif
ifneq (,$(filter chromadb,$(MAKECMDGOALS)))
CHROMADB_MODE := 1
endif
ifneq (,$(filter gotenberg,$(MAKECMDGOALS)))
GOTENBERG_MODE := 1
endif
ifneq (,$(filter monitoring,$(MAKECMDGOALS)))
MONITORING_APP_MODE := 1
endif
ifneq (,$(filter grafana,$(MAKECMDGOALS)))
GRAFANA_MODE := 1
endif
ifneq (,$(filter beacon-ollama,$(MAKECMDGOALS)))
BEACON_OLLAMA_MODE := 1
endif

up:
	@if [ -n "$(INFRA_PGADMIN_MODE)" ] || [ -n "$(INFRA_DNS_MODE)" ] || [ -n "$(INFRA_KEYCLOAK_MODE)" ] || [ -n "$(INFRA_EDGE_MODE)" ] || [ -n "$(PGADMIN_APP_MODE)" ] || [ -n "$(N8N_MODE)" ] || [ -n "$(QA_MODE)" ] || [ -n "$(TOOLS_MODE)" ] || [ -n "$(MINIO_MODE)" ] || [ -n "$(POSTGRESQL_MODE)" ] || [ -n "$(REDIS_MODE)" ] || [ -n "$(MAILHOG_MODE)" ] || [ -n "$(SUPABASE_MODE)" ] || [ -n "$(CHROMADB_MODE)" ] || [ -n "$(GOTENBERG_MODE)" ] || [ -n "$(MONITORING_APP_MODE)" ] || [ -n "$(GRAFANA_MODE)" ] || [ -n "$(BEACON_OLLAMA_MODE)" ]; then :; else $(COMPOSE_MONITORING_AUTH) up -d; fi

# Start only core edge services
up-core:
	$(COMPOSE) up -d

# Start only edge services (Traefik + static site)
up-edge:
	$(COMPOSE) up -d $(EDGE_SERVICES)

down-edge:
	$(COMPOSE) stop $(EDGE_SERVICES)

edge-logs:
	$(COMPOSE) logs -f $(EDGE_SERVICES)

edge-status:
	$(COMPOSE) ps $(EDGE_SERVICES)

build-edge:
	$(COMPOSE) build $(EDGE_SERVICES)

test-edge:
	$(MAKE) lint-nginx

down:
	@if [ -n "$(INFRA_PGADMIN_MODE)" ] || [ -n "$(INFRA_DNS_MODE)" ] || [ -n "$(INFRA_KEYCLOAK_MODE)" ] || [ -n "$(INFRA_EDGE_MODE)" ] || [ -n "$(PGADMIN_APP_MODE)" ] || [ -n "$(N8N_MODE)" ] || [ -n "$(QA_MODE)" ] || [ -n "$(TOOLS_MODE)" ] || [ -n "$(MINIO_MODE)" ] || [ -n "$(POSTGRESQL_MODE)" ] || [ -n "$(REDIS_MODE)" ] || [ -n "$(MAILHOG_MODE)" ] || [ -n "$(SUPABASE_MODE)" ] || [ -n "$(CHROMADB_MODE)" ] || [ -n "$(GOTENBERG_MODE)" ] || [ -n "$(MONITORING_APP_MODE)" ] || [ -n "$(GRAFANA_MODE)" ] || [ -n "$(BEACON_OLLAMA_MODE)" ]; then :; else $(COMPOSE_MONITORING_AUTH) down; fi

restart:
	$(COMPOSE_MONITORING_AUTH) up -d --force-recreate

logs:
	@if [ -n "$(INFRA_PGADMIN_MODE)" ] || [ -n "$(INFRA_DNS_MODE)" ] || [ -n "$(INFRA_KEYCLOAK_MODE)" ] || [ -n "$(INFRA_EDGE_MODE)" ] || [ -n "$(PGADMIN_APP_MODE)" ] || [ -n "$(N8N_MODE)" ] || [ -n "$(QA_MODE)" ] || [ -n "$(TOOLS_MODE)" ] || [ -n "$(MINIO_MODE)" ] || [ -n "$(POSTGRESQL_MODE)" ] || [ -n "$(REDIS_MODE)" ] || [ -n "$(MAILHOG_MODE)" ] || [ -n "$(SUPABASE_MODE)" ] || [ -n "$(CHROMADB_MODE)" ] || [ -n "$(GOTENBERG_MODE)" ] || [ -n "$(MONITORING_APP_MODE)" ] || [ -n "$(GRAFANA_MODE)" ] || [ -n "$(BEACON_OLLAMA_MODE)" ]; then :; else $(COMPOSE_MONITORING_AUTH) logs -f; fi

ps:
	@if [ -n "$(INFRA_PGADMIN_MODE)" ] || [ -n "$(INFRA_DNS_MODE)" ] || [ -n "$(INFRA_KEYCLOAK_MODE)" ] || [ -n "$(INFRA_EDGE_MODE)" ] || [ -n "$(PGADMIN_APP_MODE)" ] || [ -n "$(N8N_MODE)" ] || [ -n "$(QA_MODE)" ] || [ -n "$(TOOLS_MODE)" ] || [ -n "$(MINIO_MODE)" ] || [ -n "$(POSTGRESQL_MODE)" ] || [ -n "$(REDIS_MODE)" ] || [ -n "$(MAILHOG_MODE)" ] || [ -n "$(SUPABASE_MODE)" ] || [ -n "$(CHROMADB_MODE)" ] || [ -n "$(GOTENBERG_MODE)" ] || [ -n "$(MONITORING_APP_MODE)" ] || [ -n "$(GRAFANA_MODE)" ] || [ -n "$(BEACON_OLLAMA_MODE)" ]; then :; else $(COMPOSE_MONITORING_AUTH) ps; fi

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
	$(COMPOSE_MONITORING_APP) stop grafana || true
	$(COMPOSE_MONITORING_APP) rm -f grafana || true
	$(DOCKER) volume rm beacon_grafana-data 2>/dev/null || echo "Volume already removed or doesn't exist"
	@echo "Grafana reset complete. Restart with: make grafana up"

reset-monitoring:
	@echo "Resetting monitoring stack (Grafana, Prometheus, Loki, Tempo)..."
	$(COMPOSE_MONITORING_APP) stop || true
	$(COMPOSE_MONITORING_APP) rm -f || true
	$(DOCKER) volume rm beacon_grafana-data beacon_prometheus-data beacon_loki-data beacon_tempo-data 2>/dev/null || echo "Volumes already removed or don't exist"
	@echo "Monitoring reset complete. Restart with: make monitoring up"

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

up-keycloak:
	$(COMPOSE) up -d $(AUTH_SERVICES)

down-keycloak:
	$(COMPOSE) stop $(AUTH_SERVICES)

keycloak-logs:
	$(COMPOSE) logs -f $(AUTH_SERVICES)

keycloak-status:
	$(COMPOSE) ps $(AUTH_SERVICES)

# --- PgAdmin (infra) targets ---
up-pgadmin:
	$(COMPOSE_ADMIN) up -d $(PGADMIN_SERVICES)

down-pgadmin:
	$(COMPOSE_ADMIN) stop $(PGADMIN_SERVICES)

infra-pgadmin-logs:
	$(COMPOSE) logs -f $(PGADMIN_SERVICES)

infra-pgadmin-status:
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

# --- DNS targets ---
up-dns:
	$(COMPOSE) up -d $(DNS_SERVICES)

down-dns:
	$(COMPOSE) stop $(DNS_SERVICES)

dns-logs:
	$(COMPOSE) logs -f $(DNS_SERVICES)

dns-status:
	$(COMPOSE) ps $(DNS_SERVICES)

dns-build:
	$(COMPOSE) build $(DNS_SERVICES)

dns-test:
	@$(COMPOSE) exec -T infra-technitium-dns wget -q --spider http://localhost:5380/ >/dev/null

create_dns:
	@bash scripts/create_dns.sh

# --- Namespaced targets (make infra/dns up|down|logs|log|status|build|test) ---
ifneq (,$(filter infra/dns,$(MAKECMDGOALS)))
infra/dns:
	@case "$(word 2,$(MAKECMDGOALS))" in \
	  up) $(MAKE) up-dns ;; \
	  down) $(MAKE) down-dns ;; \
	  logs) $(MAKE) dns-logs ;; \
	  log) $(MAKE) dns-logs ;; \
	  status) $(MAKE) dns-status ;; \
	  build) $(MAKE) dns-build ;; \
	  test) $(MAKE) dns-test ;; \
	  *) echo "Usage: make infra/dns {up|down|logs|log|status|build|test}"; exit 2 ;; \
	esac

status:
	@:

log:
	@:

build:
	@:

test:
	@:
endif

# --- Namespaced targets (make infra/pgadmin up|down|logs|log|status|test) ---
ifneq (,$(filter infra/pgadmin,$(MAKECMDGOALS)))
infra/pgadmin:
	@case "$(word 2,$(MAKECMDGOALS))" in \
	  up) $(MAKE) up-pgadmin ;; \
	  down) $(MAKE) down-pgadmin ;; \
	  logs) $(MAKE) infra-pgadmin-logs ;; \
	  log) $(MAKE) infra-pgadmin-logs ;; \
	  status) $(MAKE) infra-pgadmin-status ;; \
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

# --- Namespaced targets (make infra/keycloak up|down|logs|log|status|reset) ---
ifneq (,$(filter infra/keycloak,$(MAKECMDGOALS)))
infra/keycloak:
	@case "$(word 2,$(MAKECMDGOALS))" in \
	  up) $(MAKE) up-keycloak ;; \
	  down) $(MAKE) down-keycloak ;; \
	  logs) $(MAKE) keycloak-logs ;; \
	  log) $(MAKE) keycloak-logs ;; \
	  status) $(MAKE) keycloak-status ;; \
	  reset) $(MAKE) reset-keycloak ;; \
	  *) echo "Usage: make infra/keycloak {up|down|logs|log|status|reset}"; exit 2 ;; \
	esac

status:
	@:

log:
	@:

reset:
	@:
endif

# --- Namespaced targets (make infra/edge up|down|logs|log|status|build|test) ---
ifneq (,$(filter infra/edge,$(MAKECMDGOALS)))
infra/edge:
	@case "$(word 2,$(MAKECMDGOALS))" in \
	  up) $(MAKE) up-edge ;; \
	  down) $(MAKE) down-edge ;; \
	  logs) $(MAKE) edge-logs ;; \
	  log) $(MAKE) edge-logs ;; \
	  status) $(MAKE) edge-status ;; \
	  build) $(MAKE) build-edge ;; \
	  test) $(MAKE) test-edge ;; \
	  *) echo "Usage: make infra/edge {up|down|logs|log|status|build|test}"; exit 2 ;; \
	esac

status:
	@:

log:
	@:

build:
	@:

test:
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

# --- Beacon QA targets ---
qa-up:
	$(COMPOSE_QA) up -d --build

qa-down:
	$(COMPOSE_QA) down

qa-build:
	$(COMPOSE_QA) build

qa-logs:
	$(COMPOSE_QA) logs -f

qa-status:
	$(COMPOSE_QA) ps

# --- Beacon Tools targets ---
tools-up:
	$(COMPOSE_BEACON_TOOLS) up -d --build

tools-down:
	$(COMPOSE_BEACON_TOOLS) down

tools-build:
	$(COMPOSE_BEACON_TOOLS) build

tools-logs:
	$(COMPOSE_BEACON_TOOLS) logs -f

tools-status:
	$(COMPOSE_BEACON_TOOLS) ps

# --- Standalone pgAdmin targets ---
pgadmin-up:
	$(COMPOSE_PGADMIN_APP) up -d

pgadmin-down:
	$(COMPOSE_PGADMIN_APP) stop

pgadmin-logs:
	$(COMPOSE_PGADMIN_APP) logs -f

pgadmin-status:
	$(COMPOSE_PGADMIN_APP) ps

# --- n8n app targets ---
n8n-up:
	$(COMPOSE_N8N) up -d

n8n-down:
	$(COMPOSE_N8N) stop

n8n-logs:
	$(COMPOSE_N8N) logs -f

n8n-status:
	$(COMPOSE_N8N) ps

# --- Namespaced targets (make qa up|down|logs|log|status|build) ---
ifneq (,$(filter qa,$(MAKECMDGOALS)))
qa:
	@case "$(word 2,$(MAKECMDGOALS))" in \
	  up) $(MAKE) qa-up ;; \
	  down) $(MAKE) qa-down ;; \
	  logs) $(MAKE) qa-logs ;; \
	  log) $(MAKE) qa-logs ;; \
	  status) $(MAKE) qa-status ;; \
	  build) $(MAKE) qa-build ;; \
	  *) echo "Usage: make qa {up|down|logs|log|status|build}"; exit 2 ;; \
	esac

status:
	@:

log:
	@:

build:
	@:
endif

# --- Namespaced targets (make tools up|down|logs|log|status|build) ---
ifneq (,$(filter tools,$(MAKECMDGOALS)))
tools:
	@case "$(word 2,$(MAKECMDGOALS))" in \
	  up) $(MAKE) tools-up ;; \
	  down) $(MAKE) tools-down ;; \
	  logs) $(MAKE) tools-logs ;; \
	  log) $(MAKE) tools-logs ;; \
	  status) $(MAKE) tools-status ;; \
	  build) $(MAKE) tools-build ;; \
	  *) echo "Usage: make tools {up|down|logs|log|status|build}"; exit 2 ;; \
	esac

status:
	@:

log:
	@:

build:
	@:
endif

# --- MinIO app targets ---
minio-up:
	$(COMPOSE_MINIO) up -d

minio-down:
	$(COMPOSE_MINIO) stop

minio-logs:
	$(COMPOSE_MINIO) logs -f

minio-status:
	$(COMPOSE_MINIO) ps

minio-test:
	$(COMPOSE_MINIO) exec -T minio1 curl -f http://localhost:9000/minio/health/live

# --- PostgreSQL app targets ---
postgresql-up:
	$(COMPOSE_POSTGRESQL) up -d

postgresql-down:
	$(COMPOSE_POSTGRESQL) stop

postgresql-logs:
	$(COMPOSE_POSTGRESQL) logs -f

postgresql-status:
	$(COMPOSE_POSTGRESQL) ps

postgresql-test:
	$(COMPOSE_POSTGRESQL) exec -T postgresql pg_isready -U $${POSTGRES_USER:-beacon} -d $${POSTGRES_DB:-beacon}

# --- Redis app targets ---
redis-up:
	$(COMPOSE_REDIS) up -d

redis-down:
	$(COMPOSE_REDIS) stop

redis-logs:
	$(COMPOSE_REDIS) logs -f

redis-status:
	$(COMPOSE_REDIS) ps

redis-test:
	$(COMPOSE_REDIS) exec -T redis redis-cli -a $${REDIS_PASSWORD:-} ping

# --- MailHog app targets ---
mailhog-up:
	$(COMPOSE_MAILHOG) up -d

mailhog-down:
	$(COMPOSE_MAILHOG) stop

mailhog-logs:
	$(COMPOSE_MAILHOG) logs -f

mailhog-status:
	$(COMPOSE_MAILHOG) ps

mailhog-test:
	$(COMPOSE_MAILHOG) exec -T mailhog wget -q --spider http://localhost:8025

# --- Supabase app targets ---
supabase-up:
	$(COMPOSE_SUPABASE) up -d

supabase-down:
	$(COMPOSE_SUPABASE) stop

supabase-logs:
	$(COMPOSE_SUPABASE) logs -f

supabase-status:
	$(COMPOSE_SUPABASE) ps

supabase-test:
	$(COMPOSE_SUPABASE) exec -T db pg_isready -U postgres -d postgres

# --- ChromaDB app targets ---
chromadb-up:
	$(COMPOSE_CHROMADB) up -d

chromadb-down:
	$(COMPOSE_CHROMADB) stop

chromadb-logs:
	$(COMPOSE_CHROMADB) logs -f

chromadb-status:
	$(COMPOSE_CHROMADB) ps

chromadb-test:
	$(COMPOSE_CHROMADB) exec -T chromadb wget -q --spider http://localhost:8000/api/v1/heartbeat

# --- Gotenberg app targets ---
gotenberg-up:
	$(COMPOSE_GOTENBERG) up -d

gotenberg-down:
	$(COMPOSE_GOTENBERG) stop

gotenberg-logs:
	$(COMPOSE_GOTENBERG) logs -f

gotenberg-status:
	$(COMPOSE_GOTENBERG) ps

# --- Grafana app targets ---
grafana-up:
	$(COMPOSE_MONITORING_APP) up -d grafana grafana-nginx

grafana-down:
	$(COMPOSE_MONITORING_APP) stop grafana grafana-nginx

grafana-logs:
	$(COMPOSE_MONITORING_APP) logs -f grafana grafana-nginx

grafana-status:
	$(COMPOSE_MONITORING_APP) ps

# --- Monitoring app targets ---
monitoring-up:
	$(COMPOSE_MONITORING_APP) up -d

monitoring-down:
	$(COMPOSE_MONITORING_APP) stop

monitoring-logs-app:
	$(COMPOSE_MONITORING_APP) logs -f

monitoring-status-app:
	$(COMPOSE_MONITORING_APP) ps

# --- Namespaced targets (make n8n up|down|logs|log|status) ---
ifneq (,$(filter n8n,$(MAKECMDGOALS)))
n8n:
	@case "$(word 2,$(MAKECMDGOALS))" in \
	  up) $(MAKE) n8n-up ;; \
	  down) $(MAKE) n8n-down ;; \
	  logs) $(MAKE) n8n-logs ;; \
	  log) $(MAKE) n8n-logs ;; \
	  status) $(MAKE) n8n-status ;; \
	  *) echo "Usage: make n8n {up|down|logs|log|status}"; exit 2 ;; \
	esac

status:
	@:

log:
	@:
endif

# --- Namespaced targets (make minio up|down|logs|log|status|test) ---
ifneq (,$(filter minio,$(MAKECMDGOALS)))
minio:
	@case "$(word 2,$(MAKECMDGOALS))" in \
	  up) $(MAKE) minio-up ;; \
	  down) $(MAKE) minio-down ;; \
	  logs) $(MAKE) minio-logs ;; \
	  log) $(MAKE) minio-logs ;; \
	  status) $(MAKE) minio-status ;; \
	  test) $(MAKE) minio-test ;; \
	  *) echo "Usage: make minio {up|down|logs|log|status|test}"; exit 2 ;; \
	esac

status:
	@:

log:
	@:

test:
	@:
endif

# --- Namespaced targets (make postgresql up|down|logs|log|status|test) ---
ifneq (,$(filter postgresql,$(MAKECMDGOALS)))
postgresql:
	@case "$(word 2,$(MAKECMDGOALS))" in \
	  up) $(MAKE) postgresql-up ;; \
	  down) $(MAKE) postgresql-down ;; \
	  logs) $(MAKE) postgresql-logs ;; \
	  log) $(MAKE) postgresql-logs ;; \
	  status) $(MAKE) postgresql-status ;; \
	  test) $(MAKE) postgresql-test ;; \
	  *) echo "Usage: make postgresql {up|down|logs|log|status|test}"; exit 2 ;; \
	esac

status:
	@:

log:
	@:

test:
	@:
endif

# --- Namespaced targets (make redis up|down|logs|log|status|test) ---
ifneq (,$(filter redis,$(MAKECMDGOALS)))
redis:
	@case "$(word 2,$(MAKECMDGOALS))" in \
	  up) $(MAKE) redis-up ;; \
	  down) $(MAKE) redis-down ;; \
	  logs) $(MAKE) redis-logs ;; \
	  log) $(MAKE) redis-logs ;; \
	  status) $(MAKE) redis-status ;; \
	  test) $(MAKE) redis-test ;; \
	  *) echo "Usage: make redis {up|down|logs|log|status|test}"; exit 2 ;; \
	esac

status:
	@:

log:
	@:

test:
	@:
endif

# --- Namespaced targets (make mailhog up|down|logs|log|status|test) ---
ifneq (,$(filter mailhog,$(MAKECMDGOALS)))
mailhog:
	@case "$(word 2,$(MAKECMDGOALS))" in \
	  up) $(MAKE) mailhog-up ;; \
	  down) $(MAKE) mailhog-down ;; \
	  logs) $(MAKE) mailhog-logs ;; \
	  log) $(MAKE) mailhog-logs ;; \
	  status) $(MAKE) mailhog-status ;; \
	  test) $(MAKE) mailhog-test ;; \
	  *) echo "Usage: make mailhog {up|down|logs|log|status|test}"; exit 2 ;; \
	esac

status:
	@:

log:
	@:

test:
	@:
endif

# --- Namespaced targets (make supabase up|down|logs|log|status|test) ---
ifneq (,$(filter supabase,$(MAKECMDGOALS)))
supabase:
	@case "$(word 2,$(MAKECMDGOALS))" in \
	  up) $(MAKE) supabase-up ;; \
	  down) $(MAKE) supabase-down ;; \
	  logs) $(MAKE) supabase-logs ;; \
	  log) $(MAKE) supabase-logs ;; \
	  status) $(MAKE) supabase-status ;; \
	  test) $(MAKE) supabase-test ;; \
	  *) echo "Usage: make supabase {up|down|logs|log|status|test}"; exit 2 ;; \
	esac

status:
	@:

log:
	@:

test:
	@:
endif

# --- Namespaced targets (make chromadb up|down|logs|log|status|test) ---
ifneq (,$(filter chromadb,$(MAKECMDGOALS)))
chromadb:
	@case "$(word 2,$(MAKECMDGOALS))" in \
	  up) $(MAKE) chromadb-up ;; \
	  down) $(MAKE) chromadb-down ;; \
	  logs) $(MAKE) chromadb-logs ;; \
	  log) $(MAKE) chromadb-logs ;; \
	  status) $(MAKE) chromadb-status ;; \
	  test) $(MAKE) chromadb-test ;; \
	  *) echo "Usage: make chromadb {up|down|logs|log|status|test}"; exit 2 ;; \
	esac

status:
	@:

log:
	@:

test:
	@:
endif

# --- Namespaced targets (make gotenberg up|down|logs|log|status) ---
ifneq (,$(filter gotenberg,$(MAKECMDGOALS)))
gotenberg:
	@case "$(word 2,$(MAKECMDGOALS))" in \
	  up) $(MAKE) gotenberg-up ;; \
	  down) $(MAKE) gotenberg-down ;; \
	  logs) $(MAKE) gotenberg-logs ;; \
	  log) $(MAKE) gotenberg-logs ;; \
	  status) $(MAKE) gotenberg-status ;; \
	  *) echo "Usage: make gotenberg {up|down|logs|log|status}"; exit 2 ;; \
	esac

status:
	@:

log:
	@:
endif

# --- Namespaced targets (make grafana up|down|logs|log|status) ---
ifneq (,$(filter grafana,$(MAKECMDGOALS)))
grafana:
	@case "$(word 2,$(MAKECMDGOALS))" in \
	  up) $(MAKE) grafana-up ;; \
	  down) $(MAKE) grafana-down ;; \
	  logs) $(MAKE) grafana-logs ;; \
	  log) $(MAKE) grafana-logs ;; \
	  status) $(MAKE) grafana-status ;; \
	  *) echo "Usage: make grafana {up|down|logs|log|status}"; exit 2 ;; \
	esac

status:
	@:

log:
	@:
endif

# --- Namespaced targets (make monitoring up|down|logs|log|status) ---
ifneq (,$(filter monitoring,$(MAKECMDGOALS)))
monitoring:
	@case "$(word 2,$(MAKECMDGOALS))" in \
	  up) $(MAKE) monitoring-up ;; \
	  down) $(MAKE) monitoring-down ;; \
	  logs) $(MAKE) monitoring-logs-app ;; \
	  log) $(MAKE) monitoring-logs-app ;; \
	  status) $(MAKE) monitoring-status-app ;; \
	  *) echo "Usage: make monitoring {up|down|logs|log|status}"; exit 2 ;; \
	esac

status:
	@:

log:
	@:
endif

# --- Namespaced targets (make pgadmin up|down|logs|log|status) ---
ifneq (,$(filter pgadmin,$(MAKECMDGOALS)))
pgadmin:
	@case "$(word 2,$(MAKECMDGOALS))" in \
	  up) $(MAKE) pgadmin-up ;; \
	  down) $(MAKE) pgadmin-down ;; \
	  logs) $(MAKE) pgadmin-logs ;; \
	  log) $(MAKE) pgadmin-logs ;; \
	  status) $(MAKE) pgadmin-status ;; \
	  *) echo "Usage: make pgadmin {up|down|logs|log|status}"; exit 2 ;; \
	esac

status:
	@:

log:
	@:
endif

# --- Beacon Ollama targets ---
beacon-ollama-up:
	$(COMPOSE_BEACON_OLLAMA) up -d

beacon-ollama-down:
	$(COMPOSE_BEACON_OLLAMA) stop

beacon-ollama-build:
	$(COMPOSE_BEACON_OLLAMA) build

beacon-ollama-test:
	@$(COMPOSE_BEACON_OLLAMA) exec -T beacon-ollama-nginx wget -qO- http://localhost:8000/healthz >/dev/null
	@$(COMPOSE_BEACON_OLLAMA) exec -T beacon-ollama-nginx wget -qO- http://localhost:8000/healthz-beacon-ollama >/dev/null
	@$(COMPOSE_BEACON_OLLAMA) exec -T beacon-ollama-nginx wget -qO- http://localhost:8000/healthz-beacon-ollama-webui >/dev/null

beacon-ollama-logs:
	$(COMPOSE_BEACON_OLLAMA) logs -f

beacon-ollama-status:
	$(COMPOSE_BEACON_OLLAMA) ps

# --- Namespaced targets (make beacon-ollama up|down|build|test|logs|log|status) ---
ifneq (,$(filter beacon-ollama,$(MAKECMDGOALS)))
beacon-ollama:
	@case "$(word 2,$(MAKECMDGOALS))" in \
	  up) $(MAKE) beacon-ollama-up ;; \
	  down) $(MAKE) beacon-ollama-down ;; \
	  build) $(MAKE) beacon-ollama-build ;; \
	  test) $(MAKE) beacon-ollama-test ;; \
	  logs) $(MAKE) beacon-ollama-logs ;; \
	  log) $(MAKE) beacon-ollama-logs ;; \
	  status) $(MAKE) beacon-ollama-status ;; \
	  *) echo "Usage: make beacon-ollama {up|down|build|test|logs|log|status}"; exit 2 ;; \
	esac

status:
	@:

log:
	@:

build:
	@:

test:
	@:
endif

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
	  PGPASSWORD=$$VECTORDB_PASSWORD psql -h $(VECTORDB_HOST) -p $${VECTORDB_PUBLIC_PORT:-$${VECTORDB_PORT:-5432}} -U $$VECTORDB_USER -d $$VECTORDB_DB -c "$(VECTORDB_QUERY)"

# --- Namespaced targets (make vectordb up|down|logs|log|status|test) ---
ifneq (,$(filter vectordb,$(MAKECMDGOALS)))
vectordb:
	@case "$(word 2,$(MAKECMDGOALS))" in \
	  up) $(MAKE) vectordb-up ;; \
	  down) $(MAKE) vectordb-down ;; \
	  logs) $(MAKE) vectordb-logs ;; \
	  log) $(MAKE) vectordb-logs ;; \
	  status) $(MAKE) vectordb-status ;; \
	  test) $(MAKE) vectordb-test ;; \
	  *) echo "Usage: make vectordb {up|down|logs|log|status|test}"; exit 2 ;; \
	esac

status:
	@:

log:
	@:

test:
	@:
endif
