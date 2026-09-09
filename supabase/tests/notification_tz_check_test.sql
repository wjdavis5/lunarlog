-- Coverage for Issue #321 (P2, epic:backend-data): time-zone contract
-- follow-ups from the #319 review --
-- 20260908210000_notification_tz_check.sql --
-- notification_preferences_time_zone_valid (the CHECK constraint) and
-- resolve_deliver_after's ad hoc zone defence removal.
begin;
select plan(8);

-- ---------------------------------------------------------------------------
-- CHECK constraint: present and validated.
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::integer from pg_constraint
    where conrelid = 'public.notification_preferences'::regclass
      and conname = 'notification_preferences_time_zone_valid'),
  1, 'notification_preferences_time_zone_valid exists');
select is(
  (select convalidated from pg_constraint
    where conrelid = 'public.notification_preferences'::regclass
      and conname = 'notification_preferences_time_zone_valid'),
  true, 'notification_preferences_time_zone_valid is validated (not left NOT VALID)');

-- ---------------------------------------------------------------------------
-- resolve_deliver_after wrapper (service-role privileges): the function
-- carries no grant to authenticated (revoke all ... from public, anon,
-- authenticated, re-issued by this migration), so this SECURITY DEFINER
-- pg_temp wrapper must be created now, before any tests.authenticate_as()
-- call below switches the session role to authenticated -- a SECURITY
-- DEFINER function runs with the privileges of its owner (the role that
-- created it), so creating it here while the role is still the suite's
-- default privileged role is what lets it call resolve_deliver_after
-- later in the file, after the fixture setup has switched roles (mirrors
-- notification_outbox_test.sql's identical wrapper, created before its
-- own first tests.authenticate_as() for the same reason).
-- ---------------------------------------------------------------------------
create function pg_temp.resolve_deliver_after(p_now timestamptz, p_start time, p_end time, p_zone text)
returns timestamptz
language sql security definer set search_path = '' as $$
  select public.resolve_deliver_after(p_now, p_start, p_end, p_zone);
$$;

-- ---------------------------------------------------------------------------
-- Fixture: one guardian pair with an accepted membership, so RLS allows a
-- notification_preferences write.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('tzc_mom');
select tests.create_supabase_user('tzc_dad');

select tests.authenticate_as('tzc_mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(2100), 'Rowan', true, 0, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(2100), 'co_parent', 'Dad',
  '9999999999999999999999999999999999999999999999999999999999999999', 48
);
select tests.authenticate_as('tzc_dad');
select public.accept_guardian_invitation(
  '9999999999999999999999999999999999999999999999999999999999999999', 'Dad'
);

-- ---------------------------------------------------------------------------
-- CHECK rejects garbage, sqlstate 23514.
-- ---------------------------------------------------------------------------
select throws_ok(
  format(
    $$insert into public.notification_preferences (user_id, profile_id, time_zone)
      values (%L, %L, 'Mars/Olympus')$$,
    tests.get_supabase_uid('tzc_dad'), tests.ulid(2100)
  ),
  '23514', null,
  'notification_preferences_time_zone_valid rejects an unrecognized zone name'
);

-- ---------------------------------------------------------------------------
-- CHECK accepts an IANA name, and a null value (three-valued CHECK logic --
-- "no quiet hours resolvable" per this column's own comment).
-- ---------------------------------------------------------------------------
select lives_ok(
  format(
    $$insert into public.notification_preferences (user_id, profile_id, time_zone)
      values (%L, %L, 'America/New_York')$$,
    tests.get_supabase_uid('tzc_dad'), tests.ulid(2100)
  ),
  'notification_preferences_time_zone_valid accepts a valid IANA zone name'
);

select lives_ok(
  format(
    $$update public.notification_preferences set time_zone = null
       where user_id = %L and profile_id = %L$$,
    tests.get_supabase_uid('tzc_dad'), tests.ulid(2100)
  ),
  'notification_preferences_time_zone_valid accepts a null time_zone (no quiet hours resolvable)'
);

-- ---------------------------------------------------------------------------
-- resolve_deliver_after: unchanged instants for a valid zone, pinned across
-- the America/New_York 2026 DST boundary (same dates timezone_contract_test
-- pins for observations_derive_local_date, so both suites reason about the
-- same real-world transition), via the service-role wrapper created above.
-- ---------------------------------------------------------------------------

-- Spring-forward day (2026-03-08, EST -05:00 -> EDT -04:00 at 2am local):
-- p_now = 2026-03-08 06:30 EDT (post-jump), inside the 22:00-07:00 wrapped
-- quiet window's early-morning tail -> resolves to 07:00 EDT the same day.
select is(
  pg_temp.resolve_deliver_after(
    '2026-03-08T10:30:00Z'::timestamptz, '22:00'::time, '07:00'::time, 'America/New_York'),
  '2026-03-08T11:00:00Z'::timestamptz,
  'resolve_deliver_after, valid zone, spring-forward day (EDT -04:00 post-jump): same instant as '
  || 'before the defence was removed -- 06:30 local resolves to 07:00 local the same day'
);

-- Fall-back day (2026-11-01, EDT -04:00 -> EST -05:00 at 2am local): p_now
-- = 2026-11-01 23:00 EST (well post-rollback), inside the window's evening
-- portion -> resolves to 07:00 EST the NEXT day.
select is(
  pg_temp.resolve_deliver_after(
    '2026-11-02T04:00:00Z'::timestamptz, '22:00'::time, '07:00'::time, 'America/New_York'),
  '2026-11-02T12:00:00Z'::timestamptz,
  'resolve_deliver_after, valid zone, fall-back day (EST -05:00 post-rollback): same instant as '
  || 'before the defence was removed -- 23:00 local resolves to 07:00 local the next day'
);

-- ---------------------------------------------------------------------------
-- The removed defence: resolve_deliver_after no longer catches an
-- exception around the zone lookup at all (proven structurally via
-- pg_get_functiondef rather than by trying to reach an unreachable branch
-- with a garbage p_zone -- the CHECK now guarantees no caller can produce
-- one). SQL line comments (`-- ...`) are stripped first: the function's
-- own rationale comment (kept per issue #321's instruction to preserve
-- every rationale comment) quotes the removed `exception when others`
-- syntax verbatim while explaining why it's gone, so a raw substring
-- match against the full pg_get_functiondef text would false-positive on
-- that prose; stripping comments checks the actual code, not the words
-- used to describe it.
-- ---------------------------------------------------------------------------
select ok(
  (select regexp_replace(
            pg_get_functiondef('public.resolve_deliver_after(timestamptz,time,time,text)'::regprocedure),
            '--[^\n]*', '', 'g')
     !~* 'exception'),
  'resolve_deliver_after''s body no longer contains an exception handler -- the removed ad hoc zone '
  || 'defence is gone, not just unreachable (comments stripped before the check, since the kept '
  || 'rationale comment itself quotes the removed syntax)'
);

select * from finish();
rollback;
