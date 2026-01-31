# ------------------------------------------------------------------
# Beacon Library targets
# ------------------------------------------------------------------
.PHONY: library-install library-dev library-dev-backend library-dev-frontend \
	library-up library-down library-restart library-logs library-ps \
	library-lint library-lint-backend library-lint-frontend library-format \
	library-test library-test-unit library-test-integration library-test-regression \
	library-ci library-cd library-docker-build library-push library-deploy \
	library-observability-up library-observability-down library-observability-logs library-observability-status \
	library-observability-test library-observability-test-loki library-observability-test-tempo library-observability-test-prometheus library-observability-test-all \
	library-minio-test library-minio-test-connection library-minio-test-upload library-minio-test-download library-minio-test-all \
	library-admin-up library-admin-down library-admin-logs library-admin-status

library-install:
	@echo "[Library Install] Installing backend and frontend dependencies..."
	cd $(LIBRARY_DIR)/backend && poetry install
	cd $(LIBRARY_DIR)/frontend && npm install

library-dev:
	@echo "[Library Dev] Starting backend and frontend in dev mode..."
	$(MAKE) -j2 library-dev-backend library-dev-frontend

library-dev-backend:
	@echo "[Library Dev Backend] Starting FastAPI with uvicorn..."
	cd $(LIBRARY_DIR)/backend && poetry run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

library-dev-frontend:
	@echo "[Library Dev Frontend] Starting Vite dev server..."
	cd $(LIBRARY_DIR)/frontend && npm run dev

library-up:
	@echo "[Library Up] Starting Beacon Library services (ENV=$(ENV))..."
	@echo "Note: relies on Beacon services (Keycloak, MinIO, monitoring) when enabled."
	$(COMPOSE_LIBRARY) up -d $(LIBRARY_BASE_SERVICES)
	$(COMPOSE_LIBRARY) up -d --no-deps $(LIBRARY_APP_SERVICES)

library-down:
	@echo "[Library Down] Stopping Beacon Library services..."
	$(COMPOSE_LIBRARY) down

library-restart:
	@echo "[Library Restart] Restarting Beacon Library services..."
	$(COMPOSE_LIBRARY) up -d --force-recreate

library-logs:
	@echo "[Library Logs] Showing Beacon Library logs..."
	$(COMPOSE_LIBRARY) logs -f

library-ps:
	@echo "[Library PS] Running Beacon Library containers..."
	$(COMPOSE_LIBRARY) ps

library-lint-backend:
	@echo "[Library Lint Backend] black, flake8, mypy..."
	cd $(LIBRARY_DIR)/backend && poetry run black --check app || exit 1
	cd $(LIBRARY_DIR)/backend && poetry run flake8 app || exit 1
	cd $(LIBRARY_DIR)/backend && poetry run mypy app || exit 1

library-lint-frontend:
	@echo "[Library Lint Frontend] eslint..."
	cd $(LIBRARY_DIR)/frontend && npm run lint

library-lint: library-lint-backend library-lint-frontend

library-format:
	@echo "[Library Format Backend] black..."
	cd $(LIBRARY_DIR)/backend && poetry run black app

library-test library-test-unit:
	@echo "[Library Unit Tests] Backend (pytest)..."
	cd $(LIBRARY_DIR)/backend && poetry run pytest tests/unit

library-test-integration:
	@echo "[Library Integration Tests] Backend (pytest)..."
	cd $(LIBRARY_DIR)/backend && poetry run pytest tests/integration

library-test-regression:
	@echo "[Library Regression Tests] (stubbed)"
	@echo "Implement E2E test commands here as needed..."

library-ci:
	@echo "[Library CI Pipeline] Lint -> Unit Tests -> Integration -> Build"
	$(MAKE) library-lint
	$(MAKE) library-test-unit
	$(MAKE) library-test-integration
	$(MAKE) library-docker-build
	@echo "[Library CI Pipeline] Complete"

library-cd:
	@echo "[Library CD Pipeline] CI -> Push -> Deploy (ENV=$(ENV))"
	$(MAKE) library-ci
	$(MAKE) library-push
	$(MAKE) library-deploy

