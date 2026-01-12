#!/bin/bash
# =============================================================================
# Renew Private Certificate Script
# =============================================================================
# Renews the server certificate using your existing private CA.
# Run this before the certificate expires (certificates are valid for 1 year).
#
# Usage: ./scripts/renew-private-cert.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Just re-run the setup script - it reuses the existing CA
"$SCRIPT_DIR/setup-private-ca.sh"

# Reload nginx if running
echo ""
echo "🔄 Reloading nginx..."
docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T nginx nginx -s reload 2>/dev/null || \
    echo "⚠️  nginx not running or reload failed. Restart manually if needed."

echo ""
echo "✅ Certificate renewed successfully!"
