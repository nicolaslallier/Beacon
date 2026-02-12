import os
import re
import unicodedata
from datetime import datetime, timezone

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from minio import Minio
from minio.commonconfig import CopySource
from minio.error import S3Error
from urllib.parse import quote

app = FastAPI(title="Beacon Tools MinIO API")


def _get_env_bool(name: str, default: str = "false") -> bool:
    value = os.getenv(name, default).strip().lower()
    return value in {"1", "true", "yes", "on"}


def get_minio_client() -> Minio:
    endpoint = os.getenv("MINIO_ENDPOINT", "minio1:9000")
    access_key = os.getenv("MINIO_ACCESS_KEY", "minioadmin")
    secret_key = os.getenv("MINIO_SECRET_KEY", "minioadmin")
    secure = _get_env_bool("MINIO_SECURE", "false")

    return Minio(
        endpoint=endpoint,
        access_key=access_key,
        secret_key=secret_key,
        secure=secure,
    )


def resolve_bucket(bucket: str | None) -> str:
    resolved = bucket or os.getenv("MINIO_DEFAULT_BUCKET", "").strip()
    if not resolved:
        raise HTTPException(status_code=400, detail="Bucket is required.")
    return resolved


def build_content_disposition(filename: str) -> str:
    """
    Build a Content-Disposition header value that is safe for non-ASCII names.

    - `filename="..."` uses an ASCII fallback (required by many
      clients/servers)
    - `filename*=` carries the UTF-8 name per RFC 5987
    """
    # Prevent header injection
    filename = re.sub(r"[\r\n]", "", filename or "").strip()

    normalized = unicodedata.normalize("NFKD", filename)
    ascii_fallback = normalized.encode("ascii", "ignore").decode("ascii")
    ascii_fallback = ascii_fallback.replace('"', "").strip() or "download"

    utf8_quoted = quote(filename, safe="")
    return (
        f'attachment; filename="{ascii_fallback}"; '
        f"filename*=UTF-8''{utf8_quoted}"
    )


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "time": datetime.now(timezone.utc).isoformat()}


@app.get("/buckets")
def list_buckets() -> dict:
    client = get_minio_client()
    try:
        buckets = client.list_buckets()
    except S3Error as exc:
        raise HTTPException(
            status_code=502, detail=f"MinIO error: {exc}"
        ) from exc

    return {
        "buckets": [
            {"name": bucket.name, "created_at": bucket.creation_date}
            for bucket in buckets
        ]
    }


@app.get("/objects")
def list_objects(bucket: str | None = None, prefix: str | None = None) -> dict:
    resolved_bucket = resolve_bucket(bucket)
    client = get_minio_client()
    try:
        objects = client.list_objects(
            resolved_bucket, prefix=prefix or "", recursive=True
        )
    except S3Error as exc:
        raise HTTPException(
            status_code=502, detail=f"MinIO error: {exc}"
        ) from exc

    return {
        "bucket": resolved_bucket,
        "objects": [
            {
                "name": obj.object_name,
                "size": obj.size,
                "etag": obj.etag,
                "last_modified": obj.last_modified,
            }
            for obj in objects
        ],
    }


@app.get("/objects/download")
def download_object(
    bucket: str | None = None, object: str | None = None
) -> StreamingResponse:
    resolved_bucket = resolve_bucket(bucket)
    object_name = (object or "").strip()
    if not object_name:
        raise HTTPException(status_code=400, detail="Object is required.")

    client = get_minio_client()
    try:
        response = client.get_object(resolved_bucket, object_name)
    except S3Error as exc:
        raise HTTPException(
            status_code=502, detail=f"MinIO error: {exc}"
        ) from exc

    content_type = response.headers.get(
        "content-type", "application/octet-stream"
    )
    filename = os.path.basename(object_name)

    def stream():
        try:
            for chunk in response.stream(32 * 1024):
                yield chunk
        finally:
            response.close()
            response.release_conn()

    return StreamingResponse(
        stream(),
        media_type=content_type,
        headers={"Content-Disposition": build_content_disposition(filename)},
    )


@app.post("/objects")
def upload_object(
    bucket: str | None = Form(None),
    object_name: str | None = Form(None),
    file: UploadFile = File(...),
) -> dict:
    resolved_bucket = resolve_bucket(bucket)
    name = (object_name or file.filename or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="Object name is required.")

    client = get_minio_client()

    try:
        if not client.bucket_exists(resolved_bucket):
            raise HTTPException(status_code=404, detail="Bucket not found.")

        result = client.put_object(
            resolved_bucket,
            name,
            file.file,
            length=-1,
            part_size=10 * 1024 * 1024,
            content_type=file.content_type or "application/octet-stream",
        )
    except HTTPException:
        raise
    except S3Error as exc:
        raise HTTPException(
            status_code=502, detail=f"MinIO error: {exc}"
        ) from exc

    return {
        "bucket": resolved_bucket,
        "object": name,
        "etag": result.etag,
        "version_id": result.version_id,
    }


@app.delete("/objects")
def delete_object(
    bucket: str | None = None, object: str | None = None
) -> dict:
    resolved_bucket = resolve_bucket(bucket)
    object_name = (object or "").strip()
    if not object_name:
        raise HTTPException(status_code=400, detail="Object is required.")

    client = get_minio_client()
    try:
        client.remove_object(resolved_bucket, object_name)
    except S3Error as exc:
        raise HTTPException(
            status_code=502, detail=f"MinIO error: {exc}"
        ) from exc

    return {"bucket": resolved_bucket, "object": object_name, "deleted": True}


@app.post("/objects/rename")
def rename_object(
    bucket: str | None = None,
    object: str | None = None,
    new_name: str | None = None,
) -> dict:
    resolved_bucket = resolve_bucket(bucket)
    old_name = (object or "").strip()
    new_name_str = (new_name or "").strip()
    if not old_name:
        raise HTTPException(status_code=400, detail="Object (current name) is required.")
    if not new_name_str:
        raise HTTPException(status_code=400, detail="new_name is required.")
    if old_name == new_name_str:
        return {
            "bucket": resolved_bucket,
            "object": old_name,
            "renamed_to": new_name_str,
            "renamed": False,
        }

    client = get_minio_client()
    try:
        client.copy_object(
            resolved_bucket,
            new_name_str,
            CopySource(resolved_bucket, old_name),
        )
        client.remove_object(resolved_bucket, old_name)
    except S3Error as exc:
        raise HTTPException(
            status_code=502, detail=f"MinIO error: {exc}"
        ) from exc

    return {
        "bucket": resolved_bucket,
        "object": old_name,
        "renamed_to": new_name_str,
        "renamed": True,
    }


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)
