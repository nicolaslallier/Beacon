# ------------------------------------------------------------------
# Helpers (help, version, info)
# ------------------------------------------------------------------
.PHONY: help version info env-check

define help_line
	@printf "  make %-24s # %s\n" "$(1)" "$(2)"
endef

help:
	@printf "\n=== CI/CD Makefile (Beacon) ===\n\n"
	@printf "\n## Applications\n"
	@printf "### pgAdmin (app)\n"
	$(call help_line,pgadmin up,Start pgAdmin app)
	$(call help_line,pgadmin down,Stop pgAdmin app)
	$(call help_line,pgadmin logs,Logs for pgAdmin app)
	$(call help_line,pgadmin status,Status for pgAdmin app)
	@printf "### Monitoring (app)\n"
	$(call help_line,monitoring up,Start monitoring app)
	$(call help_line,monitoring down,Stop monitoring app)
	$(call help_line,monitoring logs,Logs for monitoring app)
	$(call help_line,monitoring status,Status for monitoring app)
	$(call help_line,reset-monitoring,Reset monitoring data volumes)
	@printf "### Beacon Ollama\n"
	$(call help_line,beacon-ollama up,Start Beacon Ollama services)
	$(call help_line,beacon-ollama down,Stop Beacon Ollama services)
	$(call help_line,beacon-ollama build,Build Beacon Ollama services)
	$(call help_line,beacon-ollama test,Run Beacon Ollama health checks)
	$(call help_line,beacon-ollama status,Status for Beacon Ollama services)
	@printf "### n8n\n"
	$(call help_line,n8n up,Start n8n services)
	$(call help_line,n8n down,Stop n8n services)
	$(call help_line,n8n logs,Logs for n8n services)
	$(call help_line,n8n status,Status for n8n services)
	@printf "### MinIO\n"
	$(call help_line,minio up,Start MinIO services)
	$(call help_line,minio down,Stop MinIO services)
	$(call help_line,minio logs,Logs for MinIO services)
	$(call help_line,minio status,Status for MinIO services)
	$(call help_line,minio test,Run MinIO health check)
	@printf "### PostgreSQL\n"
	$(call help_line,postgresql up,Start PostgreSQL services)
	$(call help_line,postgresql down,Stop PostgreSQL services)
	$(call help_line,postgresql logs,Logs for PostgreSQL services)
	$(call help_line,postgresql status,Status for PostgreSQL services)
	$(call help_line,postgresql test,Run PostgreSQL readiness check)
	@printf "### Redis\n"
	$(call help_line,redis up,Start Redis services)
	$(call help_line,redis down,Stop Redis services)
	$(call help_line,redis logs,Logs for Redis services)
	$(call help_line,redis status,Status for Redis services)
	$(call help_line,redis test,Run Redis health check)
	@printf "### MailHog\n"
	$(call help_line,mailhog up,Start MailHog services)
	$(call help_line,mailhog down,Stop MailHog services)
	$(call help_line,mailhog logs,Logs for MailHog services)
	$(call help_line,mailhog status,Status for MailHog services)
	$(call help_line,mailhog test,Run MailHog health check)
	@printf "### Supabase\n"
	$(call help_line,supabase up,Start Supabase services)
	$(call help_line,supabase down,Stop Supabase services)
	$(call help_line,supabase logs,Logs for Supabase services)
	$(call help_line,supabase status,Status for Supabase services)
	$(call help_line,supabase test,Run Supabase readiness check)
	@printf "### ChromaDB\n"
	$(call help_line,chromadb up,Start ChromaDB services)
	$(call help_line,chromadb down,Stop ChromaDB services)
	$(call help_line,chromadb logs,Logs for ChromaDB services)
	$(call help_line,chromadb status,Status for ChromaDB services)
	$(call help_line,chromadb test,Run ChromaDB health check)
	@printf "### Gotenberg\n"
	$(call help_line,gotenberg up,Start Gotenberg services)
	$(call help_line,gotenberg down,Stop Gotenberg services)
	$(call help_line,gotenberg logs,Logs for Gotenberg services)
	$(call help_line,gotenberg status,Status for Gotenberg services)
	@printf "\n## Infra\n"
	@printf "### Edge (Traefik + static web)\n"
	$(call help_line,up-edge,Start edge services)
	$(call help_line,down-edge,Stop edge services)
	$(call help_line,edge-logs,Logs for edge services)
	$(call help_line,edge-status,Status for edge services)
	$(call help_line,build-edge,Build edge services)
	$(call help_line,test-edge,Test edge config)
	@printf "### DNS\n"
	$(call help_line,up-dns,Start DNS service)
	$(call help_line,down-dns,Stop DNS service)
	$(call help_line,dns-logs,Logs for DNS service)
	$(call help_line,dns-status,Status for DNS service)
	$(call help_line,dns-build,Build DNS service)
	$(call help_line,dns-test,Run DNS health check)
	$(call help_line,create_dns,Create DNS zone + records via Technitium API)
	@printf "### Keycloak\n"
	$(call help_line,up-keycloak,Start Keycloak services)
	$(call help_line,down-keycloak,Stop Keycloak services)
	$(call help_line,keycloak-logs,Logs for Keycloak services)
	$(call help_line,keycloak-status,Status for Keycloak services)
	$(call help_line,reset-keycloak,Reset Keycloak data volume)

version:
	@echo "$(VERSION)"

info:
	@printf "Project : $(PROJECT)\n"
	@printf "Env     : $(ENV)\n"
	@printf "Image   : $(FULL_IMAGE):$(VERSION)\n"

env-check:
	@echo "Checking environment variables..."
	@echo "TRAEFIK_HTTP_PORT: ${TRAEFIK_HTTP_PORT:-80}"
	@echo "GRAFANA_PORT: ${GRAFANA_PORT:-3000}"
	@echo "GF_SECURITY_ADMIN_PASSWORD: $${GF_SECURITY_ADMIN_PASSWORD:-not set}"
	@if [ -f .env ]; then \
	  echo "\n.env file exists. Contents:"; \
	  grep -v "^#" .env | grep -v "^$$" || echo "  (empty or only comments)"; \
	else \
	  echo "\nWARNING: .env file not found!"; \
	fi
