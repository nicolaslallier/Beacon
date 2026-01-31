# Toolsuite

Small tooling app with a Python backend, a Streamlit GUI, and a static SPA build.

## Local development

Start the Streamlit stack:

```
docker compose -f applications/toolsuite/docker-compose.yml up -d --build
```

Open the Streamlit UI:

- `http://localhost:8501`

## Build the SPA

The SPA lives in `applications/toolsuite/frontend` and expects the backend URL
from `VITE_BACKEND_URL` (defaults to `http://localhost:8001`).

```
cd applications/toolsuite/frontend
npm install
VITE_BACKEND_URL=http://localhost:8001 npm run build
```

## Publish SPA assets to NGINX

If you build a static toolsuite SPA (expected at `applications/toolsuite/frontend/dist`),
sync it into the NGINX image source tree:

```
make toolsuite-spa-sync
```

The assets are copied into `infra/html/toolsuite` and served at `/toolsuite`.

Health check:

```
curl http://localhost:8001/health
```
