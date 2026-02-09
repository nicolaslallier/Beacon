import os

import psycopg
from fastapi import FastAPI, HTTPException

app = FastAPI(title="Beacon Tools DB List")


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
    except Exception as exc:  # pragma: no cover - fast fail for connectivity issues
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
