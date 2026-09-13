-- Migration: 20260913014000_sync_server_version_indexes_and_pull.sql
--
-- Issue #525 (P1) - SERVER HALF ONLY (client adoption, item (a) "cursor_profile_guardians"
-- and item (d) "drop resolvedSeen as a reconcile trigger" are Dart-side and
-- explicitly out of scope for this migration - see AGENTS.md's "Do not
-- modify Dart code" instruction for this PR).
--
-- Two independent server-side fixes:
--
-- 1. (issue item b) `create index concurrently` cannot run inside a
--    migration transaction (Supabase/`supabase db push` wraps each
--    migration file in one transaction; `CONCURRENTLY` requires running
--    outside any transaction block). So this adds plain
--    `create index if not exists ... (server_version)` for profiles,
--    day_entries, and profile_guardians - the three tables issue #175 (the
--    "index half only" predecessor) left with a composite
--    `(user_id, server_version)` index but no bare `server_version` index,
--    unlike every table added since (observations, profile_modes,
--    cycle_overrides, care_notes, visit_prep_items all got one from day
--    one). A plain (non-concurrent) `create index` does take a brief
--    `SHARE` lock that blocks writes to the table for the build's
--    duration; on tables already indexed on `(user_id, server_version)`
--    this build is index-only and fast, and doing it inside the ordinary
--    migration transaction is the only option available in this pipeline
--    without decomposing the migration into a `CONCURRENTLY`-only,
--    non-transactional step CI does not currently support running.
--
-- 2. (issue item c) `public.sync_pull(p_cursors jsonb)`: a single
--    SECURITY DEFINER RPC that computes the caller's accepted-membership
--    profile-id set ONCE (rather than one `is_profile_guardian()` call per
--    scanned row, which the planner cannot push below `LIMIT` - the
--    issue's compounding problem 3), then returns one paginated page per
--    synced table, each filtered by that tenant predicate BEFORE the
--    cursor. This does not replace the seven per-table selects the client
--    issues today - it is an alternative shape a future client CAN adopt,
--    landed here so that adoption is a client-side change against an
--    already-tested contract, not a schema change bundled with app code.
--
-- CONTRACT for the future client-side adopter:
--   - Call `select public.sync_pull(p_cursors)` where p_cursors is a JSON
--     object mapping table name to the caller's last-seen server_version
--     for that table (any key may be omitted - an omitted or null cursor
--     defaults to 0, i.e. "everything"). Table name keys: 'profiles',
--     'day_entries', 'observations', 'profile_modes', 'cycle_overrides',
--     'care_notes', 'visit_prep_items', 'profile_guardians'.
--   - The return value is a JSON object with exactly those eight keys,
--     each an array of that table's full rows (as `to_jsonb(row)` - same
--     shape as what `select *` under RLS already returns a guardian
--     today), ordered by `server_version` ascending, capped at 500 rows
--     per table per call (mirrors sync_push's own `c_max_rows`). A table
--     with more than 500 pending rows requires a follow-up call with the
--     cursor advanced to the last row's own server_version - there is no
--     separate "has more" flag; the caller detects it by getting back
--     exactly 500 rows for a table and re-calling.
--   - Tenant scoping: every table except `profile_guardians` is filtered
--     to `profile_id = any(<the caller's accepted profile ids>)`;
--     `profiles` itself is filtered to `id = any(...)` the same way.
--     `profile_guardians` returns every membership row (any role, any
--     status - including a still-pending invite's placeholder row, if this
--     schema ever creates one, and a revoked row, both of which existing
--     clients already need to see) on every profile in that same set - not
--     just the caller's own membership row - so a shared profile's full
--     guardian list round-trips, matching what the client needs to render
--     "who else can see this profile".
--   - `deleted_profiles` (Issue #522) is deliberately NOT one of the eight
--     keys here - it has its own, simpler tenant predicate
--     (`guardian_user_ids @> array[caller]`, no profile_guardians survival
--     assumption - see 20260913013000_deleted_profiles_tombstone_purge.sql's
--     header) and is expected to be pulled and adopted as its own,
--     separate incremental query, not folded into this RPC's per-profile
--     scoping.
--   - This function computes eligibility itself (SECURITY DEFINER, its own
--     `profile_guardians` lookup) and does not rely on RLS at all for its
--     result set - RLS on the underlying tables is unchanged and still
--     applies to any OTHER access path (PostgREST `select`, sync_push,
--     etc.), so this RPC does not widen what any role can reach.
--
-- Coverage: supabase/tests/sync_pull_test.sql.

-- ---------------------------------------------------------------------------
-- 1. Plain server_version indexes (not CONCURRENTLY - see header).
-- ---------------------------------------------------------------------------

create index if not exists profiles_server_version_idx
  on public.profiles (server_version);

create index if not exists day_entries_server_version_idx
  on public.day_entries (server_version);

create index if not exists profile_guardians_server_version_idx
  on public.profile_guardians (server_version);

-- ---------------------------------------------------------------------------
-- 2. sync_pull(p_cursors jsonb)
-- ---------------------------------------------------------------------------

create or replace function public.sync_pull(p_cursors jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c_page_size constant integer := 500;
  v_uid uuid := (select auth.uid());
  v_profile_ids text[];
  v_result jsonb := '{}'::jsonb;
  v_cursor bigint;
begin
  if v_uid is null then
    raise exception 'sync_pull requires an authenticated user'
      using errcode = 'insufficient_privilege';
  end if;

  if p_cursors is null or jsonb_typeof(p_cursors) <> 'object' then
    raise exception 'p_cursors must be a JSON object'
      using errcode = 'invalid_parameter_value';
  end if;

  -- The tenant predicate, computed ONCE up front - every page below reuses
  -- this same array rather than invoking a per-row guardian-membership
  -- check (Issue #525, compounding problem 3).
  select coalesce(array_agg(profile_id), '{}') into v_profile_ids
    from public.profile_guardians
   where user_id = v_uid
     and status = 'accepted';

  v_cursor := coalesce((p_cursors ->> 'profiles')::bigint, 0);
  v_result := v_result || jsonb_build_object('profiles', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from (
      select * from public.profiles
       where id = any(v_profile_ids)
         and server_version > v_cursor
       order by server_version
       limit c_page_size
    ) t
  ));

  v_cursor := coalesce((p_cursors ->> 'day_entries')::bigint, 0);
  v_result := v_result || jsonb_build_object('day_entries', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from (
      select * from public.day_entries
       where profile_id = any(v_profile_ids)
         and server_version > v_cursor
       order by server_version
       limit c_page_size
    ) t
  ));

  v_cursor := coalesce((p_cursors ->> 'observations')::bigint, 0);
  v_result := v_result || jsonb_build_object('observations', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from (
      select * from public.observations
       where profile_id = any(v_profile_ids)
         and server_version > v_cursor
       order by server_version
       limit c_page_size
    ) t
  ));

  v_cursor := coalesce((p_cursors ->> 'profile_modes')::bigint, 0);
  v_result := v_result || jsonb_build_object('profile_modes', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from (
      select * from public.profile_modes
       where profile_id = any(v_profile_ids)
         and server_version > v_cursor
       order by server_version
       limit c_page_size
    ) t
  ));

  v_cursor := coalesce((p_cursors ->> 'cycle_overrides')::bigint, 0);
  v_result := v_result || jsonb_build_object('cycle_overrides', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from (
      select * from public.cycle_overrides
       where profile_id = any(v_profile_ids)
         and server_version > v_cursor
       order by server_version
       limit c_page_size
    ) t
  ));

  v_cursor := coalesce((p_cursors ->> 'care_notes')::bigint, 0);
  v_result := v_result || jsonb_build_object('care_notes', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from (
      select * from public.care_notes
       where profile_id = any(v_profile_ids)
         and server_version > v_cursor
       order by server_version
       limit c_page_size
    ) t
  ));

  v_cursor := coalesce((p_cursors ->> 'visit_prep_items')::bigint, 0);
  v_result := v_result || jsonb_build_object('visit_prep_items', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from (
      select * from public.visit_prep_items
       where profile_id = any(v_profile_ids)
         and server_version > v_cursor
       order by server_version
       limit c_page_size
    ) t
  ));

  -- profile_guardians: every membership row on every profile in the
  -- tenant set (not just the caller's own row) - see this migration's
  -- header contract note.
  v_cursor := coalesce((p_cursors ->> 'profile_guardians')::bigint, 0);
  v_result := v_result || jsonb_build_object('profile_guardians', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from (
      select * from public.profile_guardians
       where profile_id = any(v_profile_ids)
         and server_version > v_cursor
       order by server_version
       limit c_page_size
    ) t
  ));

  return v_result;
end;
$$;

comment on function public.sync_pull(jsonb) is
  'Issue #525: SECURITY DEFINER incremental-pull RPC returning one page '
  '(<= 500 rows, ordered by server_version) per synced table -- profiles, '
  'day_entries, observations, profile_modes, cycle_overrides, care_notes, '
  'visit_prep_items, profile_guardians -- filtered to the caller''s '
  'ACCEPTED profile_guardians membership set BEFORE the server_version '
  'cursor, computed once up front rather than per row. Not yet called by '
  'the client (the seven-table pull in supabase_sync_engine.dart is '
  'unchanged) -- this is the contract a future client-side change adopts. '
  'See 20260913014000_sync_server_version_indexes_and_pull.sql''s header '
  'for the full per-key contract.';

revoke all on function public.sync_pull(jsonb) from public, anon;
grant execute on function public.sync_pull(jsonb) to authenticated;
