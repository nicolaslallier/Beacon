# ------------------------------------------------------------------
# CI pipeline
# ------------------------------------------------------------------
.PHONY: ci

ci: lint docker-build
	@echo "CI pipeline completed successfully"
