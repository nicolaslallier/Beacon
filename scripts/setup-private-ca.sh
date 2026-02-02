#!/bin/bash
# =============================================================================
# Private CA and Certificate Setup Script
# =============================================================================
# Creates a private Certificate Authority and issues certificates for your
# internal network. No internet or public DNS required.
#
# Usage: ./scripts/setup-private-ca.sh
#
# After running this script:
# 1. Install config/ca/beacon-ca.crt on devices that need to trust your certificates
# 2. Certificates will be valid for 1 year, CA valid for 10 years
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load environment if exists
if [ -f "$PROJECT_DIR/.env" ]; then
    export $(grep -v '^#' "$PROJECT_DIR/.env" | xargs)
fi

# Configuration
CA_DIR="$PROJECT_DIR/config/ca"
CERTS_DIR="$PROJECT_DIR/config/certs"
CA_DAYS=3650  # 10 years for CA
CERT_DAYS=365 # 1 year for certificates

# Your domains - add any local domains you use
DOMAINS=(
    "beacon-library.famillelallier.net"
    "grafana.beacon.famillelallier.net"
    "prometheus.beacon.famillelallier.net"
    "loki.beacon.famillelallier.net"
    "tempo.beacon.famillelallier.net"
    "minio.beacon.famillelallier.net"
    "s3.beacon.famillelallier.net"
    "keycloak.beacon.famillelallier.net"
    "mcp-vector.beacon.famillelallier.net"
    "postgresql.beacon.famillelallier.net"
    "beacon-ollama-webui.beacon.famillelallier.net"
    "redis.beacon.famillelallier.net"
    "supabase.beacon.famillelallier.net"
    "chromadb.beacon.famillelallier.net"
    "localhost"
)

# IP addresses to include (add your server's IPs)
IP_ADDRESSES=(
    "127.0.0.1"
    "192.168.2.35"   # Your LM Studio server
    # Add more IPs as needed
)

# CA details
CA_COUNTRY="${CA_COUNTRY:-CA}"
CA_STATE="${CA_STATE:-Quebec}"
CA_CITY="${CA_CITY:-Montreal}"
CA_ORG="${CA_ORG:-Famille Lallier}"
CA_OU="${CA_OU:-IT Department}"
CA_CN="${CA_CN:-Beacon Private CA}"
CA_EMAIL="${CA_EMAIL:-admin@famillelallier.net}"

echo "=============================================="
echo "Private CA and Certificate Setup"
echo "=============================================="
echo "CA Directory: $CA_DIR"
echo "Certs Directory: $CERTS_DIR"
echo "Domains: ${DOMAINS[*]}"
echo "IPs: ${IP_ADDRESSES[*]}"
echo "=============================================="

# Create directories
mkdir -p "$CA_DIR"
mkdir -p "$CERTS_DIR"

# =============================================================================
# Step 1: Create Private CA (if not exists)
# =============================================================================
if [ ! -f "$CA_DIR/beacon-ca.key" ]; then
    echo ""
    echo "📜 Creating Private Certificate Authority..."
    
    # Generate CA private key
    openssl genrsa -out "$CA_DIR/beacon-ca.key" 4096
    chmod 600 "$CA_DIR/beacon-ca.key"
    
    # Generate CA certificate
    openssl req -x509 -new -nodes \
        -key "$CA_DIR/beacon-ca.key" \
        -sha256 \
        -days $CA_DAYS \
        -out "$CA_DIR/beacon-ca.crt" \
        -subj "/C=$CA_COUNTRY/ST=$CA_STATE/L=$CA_CITY/O=$CA_ORG/OU=$CA_OU/CN=$CA_CN/emailAddress=$CA_EMAIL"
    
    echo "✅ CA created: $CA_DIR/beacon-ca.crt"
    echo "   CA valid for $CA_DAYS days ($(($CA_DAYS / 365)) years)"
else
    echo "✅ CA already exists, reusing..."
fi

# =============================================================================
# Step 2: Create Server Certificate
# =============================================================================
echo ""
echo "🔐 Creating server certificate..."

# Build SAN (Subject Alternative Names) extension
SAN="[req]\nreq_extensions = v3_req\ndistinguished_name = req_distinguished_name\n\n"
SAN+="[req_distinguished_name]\n\n"
SAN+="[v3_req]\nbasicConstraints = CA:FALSE\nkeyUsage = nonRepudiation, digitalSignature, keyEncipherment\n"
SAN+="subjectAltName = @alt_names\n\n"
SAN+="[alt_names]\n"

