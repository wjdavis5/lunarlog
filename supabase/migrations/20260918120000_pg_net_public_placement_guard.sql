-- Migration: 20260918120000_pg_net_public_placement_guard.sql
-- Issue #194 (D-4), the deferred half: the pg_net relocation follow-up.
-- PR #701 (20260915180000_pin_search_path_four_functions.sql) closed D-3
-- (search_path pinning) and deliberately deferred D-4 after coordinator
-- review found production's pg_net is supabase_admin-owned and
-- non-relocatable; this migration is that follow-up, and it documents --
-- with the local-empirical evidence gathered while building it -- why the
-- relocation itself can never be a migration, then installs a never-failing
-- guard so the deferral stays visible instead of silent.
--
-- Why no migration can relocate pg_net (three independently sufficient
-- reasons, each verified against the local stack, which mirrors production
-- exactly: pg_net 0.20.4, extnamespace = public, extrelocatable = false,
-- owner supabase_admin; pg_cron 1.6.4 under pg_catalog):
--
--   1. Migrations run as `postgres`, which is NOT superuser -- locally
--      (rolsuper = false on the CLI's stack) or on Supabase hosted. Every
--      path that moves a non-relocatable extension writes pg_extension
--      directly, and direct system-catalog writes are superuser-only.
--   2. `alter extension pg_net set schema extensions` fails with SQLSTATE
--      0A000 (`extension "pg_net" is not relocatable`) -- confirmed locally
--      and on production by #701's review, re-confirmed here.
--   3. Even as superuser, flipping extrelocatable first (the sequence
--      Supabase community answers suggest for non-relocatable extensions)
--      still fails: `alter extension pg_net set schema extensions` then
--      raises `extension "pg_net" does not support SET SCHEMA -- type
--      net.http_method is not in the extension's schema "public"`, because
--      pg_net's 28 member objects live in its own `net` schema, not in the
--      extension's registered namespace. Observed in a rolled-back
--      transaction while building this migration; `alter extension pg_net
--      update` is no escape either -- 0.20.4 is the newest version in the
--      platform image with no forward update path.
--
-- The one procedure that provably works is a single-column catalog update,
-- verified locally as superuser in a rolled-back transaction (all 28 member
-- objects intact, net.* still resolving at the same OIDs, net.http_request_
-- queue still readable, rollback clean):
--
--   begin;
--   update pg_extension set extnamespace = 'extensions'::regnamespace
--    where extname = 'pg_net' and extnamespace = 'public'::regnamespace;
--   commit;
--
-- It moves no objects and touches no grants (the `net` schema ACL
-- supabase_admin granted to postgres/anon/authenticated/service_role/
-- supabase_functions_admin is exactly what a drop-and-recreate could not be
-- trusted to restore). It needs superuser, so on the cloud project it is a
-- Supabase-Support-assisted action, not a migration -- the full ticket text,
-- local-dev parity steps, and post-move verification/cleanup live in
-- docs/ops/supabase-go-live.md, "pg_net relocation runbook (issue #194)".
--
-- pg_cron needs nothing: it is registered under pg_catalog both locally and
-- on production (pinned by supabase/tests/pg_net_placement_test.sql), which
-- is why #194's original "and pg_cron, for consistency" item closed as a
-- no-op in the issue's own partial-fix comment.
--
-- What this migration DOES install: a placement guard that raises a warning
-- into every `db reset` / `db push` / `db test` log while pg_net is still
-- registered under public, pointing at the runbook, and goes quiet once the
-- runbook has landed. It never raises an error and never writes anything --
-- a guard that could fail would reintroduce the exact "#701 review rejected
-- this" failure mode of a migration blocking every migration after it. No
-- schema objects are created, altered, or dropped, so the CI
-- database.types.ts snapshot freshness step is unaffected.

do $$
declare
  v_namespace text;
begin
  select n.nspname
    into v_namespace
    from pg_catalog.pg_extension e
    join pg_catalog.pg_namespace n on n.oid = e.extnamespace
   where e.extname = 'pg_net';

  if v_namespace is null then
    -- pg_net is not installed on this stack (20260906230000's own
    -- pg_available_extensions guard covers the same situation) -- nothing
    -- to report.
    null;
  elsif v_namespace = 'public' then
    raise warning 'pg_net is still registered in pg_extension under schema public (advisor extension_in_public, issue #194): a migration cannot move it -- see docs/ops/supabase-go-live.md, "pg_net relocation runbook (issue #194)"';
  else
    raise notice 'pg_net is registered under schema % -- issue #194''s relocation has landed, nothing to do', v_namespace;
  end if;
end;
$$;
