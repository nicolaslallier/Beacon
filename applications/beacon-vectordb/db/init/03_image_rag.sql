-- Image RAG: CLIP embeddings for text/image search
-- Requires vector extension and core schema from 01/02

CREATE TABLE IF NOT EXISTS core.rag_images (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket TEXT NOT NULL,
  object_name TEXT NOT NULL,
  caption TEXT,
  tags JSONB,
  metadata JSONB,
  embedding vector(512) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (bucket, object_name)
);

CREATE INDEX IF NOT EXISTS rag_images_embedding_idx
  ON core.rag_images
  USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);
