# ------------------------------------------------------------------
# Frey (Beacon Tools frontend) targets
# ------------------------------------------------------------------
.PHONY: frey-install frey-dev frey-build frey-lint frey-format frey-test frey-preview \
	frey-up frey-down frey-logs frey-status frey

frey-up:
	$(COMPOSE_FREY) up -d --build

frey-down:
	$(COMPOSE_FREY) down

frey-logs:
	$(COMPOSE_FREY) logs -f

frey-status:
	$(COMPOSE_FREY) ps

frey-install:
	@echo "[Frey Install] Installing dependencies..."
	cd $(FREY_DIR) && pnpm install

frey-dev:
	@echo "[Frey Dev] Starting Vite dev server..."
	cd $(FREY_DIR) && pnpm run dev

frey-build:
	@echo "[Frey Build] Building for production..."
	cd $(FREY_DIR) && pnpm run build

frey-lint:
	@echo "[Frey Lint] Running ESLint..."
	cd $(FREY_DIR) && pnpm run lint

frey-format:
	@echo "[Frey Format] Running Prettier..."
	cd $(FREY_DIR) && pnpm run format

frey-test:
	@echo "[Frey Test] Running Vitest..."
	cd $(FREY_DIR) && pnpm run test

frey-preview:
	@echo "[Frey Preview] Previewing production build..."
	cd $(FREY_DIR) && pnpm run preview

# --- Namespaced targets (make frey up|down|test|install|build|lint|format|preview) ---
ifneq (,$(filter frey,$(MAKECMDGOALS)))
frey:
	@case "$(word 2,$(MAKECMDGOALS))" in \
	  up) $(MAKE) frey-up ;; \
	  down) $(MAKE) frey-down ;; \
	  logs) $(MAKE) frey-logs ;; \
	  status) $(MAKE) frey-status ;; \
	  test) $(MAKE) frey-test ;; \
	  install) $(MAKE) frey-install ;; \
	  build) $(MAKE) frey-build ;; \
	  lint) $(MAKE) frey-lint ;; \
	  format) $(MAKE) frey-format ;; \
	  preview) $(MAKE) frey-preview ;; \
	  dev) $(MAKE) frey-dev ;; \
	  *) echo "Usage: make frey {up|down|logs|status|test|install|build|lint|format|preview|dev}"; exit 2 ;; \
	esac

# Stub targets so word 2 does not invoke missing/global rules (up/down use FREY_MODE in compose.mk)
test install build lint format preview dev logs status:
	@:
endif
