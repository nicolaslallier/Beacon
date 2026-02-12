import logging
import os
import time
from datetime import datetime
from typing import Optional
from urllib.parse import quote, urlparse, urlunparse

import httpx
import psycopg
from psycopg import errors, sql
from fastapi import Depends, FastAPI, Header, HTTPException, Query, status
from fastapi.encoders import jsonable_encoder
from jose import JWTError, jwt
from pydantic import BaseModel, Field

app = FastAPI(title="Beacon Tools API")

LOGGER = logging.getLogger("uvicorn.error")

JWKS_CACHE: dict[str, object] = {"keys": None, "expires_at": 0.0}
JWKS_CACHE_TTL_SECONDS = 3600


def get_db_config() -> dict:
    return {
        "host": os.getenv("DB_HOST", "beacon-tools-postgres"),
        "port": int(os.getenv("DB_PORT", "5432")),
        "dbname": os.getenv(
            "DB_NAME", os.getenv("BEACON_TOOLS_DB_NAME", "beacon_tools")
        ),
        "user": os.getenv(
            "DB_USER", os.getenv("BEACON_TOOLS_DB_USER", "beacon_tools")
        ),
        "password": os.getenv(
            "DB_PASSWORD", os.getenv("BEACON_TOOLS_DB_PASSWORD", "change_me")
        ),
        "connect_timeout": 5,
    }


def get_encryption_key() -> str:
    key = os.getenv("BEACON_TOOLS_DB_ENCRYPTION_KEY")
    if not key:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Missing BEACON_TOOLS_DB_ENCRYPTION_KEY.",
        )
    return key


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
    claims = decode_token(token)
    sub = claims.get("sub")
    if not sub:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token missing subject.",
        )
    return sub


class ConnectionStringCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    host: str = Field(..., min_length=1)
    port: int = Field(..., ge=1, le=65535)
    username: str = Field(..., min_length=1)
    password: str = Field(..., min_length=1)
    ssl: bool = Field(default=False)


class ConnectionStringUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=120)
    host: Optional[str] = Field(None, min_length=1)
    port: Optional[int] = Field(None, ge=1, le=65535)
    username: Optional[str] = Field(None, min_length=1)
    password: Optional[str] = Field(None, min_length=1)
    ssl: Optional[bool] = Field(default=None)


class ConnectionStringListItem(BaseModel):
    id: str
    name: str
    created_at: datetime
    updated_at: datetime


class ConnectionStringDetail(ConnectionStringListItem):
    connection_string: str

def build_connection_string(
    *, host: str, port: int, username: str, password: str, ssl: bool
) -> str:
    safe_user = quote(username, safe="")
    safe_pass = quote(password, safe="")
    base = f"postgresql://{safe_user}:{safe_pass}@{host}:{port}/"
    if ssl:
        return f"{base}?sslmode=require"
    return base


def should_update_connection_payload(payload: ConnectionStringUpdate) -> bool:
    return any(
        value is not None
        for value in (
            payload.host,
            payload.port,
            payload.username,
            payload.password,
            payload.ssl,
        )
    )


def validate_update_payload(payload: ConnectionStringUpdate) -> None:
    if not should_update_connection_payload(payload):
        return
    missing = [
        field
        for field in ("host", "port", "username", "password")
        if getattr(payload, field) is None
    ]
    if missing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Missing fields for connection update: {', '.join(missing)}.",
        )


def fetch_connection_string_for_user(connection_id: str, user_sub: str) -> str:
    config = get_db_config()
    key = get_encryption_key()
    query = """
        SELECT pgp_sym_decrypt(conn_encrypted, %s)::text
        FROM connection_strings
        WHERE id = %s AND owner_sub = %s
    """
    with psycopg.connect(**config) as conn:
        with conn.cursor() as cur:
            cur.execute(query, (key, connection_id, user_sub))
            row = cur.fetchone()
    if not row or not row[0]:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Connection string not found.",
        )
    return row[0]


