"""Application configuration using Pydantic Settings."""

from functools import lru_cache
from typing import List, Optional

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # ==========================================================================
    # Application
    # ==========================================================================
    app_name: str = Field(default="Beacon QA", description="Application name")
    app_version: str = Field(default="0.1.0", description="Application version")
    env: str = Field(default="local", description="Environment name")
    api_prefix: str = Field(default="/api", description="API route prefix")
    api_version: str = Field(default="v1", description="Current API version")

    # CORS
    cors_origins: List[str] = Field(
        default=["http://localhost:3010", "http://localhost:5173"],
        description="Allowed CORS origins",
    )

    # ==========================================================================
    # Database
    # ==========================================================================
    database_url: str = Field(
        default="sqlite:////data/qa.db",
        description="Database URL (SQLite default)",
    )

    # ==========================================================================
    # N8N
    # ==========================================================================
    n8n_base_url: str = Field(
        default="http://beacon-n8n:5678",
        description="Base URL for the internal N8N service",
    )
    n8n_webhook_path: str = Field(
        default="/webhook/replace-me",
        description="Webhook path for execution",
    )
    n8n_api_key: Optional[str] = Field(
        default=None,
        description="Optional API key for N8N API calls",
    )
    n8n_mode: str = Field(
        default="webhook",
        description="Execution mode: webhook or api",
    )
    n8n_workflow_id: Optional[str] = Field(
        default=None,
        description="Workflow ID for API execution",
    )
    n8n_api_base_url: str = Field(
        default="http://beacon-n8n:5678/api/v1",
        description="Base URL for N8N API",
    )
    n8n_api_input_key: str = Field(
        default="input",
        description="Wrapper key for workflow input (input, data, or none)",
    )


@lru_cache
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()


settings = get_settings()
