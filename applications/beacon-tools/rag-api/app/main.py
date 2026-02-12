import json
import logging
import os
import re
import tempfile
import time
from datetime import datetime
from pathlib import Path
from typing import Optional

import httpx
import psycopg
from psycopg.rows import dict_row
import redis
import tiktoken
from fastapi import Depends, FastAPI, Header, HTTPException, status
from jose import JWTError, jwt
from openai import OpenAI
from pydantic import BaseModel, Field
from unstructured.partition.auto import partition

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)

app = FastAPI(title="Beacon Tools RAG API")

LOGGER = logging.getLogger("beacon-tools-rag")

JWKS_CACHE: dict[str, object] = {"keys": None, "expires_at": 0.0}
JWKS_CACHE_TTL_SECONDS = 3600
RAG_STATUS_CACHE_TTL_SECONDS = int(
    os.getenv("TOOLS_RAG_STATUS_CACHE_TTL_SECONDS", "300")
)


def get_vectordb_config() -> dict:
    config = {
        "host": os.getenv("VECTORDB_HOST", "vectordb"),
        "port": int(os.getenv("VECTORDB_PORT", "5432")),
        "dbname": os.getenv("VECTORDB_DB", "vectordb"),
        "user": os.getenv("VECTORDB_USER", "vectordb"),
        "password": os.getenv("VECTORDB_PASSWORD", "change_me"),
        "connect_timeout": 5,
    }
    # Ensure unqualified table names resolve even when the table lives in a
    # non-default schema (e.g. `core.rag_standards`).
    #
    # This keeps compatibility with deployments that used `public`.
    search_path = os.getenv("VECTORDB_SEARCH_PATH", "core,public").strip()
    if search_path:
        config["options"] = f"-c search_path={search_path}"
    return config


def get_tools_db_config() -> dict:
    return {
        "host": os.getenv("BEACON_TOOLS_DB_HOST", "beacon-tools-postgres"),
        "port": int(os.getenv("BEACON_TOOLS_DB_PORT", "5432")),
        "dbname": os.getenv("BEACON_TOOLS_DB_NAME", "beacon_tools"),
        "user": os.getenv("BEACON_TOOLS_DB_USER", "beacon_tools"),
        "password": os.getenv("BEACON_TOOLS_DB_PASSWORD", "change_me"),
        "connect_timeout": 5,
    }


