# ------------------------------------------------------------------
# SSL / Private CA targets
# ------------------------------------------------------------------
.PHONY: ssl-init ssl-renew ssl-status ssl-install-ca-macos ssl-show-ca-path

ssl-init:
	@echo "Setting up Private CA and certificates..."
	@./scripts/setup-private-ca.sh

ssl-renew:
	@echo "Renewing server certificate..."
	@./scripts/renew-private-cert.sh

ssl-status:
	@echo "=== Certificate Status ==="
	@if [ -f config/certs/fullchain.pem ]; then \
		echo "Server Certificate:"; \
		openssl x509 -in config/certs/fullchain.pem -noout -subject -dates 2>/dev/null || echo "Could not read certificate"; \
		echo ""; \
		echo "Subject Alternative Names:"; \
		openssl x509 -in config/certs/fullchain.pem -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 || true; \
	else \
		echo "No certificate found at config/certs/fullchain.pem"; \
		echo "Run 'make ssl-init' to create certificates"; \
	fi
	@echo ""
	@if [ -f config/ca/beacon-ca.crt ]; then \
		echo "CA Certificate:"; \
		openssl x509 -in config/ca/beacon-ca.crt -noout -subject -dates 2>/dev/null || echo "Could not read CA certificate"; \
	fi

ssl-install-ca-macos:
	@echo "Installing CA certificate on macOS..."
	@if [ -f config/ca/beacon-ca.crt ]; then \
		sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain config/ca/beacon-ca.crt; \
		echo "CA installed. You may need to restart browsers."; \
	else \
		echo "CA not found. Run 'make ssl-init' first."; \
	fi

ssl-show-ca-path:
	@echo "CA certificate path for NODE_EXTRA_CA_CERTS:"
	@echo "export NODE_EXTRA_CA_CERTS=$(PWD)/config/ca/beacon-ca.crt"
