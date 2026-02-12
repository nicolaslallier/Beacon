import base64
import json
import logging
import os
import re
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

import httpx
import psycopg
from psycopg.rows import dict_row
from fastapi import Depends, FastAPI, Header, HTTPException, status
from jose import JWTError, jwt
from openai import OpenAI
from pydantic import BaseModel, Field

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)

app = FastAPI(title="Beacon Tools Image AI")

LOGGER = logging.getLogger("beacon-tools-image-ai")

JWKS_CACHE: dict[str, Any] = {"keys": None, "expires_at": 0.0}
JWKS_CACHE_TTL_SECONDS = 3600

IMAGE_ANALYSIS_PROMPT = """Analyze this image and respond with a JSON object only (no other text).
Use this exact format:
{"caption": "A short descriptive caption in English or French.", "tags": ["tag1", "tag2", "tag3"]}
Caption: one sentence. Tags: 3 to 8 lowercase keywords (English or French) for search."""


def get_tools_db_config() -> dict:
    return {
        "host": os.getenv("BEACON_TOOLS_DB_HOST", "beacon-tools-postgres"),
        "port": int(os.getenv("BEACON_TOOLS_DB_PORT", "5432")),
        "dbname": os.getenv("BEACON_TOOLS_DB_NAME", "beacon_tools"),
        "user": os.getenv("BEACON_TOOLS_DB_USER", "beacon_tools"),
        "password": os.getenv("BEACON_TOOLS_DB_PASSWORD", "change_me"),
        "connect_timeout": 5,
    }


def get_minio_api_base() -> str:
    return os.getenv("TOOLS_MINIO_API_BASE", "http://beacon-tools-minio:8000")


def get_llm_studio_base_url() -> str:
    # Default: LLM Studio on host (use host.docker.internal when running in Docker)
    return os.getenv(
        "LLM_STUDIO_BASE_URL", "http://host.docker.internal:1234/v1"
    ).rstrip("/")


def get_llm_studio_model() -> str:
    return os.getenv("LLM_STUDIO_MODEL", "qwen3-vl-30B")


def get_keycloak_config() -> dict:
    issuer = os.getenv("TOOLS_KEYCLOAK_ISSUER")
    jwks_url = os.getenv("TOOLS_KEYCLOAK_JWKS_URL")
    audience = os.getenv("TOOLS_KEYCLOAK_AUDIENCE")
    if not issuer or not jwks_url:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Missing Keycloak configuration for tools API.",
        )
    return {"issuer": issuer, "jwks_url": jwks_url, "audience": audience}


def fetch_jwks(jwks_url: str) -> dict:
    try:
        response = httpx.get(jwks_url, timeout=5.0)
        response.raise_for_status()
        return response.json()
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to fetch JWKS for token validation.",
        ) from exc


def get_jwks(jwks_url: str) -> dict:
    now = time.time()
    if (
        JWKS_CACHE["keys"] is not None
        and isinstance(JWKS_CACHE["keys"], dict)
        and now < float(JWKS_CACHE["expires_at"])
    ):
        return JWKS_CACHE["keys"]
    jwks = fetch_jwks(jwks_url)
    JWKS_CACHE["keys"] = jwks
    JWKS_CACHE["expires_at"] = now + JWKS_CACHE_TTL_SECONDS
    return jwks


def decode_token(token: str) -> dict:
    config = get_keycloak_config()
    jwks = get_jwks(config["jwks_url"])
    header = jwt.get_unverified_header(token)
    kid = header.get("kid")
    key = next((k for k in jwks.get("keys", []) if k.get("kid") == kid), None)
    if not key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unable to find matching JWKS key.",
        )
    options = {"verify_aud": bool(config.get("audience"))}
    try:
        return jwt.decode(
            token,
            key,
            algorithms=["RS256"],
            audience=config.get("audience"),
            issuer=config["issuer"],
            options=options,
        )
    except JWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication token.",
        ) from exc


def get_current_user_sub(authorization: Optional[str] = Header(None)) -> str:
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization header missing.",
        )
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Bearer token required.",
        )
    if token.count(".") != 2:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid bearer token.",
        )
    claims = decode_token(token)
    sub = claims.get("sub")
    if not sub:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token missing subject.",
        )
    return sub


class AnalyzeRequest(BaseModel):
    bucket: str = Field(..., min_length=1)
    object_name: str = Field(..., min_length=1)