library-docker-build:
	@echo "[Library Docker Build] Building backend, frontend, and MCP images..."
	$(COMPOSE_LIBRARY) build

library-push:
	@echo "[Library Docker Push] Pushing images..."
	$(COMPOSE_LIBRARY) push || echo "Implement auth and registry logic as needed"

library-deploy:
	@echo "[Library Deploy] (Stub) Implement deploy logic as needed for ENV=$(ENV)"
	@echo "(Options: docker compose up for prod, SSH-based, etc.)"

# Observability targets for Beacon Library
library-observability-up:
	@echo "[Library Observability] Starting collectors..."
	$(COMPOSE_LIBRARY_OBS) up -d $(LIBRARY_OBSERVABILITY_SERVICES)

library-observability-down:
	@echo "[Library Observability] Stopping collectors..."
	$(COMPOSE_OBSERVABILITY) stop $(LIBRARY_OBSERVABILITY_SERVICES)
	$(COMPOSE_OBSERVABILITY) rm -f $(LIBRARY_OBSERVABILITY_SERVICES)

library-observability-logs:
	@echo "[Library Observability] Showing collector logs..."
	$(COMPOSE_OBSERVABILITY) logs -f beacon-library-promtail beacon-library-alloy

library-observability-status:
	@echo "[Library Observability] Checking pipeline status..."
	@$(COMPOSE_OBSERVABILITY) ps $(LIBRARY_OBSERVABILITY_SERVICES) 2>/dev/null || echo "Collectors not running"

library-observability-test: library-observability-test-all
	@echo "All library observability tests completed!"

library-observability-test-loki:
	@echo "[Library Test Loki] Testing log ingestion..."
	@$(DOCKER) run --rm --network $(LIBRARY_OBSERVABILITY_TEST_NETWORK) $(LIBRARY_OBSERVABILITY_TEST_IMAGE) \
		-sf http://beacon-loki:3100/ready || (echo "Loki not ready"; exit 1)
	@$(DOCKER) run --rm --network $(LIBRARY_OBSERVABILITY_TEST_NETWORK) $(LIBRARY_OBSERVABILITY_TEST_IMAGE) \
		-X POST "http://beacon-loki:3100/loki/api/v1/push" \
		-H "Content-Type: application/json" \
		-d '{"streams":[{"stream":{"job":"beacon-library-test","service":"makefile-test"},"values":[["'$$(date +%s)000000000'","Test log from make library-observability-test-loki"]]}]}'

library-observability-test-tempo:
	@echo "[Library Test Tempo] Testing trace ingestion..."
	@$(DOCKER) run --rm --network $(LIBRARY_OBSERVABILITY_TEST_NETWORK) $(LIBRARY_OBSERVABILITY_TEST_IMAGE) \
		-sf http://beacon-tempo:3200/ready || (echo "Tempo not ready"; exit 1)
	@TRACE_ID=$$(openssl rand -hex 16) && \
	SPAN_ID=$$(openssl rand -hex 8) && \
	NOW=$$(date +%s)000000000 && \
	END=$$(( $$(date +%s) + 1 ))000000000 && \
	$(DOCKER) run --rm --network $(LIBRARY_OBSERVABILITY_TEST_NETWORK) $(LIBRARY_OBSERVABILITY_TEST_IMAGE) \
		-X POST "http://beacon-tempo:4318/v1/traces" \
		-H "Content-Type: application/json" \
		-d '{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"makefile-test"}}]},"scopeSpans":[{"spans":[{"traceId":"'"$$TRACE_ID"'","spanId":"'"$$SPAN_ID"'","name":"test-span","kind":1,"startTimeUnixNano":"'"$$NOW"'","endTimeUnixNano":"'"$$END"'","attributes":[{"key":"test.source","value":{"stringValue":"makefile"}}]}]}]}]}'

