-- Coverage for 20260918120000_pg_net_public_placement_guard.sql
-- (Issue #194, D-4): pins the pg_net/pg_cron catalog state around the
-- deferred relocation. The relocation itself cannot be a migration (the
-- migration's header and docs/ops/supabase-go-live.md's "pg_net relocation
-- runbook (issue #194)" carry the three verified reasons), so these
-- assertions pin the invariants that must hold in EVERY state -- before the
-- runbook lands (pg_net registered under public) and after (registered under
-- extensions) -- plus a self-tightening two-state check that starts passing
-- as "runbook pending" today and passes as "relocated" once it lands, while
-- still failing for any registration schema outside those two.
--
-- Every pg_net assertion is absent-tolerant: a stack started without pg_net
-- binaries (20260906230000's pg_available_extensions guard) skips rather
-- than fails, matching that migration's own posture.
begin;
select plan(5);

-- ---------------------------------------------------------------------------
-- pg_cron: registered under pg_catalog, never public. This is why #194's
-- "and pg_cron, for consistency" item needed nothing -- it is where the
-- platform put it on both the local stack and production, and the advisor
-- only flags public. Absent-tolerant for stacks without pg_cron binaries.
-- ---------------------------------------------------------------------------
select case
  when not exists (select 1 from pg_catalog.pg_extension where extname = 'pg_cron')
    then pass('pg_cron not installed on this stack: placement assertion skipped')
    else is(
      (select n.nspname
         from pg_catalog.pg_extension e
         join pg_catalog.pg_namespace n on n.oid = e.extnamespace
        where e.extname = 'pg_cron'),
      'pg_catalog',
      'pg_cron is registered under pg_catalog, never public (issue #194 D-4: nothing to move)'
    )
end;

-- ---------------------------------------------------------------------------
-- The dispatch contract (issue #194 AC4): trigger_push_dispatch()'s
-- availability probe resolves net.http_post at the real installed 5-argument
-- signature (LLA-073, 20260914104000). Registration placement is irrelevant
-- to this -- pg_net's objects live in their own `net` schema wherever the
-- extension row points -- which is exactly why the relocation is safe. This
-- pins it independently so a future pg_net upgrade that changes the
-- signature again cannot silently dead-end the cron dispatch path.
-- ---------------------------------------------------------------------------
select case
  when not exists (select 1 from pg_catalog.pg_extension where extname = 'pg_net')
    then pass('pg_net not installed on this stack: net.* resolution assertion skipped')
    else ok(
      to_regprocedure('net.http_post(text, jsonb, jsonb, jsonb, integer)') is not null,
      'net.http_post resolves at the 5-arg signature trigger_push_dispatch probes (AC4), independent of registration schema'
    )
end;

-- ---------------------------------------------------------------------------
-- extrelocatable stays false: the runbook's catalog update touches only
-- extnamespace, and nobody should ever leave a flipped relocatable flag
-- behind (a half-run of the community "flip/alter/unflip" sequence, which
-- cannot work on this extension shape anyway -- see the migration header).
-- ---------------------------------------------------------------------------
select case
  when not exists (select 1 from pg_catalog.pg_extension where extname = 'pg_net')
    then pass('pg_net not installed on this stack: extrelocatable assertion skipped')
    else is(
      (select e.extrelocatable from pg_catalog.pg_extension e where e.extname = 'pg_net'),
      false,
      'pg_net stays registered non-relocatable (no leftover flip from an aborted relocation attempt)'
    )
end;

-- ---------------------------------------------------------------------------
-- The real exposure is nil whatever the registration says: no pg_net member
-- object lives in public. This is the invariant that makes the advisor
-- finding cosmetic (it flags pg_extension.extnamespace, not where callable
-- objects sit), and it must survive the relocation unchanged.
-- ---------------------------------------------------------------------------
select is(
  (select count(*)
     from pg_catalog.pg_proc p
     join pg_catalog.pg_depend d
       on d.classid = 'pg_catalog.pg_proc'::pg_catalog.regclass and d.objid = p.oid
    where d.refclassid = 'pg_catalog.pg_extension'::pg_catalog.regclass
      and d.refobjid = (select e.oid from pg_catalog.pg_extension e where e.extname = 'pg_net')
      and d.deptype = 'e'
      and p.pronamespace = 'public'::pg_catalog.regnamespace),
  0::bigint,
  'zero pg_net member functions resolve in schema public (the finding is registration-only, before and after the runbook)'
);

-- ---------------------------------------------------------------------------
-- The two-state goal check, self-tightening: today (runbook pending) the
-- registration is public and this passes as the documented interim state;
-- once the runbook lands it must be exactly `extensions` -- and anything
-- else (a stray `net`, an unexpected downgrade) fails. Absent-tolerant:
-- no pg_net on the stack compares null to null.
-- ---------------------------------------------------------------------------
select is(
  (select e.extnamespace::pg_catalog.regnamespace::text
     from pg_catalog.pg_extension e where e.extname = 'pg_net'),
  (select case
           when e.extnamespace = 'public'::pg_catalog.regnamespace then 'public'
           else 'extensions'
         end
     from pg_catalog.pg_extension e where e.extname = 'pg_net'),
  'pg_net registration is public (relocation runbook pending, issue #194) or extensions (relocated) -- never any other schema'
);

select * from finish();
rollback;
