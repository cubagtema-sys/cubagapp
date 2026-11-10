-- SEC-10: stop Supabase's public REST API (PostgREST) from exposing CUBAG tables.
--
-- WHY: every CUBAG table lives in the `public` schema and RLS is OFF. Supabase
-- exposes `public` through its REST API to the `anon` and `authenticated`
-- roles, so anyone holding the project's (non-secret) anon key could read
-- tables such as `members` (incl. password hashes) unless grants were removed.
--
-- SAFE FOR THE CUBAG BACKEND: the Flask API connects with DATABASE_URL as the
-- table owner (postgres). Table owners bypass RLS, and these statements do not
-- touch the owner's privileges. Nothing in the Flutter app talks to Supabase
-- REST directly.
--
-- HOW TO APPLY (owner action — NOT run automatically):
--   1. Take a backup (Supabase Dashboard → Database → Backups) .
--   2. Run the CHECK query; save the output.
--   3. Run the APPLY block in the SQL editor.
--   4. Re-run the CHECK query: every row should show rls = true.
--   5. Smoke-test the app (login, payments, documents).
--   ROLLBACK: see bottom of file.

-- CHECK -----------------------------------------------------------------------
-- select c.relname as table, c.relrowsecurity as rls,
--        has_table_privilege('anon', c.oid, 'SELECT') as anon_can_select
-- from pg_class c join pg_namespace n on n.oid = c.relnamespace
-- where n.nspname = 'public' and c.relkind = 'r' order by 1;

-- APPLY -----------------------------------------------------------------------
begin;

do $$
declare r record;
begin
  for r in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', r.tablename);
  end loop;
end $$;

revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from anon, authenticated;

-- Tables created later by the app must not be exposed either.
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke all on functions from anon, authenticated;

commit;

-- ROLLBACK (only if something unexpected depends on REST access) -------------
-- grant select, insert, update, delete on all tables in schema public to authenticated;
-- (do NOT re-grant to anon)