library-observability-test-prometheus:
	@echo "[Library Test Prometheus] Testing metrics endpoint..."
	@$(DOCKER) run --rm --network $(LIBRARY_OBSERVABILITY_TEST_NETWORK) $(LIBRARY_OBSERVABILITY_TEST_IMAGE) \
		-sf http://beacon-prometheus:9090/-/ready || (echo "Prometheus not ready"; exit 1)
	@$(DOCKER) run --rm --network $(LIBRARY_OBSERVABILITY_TEST_NETWORK) $(LIBRARY_OBSERVABILITY_TEST_IMAGE) \
		-sf 'http://beacon-prometheus:9090/api/v1/query?query=up' >/dev/null

library-observability-test-all: library-observability-test-loki library-observability-test-tempo library-observability-test-prometheus
	@echo "[Library Observability] All endpoints tested."

# MinIO Storage Targets for Beacon Library
library-minio-test: library-minio-test-all
	@echo "All MinIO tests completed!"

library-minio-test-connection:
	@echo "[Library Test MinIO] Testing connection..."
	@$(DOCKER) run --rm --network $(LIBRARY_MINIO_TEST_NETWORK) --entrypoint /bin/sh $(LIBRARY_MINIO_TEST_IMAGE) \
		-c "mc alias set testminio http://$(LIBRARY_MINIO_ENDPOINT) $(LIBRARY_MINIO_ACCESS_KEY) $(LIBRARY_MINIO_SECRET_KEY) && mc admin info testminio"

library-minio-test-upload:
	@echo "[Library Test MinIO] Testing upload..."
	@$(DOCKER) run --rm --network $(LIBRARY_MINIO_TEST_NETWORK) --entrypoint /bin/sh $(LIBRARY_MINIO_TEST_IMAGE) \
		-c "mc alias set testminio http://$(LIBRARY_MINIO_ENDPOINT) $(LIBRARY_MINIO_ACCESS_KEY) $(LIBRARY_MINIO_SECRET_KEY) && \
		    mc mb --ignore-existing testminio/$(LIBRARY_MINIO_BUCKET)"
	@$(DOCKER) run --rm --network $(LIBRARY_MINIO_TEST_NETWORK) --entrypoint /bin/sh $(LIBRARY_MINIO_TEST_IMAGE) \
		-c "mc alias set testminio http://$(LIBRARY_MINIO_ENDPOINT) $(LIBRARY_MINIO_ACCESS_KEY) $(LIBRARY_MINIO_SECRET_KEY) && \
		    echo 'Test file from make library-minio-test at $$(date)' > /tmp/test.txt && \
		    mc cp /tmp/test.txt testminio/$(LIBRARY_MINIO_BUCKET)/test-$$(date +%s).txt"

library-minio-test-download:
	@echo "[Library Test MinIO] Testing download..."
	@$(DOCKER) run --rm --network $(LIBRARY_MINIO_TEST_NETWORK) --entrypoint /bin/sh $(LIBRARY_MINIO_TEST_IMAGE) \
		-c "mc alias set testminio http://$(LIBRARY_MINIO_ENDPOINT) $(LIBRARY_MINIO_ACCESS_KEY) $(LIBRARY_MINIO_SECRET_KEY) > /dev/null 2>&1 && \
		    mc find testminio/$(LIBRARY_MINIO_BUCKET)/ --name 'test-*.txt' | tail -1 | while read filepath; do \
		        if [ -n \"\$$filepath\" ]; then \
		            mc cat \"\$$filepath\" && echo; \
		        fi; \
		    done"

library-minio-test-all: library-minio-test-connection library-minio-test-upload library-minio-test-download
	@echo "[Library MinIO] All storage tests passed."

# Admin services for Beacon Library (profile: admin)
library-admin-up:
	@echo "[Library Admin] Starting admin services..."
	$(COMPOSE_ADMIN_LIBRARY) up -d

library-admin-down:
	@echo "[Library Admin] Stopping admin services..."
	$(COMPOSE_ADMIN_LIBRARY) stop
	$(COMPOSE_ADMIN_LIBRARY) rm -f

library-admin-logs:
	@echo "[Library Admin] Showing admin services logs..."
	$(COMPOSE_ADMIN_LIBRARY) logs -f

library-admin-status:
	@echo "[Library Admin] Admin services status..."
	$(COMPOSE_ADMIN_LIBRARY) ps
