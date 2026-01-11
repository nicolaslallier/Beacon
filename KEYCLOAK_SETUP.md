# Keycloak Setup Guide

This guide documents the Keycloak configuration for the Beacon infrastructure.

## Overview

Keycloak is deployed behind an NGINX reverse proxy that handles SSL/TLS termination. The setup allows Keycloak to run on HTTP internally while being accessed via HTTPS externally.

## Architecture

```
Internet (HTTPS) → NGINX (SSL termination) → Keycloak (HTTP:8080)
```

- **External URL**: `https://keycloak.beacon.famillelallier.net`
- **Internal URL**: `http://keycloak:8080`

## Configuration

### Docker Compose Settings

Key environment variables in `docker-compose.yml`:

```yaml
environment:
  # Proxy configuration
  - KC_PROXY=edge                    # Trust X-Forwarded-* headers
  - KC_PROXY_HEADERS=xforwarded      # Use X-Forwarded headers
  - KC_HTTP_ENABLED=true             # Enable HTTP (NGINX handles HTTPS)
  
  # Hostname configuration
  - KC_HOSTNAME=keycloak.beacon.famillelallier.net
  - KC_HOSTNAME_STRICT=false
  - KC_HOSTNAME_STRICT_HTTPS=false
  
  # Frontend URLs (what users see)
  - KC_HOSTNAME_URL=https://keycloak.beacon.famillelallier.net
  - KC_HOSTNAME_ADMIN_URL=https://keycloak.beacon.famillelallier.net
```

### NGINX Proxy Configuration

The proxy is configured in `templates/nginx.conf.template` with the following headers:

```nginx
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host $host;
proxy_set_header X-Forwarded-Port $server_port;
```

### Initial Realm Configuration

After first deployment, the master realm needs to be configured to accept connections through the reverse proxy:

```bash
# Login to Keycloak Admin CLI
docker exec beacon-keycloak /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user admin \
  --password "${KEYCLOAK_ADMIN_PASSWORD:-admin}"

# Disable SSL requirement (handled by NGINX)
docker exec beacon-keycloak /opt/keycloak/bin/kcadm.sh update realms/master \
  -s sslRequired=NONE

# Update admin console redirect URIs
docker exec beacon-keycloak /opt/keycloak/bin/kcadm.sh update clients/[CLIENT_ID] \
  -r master \
  -s 'redirectUris=["https://keycloak.beacon.famillelallier.net/admin/master/console/*","/admin/master/console/*"]'

# Update web origins
docker exec beacon-keycloak /opt/keycloak/bin/kcadm.sh update clients/[CLIENT_ID] \
  -r master \
  -s 'webOrigins=["https://keycloak.beacon.famillelallier.net","+"]'
```

## Common Issues and Solutions

### Issue 1: SSL Required Error

**Error**: `type="LOGIN_ERROR", error="ssl_required"`

**Solution**: The realm's SSL requirement needs to be set to "none" or "external" since NGINX handles SSL termination.

```bash
docker exec beacon-keycloak /opt/keycloak/bin/kcadm.sh update realms/master -s sslRequired=NONE
```

### Issue 2: Invalid Redirect URI

**Error**: `error="invalid_redirect_uri", redirect_uri="http://keycloak.beacon.famillelallier.net/..."`

**Solution**: Update the client's redirect URIs to include the HTTPS URL:

1. Find the client ID:
   ```bash
   docker exec beacon-keycloak /opt/keycloak/bin/kcadm.sh get clients -r master -q clientId=security-admin-console
   ```

2. Update redirect URIs with the client UUID:
   ```bash
   docker exec beacon-keycloak /opt/keycloak/bin/kcadm.sh update clients/[UUID] -r master \
     -s 'redirectUris=["https://keycloak.beacon.famillelallier.net/admin/master/console/*","/admin/master/console/*"]'
   ```

### Issue 3: CORS Errors

If you encounter CORS errors when accessing the admin console:

```bash
docker exec beacon-keycloak /opt/keycloak/bin/kcadm.sh update clients/[UUID] -r master \
  -s 'webOrigins=["https://keycloak.beacon.famillelallier.net","+"]'
```

## Accessing Keycloak

- **Admin Console**: https://keycloak.beacon.famillelallier.net/admin
- **Default Credentials**: 
  - Username: `admin` (configured via `KEYCLOAK_ADMIN`)
  - Password: `admin` (configured via `KEYCLOAK_ADMIN_PASSWORD`)

⚠️ **Security Warning**: Change the default admin password in production!

## Creating a New Realm for Beacon Library

To create a dedicated realm for the Beacon Library application:

1. Access the admin console
2. Click "Create Realm"
3. Set realm name: `beacon`
4. Configure SSL requirement: `None` or `External requests`
5. Create a client for `beacon-library` with:
   - Client Protocol: `openid-connect`
   - Access Type: `confidential`
   - Valid Redirect URIs: `https://beacon-library.famillelallier.net/*`
   - Web Origins: `https://beacon-library.famillelallier.net`

## Management Commands

```bash
# Start Keycloak and database
make up-auth-only

# View logs
make auth-logs

# Check status
make auth-status

# Restart Keycloak
docker-compose --profile auth restart keycloak

# Reset Keycloak (deletes all data)
make reset-keycloak
```

## Health Checks

Keycloak provides health endpoints:

- **Ready**: http://localhost:8080/health/ready
- **Live**: http://localhost:8080/health/live
- **Metrics**: http://localhost:9000/metrics

## Environment Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `KEYCLOAK_ADMIN` | `admin` | Admin username |
| `KEYCLOAK_ADMIN_PASSWORD` | `admin` | Admin password |
| `KEYCLOAK_HOSTNAME` | `keycloak.beacon.famillelallier.net` | Public hostname |
| `KEYCLOAK_DB_NAME` | `keycloak` | Database name |
| `KEYCLOAK_DB_USER` | `keycloak` | Database user |
| `KEYCLOAK_DB_PASSWORD` | `keycloak` | Database password |
| `KEYCLOAK_LOG_LEVEL` | `info` | Logging level |

## Troubleshooting

### Check if Keycloak is running

```bash
docker ps --filter "name=keycloak"
```

### View recent logs

```bash
docker logs --tail 50 beacon-keycloak
```

### Test internal connectivity

```bash
docker exec beacon-keycloak curl -s http://localhost:8080/health/ready
```

### Test external connectivity

```bash
curl -k https://keycloak.beacon.famillelallier.net/health/ready
```

### Access Keycloak shell

```bash
docker exec -it beacon-keycloak bash
```

## References

- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [Keycloak on Docker Guide](https://www.keycloak.org/server/containers)
- [Reverse Proxy Configuration](https://www.keycloak.org/server/reverseproxy)
