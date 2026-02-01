#!/bin/bash
# Generate self-signed SSL certificates for development/testing
# For production, use Let's Encrypt or proper CA-signed certificates

set -e

CERTS_DIR="${1:-./config/certs}"
DOMAIN="${2:-beacon.famillelallier.net}"

# Create certs directory
mkdir -p "$CERTS_DIR"

# Generate private key
openssl genrsa -out "$CERTS_DIR/privkey.pem" 2048

# Generate certificate signing request (CSR) with SANs
cat > "$CERTS_DIR/csr.conf" << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[dn]
C = CA
ST = Quebec
L = Montreal
O = Beacon
OU = Development
CN = ${DOMAIN}

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}
DNS.2 = *.${DOMAIN}
DNS.3 = keycloak.${DOMAIN}
DNS.4 = grafana.${DOMAIN}
DNS.5 = prometheus.${DOMAIN}
DNS.6 = loki.${DOMAIN}
DNS.7 = tempo.${DOMAIN}
DNS.8 = minio.${DOMAIN}
DNS.9 = s3.${DOMAIN}
DNS.10 = beacon-library.famillelallier.net
DNS.11 = postgresql.${DOMAIN}
DNS.12 = redis.${DOMAIN}
DNS.13 = supabase.${DOMAIN}
DNS.14 = chromadb.${DOMAIN}
DNS.15 = localhost
EOF

# Generate self-signed certificate
openssl req -x509 -nodes -days 365 \
  -key "$CERTS_DIR/privkey.pem" \
  -out "$CERTS_DIR/fullchain.pem" \
  -config "$CERTS_DIR/csr.conf" \
  -extensions req_ext

# Clean up CSR config
rm -f "$CERTS_DIR/csr.conf"

echo "✅ Self-signed certificates generated in $CERTS_DIR/"
echo "   - fullchain.pem (certificate)"
echo "   - privkey.pem (private key)"
echo ""
echo "⚠️  These are SELF-SIGNED certificates for development only!"
echo "   For production, use Let's Encrypt or a proper CA."
echo ""
echo "To trust this certificate on macOS:"
echo "   sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $CERTS_DIR/fullchain.pem"
