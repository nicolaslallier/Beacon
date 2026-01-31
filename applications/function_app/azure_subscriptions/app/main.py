from functools import lru_cache
from typing import List, Optional

import httpx
from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    azure_tenant_id: Optional[str] = Field(
        default=None, description="Azure tenant (directory) ID"
    )
    azure_client_id: Optional[str] = Field(
        default=None, description="Azure service principal client ID"
    )
    azure_client_secret: Optional[str] = Field(
        default=None, description="Azure service principal client secret"
    )
    azure_scope: str = Field(
        default="https://management.azure.com/.default",
        description="Azure resource scope for access token",
    )
    azure_api_version: str = Field(
        default="2020-01-01", description="Azure Subscriptions API version"
    )
    request_timeout_seconds: float = Field(
        default=10.0, description="HTTP request timeout in seconds"
    )

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False)


@lru_cache
def get_settings() -> Settings:
    return Settings()


class SubscriptionItem(BaseModel):
    subscription_id: str = Field(..., description="Azure subscription ID")
    display_name: str = Field(
        ..., description="Azure subscription display name"
    )
    state: str = Field(..., description="Subscription state")


class SubscriptionListResponse(BaseModel):
    count: int
    subscriptions: List[SubscriptionItem]


app = FastAPI(title="Azure Subscriptions Function App", version="0.1.0")


@app.get("/health")
async def health_check() -> dict:
    return {"status": "ok"}


async def fetch_access_token(settings: Settings) -> str:
    token_url = (
        f"https://login.microsoftonline.com/{settings.azure_tenant_id}"
        "/oauth2/v2.0/token"
    )
    data = {
        "client_id": settings.azure_client_id,
        "client_secret": settings.azure_client_secret,
        "grant_type": "client_credentials",
        "scope": settings.azure_scope,
    }
    timeout = httpx.Timeout(settings.request_timeout_seconds)
    async with httpx.AsyncClient(timeout=timeout) as client:
        response = await client.post(token_url, data=data)
        response.raise_for_status()
        payload = response.json()

    access_token = payload.get("access_token")
    if not access_token:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Azure token response missing access_token",
        )
    return access_token


async def fetch_subscriptions(
    settings: Settings, access_token: str
) -> List[SubscriptionItem]:
    url = (
        "https://management.azure.com/subscriptions"
        f"?api-version={settings.azure_api_version}"
    )
    headers = {"Authorization": f"Bearer {access_token}"}
    timeout = httpx.Timeout(settings.request_timeout_seconds)
    async with httpx.AsyncClient(timeout=timeout) as client:
        response = await client.get(url, headers=headers)
        response.raise_for_status()
        payload = response.json()

    subscriptions = []
    for item in payload.get("value", []):
        subscription_id = item.get("subscriptionId")
        display_name = item.get("displayName")
        state = item.get("state", "unknown")
        if not subscription_id or not display_name:
            continue
        subscriptions.append(
            SubscriptionItem(
                subscription_id=subscription_id,
                display_name=display_name,
                state=state,
            )
        )
    return subscriptions


@app.get("/azure/subscriptions", response_model=SubscriptionListResponse)
async def list_azure_subscriptions() -> SubscriptionListResponse:
    settings = get_settings()
    if not all(
        [
            settings.azure_tenant_id,
            settings.azure_client_id,
            settings.azure_client_secret,
        ]
    ):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Azure credentials are not configured",
        )

    try:
        access_token = await fetch_access_token(settings)
        subscriptions = await fetch_subscriptions(settings, access_token)
    except httpx.HTTPStatusError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Azure API request failed: {exc.response.status_code}",
        ) from exc
    except httpx.RequestError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Unable to reach Azure API",
        ) from exc

    return SubscriptionListResponse(
        count=len(subscriptions),
        subscriptions=subscriptions,
    )
