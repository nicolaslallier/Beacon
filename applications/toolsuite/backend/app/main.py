from datetime import datetime, timezone

from fastapi import FastAPI
from pydantic import BaseModel


class PingRequest(BaseModel):
    message: str = "ping"


class PingResponse(BaseModel):
    message: str
    received_at: str


app = FastAPI(title="Toolsuite Backend", version="0.1.0")


@app.get("/health")
def health_check() -> dict:
    return {"status": "ok"}


@app.post("/tools/ping", response_model=PingResponse)
def run_ping_tool(payload: PingRequest) -> PingResponse:
    return PingResponse(
        message=payload.message,
        received_at=datetime.now(timezone.utc).isoformat(),
    )