def build_target_connection_strings(
    connection_string: str, database: Optional[str] = None
) -> list[str]:
    parsed = urlparse(connection_string)
    scheme = parsed.scheme or "postgresql"
    netloc = parsed.netloc
    query = parsed.query
    path = parsed.path or ""

    gateway_host = os.getenv("TOOLS_TRAEFIK_HOST")
    gateway_pg_port = int(os.getenv("TOOLS_TRAEFIK_POSTGRES_PORT", "5432"))
    gateway_vectordb_port = int(os.getenv("TOOLS_TRAEFIK_VECTORDB_PORT", "5433"))
    original_host = parsed.hostname or ""
    if gateway_host:
        port = (
            gateway_vectordb_port
            if "vectordb" in original_host
            else gateway_pg_port
        )
        user = quote(parsed.username or "", safe="")
        password = quote(parsed.password or "", safe="")
        auth = ""
        if user and password:
            auth = f"{user}:{password}@"
        elif user:
            auth = f"{user}@"
        netloc = f"{auth}{gateway_host}:{port}"
    if database:
        target_path = f"/{quote(database, safe='')}"
        return [
            urlunparse(
                (scheme, netloc, target_path, parsed.params, query, parsed.fragment)
            )
        ]
    if path and path != "/":
        return [
            urlunparse((scheme, netloc, path, parsed.params, query, parsed.fragment))
        ]
    candidates = ["postgres", "template1"]
    return [
        urlunparse(
            (
                scheme,
                netloc,
                f"/{quote(candidate, safe='')}",
                parsed.params,
                query,
                parsed.fragment,
            )
        )
        for candidate in candidates
    ]


def get_external_connection(
    connection_id: str, user_sub: str, database: Optional[str] = None
):
    connection_string = fetch_connection_string_for_user(connection_id, user_sub)
    parsed = urlparse(connection_string)
    host_label = parsed.hostname or "unknown"
    port_label = parsed.port or "unknown"
    targets = build_target_connection_strings(connection_string, database)
    last_exc: Optional[Exception] = None
    for target in targets:
        try:
            return psycopg.connect(target, connect_timeout=5)
        except errors.InvalidCatalogName as exc:
            last_exc = exc
            LOGGER.warning(
                "Target database missing for host=%s port=%s error=%s",
                host_label,
                port_label,
                exc,
            )
            continue
        except psycopg.Error as exc:
            LOGGER.warning(
                "Unable to connect to host=%s port=%s error_type=%s error=%s",
                host_label,
                port_label,
                type(exc).__name__,
                exc,
            )
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"Unable to connect to target database: {exc}",
            ) from exc
    raise HTTPException(
        status_code=status.HTTP_502_BAD_GATEWAY,
        detail=f"Unable to connect to target database: {last_exc}",
    ) from last_exc



def fetch_databases() -> list[dict]:
    config = get_db_config()
    query = (
        "SELECT name, owner, is_template, allow_conn FROM list_databases();"
    )

    try:
        with psycopg.connect(**config) as conn:
            with conn.cursor() as cur:
                cur.execute(query)
                rows = cur.fetchall()
    except Exception as exc:  # pragma: no cover
        raise HTTPException(
            status_code=500, detail=f"Database query failed: {exc}"
        ) from exc

    return [
        {
            "name": row[0],
            "owner": row[1],
            "is_template": row[2],
            "allow_conn": row[3],
        }
        for row in rows
    ]


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.get("/databases")
def list_databases() -> dict:
    return {"databases": fetch_databases()}


@app.get(
    "/api/tools/connection-strings",
    response_model=list[ConnectionStringListItem],
)
def list_connection_strings(
    user_sub: str = Depends(get_current_user_sub),
) -> list[dict]:
    config = get_db_config()
    query = """
        SELECT id::text, name, created_at, updated_at
        FROM connection_strings
        WHERE owner_sub = %s
        ORDER BY updated_at DESC
    """
    with psycopg.connect(**config) as conn:
        with conn.cursor() as cur:
            cur.execute(query, (user_sub,))
            rows = cur.fetchall()
    return [
        {
            "id": row[0],
            "name": row[1],
            "created_at": row[2],
            "updated_at": row[3],
        }
        for row in rows
    ]


