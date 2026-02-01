CREATE TABLE IF NOT EXISTS public.schema_migrations (
  version bigint PRIMARY KEY,
  inserted_at timestamp NOT NULL DEFAULT now()
);

ALTER TABLE IF EXISTS public.schema_migrations
  ALTER COLUMN version TYPE bigint USING version::bigint;

ALTER TABLE IF EXISTS public.schema_migrations
  ALTER COLUMN inserted_at TYPE timestamp USING inserted_at::timestamp;

ALTER TABLE IF EXISTS public.schema_migrations
  ADD COLUMN IF NOT EXISTS inserted_at timestamp NOT NULL DEFAULT now();