def download_minio_object(bucket: str, object_name: str) -> Path:
    base_url = get_minio_api_base().rstrip("/")
    params = {"bucket": bucket, "object": object_name}
    suffix = Path(object_name).suffix or ".bin"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        temp_path = Path(tmp.name)
        try:
            with httpx.stream(
                "GET",
                f"{base_url}/objects/download",
                params=params,
                timeout=60.0,
            ) as response:
                response.raise_for_status()
                for chunk in response.iter_bytes():
                    tmp.write(chunk)
        except httpx.HTTPError as exc:
            temp_path.unlink(missing_ok=True)
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"MinIO download failed: {exc}",
            ) from exc
    return temp_path


def _infer_media_type(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix in (".jpg", ".jpeg"):
        return "image/jpeg"
    if suffix == ".png":
        return "image/png"
    if suffix == ".gif":
        return "image/gif"
    if suffix == ".webp":
        return "image/webp"
    if suffix == ".bmp":
        return "image/bmp"
    return "image/jpeg"


def parse_json_from_response(text: str) -> dict:
    text = text.strip()
    # Optional markdown code block
    match = re.search(r"```(?:json)?\s*([\s\S]*?)```", text)
    if match:
        text = match.group(1).strip()
    return json.loads(text)


def _slugify_caption_to_filename(caption: str, original_object_name: str) -> str:
    """Build a safe filename from caption, preserving extension from original."""
    ext = Path(original_object_name).suffix or ".jpg"
    ext = ext.lower() if ext.lower() in {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp"} else ".jpg"
    caption = (caption or "").strip()
    if not caption:
        return original_object_name
    slug = re.sub(r"[^\w\s-]", "", caption)
    slug = re.sub(r"[-\s]+", "-", slug).strip("-").lower()
    slug = slug[:50] if len(slug) > 50 else slug
    if not slug:
        return original_object_name
    return f"{slug}{ext}"


def rename_minio_object(bucket: str, old_name: str, new_name: str) -> bool:
    """Rename object in MinIO via minio-api. Returns True if renamed."""
    base_url = get_minio_api_base().rstrip("/")
    params = {"bucket": bucket, "object": old_name, "new_name": new_name}
    try:
        response = httpx.post(
            f"{base_url}/objects/rename",
            params=params,
            timeout=30.0,
        )
        response.raise_for_status()
        data = response.json()
        return data.get("renamed", False)
    except Exception as exc:
        LOGGER.warning("MinIO rename failed: %s", exc)
        return False


def delete_image_analysis_status(bucket: str, object_name: str) -> None:
    config = get_tools_db_config()
    with psycopg.connect(**config) as conn:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM image_analysis_status WHERE bucket = %s AND object_name = %s",
                (bucket, object_name),
            )


def upsert_image_analysis_status(
    *,
    bucket: str,
    object_name: str,
    status: str,
    analyzed_by: str,
    started_at: datetime,
    finished_at: Optional[datetime] = None,
    error_message: Optional[str] = None,
    caption: Optional[str] = None,
    tags: Optional[list[str]] = None,
    model: Optional[str] = None,
) -> None:
    config = get_tools_db_config()
    tags_json = json.dumps(tags) if tags is not None else None
    with psycopg.connect(**config) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO image_analysis_status (
                    bucket,
                    object_name,
                    status,
                    caption,
                    tags,
                    model,
                    started_at,
                    finished_at,
                    error_message,
                    analyzed_by
                )
                VALUES (%s, %s, %s, %s, %s::jsonb, %s, %s, %s, %s, %s)
                ON CONFLICT (bucket, object_name)
                DO UPDATE SET
                    status = EXCLUDED.status,
                    caption = EXCLUDED.caption,
                    tags = EXCLUDED.tags,
                    model = EXCLUDED.model,
                    started_at = EXCLUDED.started_at,
                    finished_at = EXCLUDED.finished_at,
                    error_message = EXCLUDED.error_message,
                    analyzed_by = EXCLUDED.analyzed_by
                """,
                (
                    bucket,
                    object_name,
                    status,
                    caption,
                    tags_json,
                    model,
                    started_at,
                    finished_at,
                    error_message,
                    analyzed_by,
                ),
            )


def list_image_analysis_status(bucket: str) -> list[dict]:
    config = get_tools_db_config()
    with psycopg.connect(**config, row_factory=dict_row) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    bucket,
                    object_name,
                    status,
                    caption,
                    tags,
                    model,
                    started_at,
                    finished_at,
                    error_message,
                    analyzed_by
                FROM image_analysis_status
                WHERE bucket = %s
                ORDER BY started_at DESC
                """,
                (bucket,),
            )
            rows = cur.fetchall()
    items: list[dict] = []
    for row in rows:
        entry = dict(row)
        if entry.get("tags") is not None and not isinstance(entry["tags"], list):
            try:
                entry["tags"] = (
                    json.loads(entry["tags"])
                    if isinstance(entry["tags"], str)
                    else list(entry["tags"])
                )
            except (TypeError, json.JSONDecodeError):
                entry["tags"] = []
        for key in ("started_at", "finished_at"):
            if entry.get(key):
                val = entry[key]
                entry[key] = (
                    val.isoformat() if hasattr(val, "isoformat") else val
                )
        items.append(entry)
    return items


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "time": datetime.now(timezone.utc).isoformat()}


