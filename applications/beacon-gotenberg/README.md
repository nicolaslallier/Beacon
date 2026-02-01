# beacon-gotenberg

Gotenberg document conversion service with an nginx sidecar.

## Usage
- Start: `docker compose up -d`
- Default server name: `gotenberg.beacon.famillelallier.net`
- Upstream listens on port `3000` inside the compose network

## Configuration
Set these in `.env` as needed:
- `GOTENBERG_SERVER_NAME`
- `GOTENBERG_PORT`
- `TECHNITIUM_DNS_IP`
- `TECHNITIUM_DNS_SEARCH`
