CREATE TABLE IF NOT EXISTS image_analysis_status (
    bucket text NOT NULL,
    object_name text NOT NULL,
    status text NOT NULL,
    caption text,
    tags jsonb,
    model text,
    started_at timestamptz NOT NULL,
    finished_at timestamptz,
    error_message text,
    analyzed_by text NOT NULL,
    PRIMARY KEY (bucket, object_name)
);