@app.get("/api/tools/images/analysis-status")
def get_analysis_status(
    bucket: str,
    user_sub: str = Depends(get_current_user_sub),
) -> dict:
    if not bucket:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Bucket is required.",
        )
    items = list_image_analysis_status(bucket)
    return {"bucket": bucket, "items": items}


@app.post("/api/tools/images/analyze")
def analyze_image(
    payload: AnalyzeRequest,
    user_sub: str = Depends(get_current_user_sub),
) -> dict:
    LOGGER.info(
        "Image analyze start bucket=%s object=%s user=%s",
        payload.bucket,
        payload.object_name,
        user_sub,
    )
    started_at = datetime.now(timezone.utc)
    upsert_image_analysis_status(
        bucket=payload.bucket,
        object_name=payload.object_name,
        status="started",
        analyzed_by=user_sub,
        started_at=started_at,
    )
    temp_path: Optional[Path] = None
    try:
        temp_path = download_minio_object(payload.bucket, payload.object_name)
        media_type = _infer_media_type(temp_path)
        data = temp_path.read_bytes()
        b64 = base64.standard_b64encode(data).decode("ascii")
        data_url = f"data:{media_type};base64,{b64}"

        base_url = get_llm_studio_base_url()
        model = get_llm_studio_model()
        # Longer timeouts: connect 30s (network), read 300s (VL inference can be slow)
        llm_timeout = httpx.Timeout(
            float(os.getenv("LLM_STUDIO_CONNECT_TIMEOUT", "30")),
            read=float(os.getenv("LLM_STUDIO_READ_TIMEOUT", "300")),
        )
        client = OpenAI(
            base_url=base_url,
            api_key=os.getenv("LLM_STUDIO_API_KEY", "not-needed"),
            http_client=httpx.Client(timeout=llm_timeout),
        )
        response = client.chat.completions.create(
            model=model,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": IMAGE_ANALYSIS_PROMPT},
                        {
                            "type": "image_url",
                            "image_url": {"url": data_url},
                        },
                    ],
                },
                ],
            max_tokens=512,
        )
        choice = response.choices and response.choices[0]
        if not choice or not getattr(choice, "message", None):
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Empty or invalid response from LLM.",
            )
        content = (choice.message.content or "").strip()
        if not content:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Empty content from LLM.",
            )
        parsed = parse_json_from_response(content)
        caption = parsed.get("caption") or ""
        tags = parsed.get("tags")
        if not isinstance(tags, list):
            tags = [t for t in (tags,) if t] if tags else []
        tags = [str(t).strip() for t in tags if t]

        finished_at = datetime.now(timezone.utc)
        current_object_name = payload.object_name
        new_name = _slugify_caption_to_filename(caption, payload.object_name)
        if new_name and new_name != current_object_name:
            if rename_minio_object(payload.bucket, current_object_name, new_name):
                delete_image_analysis_status(payload.bucket, current_object_name)
                current_object_name = new_name
                LOGGER.info("Renamed object to %s", new_name)

        upsert_image_analysis_status(
            bucket=payload.bucket,
            object_name=current_object_name,
            status="completed",
            analyzed_by=user_sub,
            started_at=started_at,
            finished_at=finished_at,
            caption=caption,
            tags=tags,
            model=model,
        )
        return {
            "status": "completed",
            "caption": caption,
            "tags": tags,
            "model": model,
            "object_name": current_object_name,
        }
    except HTTPException as exc:
        finished_at = datetime.now(timezone.utc)
        upsert_image_analysis_status(
            bucket=payload.bucket,
            object_name=payload.object_name,
            status="failed",
            analyzed_by=user_sub,
            started_at=started_at,
            finished_at=finished_at,
            error_message=str(exc.detail),
        )
        raise
    except Exception as exc:
        LOGGER.exception("Image analysis failed")
        finished_at = datetime.now(timezone.utc)
        upsert_image_analysis_status(
            bucket=payload.bucket,
            object_name=payload.object_name,
            status="failed",
            analyzed_by=user_sub,
            started_at=started_at,
            finished_at=finished_at,
            error_message=str(exc),
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        ) from exc
    finally:
        if temp_path and temp_path.exists():
            temp_path.unlink(missing_ok=True)