@app.post(
    "/api/tools/connection-strings",
    response_model=ConnectionStringListItem,
    status_code=status.HTTP_201_CREATED,
)
def create_connection_string(
    payload: ConnectionStringCreate,
    user_sub: str = Depends(get_current_user_sub),
) -> dict:
    config = get_db_config()
    key = get_encryption_key()
    connection_string = build_connection_string(
        host=payload.host.strip(),
        port=payload.port,
        username=payload.username.strip(),
        password=payload.password,
        ssl=payload.ssl,
    )
    query = """
        INSERT INTO connection_strings (owner_sub, name, conn_encrypted)
        VALUES (%s, %s, pgp_sym_encrypt(%s, %s))
        RETURNING id::text, name, created_at, updated_at
    """
    try:
        with psycopg.connect(**config) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    query,
                    (
                        user_sub,
                        payload.name.strip(),
                        connection_string,
                        key,
                    ),
                )
                row = cur.fetchone()
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unable to save connection string: {exc}",
        ) from exc
    return {
        "id": row[0],
        "name": row[1],
        "created_at": row[2],
        "updated_at": row[3],
    }


@app.get(
    "/api/tools/connection-strings/{connection_id}",
    response_model=ConnectionStringDetail,
)
def get_connection_string(
    connection_id: str,
    user_sub: str = Depends(get_current_user_sub),
) -> dict:
    config = get_db_config()
    key = get_encryption_key()
    query = """
        SELECT id::text, name, pgp_sym_decrypt(conn_encrypted, %s)::text,
               created_at, updated_at
        FROM connection_strings
        WHERE id = %s AND owner_sub = %s
    """
    with psycopg.connect(**config) as conn:
        with conn.cursor() as cur:
            cur.execute(query, (key, connection_id, user_sub))
            row = cur.fetchone()
    if not row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Connection string not found.",
        )
    return {
        "id": row[0],
        "name": row[1],
        "connection_string": row[2],
        "created_at": row[3],
        "updated_at": row[4],
    }


@app.put(
    "/api/tools/connection-strings/{connection_id}",
    response_model=ConnectionStringListItem,
)
def update_connection_string(
    connection_id: str,
    payload: ConnectionStringUpdate,
    user_sub: str = Depends(get_current_user_sub),
) -> dict:
    config = get_db_config()
    key = get_encryption_key()
    fields = []
    params = []
    if payload.name:
        fields.append("name = %s")
        params.append(payload.name.strip())
    validate_update_payload(payload)
    if should_update_connection_payload(payload):
        connection_string = build_connection_string(
            host=payload.host.strip(),
            port=payload.port,
            username=payload.username.strip(),
            password=payload.password,
            ssl=bool(payload.ssl),
        )
        fields.append("conn_encrypted = pgp_sym_encrypt(%s, %s)")
        params.extend([connection_string, key])
    if not fields:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No fields provided to update.",
        )
    fields.append("updated_at = now()")
    query = f"""
        UPDATE connection_strings
        SET {", ".join(fields)}
        WHERE id = %s AND owner_sub = %s
        RETURNING id::text, name, created_at, updated_at
    """
    params.extend([connection_id, user_sub])
    with psycopg.connect(**config) as conn:
        with conn.cursor() as cur:
            cur.execute(query, params)
            row = cur.fetchone()
    if not row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Connection string not found.",
        )
    return {
        "id": row[0],
        "name": row[1],
        "created_at": row[2],
        "updated_at": row[3],
    }


