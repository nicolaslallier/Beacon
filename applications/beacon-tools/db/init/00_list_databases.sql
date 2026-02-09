CREATE OR REPLACE FUNCTION list_databases()
RETURNS TABLE (name text, owner text, is_template boolean, allow_conn boolean)
LANGUAGE sql
AS $$
  SELECT datname, datdba::regrole::text, datistemplate, datallowconn
  FROM pg_database
  ORDER BY datname;
$$;
