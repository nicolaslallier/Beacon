"""API router."""

from fastapi import APIRouter

from app.api.v1.qa import router as qa_router

api_router = APIRouter()
api_router.include_router(qa_router, prefix="/v1", tags=["qa"])
