CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS vector;

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
