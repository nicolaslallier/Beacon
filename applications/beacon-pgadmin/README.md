# Beacon pgAdmin

Standalone pgAdmin service for Beacon, with an nginx sidecar for proxying.

## Quick start

```bash
cd applications/beacon-pgadmin
docker compose up -d
```

Or from the repo root:

```bash
make pgadmin-app up
```

## Configuration

Edit `.env` to set:

- `PGADMIN_EMAIL`: initial admin email
- `PGADMIN_PASSWORD`: initial admin password
- `PGADMIN_SCRIPT_NAME`: base path for reverse proxy (default `/pgadmin`)
- `PGADMIN_SERVER_MODE`: `False` for single-user mode
- `PGADMIN_MASTER_PASSWORD_REQUIRED`: `False` to avoid master password prompts

## Access

The app includes its own nginx sidecar and also connects to `beacon_nginx_net`.
Use the script name path:

`https://<your-domain>${PGADMIN_SCRIPT_NAME}`
