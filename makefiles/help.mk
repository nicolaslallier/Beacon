# ------------------------------------------------------------------
# Helpers (help, version, info)
# ------------------------------------------------------------------
.PHONY: help version info env-check

define help_line
	@printf "  make %-24s # %s\n" "$(1)" "$(2)"
endef

help:
	@printf "\n=== CI/CD Makefile (Beacon) ===\n\n"
	@printf "## Dev/Build\n"
	$(call help_line,docker-build,Construit l'image Docker)
	@printf "\n## Quality\n"
	$(call help_line,lint,Lint global (Dockerfile, shell, nginx))
	$(call help_line,lint-docker,Lint du Dockerfile (hadolint))
	$(call help_line,lint-shell,Lint des scripts shell (shellcheck))
	$(call help_line,lint-nginx,Test la conf NGINX)
	@printf "\n## Docker Compose\n"
	$(call help_line,up,Demarre tous les services (nginx + monitoring + auth))
	$(call help_line,up-core,Demarre uniquement nginx)
	$(call help_line,up-monitoring,Demarre nginx + monitoring)
	$(call help_line,up-auth,Demarre nginx + auth (Keycloak))
	$(call help_line,up-monitoring-only,Seulement la stack monitoring)
	$(call help_line,up-auth-only,Seulement Keycloak + DB)
	$(call help_line,down,Stoppe tous les services)
	$(call help_line,down-monitoring,Arrete tout avec monitoring)
	$(call help_line,down-auth,Arrete tout avec auth)
	$(call help_line,down-monitoring-only,Stoppe uniquement la stack monitoring)
	$(call help_line,down-auth-only,Stoppe uniquement Keycloak + DB)
	$(call help_line,restart,Redemarre les services)
	$(call help_line,logs,Affiche les logs)
	$(call help_line,monitoring-logs,Logs only monitoring services)
	$(call help_line,auth-logs,Logs only auth services (Keycloak))
	$(call help_line,ps,Montre le statut des services)
	$(call help_line,monitoring-status,Statut health monitoring)
	$(call help_line,auth-status,Statut health auth (Keycloak))
	$(call help_line,reset-grafana,Reset Grafana (delete data, use new password))
	$(call help_line,reset-keycloak,Reset Keycloak (delete data))
	@printf "\n## Beacon Library\n"
	$(call help_line,library-install,Install backend and frontend deps)
	$(call help_line,library-dev,Run backend + frontend in dev mode)
	$(call help_line,library-up,Start Beacon Library services)
	$(call help_line,library-down,Stop Beacon Library services)
	$(call help_line,library-logs,Logs for Beacon Library services)
	$(call help_line,library-lint,Lint backend + frontend)
	$(call help_line,library-test-unit,Run backend unit tests)
	$(call help_line,library-observability-up,Start library collectors)
	$(call help_line,library-minio-test,Run library MinIO tests)
	@printf "\n## SSL / Private CA\n"
	$(call help_line,ssl-init,Create private CA and certificates)
	$(call help_line,ssl-renew,Renew server certificate)
	$(call help_line,ssl-status,Show certificate info and expiry)
	$(call help_line,ssl-install-ca-macos,Install CA on macOS)
	$(call help_line,ssl-show-ca-path,Show path for NODE_EXTRA_CA_CERTS)
	@printf "\n## CI Pipeline\n"
	$(call help_line,ci,Pipeline CI complet (lint + build))
	@printf "\n## Release/Deploy\n"
	$(call help_line,push,Push l'image vers le registry)
	@printf "\n## Info\n"
	$(call help_line,version,Affiche la version)
	$(call help_line,info,Affiche project/env/image)
	$(call help_line,env-check,Verifie les variables d'environnement)

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
