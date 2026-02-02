CREATE OR REPLACE FUNCTION public.match_embeddings(
  query_embedding vector(768),
  match_library_id UUID DEFAULT NULL,
  match_threshold float DEFAULT 0.5,
  match_count int DEFAULT 10
)
RETURNS TABLE (
  id UUID,
  library_id UUID,
  file_id UUID,
  chunk_id TEXT,
  content TEXT,
  metadata JSONB,
  similarity float
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.id,
    e.library_id,
    e.file_id,
    e.chunk_id,
    e.content,
    e.metadata,
    1 - (e.embedding <=> query_embedding) AS similarity
  FROM public.embeddings e
  WHERE
    (match_library_id IS NULL OR e.library_id = match_library_id)
    AND 1 - (e.embedding <=> query_embedding) > match_threshold
  ORDER BY e.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.match_embeddings TO authenticated, service_role;
