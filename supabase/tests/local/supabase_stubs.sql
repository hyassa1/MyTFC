-- =============================================================================
-- Imitation minimale de l'environnement Supabase, pour tester les migrations
-- sur un PostgreSQL ordinaire (sans Docker ni CLI Supabase).
-- NE PAS exécuter sur un vrai projet Supabase : ces objets y existent déjà.
-- =============================================================================

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end;
$$;

create schema if not exists auth;
grant usage on schema auth to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;

create table if not exists auth.users (
  id         uuid primary key default gen_random_uuid(),
  phone      text unique,
  email      text unique,
  created_at timestamptz not null default now()
);

-- Comme Supabase : l'identité vient des « claims » du jeton JWT.
create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(
    coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
             nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'),
    '')::uuid;
$$;

create or replace function auth.role() returns text
language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', 'anon');
$$;

grant execute on function auth.uid() to anon, authenticated, service_role;
grant execute on function auth.role() to anon, authenticated, service_role;

-- Comme Supabase : privilèges par défaut larges, la RLS fait le tri.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
