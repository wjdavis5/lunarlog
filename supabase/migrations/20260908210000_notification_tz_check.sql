-- Migration: 20260908210000_notification_tz_check.sql
-- Issue #321 (P2, epic:backend-data): time-zone contract follow-ups from
-- the #319 review (issue #180's PR). #319's own migration
-- (`20260908180000_timezone_contract.sql`) added `public.is_valid_timezone`
-- and a CHECK on `observations.tz`/`day_entries.tz`, the two `tz`-carrying
-- columns on the sync tables, but deliberately left
-- `notification_preferences.time_zone` -- the third `tz`-carrying column in
-- the schema, and the exact input `resolve_deliver_after`'s own ad hoc zone
-- defence (`20260906220000_notification_outbox.sql`) exists to guard
-- against -- untouched, "existing defensive code may be
-- simplified/removed as a follow-up, not required here" per that
-- migration's own header, item 5. This migration is that follow-up.
--
-- Timestamp note: this migration sorts after `20260908200000_` (in-flight
-- issue #247, a flow model) and `20260908190000_` (in-flight issue #167, a
-- bulk import) per this run's assigned timestamp -- neither touches
-- `notification_preferences`, `resolve_deliver_after`, or
-- `is_valid_timezone`, so there is no ordering dependency with either.
--
-- Scope (see issue #321's four checkboxes):
--   1. `notification_preferences_time_zone_valid`: the same
--      `is_valid_timezone` CHECK #319 put on `observations.tz`/
--      `day_entries.tz`, now on `notification_preferences.time_zone` too --
--      `not valid` + `validate constraint`, matching #319's pattern (see
--      that migration's header, "Judgement calls", for why this pattern
--      was chosen over a hand-written pre-check).
--
--      OPERATOR PRE-FLIGHT (run against `dleexnnevuuddcgcpztq` before
--      `supabase db push` deploys this migration -- `validate constraint`
--      aborts the migration and rolls back the whole transaction on the
--      FIRST invalid stored value it finds, so this query is how an
--      operator finds every offending row up front instead of discovering
--      them one deploy attempt at a time; adapted from #319's migration,
--      which covered `observations`/`day_entries` -- this is the same
--      shape for `notification_preferences`, with a `time_zone is not
--      null` filter added since this column, unlike `tz` on the other two
--      tables, is nullable ("no quiet hours resolvable")):
--
--        select user_id, profile_id, time_zone
--          from public.notification_preferences
--         where time_zone is not null
--           and not public.is_valid_timezone(time_zone);
--
--      (This is the exact predicate the CHECK uses -- `is_valid_timezone`
--      exists on the project once 20260908180000 is deployed. The catalog
--      form `not in (select name from pg_timezone_names) and not in (select
--      abbrev from pg_timezone_abbrevs)` is an over-inclusive fallback: it is
--      case-sensitive and misses POSIX specs the CHECK accepts. Pay attention
--      to empty-string values -- `''` fails the CHECK.)
--
--      A non-empty result means `validate constraint` WILL fail and the
--      migration transaction WILL roll back (no partial application -- the
--      CHECK and `resolve_deliver_after`'s redefinition below either land
--      together or not at all); fix or null out the offending row(s)
--      first.
--   2. `resolve_deliver_after` (`public.resolve_deliver_after(timestamptz,
--      time, time, text)`): re-emitted here via `create or replace`,
--      latest body copied verbatim from
--      `20260906220000_notification_outbox.sql` (its only definition --
--      `grep -l "function public.resolve_deliver_after"
--      supabase/migrations/*.sql` returns just that one file) with every
--      rationale comment kept EXCEPT the bare `begin ... exception when
--      others ... end;` block around the zone lookup, which is now
--      simplified to a direct assignment -- see the inline comment at that
--      line for the full "why this is safe now" reasoning. Short version:
--      every caller of this function (`enqueue_caregiver_alerts` in
--      `20260906220000_notification_outbox.sql`/
--      `20260908110000_alert_digest_cadence.sql`,
--      `scan_missed_entry_reminders` in
--      `20260906230000_reminder_windows_and_cron.sql`,
--      `sweep_alert_digests` in `20260908110000_alert_digest_cadence.sql`)
--      passes `p_zone` from `notification_preferences.time_zone` and
--      nowhere else -- `grep -n "resolve_deliver_after(" supabase/
--      migrations/*.sql` confirms all four call sites read that one
--      column, none a literal or a different table -- so the
--      `notification_preferences_time_zone_valid` CHECK added in item 1
--      above now guarantees every non-null `p_zone` reaching this function
--      is a string `public.is_valid_timezone` already accepted at write
--      time. No defensive fallback is kept, because there is currently no
--      other source `p_zone` can come from; if a future caller ever passes
--      it from anywhere else (a literal, a different table, a request
--      parameter), that caller is responsible for validating its own input
--      before calling this function, or a guard must be reintroduced here.
--      The function's own `comment on function` is updated to match (drops
--      the "unrecognized IANA zone name" clause). `revoke all ... from
--      public, anon, authenticated` is re-issued exactly as before --
--      `create or replace function` does not by itself change existing
--      grants/revokes, but this codebase's convention (see #159/#180's
--      `sync_push` re-emissions) is to re-state them anyway so a
--      migration's privilege posture is self-contained and not dependent
--      on reading an older file.
--   3. `is_valid_timezone(null) is null`: already true on `main`.
--      `20260908180000_timezone_contract.sql` made `is_valid_timezone`
--      `strict` (review fix, its own header item 1), and
--      `timezone_contract_test.sql` already asserts
--      `is_valid_timezone(null) is null` directly. Nothing to add here;
--      this migration's own pgTAP coverage
--      (`notification_tz_check_test.sql`) does not re-assert it, per the
--      issue's own instruction to reference rather than duplicate.
--   4. Permissiveness note (CHECK looser than the client's
--      `isValidIanaTimeZone`): already documented, verbatim, in
--      `20260908180000_timezone_contract.sql`'s header (item 1) and its
--      `comment on function public.is_valid_timezone` -- both apply
--      unchanged to this CHECK, since it uses the identical predicate.
--      Referenced here rather than duplicated, per the issue.
--
-- Judgement calls (mirrored in the PR's Assumptions section):
--   * Same `not valid` + `validate constraint` reasoning as #319 -- see
--     that migration's header for the full rationale; not repeated here.
--   * `resolve_deliver_after`'s removed defence was the only code in this
--     migration's scope that read `p_zone` before this CHECK existed.
--     `enqueue_caregiver_alerts`, `scan_missed_entry_reminders`, and
--     `sweep_alert_digests` all resolve their own zone-lookup failures
--     independently (`sweep_alert_digests` already degrades a bad zone to
--     `'UTC'` with its own `begin/exception` block, unrelated to this
--     function) and are out of this issue's scope -- untouched here.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. notification_preferences_time_zone_valid: see header item 1.
-- ---------------------------------------------------------------------------

alter table public.notification_preferences
  add constraint notification_preferences_time_zone_valid
  check (public.is_valid_timezone(time_zone)) not valid;

alter table public.notification_preferences
  validate constraint notification_preferences_time_zone_valid;

-- ---------------------------------------------------------------------------
-- 2. resolve_deliver_after: re-emitted, defence removed. See header item 2.
-- ---------------------------------------------------------------------------

create or replace function public.resolve_deliver_after(
  p_now timestamptz,
  p_quiet_start time,
  p_quiet_end time,
  p_zone text
) returns timestamptz
language plpgsql
stable
as $$
declare
  v_local_ts timestamp;
  v_local_date date;
  v_local_time time;
  v_wraps boolean;
  v_inside boolean;
  v_end_date date;
begin
  if p_quiet_start is null or p_quiet_end is null or p_zone is null
     or p_quiet_start = p_quiet_end then
    return p_now;
  end if;

  -- Issue #321 (follow-up from #180/#319's review): #3's original review
  -- fix wrapped this assignment in a bare `exception when others` because
  -- p_zone was, at the time, an unvalidated guardian-supplied IANA zone
  -- name (lib/domain/util/timezone.dart) with no server-side check on
  -- notification_preferences.time_zone -- a garbage value could reach here
  -- from a day_entries AFTER trigger or the nightly scan and, left
  -- unguarded, would have aborted the profile holder's own entry write,
  -- the account-deletion re-home, or the whole nightly cron command for
  -- every tenant, over one guardian's bad setting.
  --
  -- notification_preferences_time_zone_valid (added by this migration,
  -- above) now enforces the same public.is_valid_timezone CHECK on that
  -- column that observations.tz/day_entries.tz already had, and every
  -- caller of this function reads p_zone from that column and nowhere
  -- else (see this migration's header for the grep that confirms it) --
  -- so a non-null p_zone reaching this line is guaranteed to be a string
  -- `at time zone` can evaluate. The exception handler is now dead code
  -- and has been removed; if a future caller ever passes p_zone from
  -- somewhere other than notification_preferences.time_zone, that caller
  -- must validate it first, or a guard belongs here again.
  v_local_ts := p_now at time zone p_zone;
  v_local_date := v_local_ts::date;
  v_local_time := v_local_ts::time;
  v_wraps := p_quiet_start > p_quiet_end;

  if v_wraps then
    v_inside := v_local_time >= p_quiet_start or v_local_time < p_quiet_end;
  else
    v_inside := v_local_time >= p_quiet_start and v_local_time < p_quiet_end;
  end if;

  if not v_inside then
    return p_now;
  end if;

  if v_wraps and v_local_time >= p_quiet_start then
    -- Evening portion of a wrapped window: it ends tomorrow morning.
    v_end_date := v_local_date + 1;
  else
    -- A same-day window, or the early-morning tail of a wrapped one.
    v_end_date := v_local_date;
  end if;

  return (v_end_date + p_quiet_end) at time zone p_zone;
end;
$$;

comment on function public.resolve_deliver_after(timestamptz, time, time, text) is
  'Resolves when an alert should actually deliver given the recipient''s '
  'quiet hours (KTD5, R12): p_now unchanged outside the window, or the '
  'window''s end (today or tomorrow, for a wrapped window) when inside it. '
  'A null zone, null start/end, or a zero-length window all mean no quiet '
  'hours. Issue #321: the ad hoc exception handler around the zone lookup '
  '(#3''s original review fix) was removed once '
  'notification_preferences_time_zone_valid guaranteed every caller''s '
  'p_zone (always read from that column) is a string public.is_valid_timezone '
  'already accepted at write time -- an unrecognized zone can no longer '
  'reach this function through its only input source.';

revoke all on function public.resolve_deliver_after(timestamptz, time, time, text)
  from public, anon, authenticated;
