import httpx

from app.core.config import settings
from app.services.n8n_client import build_api_url, build_webhook_url, execute_webhook, execute_workflow_api


def test_build_webhook_url() -> None:
    settings.n8n_base_url = "http://beacon-n8n:5678/"
    settings.n8n_webhook_path = "webhook/test-path"
    assert build_webhook_url() == "http://beacon-n8n:5678/webhook/test-path"


def test_execute_webhook_returns_json() -> None:
    settings.n8n_base_url = "http://beacon-n8n:5678"
    settings.n8n_webhook_path = "/webhook/test-path"

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url == httpx.URL("http://beacon-n8n:5678/webhook/test-path")
        return httpx.Response(200, json={"answer": "ok", "score": 1.0})

    transport = httpx.MockTransport(handler)
    client = httpx.Client(transport=transport)

    response = execute_webhook({"prompt": "hello"}, client=client)
    assert response["answer"] == "ok"
    assert response["score"] == 1.0


def test_execute_workflow_api_wraps_input() -> None:
    settings.n8n_api_base_url = "http://beacon-n8n:5678/api/v1"
    settings.n8n_api_input_key = "input"

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url == httpx.URL("http://beacon-n8n:5678/api/v1/workflows/abc123/run")
        return httpx.Response(200, json={"result": "ok"})

    transport = httpx.MockTransport(handler)
    client = httpx.Client(transport=transport)

    response = execute_workflow_api("abc123", {"prompt": "hello"}, client=client)
    assert response["result"] == "ok"
