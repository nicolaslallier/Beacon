#!/bin/bash
# =============================================================================
# Launch LM Studio with Beacon Private CA trusted
# =============================================================================
# This script sets the NODE_EXTRA_CA_CERTS environment variable
# so that LM Studio's internal Node.js will trust your private CA.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CA_CERT="$PROJECT_DIR/ca/beacon-ca.crt"

if [ ! -f "$CA_CERT" ]; then
    echo "❌ CA certificate not found: $CA_CERT"
    echo "   Run: cd $PROJECT_DIR && make ssl-init"
    exit 1
fi

echo "🔐 Setting NODE_EXTRA_CA_CERTS=$CA_CERT"
export NODE_EXTRA_CA_CERTS="$CA_CERT"

echo "🚀 Launching LM Studio..."
open -a "LM Studio"

echo "✅ LM Studio launched with private CA trusted"
