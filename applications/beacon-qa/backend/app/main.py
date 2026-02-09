"""FastAPI application entry point."""

import logging
import time
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.requests import Request

from app.api.api_router import api_router
from app.core.config import settings
from app.core.database import engine
from app.models.base import Base
from app.models import qa as qa_models  # noqa: F401

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)
logger = logging.getLogger("beacon-qa")


def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.app_name,
        version=settings.app_version,
        docs_url="/api/docs",
        redoc_url="/api/redoc",
        openapi_url="/api/openapi.json",
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(api_router, prefix=settings.api_prefix)

    @app.middleware("http")
    async def log_requests(request: Request, call_next):
        start = time.perf_counter()
        response = await call_next(request)
        elapsed_ms = (time.perf_counter() - start) * 1000
        logger.info(
            "request",
            extra={
                "method": request.method,
                "path": request.url.path,
                "status_code": response.status_code,
                "elapsed_ms": round(elapsed_ms, 2),
            },
        )
        return response

    @app.on_event("startup")
    def init_db() -> None:
        Base.metadata.create_all(bind=engine)
        logger.info("database_ready")

    @app.get("/health")
    def health_check() -> dict:
        logger.info("health_check")
        return {
            "status": "ok",
            "version": settings.app_version,
            "env": settings.env,
        }

    @app.get("/")
    def root() -> dict:
        logger.info("root")
        return {
            "message": f"{settings.app_name} API",
            "version": settings.app_version,
        }

    return app


app = create_app()
