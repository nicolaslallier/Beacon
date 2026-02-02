CREATE TABLE IF NOT EXISTS public.embeddings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  library_id UUID NOT NULL,
  file_id UUID NOT NULL,
  chunk_id TEXT NOT NULL,
  content TEXT NOT NULL,
  embedding vector(192),
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (library_id, file_id, chunk_id)
);

CREATE INDEX IF NOT EXISTS embeddings_library_file_idx
  ON public.embeddings (library_id, file_id);

CREATE INDEX IF NOT EXISTS embeddings_vector_idx
  ON public.embeddings
  USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);

ALTER TABLE public.embeddings ENABLE ROW LEVEL SECURITY;

CREATE POLICY embeddings_authenticated_read
  ON public.embeddings
  FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY embeddings_service_role_all
  ON public.embeddings
  FOR ALL
  USING (auth.role() = 'service_role');

GRANT SELECT ON public.embeddings TO authenticated;
GRANT ALL ON public.embeddings TO service_role;
