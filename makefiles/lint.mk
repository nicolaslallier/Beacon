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
