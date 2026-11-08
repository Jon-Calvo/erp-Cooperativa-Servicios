-- SOLO PARA PRUEBAS LOCALES. No se aplica en Supabase (allí ya existe todo esto).
-- Imita lo mínimo de Supabase: esquema auth, auth.uid(), roles y permisos por defecto.
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key default gen_random_uuid(), email text);
create or replace function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin; end if;
end $$;
grant usage on schema public, auth to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;   -- Supabase lo hace así
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'admin@coop.test'),
  ('00000000-0000-0000-0000-000000000002', 'lector@coop.test'),
  ('00000000-0000-0000-0000-000000000003', 'operador@coop.test'),
  ('00000000-0000-0000-0000-000000000004', 'inactivo@coop.test')
on conflict do nothing;
