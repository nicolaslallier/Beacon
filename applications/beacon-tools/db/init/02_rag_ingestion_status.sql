CREATE TABLE IF NOT EXISTS rag_ingestion_status (
    bucket text NOT NULL,
    object_name text NOT NULL,
    status text NOT NULL,
    started_at timestamptz NOT NULL,
    finished_at timestamptz,
    error_message text,
    chunks integer,
    standard_id text,
    ingested_by text NOT NULL,
    PRIMARY KEY (bucket, object_name)
);