# Add DNS entries
i=1
for domain in "${DOMAINS[@]}"; do
    SAN+="DNS.$i = $domain\n"
    ((i++))
done

# Add IP entries
j=1
for ip in "${IP_ADDRESSES[@]}"; do
    SAN+="IP.$j = $ip\n"
    ((j++))
done

# Write OpenSSL config
echo -e "$SAN" > "$CA_DIR/san.cnf"

# Generate server private key
openssl genrsa -out "$CERTS_DIR/privkey.pem" 2048
chmod 600 "$CERTS_DIR/privkey.pem"

# Generate Certificate Signing Request (CSR)
openssl req -new \
    -key "$CERTS_DIR/privkey.pem" \
    -out "$CA_DIR/server.csr" \
    -config "$CA_DIR/san.cnf" \
    -subj "/C=$CA_COUNTRY/ST=$CA_STATE/L=$CA_CITY/O=$CA_ORG/OU=$CA_OU/CN=${DOMAINS[0]}/emailAddress=$CA_EMAIL"

# Sign the certificate with our CA
openssl x509 -req \
    -in "$CA_DIR/server.csr" \
    -CA "$CA_DIR/beacon-ca.crt" \
    -CAkey "$CA_DIR/beacon-ca.key" \
    -CAcreateserial \
    -out "$CERTS_DIR/cert.pem" \
    -days $CERT_DAYS \
    -sha256 \
    -extensions v3_req \
    -extfile "$CA_DIR/san.cnf"

# Create fullchain (cert + CA)
cat "$CERTS_DIR/cert.pem" "$CA_DIR/beacon-ca.crt" > "$CERTS_DIR/fullchain.pem"

# Set permissions
chmod 644 "$CERTS_DIR/cert.pem"
chmod 644 "$CERTS_DIR/fullchain.pem"
chmod 644 "$CA_DIR/beacon-ca.crt"

# Cleanup CSR
rm -f "$CA_DIR/server.csr"

echo "✅ Server certificate created"

# =============================================================================
# Step 3: Verify certificates
# =============================================================================
echo ""
echo "🔍 Verifying certificates..."

echo ""
echo "CA Certificate:"
openssl x509 -in "$CA_DIR/beacon-ca.crt" -noout -subject -dates

echo ""
echo "Server Certificate:"
openssl x509 -in "$CERTS_DIR/cert.pem" -noout -subject -dates

echo ""
echo "Subject Alternative Names:"
openssl x509 -in "$CERTS_DIR/cert.pem" -noout -text | grep -A1 "Subject Alternative Name" | tail -1

# Verify chain
echo ""
echo "Chain verification:"
openssl verify -CAfile "$CA_DIR/beacon-ca.crt" "$CERTS_DIR/cert.pem"

# =============================================================================
# Done!
# =============================================================================
echo ""
echo "=============================================="
echo "✅ Private CA Setup Complete!"
echo "=============================================="
echo ""
echo "Created files:"
echo "  CA Certificate:     $CA_DIR/beacon-ca.crt"
echo "  CA Private Key:     $CA_DIR/beacon-ca.key (KEEP SECRET!)"
echo "  Server Certificate: $CERTS_DIR/fullchain.pem"
echo "  Server Private Key: $CERTS_DIR/privkey.pem"
echo ""
echo "=============================================="
echo "NEXT STEPS - Install the CA on your devices:"
echo "=============================================="
echo ""
echo "📱 macOS:"
echo "   sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $CA_DIR/beacon-ca.crt"
echo ""
echo "🐧 Linux (Ubuntu/Debian):"
echo "   sudo cp $CA_DIR/beacon-ca.crt /usr/local/share/ca-certificates/beacon-ca.crt"
echo "   sudo update-ca-certificates"
echo ""
echo "🪟 Windows:"
echo "   1. Double-click beacon-ca.crt"
echo "   2. Install Certificate > Local Machine > Trusted Root Certification Authorities"
echo ""
echo "🤖 LM Studio / Node.js:"
echo "   Set environment variable:"
echo "   export NODE_EXTRA_CA_CERTS=$CA_DIR/beacon-ca.crt"
echo ""
echo "🐳 Docker (for services that need to trust the CA):"
echo "   Mount the CA cert and run update-ca-certificates"
echo ""