def upsert_ingestion_status(
    *,
    bucket: str,
    object_name: str,
    status: str,
    ingested_by: str,
    started_at: datetime,
    finished_at: Optional[datetime] = None,
    error_message: Optional[str] = None,
    chunks: Optional[int] = None,
    standard_id: Optional[str] = None,
) -> None:
    config = get_tools_db_config()
    with psycopg.connect(**config) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO rag_ingestion_status (
                    bucket,
                    object_name,
                    status,
                    started_at,
                    finished_at,
                    error_message,
                    chunks,
                    standard_id,
                    ingested_by
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (bucket, object_name)
                DO UPDATE SET
                    status = EXCLUDED.status,
                    started_at = EXCLUDED.started_at,
                    finished_at = EXCLUDED.finished_at,
                    error_message = EXCLUDED.error_message,
                    chunks = EXCLUDED.chunks,
                    standard_id = EXCLUDED.standard_id,
                    ingested_by = EXCLUDED.ingested_by
                """,
                (
                    bucket,
                    object_name,
                    status,
                    started_at,
                    finished_at,
                    error_message,
                    chunks,
                    standard_id,
                    ingested_by,
                ),
            )


def _get_redis_client() -> Optional[redis.Redis]:
    host = os.getenv("TOOLS_REDIS_HOST", "").strip()
    if not host:
        return None
    port = int(os.getenv("TOOLS_REDIS_PORT", "6379"))
    password = os.getenv("TOOLS_REDIS_PASSWORD", "").strip() or None
    return redis.Redis(host=host, port=port, password=password, decode_responses=True)


def _cache_get_json(key: str) -> Optional[object]:
    client = _get_redis_client()
    if not client:
        return None
    try:
        raw = client.get(key)
        if not raw:
            return None
        return json.loads(raw)
    except Exception:
        LOGGER.exception("Failed reading cache key %s", key)
        return None


def _cache_set_json(key: str, payload: object, ttl_seconds: int) -> None:
    client = _get_redis_client()
    if not client:
        return
    try:
        client.setex(key, ttl_seconds, json.dumps(payload))
    except Exception:
        LOGGER.exception("Failed writing cache key %s", key)


def _invalidate_ingestion_status_cache(bucket: str) -> None:
    client = _get_redis_client()
    if not client:
        return
    key = f"rag_ingestion_status:{bucket}"
    try:
        client.delete(key)
    except Exception:
        LOGGER.exception("Failed deleting cache key %s", key)
def get_minio_api_base() -> str:
    return os.getenv("TOOLS_MINIO_API_BASE", "http://beacon-tools-minio:8000")


def get_openai_client() -> OpenAI:
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Missing OPENAI_API_KEY.",
        )
    return OpenAI(api_key=api_key)


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


class RagIngestRequest(BaseModel):
    bucket: str = Field(..., min_length=1)
    object_name: str = Field(..., min_length=1)


def download_minio_object(bucket: str, object_name: str) -> Path:
    base_url = get_minio_api_base().rstrip("/")
    params = {"bucket": bucket, "object": object_name}
    suffix = Path(object_name).suffix
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


def extract_text(file_path: Path) -> str:
    elements = partition(filename=str(file_path))
    text_blocks = [
        element.text
        for element in elements
        if getattr(element, "text", None)
    ]
    return "\n".join(text_blocks)


def _element_kind(element: object) -> str:
    category = getattr(element, "category", None)
    if category:
        return str(category)
    return type(element).__name__


def _is_list_item_kind(kind: str) -> bool:
    return kind.lower().replace("_", "") in {"listitem", "list", "bulletlist"}


def _is_title_kind(kind: str) -> bool:
    return kind.lower().replace("_", "") in {"title", "header", "heading"}


def elements_to_markdown(elements: list, *, file_name: str) -> str:
    blocks: list[str] = []
    title_count = 0
    last_page = None
    for element in elements:
        text = getattr(element, "text", None)
        if not text:
            continue
        kind = _element_kind(element)

        page_number = getattr(getattr(element, "metadata", None), "page_number", None)
        if page_number and page_number != last_page:
            blocks.append(f"## Page {page_number}")
            last_page = page_number

        if _is_title_kind(kind):
            title_count += 1
            heading = "# " if title_count == 1 else "## "
            blocks.append(f"{heading}{text.strip()}")
            continue

        if _is_list_item_kind(kind):
            blocks.append(f"- {text.strip()}")
            continue

        if kind.lower() == "table":
            html = getattr(getattr(element, "metadata", None), "text_as_html", None)
            if html:
                blocks.append(html.strip())
            else:
                blocks.append(text.strip())
            continue

        blocks.append(text.strip())

    if not blocks:
        return ""
    return "\n\n".join(blocks)


def extract_markdown(file_path: Path) -> str:
    elements = partition(filename=str(file_path))
    return elements_to_markdown(elements, file_name=file_path.name)


def normalize_text(text: str) -> str:
    lines = []
    for line in text.splitlines():
        if "Table of Contents" in line:
            continue
        if line.strip().isdigit():
            continue
        if not line.strip():
            lines.append("")
            continue
        if re.match(r"^\s*(#{1,6}\s|[-*]\s+|\d+\.\s+)", line):
            lines.append(line.rstrip())
        else:
            lines.append(line.strip())
    return "\n".join(lines)


def _clean_markdown_line(line: str) -> str:
    clean_line = re.sub(r"^#{1,6}\s*", "", line)
    clean_line = re.sub(r"^[-*]\s+", "", clean_line)
    clean_line = re.sub(r"^\d+\.\s+", "", clean_line)
    return clean_line.strip()


def detect_metadata(text: str, file_name: str) -> dict:
    std_match = re.search(r"(STD-[A-Z0-9\\-]+)", text)
    std_id = std_match.group(1) if std_match else file_name
    version_match = re.search(
        r"\\bVersion\\s*:?\s*([0-9]+(?:\\.[0-9]+)*)",
        text,
        flags=re.IGNORECASE,
    )
    version = version_match.group(1) if version_match else None
    title = file_name
    for line in text.split("\n"):
        if not line.strip():
            continue
        clean_line = _clean_markdown_line(line)
        if not clean_line:
            continue
        if re.match(
            r"^page\s*\d+\s*$",
            clean_line,
            flags=re.IGNORECASE,
        ):
            continue
        if re.match(
            r"^##?\s*page\s+\d+\s*$",
            line,
            flags=re.IGNORECASE,
        ):
            continue
        if clean_line.isdigit():
            continue
        title = clean_line[:200] or file_name
        break
    meta = {
        "standard_id": std_id,
        "title": title,
        "file_name": file_name,
        "doc_type": "standard",
        "source": "EA Governance",
        "language": "FR",
    }
    if version:
        meta["version"] = version
    return meta


def chunk_text(text: str) -> list[str]:
    sections = re.split(r"\n(?=(?:\\d+\\.\\s|#{1,6}\\s))", text)
    return [section.strip() for section in sections if len(section) > 300]


def _get_token_encoder(model: str) -> tiktoken.Encoding:
    try:
        return tiktoken.encoding_for_model(model)
    except KeyError:
        return tiktoken.get_encoding("cl100k_base")

def _token_count(text: str, encoder: tiktoken.Encoding) -> int:
    return len(encoder.encode(text))


def parse_markdown_blocks(text: str) -> list[dict]:
    lines = text.splitlines()
    blocks: list[dict] = []
    current_section = "Uncategorized"
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
            continue

        if "<table" in line:
            table_lines = [line.rstrip()]
            i += 1
            while i < len(lines) and "</table>" not in lines[i]:
                table_lines.append(lines[i].rstrip())
                i += 1
            if i < len(lines):
                table_lines.append(lines[i].rstrip())
                i += 1
            blocks.append(
                {
                    "kind": "table",
                    "text": "\n".join(table_lines).strip(),
                    "section": current_section,
                }
            )
            continue

        heading_match = re.match(r"^(#{1,6})\s+(.*)", line)
        if heading_match:
            current_section = heading_match.group(2).strip() or "Uncategorized"
            i += 1
            continue

        rule_match = re.match(r"^\s*\d+(?:\.\d+)*\.\s+\S+", line)
        if rule_match:
            rule_lines = [line.rstrip()]
            i += 1
            while i < len(lines):
                nxt = lines[i]
                if not nxt.strip():
                    break
                if re.match(r"^(#{1,6})\s+", nxt):
                    break
                if re.match(r"^\s*\d+(?:\.\d+)*\.\s+\S+", nxt):
                    break
                if re.match(r"^\s+", nxt):
                    rule_lines.append(nxt.rstrip())
                    i += 1
                    continue
                break
            blocks.append(
                {
                    "kind": "rule",
                    "text": "\n".join(rule_lines).strip(),
                    "section": current_section,
                }
            )
            continue

        if re.match(r"^\s*[-*]\s+\S+", line):
            list_lines = [line.rstrip()]
            i += 1
            while i < len(lines) and re.match(r"^\s*[-*]\s+\S+", lines[i]):
                list_lines.append(lines[i].rstrip())
                i += 1
            blocks.append(
                {
                    "kind": "list",
                    "text": "\n".join(list_lines).strip(),
                    "section": current_section,
                }
            )
            continue

        paragraph_lines = [line.rstrip()]
        i += 1
        while i < len(lines):
            nxt = lines[i]
            if not nxt.strip():
                break
            if re.match(r"^(#{1,6})\s+", nxt):
                break
            if re.match(r"^\s*\d+(?:\.\d+)*\.\s+\S+", nxt):
                break
            if "<table" in nxt:
                break
            paragraph_lines.append(nxt.rstrip())
            i += 1
        blocks.append(
            {
                "kind": "paragraph",
                "text": "\n".join(paragraph_lines).strip(),
                "section": current_section,
            }
        )
    return blocks


def pack_blocks(
    blocks: list[dict],
    *,
    model: str,
    min_tokens: int,
    max_tokens: int,
    overlap_tokens: int = 0,
) -> list[dict]:
    if not blocks:
        return []
    encoder = _get_token_encoder(model)
    chunks: list[dict] = []
    current: list[dict] = []
    current_tokens = 0
    current_section = blocks[0]["section"]

    def flush(keep_overlap: bool) -> None:
        nonlocal current, current_tokens, current_section
        if not current:
            return
        chunk_text = "\n\n".join(block["text"] for block in current).strip()
        if current_section and current_section != "Uncategorized":
            chunk_text = f"## {current_section}\n\n{chunk_text}"
        if chunk_text:
            chunks.append({"text": chunk_text, "section": current_section})
        if keep_overlap and overlap_tokens > 0:
            overlap: list[dict] = []
            overlap_token_count = 0
            for block in reversed(current):
                block_tokens = _token_count(block["text"], encoder)
                if overlap and overlap_token_count + block_tokens > overlap_tokens:
                    break
                overlap.append(block)
                overlap_token_count += block_tokens
            current = list(reversed(overlap))
            current_tokens = overlap_token_count
        else:
            current = []
            current_tokens = 0

    for block in blocks:
        block_tokens = _token_count(block["text"], encoder)
        if block_tokens > max_tokens and block["kind"] in {"rule", "table"}:
            LOGGER.warning(
                "Block kind=%s exceeds max_tokens=%s (%s tokens).",
                block["kind"],
                max_tokens,
                block_tokens,
            )

        if not current:
            current_section = block["section"]
            current.append(block)
            current_tokens = block_tokens
            continue

        if block["section"] != current_section:
            flush(False)
            current_section = block["section"]
            current.append(block)
            current_tokens = block_tokens
            continue

        if current_tokens + block_tokens <= max_tokens:
            current.append(block)
            current_tokens += block_tokens
            continue

        if current_tokens >= min_tokens:
            flush(True)
            current_section = block["section"]
            current.append(block)
            current_tokens = block_tokens
            continue

        if block["kind"] in {"rule", "table"} or block_tokens > max_tokens:
            flush(True)
            current_section = block["section"]
            current.append(block)
            current_tokens = block_tokens
            continue

        current.append(block)
        current_tokens += block_tokens

    flush(False)
    return chunks


def embed_text(client: OpenAI, model: str, text: str) -> list[float]:
    response = client.embeddings.create(model=model, input=text)
    return response.data[0].embedding


def insert_rag_chunk(
    cur: psycopg.Cursor,
    chunk: str,
    meta: dict,
    vector: list[float],
) -> None:
    vector_literal = "[" + ",".join(str(value) for value in vector) + "]"
    cur.execute(
        """
        INSERT INTO rag_standards
        (standard_id, title, section, content, metadata, embedding)
        VALUES (%s, %s, %s, %s, %s, %s::vector)
        """,
        (
            meta["standard_id"],
            meta["title"],
            meta.get("section") or chunk[:120],
            chunk,
            json.dumps(meta),
            vector_literal,
        ),
    )


def list_ingestion_status(bucket: str) -> list[dict]:
    config = get_tools_db_config()
    with psycopg.connect(**config, row_factory=dict_row) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    bucket,
                    object_name,
                    status,
                    started_at,
                    finished_at,
                    error_message,
                    chunks,
                    standard_id,
                    ingested_by
                FROM rag_ingestion_status
                WHERE bucket = %s
                ORDER BY started_at DESC
                """,
                (bucket,),
            )
            rows = cur.fetchall()
    items: list[dict] = []
    for row in rows:
        entry = dict(row)
        for key in ("started_at", "finished_at"):
            if entry.get(key):
                entry[key] = entry[key].isoformat()
        items.append(entry)
    return items


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "time": datetime.utcnow().isoformat()}


