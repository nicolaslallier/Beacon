# Private CA SSL Certificates for Beacon

This guide explains how to create and manage SSL certificates using your own private Certificate Authority (CA) for your internal network.

## Why Private CA?

- **No internet required**: Works completely offline
- **No public DNS needed**: Use any domain names you want internally
- **Full control**: You manage certificate validity and renewal
- **Trusted by your devices**: Once you install the CA, all certificates it issues are trusted

## Quick Start

### Step 1: Create Private CA and Certificates

```bash
cd /path/to/Beacon
make ssl-init
```

This creates:
- A private Certificate Authority (valid 10 years)
- Server certificates for all your domains (valid 1 year)

### Step 2: Install CA on Your Devices

The CA certificate must be installed on any device that needs to trust your HTTPS sites.

**macOS (easiest):**
```bash
make ssl-install-ca-macos
```

**macOS (manual):**
```bash
sudo security add-trusted-cert -d -r trustRoot \
    -k /Library/Keychains/System.keychain ca/beacon-ca.crt
```

**Linux (Ubuntu/Debian):**
```bash
sudo cp ca/beacon-ca.crt /usr/local/share/ca-certificates/beacon-ca.crt
sudo update-ca-certificates
```

**Windows:**
1. Double-click `ca/beacon-ca.crt`
2. Click "Install Certificate"
3. Select "Local Machine"
4. Choose "Place all certificates in the following store"
5. Browse → "Trusted Root Certification Authorities"
6. Finish

### Step 3: Restart nginx

```bash
make restart
```

### Step 4: Verify

```bash
make ssl-status
```

Visit https://beacon-library.famillelallier.net - should show secure! 🔒

## LM Studio Integration

For LM Studio to trust your private CA:

**Option 1: Environment Variable**
```bash
# Get the path
make ssl-show-ca-path

# Set it before starting LM Studio
export NODE_EXTRA_CA_CERTS=/path/to/Beacon/ca/beacon-ca.crt
```

**Option 2: Install CA system-wide (recommended)**

Use the macOS/Linux/Windows instructions above. LM Studio will automatically trust certificates signed by your CA.

## Domains Included

The certificate covers these domains by default:
- `beacon-library.famillelallier.net`
- `grafana.beacon.famillelallier.net`
- `prometheus.beacon.famillelallier.net`
- `loki.beacon.famillelallier.net`
- `tempo.beacon.famillelallier.net`
- `minio.beacon.famillelallier.net`
- `s3.beacon.famillelallier.net`
- `keycloak.beacon.famillelallier.net`
- `localhost`

And IP addresses:
- `127.0.0.1`
- `192.168.2.35`

To add more domains/IPs, edit `scripts/setup-private-ca.sh`.

## Certificate Renewal

Certificates are valid for 1 year. To renew:

```bash
make ssl-renew
```

The CA remains valid for 10 years. You only need to recreate it if:
- It expires (after 10 years)
- The CA private key is compromised
- You want to change CA details

## File Locations

| Path | Description |
|------|-------------|
| `ca/beacon-ca.crt` | CA certificate (distribute to clients) |
| `ca/beacon-ca.key` | CA private key (KEEP SECRET!) |
| `certs/fullchain.pem` | Server certificate + CA chain |
| `certs/privkey.pem` | Server private key |

## Security Notes

1. **Protect the CA private key**: `ca/beacon-ca.key` can sign ANY certificate
2. **Don't share the CA key**: Only share `ca/beacon-ca.crt`
3. **Backup the CA**: If you lose it, you'll need to reinstall on all devices

## Troubleshooting

### Browser shows "Not Secure"

The CA isn't installed or trusted. Follow the installation steps above.

### LM Studio SSL error

Set the environment variable:
```bash
export NODE_EXTRA_CA_CERTS=/path/to/Beacon/ca/beacon-ca.crt
```

Or install the CA system-wide.

### Certificate expired

Run `make ssl-renew` to generate a new certificate.

### Need to add more domains

1. Edit `scripts/setup-private-ca.sh`
2. Add domains to the `DOMAINS` array
3. Run `make ssl-init` (reuses existing CA)

### Verify certificate chain

```bash
openssl verify -CAfile ca/beacon-ca.crt certs/fullchain.pem
```

Should output: `certs/fullchain.pem: OK`
