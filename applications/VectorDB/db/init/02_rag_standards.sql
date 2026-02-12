CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS core;

CREATE TABLE IF NOT EXISTS core.rag_standards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  standard_id TEXT,
  title TEXT,
  section TEXT,
  content TEXT,
  metadata JSONB,
  embedding vector(3072),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Note: vector(3072) exceeds the 2000-dimension limit for both HNSW and
-- IVFFlat indexes in pgvector <= 0.8.x.  A sequential scan is used for
-- similarity queries until either the dimensions are reduced or pgvector
-- lifts the limit.
-- CREATE INDEX IF NOT EXISTS rag_standards_embedding_idx
--   ON core.rag_standards
--   USING ivfflat (embedding vector_cosine_ops)
--   WITH (lists = 100);