@app.get("/api/tools/rag/ingestion-status")
def get_ingestion_status(
    bucket: str, user_sub: str = Depends(get_current_user_sub)
) -> dict:
    if not bucket:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Bucket is required.",
        )
    cache_key = f"rag_ingestion_status:{bucket}"
    cached = _cache_get_json(cache_key)
    if cached is not None:
        return {"bucket": bucket, "items": cached, "cached": True}
    items = list_ingestion_status(bucket)
    _cache_set_json(cache_key, items, RAG_STATUS_CACHE_TTL_SECONDS)
    return {"bucket": bucket, "items": items, "cached": False}


@app.post("/api/tools/rag/ingest")
def ingest_rag_document(
    payload: RagIngestRequest,
    user_sub: str = Depends(get_current_user_sub),
) -> dict:
    LOGGER.info(
        "RAG ingest start bucket=%s object=%s user=%s",
        payload.bucket,
        payload.object_name,
        user_sub,
    )
    started_at = datetime.utcnow()
    upsert_ingestion_status(
        bucket=payload.bucket,
        object_name=payload.object_name,
        status="started",
        ingested_by=user_sub,
        started_at=started_at,
    )
    _invalidate_ingestion_status_cache(payload.bucket)
    try:
        temp_path = download_minio_object(payload.bucket, payload.object_name)
        suffix = temp_path.suffix.lower()
        LOGGER.info("Detected file type suffix=%s", suffix or "unknown")
        try:
            file_size = temp_path.stat().st_size
        except OSError:
            file_size = None
        LOGGER.info(
            "Downloaded object to %s (size=%s)",
            temp_path,
            file_size,
        )
        try:
            if suffix in {".pdf", ".docx"}:
                raw_text = extract_markdown(temp_path)
            else:
                raw_text = extract_text(temp_path)
        except Exception as exc:
            LOGGER.exception("Text extraction failed")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Unable to extract text: {exc}",
            ) from exc
        finally:
            temp_path.unlink(missing_ok=True)

        clean_text = normalize_text(raw_text)
        if not clean_text.strip():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No text extracted from file.",
            )
        LOGGER.info("Prepared markdown length=%s", len(clean_text))

        meta = detect_metadata(clean_text, payload.object_name)
        meta.update(
            {
                "bucket": payload.bucket,
                "object_name": payload.object_name,
                "ingested_by": user_sub,
            }
        )
        model = os.getenv("OPENAI_EMBEDDING_MODEL", "text-embedding-3-large")
        min_tokens = int(os.getenv("RAG_CHUNK_MIN_TOKENS", "400"))
        max_tokens = int(os.getenv("RAG_CHUNK_MAX_TOKENS", "900"))
        overlap_tokens = int(os.getenv("RAG_CHUNK_OVERLAP_TOKENS", "120"))
        blocks = parse_markdown_blocks(clean_text)
        LOGGER.info("Parsed %s semantic blocks", len(blocks))
        sections = list({block["section"] for block in blocks})
        if sections:
            LOGGER.info("Detected sections: %s", ", ".join(sorted(sections)[:5]))
        chunk_items = pack_blocks(
            blocks,
            model=model,
            min_tokens=min_tokens,
            max_tokens=max_tokens,
            overlap_tokens=overlap_tokens,
        )
        LOGGER.info("Chunked document into %s chunks", len(chunk_items))
        if not chunk_items:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No suitable chunks found for ingestion.",
            )

        client = get_openai_client()
        config = get_vectordb_config()
        ingested = 0
        with psycopg.connect(**config) as conn:
            with conn.cursor() as cur:
                for chunk_item in chunk_items:
                    chunk = chunk_item["text"]
                    chunk_meta = dict(meta)
                    chunk_meta["section"] = chunk_item["section"]
                    section_title = chunk_item.get("section") or ""
                    if re.match(r"^page\s+\d+\s*$", section_title, re.IGNORECASE):
                        chunk_meta["title"] = section_title
                    vector = embed_text(client, model, chunk)
                    insert_rag_chunk(cur, chunk, chunk_meta, vector)
                    ingested += 1

        LOGGER.info("RAG ingest completed chunks=%s", ingested)
        upsert_ingestion_status(
            bucket=payload.bucket,
            object_name=payload.object_name,
            status="completed",
            ingested_by=user_sub,
            started_at=started_at,
            finished_at=datetime.utcnow(),
            chunks=ingested,
            standard_id=meta["standard_id"],
        )
        _invalidate_ingestion_status_cache(payload.bucket)
        return {
            "status": "completed",
            "file": payload.object_name,
            "standard_id": meta["standard_id"],
            "chunks": ingested,
        }
    except HTTPException as exc:
        upsert_ingestion_status(
            bucket=payload.bucket,
            object_name=payload.object_name,
            status="failed",
            ingested_by=user_sub,
            started_at=started_at,
            finished_at=datetime.utcnow(),
            error_message=str(exc.detail),
        )
        _invalidate_ingestion_status_cache(payload.bucket)
        raise
    except Exception as exc:
        LOGGER.exception("RAG ingest failed")
        upsert_ingestion_status(
            bucket=payload.bucket,
            object_name=payload.object_name,
            status="failed",
            ingested_by=user_sub,
            started_at=started_at,
            finished_at=datetime.utcnow(),
            error_message=str(exc),
        )
        _invalidate_ingestion_status_cache(payload.bucket)
        raise