@app.delete("/api/tools/connection-strings/{connection_id}")
def delete_connection_string(
    connection_id: str,
    user_sub: str = Depends(get_current_user_sub),
) -> dict:
    config = get_db_config()
    query = """
        DELETE FROM connection_strings
        WHERE id = %s AND owner_sub = %s
        RETURNING id::text
    """
    with psycopg.connect(**config) as conn:
        with conn.cursor() as cur:
            cur.execute(query, (connection_id, user_sub))
            row = cur.fetchone()
    if not row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Connection string not found.",
        )
    return {"status": "deleted"}


@app.get("/api/tools/connections/{connection_id}/databases")
def list_target_databases(
    connection_id: str,
    user_sub: str = Depends(get_current_user_sub),
) -> dict:
    query = """
        SELECT datname
        FROM pg_database
        WHERE datistemplate = false
        ORDER BY datname
    """
    with get_external_connection(connection_id, user_sub) as conn:
        with conn.cursor() as cur:
            cur.execute(query)
            rows = cur.fetchall()
    return {"databases": [row[0] for row in rows]}


@app.get("/api/tools/connections/{connection_id}/schemas")
def list_target_schemas(
    connection_id: str,
    database: str = Query(..., min_length=1),
    user_sub: str = Depends(get_current_user_sub),
) -> dict:
    query = """
        SELECT schema_name
        FROM information_schema.schemata
        WHERE schema_name NOT IN ('pg_catalog', 'information_schema')
        ORDER BY schema_name
    """
    with get_external_connection(connection_id, user_sub, database) as conn:
        with conn.cursor() as cur:
            cur.execute(query)
            rows = cur.fetchall()
    return {"schemas": [row[0] for row in rows]}


@app.get("/api/tools/connections/{connection_id}/tables")
def list_target_tables(
    connection_id: str,
    database: str = Query(..., min_length=1),
    schema: str = Query(..., min_length=1),
    user_sub: str = Depends(get_current_user_sub),
) -> dict:
    query = """
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = %s
          AND table_type = 'BASE TABLE'
        ORDER BY table_name
    """
    with get_external_connection(connection_id, user_sub, database) as conn:
        with conn.cursor() as cur:
            cur.execute(query, (schema,))
            rows = cur.fetchall()
    return {"tables": [row[0] for row in rows]}


@app.get("/api/tools/connections/{connection_id}/table-details")
def get_target_table_details(
    connection_id: str,
    database: str = Query(..., min_length=1),
    schema: str = Query(..., min_length=1),
    table: str = Query(..., min_length=1),
    user_sub: str = Depends(get_current_user_sub),
) -> dict:
    query = """
        SELECT column_name, data_type, is_nullable, column_default, ordinal_position
        FROM information_schema.columns
        WHERE table_schema = %s AND table_name = %s
        ORDER BY ordinal_position
    """
    with get_external_connection(connection_id, user_sub, database) as conn:
        with conn.cursor() as cur:
            cur.execute(query, (schema, table))
            rows = cur.fetchall()
    return {
        "columns": [
            {
                "name": row[0],
                "type": row[1],
                "nullable": row[2],
                "default": row[3],
                "position": row[4],
            }
            for row in rows
        ]
    }


@app.get("/api/tools/connections/{connection_id}/table-rows")
def get_target_table_rows(
    connection_id: str,
    database: str = Query(..., min_length=1),
    schema: str = Query(..., min_length=1),
    table: str = Query(..., min_length=1),
    limit: int = Query(100, ge=1, le=100),
    offset: int = Query(0, ge=0),
    user_sub: str = Depends(get_current_user_sub),
) -> dict:
    query = sql.SQL("SELECT * FROM {}.{} LIMIT %s OFFSET %s").format(
        sql.Identifier(schema),
        sql.Identifier(table),
    )
    with get_external_connection(connection_id, user_sub, database) as conn:
        with conn.cursor() as cur:
            cur.execute(query, (limit, offset))
            rows = cur.fetchall()
            columns = [desc[0] for desc in cur.description]
    row_data = [dict(zip(columns, row)) for row in rows]
    return {
        "columns": columns,
        "rows": jsonable_encoder(row_data),
        "limit": limit,
        "offset": offset,
    }
