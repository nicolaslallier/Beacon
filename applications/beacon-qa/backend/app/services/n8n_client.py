"""N8N webhook client."""

import logging
from typing import Any

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)


def build_webhook_url() -> str:
    base = settings.n8n_base_url.rstrip("/")
    path = settings.n8n_webhook_path.strip()
    if not path.startswith("/"):
        path = f"/{path}"
    return f"{base}{path}"


def build_api_url(workflow_id: str) -> str:
    base = settings.n8n_api_base_url.rstrip("/")
    return f"{base}/workflows/{workflow_id}/run"


def execute_webhook(
    payload: dict[str, Any],
    client: httpx.Client | None = None,
) -> dict[str, Any]:
    """Send payload to N8N webhook and return JSON response."""
    url = build_webhook_url()
    headers = {"Content-Type": "application/json"}
    if settings.n8n_api_key:
        headers["Authorization"] = f"Bearer {settings.n8n_api_key}"

    logger.info(
        "n8n_webhook_request",
        extra={"url": url, "payload_keys": list(payload.keys())},
    )
    if client is None:
        with httpx.Client(timeout=60) as owned_client:
            response = owned_client.post(url, json=payload, headers=headers)
    else:
        response = client.post(url, json=payload, headers=headers)

    logger.info("n8n_webhook_response", extra={"status_code": response.status_code})
    response.raise_for_status()
    if response.headers.get("content-type", "").startswith("application/json"):
        return response.json()
    return {"raw": response.text}


def execute_workflow_api(
    workflow_id: str,
    payload: dict[str, Any],
    client: httpx.Client | None = None,
) -> dict[str, Any]:
    """Execute an N8N workflow via the public API."""
    url = build_api_url(workflow_id)
    headers = {"Content-Type": "application/json"}
    if settings.n8n_api_key:
        headers["X-N8N-API-KEY"] = settings.n8n_api_key

    input_key = settings.n8n_api_input_key.strip().lower()
    if input_key == "none":
        body = payload
    else:
        body = {input_key: payload}

    logger.info(
        "n8n_api_request",
        extra={
            "url": url,
            "payload_keys": list(payload.keys()),
            "input_key": input_key,
        },
    )
    if client is None:
        with httpx.Client(timeout=60) as owned_client:
            response = owned_client.post(url, json=body, headers=headers)
    else:
        response = client.post(url, json=body, headers=headers)

    logger.info("n8n_api_response", extra={"status_code": response.status_code})
    response.raise_for_status()
    if response.headers.get("content-type", "").startswith("application/json"):
        return response.json()
    return {"raw": response.text}
