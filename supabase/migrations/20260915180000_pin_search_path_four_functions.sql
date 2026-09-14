-- Migration: 20260915180000_pin_search_path_four_functions.sql
-- Issue #194 (D-3): pins `search_path = ''` on four functions in `public`
-- that the security advisor's `function_search_path_mutable` lint flags --
-- the two the issue names, `is_valid_tags_array` and `resolve_deliver_after`
-- (20260907010000_tags_element_length_check.sql / latest body in
-- 20260908210000_notification_tz_check.sql:134-201), plus two more found by
-- a local `supabase db advisors --local --type security` sweep while
-- building this migration (2026-09-15), added by migrations that landed
-- after #194 was filed: `is_valid_tracking_preferences`
-- (20260915000000_profile_tracking_preferences.sql) and
-- `is_valid_flow_level` (20260915130000_data_consistency_bundle.sql). All
-- four are pinned together here rather than only the two #194 names, since
-- leaving the other two unpinned would keep the advisor gate #454 tightens
-- (the same PR) failing for no reason tied to scope, only to timing.
--
-- Coordinator review (production, read-only) confirmed pg_net is
-- `supabase_admin`-owned, non-relocatable, and its `net` schema ACL was
-- granted by `supabase_admin` to postgres/anon/authenticated/service_role/
-- supabase_functions_admin -- a `drop extension pg_net` inside an
-- unattended migration is too risky (the `postgres` role may not be
-- permitted to drop it at all, blocking every later migration on failure;
-- a successful recreate is not guaranteed to restore every one of those
-- Supabase-managed grants, silently breaking push dispatch). D-4 (moving
-- pg_net out of public) is therefore **deferred**, not done here -- this
-- migration does not touch pg_net or pg_cron at all. The `extension_in_public`
-- advisor finding for pg_net is instead narrowly excluded from the
-- tightened gate by `.github/scripts/check-advisor-gate.sh` (see that
-- script's header and #454's PR for the full rationale), pending a
-- Supabase-supported relocation path as a follow-up.
--
-- `alter function ... set search_path = '';` is used instead of `create or
-- replace function` for all four: it needs no re-emission of any function
-- body, so there is no risk of transcribing a stale body (the mistake this
-- migration made and fixed during review -- see is_valid_tags_array/
-- resolve_deliver_after below) and no reason to drop and re-add
-- day_entries_tags_check (ALTER FUNCTION does not change the function's
-- OID, so Postgres has no reason to revalidate a CHECK that calls it --
-- unlike CREATE OR REPLACE, which was the original plan here before
-- review; that would have been a full-table re-validation scan in
-- production for zero behavioral benefit). Each function's body was
-- checked before pinning (see below) to confirm it references only
-- `pg_catalog` builtins or nothing at all -- never an unqualified
-- `public.*` reference, which `search_path = ''` would break.
--
-- Body review (2026-09-15, against the current definition of each on
-- `origin/main`):
--   * is_valid_tags_array(jsonb): jsonb_typeof, jsonb_array_length,
--     jsonb_array_elements, char_length -- all pg_catalog. Safe.
--   * resolve_deliver_after(timestamptz, time, time, text): only built-in
--     operators/casts (`at time zone`, `::date`, `::time`, interval
--     arithmetic) -- all pg_catalog. Safe.
--   * is_valid_tracking_preferences(jsonb): jsonb_typeof, jsonb_each,
--     jsonb_object_keys, length, a numeric cast -- all pg_catalog. Safe.
--   * is_valid_flow_level(text): a bare `p_flow in (...)` literal
--     comparison -- no object reference at all. Safe.
-- None of the four calls any other function or reads any table, so none
-- needed a `public.`-qualification fix before pinning.

alter function public.is_valid_tags_array(jsonb) set search_path = '';

comment on function public.is_valid_tags_array(jsonb) is
  'Validates that a JSONB value is an array of at most 32 strings, each at '
  'most 64 characters (Issues #40, #94). search_path pinned to an empty '
  'string (Issue #194, D-3) -- the body only ever calls pg_catalog '
  'functions, which are always implicitly searched regardless of '
  'search_path, so this changes nothing about how it resolves.';

alter function public.resolve_deliver_after(timestamptz, time, time, text) set search_path = '';

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
  'reach this function through its only input source. search_path pinned to '
  'an empty string (Issue #194, D-3) -- the body only ever uses built-in '
  'operators and casts, which resolve via pg_catalog regardless of '
  'search_path, so this changes nothing about how it behaves.';

alter function public.is_valid_tracking_preferences(jsonb) set search_path = '';

comment on function public.is_valid_tracking_preferences(jsonb) is
  'Shape check for Issue #259 tracking-preferences documents: an object mapping category wire names (1-64 chars, any string -- the taxonomy is client-owned and grows, so keys are never validated against a closed set) to objects carrying exactly a boolean enabled and an integer sort_order in [0, 1000]. Mirrors is_valid_tags_array()''s role for day_entries.tags (issue #40). search_path pinned to an empty string (Issue #194, D-3, found via a local advisor sweep while building that migration) -- the body only ever calls pg_catalog functions, so this changes nothing about how it resolves.';

alter function public.is_valid_flow_level(text) set search_path = '';

comment on function public.is_valid_flow_level(text) is
  'Issue #303: the single SQL source of truth for flow''s allowed values -- '
  'called by the flow_level domain''s own CHECK below, by sync_push''s '
  'per-row validation, and by bulk_import_entries''s set-based rejection '
  'CASE, so the seven-value list (Issue #247''s super_heavy/not_bleeding '
  'included) is declared exactly once in SQL. A plain boolean predicate, '
  'never a domain cast, so bulk_import_entries''s set-based CASE can keep '
  'rejecting one bad row instead of aborting the whole batch on a '
  'check_violation. search_path pinned to an empty string (Issue #194, D-3, '
  'found via a local advisor sweep while building that migration) -- the '
  'body is a bare literal comparison with no object reference at all, so '
  'this changes nothing about how it resolves.';
