-- Stub mínimo do Supabase (papéis + auth.uid/role) para testar migrations num Postgres local.
-- Uso: psql -f stub_supabase.sql; aplicar 001,004,005,006,007,008,009; psql -f testes/00N_*_teste.sql
create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
create schema auth;
create table auth.users(id uuid primary key, email text);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;
create function auth.role() returns text language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claim.role', true),''),'anon') $$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on all functions in schema auth to anon, authenticated, service_role;
