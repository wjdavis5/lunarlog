-- Migration: 20260908160000_observations.sql
-- Issue #240 (P0, epic: Tracking Model): the foundation schema decision
-- every other tracking/import/health/export issue in the epic depends on.
-- Adds a synced `observations` child table -- one row per logged option --
-- instead of widening `day_entries` into ~40 mostly-null columns or a
-- jsonb blob. See the issue body for the full column-shape rationale and
-- the rejected alternatives; this migration implements exactly the
-- decided shape.
--
-- Timestamp note: `20260908150000_` belongs to the still-open, not-yet-
-- merged PR #291 (`export_account_data()`) -- this file sorts after it
-- (AGENTS.md's Migration Flow item 7: sort after whatever is already on
-- `main`, and #291 is not on `main` yet, so this timestamp only needs to
-- clear what IS on `main`, which it does; picking a value after 150000
-- avoids a same-day collision either way this and #291 land).
--
-- Scope for this migration (deliberately not the whole epic - see the
-- issue's "Scope for THIS PR" note):
--   1. Server: the `public.observations` table, its RLS/grants/indexes,
--      the `set_server_version`/`touch_sync_signal` trigger wiring, an
--      attribution guard mirroring `enforce_day_entry_attribution`,
--      `sync_push` gaining a third `p_observations` parameter (2-arg calls
--      keep working via the added parameter's default), a per-day
--      observation cap (200) enforced in the RPC (not a CHECK -- a CHECK
--      cannot count sibling rows), and a one-off backfill of
--      `day_entries.tags` into `observations` rows.
--   2. `day_entries.tags`/`flow`/`note` are UNTOUCHED here -- kept as a
--      derived, deprecated mirror for at least one release per the issue's
--      migration/backfill plan step 4; retiring the mirror is a follow-up.
--   3. `delete_account_data()` gains an explicit `observations` delete (see
--      below for why it needs one at all despite the cascades already
--      covering it). `export_account_data()` does not exist on `main` yet
--      (PR #291, unmerged) -- there is nothing to `create or replace` here;
--      whichever of #240/#291 merges second must fold observations into
--      the export RPC. Flagged under this migration's own header and in
--      the PR's Follow-ups, not silently skipped.
--
-- Judgement calls (mirrored in the PR's Assumptions section):
--   * Same-date collision "merge" (issue: "set-union on (category, code),
--     the natural analogue of `merge_tag_arrays`"): `day_entries.tags` was
--     a single JSON array on one row, so two devices' independently-created
--     overlapping tag sets could genuinely be unioned into one array.
--     `observations` is a child table where multiple rows per
--     (profile, day, category) are the entire point (Clue's own
--     multi-same-day-category entries, e.g. two sexual-activity logs) --
--     there is no "array" to union, only individual rows. The literal
--     analogue implemented here: when a brand-new incoming row (never
--     before stored under its own id) collides with an already-live row
--     sharing (profile_id, local_date, category, code), the two are
--     resolved head-to-head by the same newer-wins/ulid-tiebreak rule
--     `sync_push`'s day_entries resolver already uses, and the loser
--     becomes a payload-free tombstone rather than a second live row for
--     what is almost always the same tap on two devices ("I have a
--     headache today," logged offline on two phones, must not create two
--     rows). This intentionally does NOT collapse deliberate repeats
--     logged one-at-a-time from a single device/session (those never
--     collide on `id`, so the by-id upsert path leaves them alone) --
--     collapsing is same-row-identity dedup on a race, not a taxonomy
--     rule. Scoped to a brand-new row only (not an edit of an
--     already-stored row) to keep this foundation-scope migration
--     tractable; a `category`/`code` edit on a pre-existing row colliding
--     with a sibling is not resolved by this migration and is left for a
--     follow-up if it proves to matter in practice.
--   * Tombstone payload clearing: every value column is cleared
--     (`code`, `value_num`, `value_text`, `unit`, `intensity`, `excluded`
--     reset to false, `source_id`, `raw`, `observed_at`) mirroring
--     `day_entries`' tombstone-carries-no-payload precedent (issue #224).
--     `category` is deliberately KEPT on a tombstone -- unlike `flow`/
--     `tags`/`note`, it is a closed-vocabulary taxonomy label (e.g.
--     `pain`), not free text or a symptom detail, and `category` is
--     `not null` with no natural sentinel value the way `flow` had `none`
--     available. `local_date`/`tz`/`day_entry_id`/`profile_id` are also
--     kept, matching `day_entries` keeping its own identity columns on a
--     tombstone.
--   * `day_entry_id` and `profile_id` are immutable once a row exists
--     (mirrors `day_entries`' "an entry never legitimately changes
--     profiles" guard) -- enforced in `sync_push`, not by a table
--     constraint, since the RPC is the only insert/update path that needs
--     to reason about the *previous* stored value.
--   * The 500-row `c_max_rows` cap applies to `p_observations` exactly as
--     it does to `p_profiles`/`p_day_entries` today. The issue itself
--     flags that a multi-year Clue import produces far more than 500 rows
--     and that batch sizing needs revisiting "before any importer ships" --
--     that resizing is explicitly out of scope for this foundation
--     migration and tracked as a follow-up, not silently done here.

-- ---------------------------------------------------------------------------
-- 0. day_entries needs a standalone unique constraint on `id` before
--    anything can `references public.day_entries (id)`: its primary key is
--    the composite `(id, user_id)` (unchanged since
--    20260903014208_initial_sync_schema.sql), so `id` alone has never been
--    unique. `public.profiles` hit this exact gap when `profile_guardians`
--    needed to reference it by `id` alone and was fixed the same way
--    (`profiles_id_uq`, 20260904010000_multi_guardian_schema.sql); nothing
--    before this migration ever needed to reference day_entries by id
--    alone, so the gap was never closed for it until now.
-- ---------------------------------------------------------------------------

alter table public.day_entries
  add constraint day_entries_id_uq unique (id);

-- ---------------------------------------------------------------------------
-- 1. public.observations
-- ---------------------------------------------------------------------------

create table public.observations (
  id text not null
    constraint observations_id_ulid_check
    check (id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'),
  day_entry_id text not null
    references public.day_entries (id) on delete cascade,
  profile_id text not null
    references public.profiles (id) on delete cascade,
  local_date date not null,
  observed_at timestamptz,
  tz text not null
    constraint observations_tz_length_check
    check (char_length(tz) <= 64),
  category text not null
    constraint observations_category_length_check
    check (char_length(category) >= 1 and char_length(category) <= 64),
  -- Nullable only for a purely-numeric category (e.g. a bare BBT reading);
  -- free text, bounded, never validated against a closed set here (issue
  -- #240 D-10 companion note: the ~200 option codes are the opposite case
  -- from `flow` -- stored, never rejected, so a newer client's or a Clue
  -- import's not-yet-locally-known code always round-trips).
  code text
    constraint observations_code_length_check
    check (code is null or char_length(code) <= 64),
  value_num numeric,
  value_text text
    constraint observations_value_text_length_check
    check (value_text is null or char_length(value_text) <= 2000),
  unit text
    constraint observations_unit_length_check
    check (unit is null or char_length(unit) <= 32),
  intensity smallint
    constraint observations_intensity_check
    check (intensity is null or (intensity between 1 and 5)),
  excluded boolean not null default false,
  source text not null default 'manual'
    constraint observations_source_check
    check (source in ('manual', 'apple_health', 'health_connect', 'wearable', 'clue_import')),
  source_id text
    constraint observations_source_id_length_check
    check (source_id is null or char_length(source_id) <= 128),
  -- Escape hatch for an unrecognised type/value shape (A1-45); bounded so it
  -- cannot become an unbounded payload dump the way an open jsonb column on
  -- day_entries itself was rejected for (see this migration's header / the
  -- issue's "why not a jsonb blob" section).
  raw jsonb
    constraint observations_raw_size_check
    check (raw is null or pg_column_size(raw) <= 8192),
  logged_by_user_id uuid references auth.users (id) on delete set null,
  last_modified_by_user_id uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_version bigint not null default 0,
  primary key (id),
  -- Structural backstop (issue #224 precedent: the table CHECK is the
  -- enforcement mechanism that survives a future sync_push re-emission
  -- that forgets to clear a field in-RPC). category is deliberately
  -- exempted -- see this migration's header "Judgement calls".
  constraint observations_tombstone_payload_check
    check (
      deleted_at is null
      or (
        code is null
        and value_num is null
        and value_text is null
        and unit is null
        and intensity is null
        and excluded = false
        and source_id is null
        and raw is null
        and observed_at is null
      )
    )
);

comment on table public.observations is
  'Issue #240: one row per logged option (Clue tracking model). Child of day_entries via day_entry_id (cascades with the day''s tombstone); profile_id is denormalized for RLS predicates and query, matching day_entries. Tombstones (deleted_at not null) carry no payload except category/local_date/tz/day_entry_id/profile_id (see observations_tombstone_payload_check and this migration''s header). day_entries.tags/flow/note remain the source of truth for this release; a backfill below mirrors existing tags into observations rows.';

create index observations_profile_id_local_date_idx
  on public.observations (profile_id, local_date);
create index observations_profile_id_category_local_date_idx
  on public.observations (profile_id, category, local_date);
create index observations_server_version_idx
  on public.observations (server_version);
-- Not one of the issue's three listed indexes, but every other FK in this
-- schema that participates in a cascade delete has one (day_entries_profile_fk
-- has no separate index because profile_id already leads the two indexes
-- above; day_entry_id leads neither) -- added so a day_entries cascade
-- delete (tombstone-cascade or account deletion) doesn't sequential-scan
-- observations, and so the security/performance advisor gate in
-- supabase-migrate.yml has nothing to flag.
create index observations_day_entry_id_idx
  on public.observations (day_entry_id);

create trigger observations_set_server_version
  before insert or update on public.observations
  for each row execute function public.set_server_version();

-- Realtime: no new publication membership. observations reuses the
-- existing content-free public.sync_signals wake-signal exactly like
-- day_entries -- touch_sync_signal() already branches on `new.profile_id`/
-- `old.profile_id` for anything that isn't literally the profiles table, so
-- observations needs no change there, only this trigger wiring it in.
create trigger observations_after_change_signal
  after insert or update or delete on public.observations
  for each row execute function public.touch_sync_signal();

-- ---------------------------------------------------------------------------
-- 2. Attribution guard, mirroring enforce_day_entry_attribution() exactly
--    (Issue #240: "attribution stamping via the same guard pattern").
-- ---------------------------------------------------------------------------

create or replace function public.enforce_observation_attribution()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if (new.logged_by_user_id is not null
          and new.logged_by_user_id is distinct from v_uid)
       or (new.last_modified_by_user_id is not null
             and new.last_modified_by_user_id is distinct from v_uid) then
      raise exception 'attribution columns are server-authoritative'
        using errcode = 'insufficient_privilege';
    end if;
  else
    if new.logged_by_user_id is distinct from old.logged_by_user_id then
      raise exception 'logged_by_user_id is server-authoritative'
        using errcode = 'insufficient_privilege';
    end if;
    if new.last_modified_by_user_id is distinct from v_uid then
      raise exception 'last_modified_by_user_id must be the calling user'
        using errcode = 'insufficient_privilege';
    end if;
  end if;
  return new;
end;
$$;

create trigger observations_attribution_insert_guard
  before insert on public.observations
  for each row execute function public.enforce_observation_attribution();

create trigger observations_attribution_update_guard
  before update on public.observations
  for each row execute function public.enforce_observation_attribution();

revoke execute on function public.enforce_observation_attribution() from public, anon;

-- ---------------------------------------------------------------------------
-- 3. Row-Level Security -- mirrors day_entries' guardian-role predicates
--    exactly (issue #240 acceptance criteria): guardian select; primary/
--    co_parent/caregiver write; no client DELETE (tombstone-only, like
--    every other synced table).
-- ---------------------------------------------------------------------------

alter table public.observations enable row level security;
alter table public.observations force row level security;

create policy "observations_select_guardians" on public.observations
  for select to authenticated
  using (
    public.is_profile_guardian(profile_id, (select auth.uid()))
  );

create policy "observations_insert_guardians" on public.observations
  for insert to authenticated
  with check (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent', 'caregiver'])
  );

create policy "observations_update_guardians" on public.observations
  for update to authenticated
  using (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent', 'caregiver'])
  )
  with check (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent', 'caregiver'])
  );

-- ---------------------------------------------------------------------------
-- 4. Privileges (KTD15): column-list grants, no DELETE, matching day_entries.
--    day_entry_id/profile_id are granted (a client's own row still needs to
--    be able to round-trip them in an UPDATE) but sync_push itself refuses
--    any change to either on an existing row (see below) -- exactly the
--    same "grant the column, enforce immutability in the RPC" shape
--    day_entries already uses for profile_id.
-- ---------------------------------------------------------------------------

revoke all on table public.observations from public, anon, authenticated;

grant select, insert on table public.observations to authenticated;
grant update (
  day_entry_id, profile_id, local_date, observed_at, tz, category, code,
  value_num, value_text, unit, intensity, excluded, source, source_id, raw,
  updated_at, deleted_at
) on table public.observations to authenticated;
grant update (last_modified_by_user_id) on table public.observations to authenticated;

-- ---------------------------------------------------------------------------
-- 5. sync_push: create-or-replaced from its latest body
--    (20260908140000_tombstone_flow_clear.sql, the current tip on main),
--    copied verbatim, with a third parameter (p_observations jsonb default
--    '[]') and a new "observations" section appended after the existing day
--    entries section. Nothing about the profiles/day_entries handling
--    changes: winner/loser selection, tombstone stamps, role checks,
--    attribution stamping, the advisory lock, the row-count caps, and the
--    key allow-lists are all untouched.
--
--    Postgres identifies a function by name + parameter TYPE LIST, so
--    adding a third parameter does not `CREATE OR REPLACE` the existing
--    2-argument `sync_push(jsonb, jsonb)` in place - it would instead sit
--    alongside it as a second, distinct overload, silently forking the
--    function in two (a 2-arg call would keep resolving to the OLD,
--    unmaintained body forever - the exact-arity match wins over a
--    default-substituted one - defeating the entire point of adding the
--    parameter here rather than in a follow-up). The explicit drop below
--    removes that old 2-arg overload first, so there is exactly one
--    `sync_push` after this migration and a 2-arg call resolves to *this*
--    body with `p_observations` taking its `'[]'::jsonb` default - which is
--    what "keep the old 2-arg call working" in the issue means.
-- ---------------------------------------------------------------------------

drop function if exists public.sync_push(jsonb, jsonb);

create or replace function public.sync_push(
  p_profiles jsonb,
  p_day_entries jsonb,
  p_observations jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  c_max_rows constant integer := 500;
  c_max_observations_per_day constant integer := 200;
  c_ulid constant text := '^[0-9A-HJKMNP-TV-Z]{26}$';
  c_profile_keys constant text[] := array[
    'id', 'display_name', 'is_minor', 'sort_order', 'archived_at',
    'created_at', 'updated_at', 'deleted_at',
    -- U1: profile subject metadata, syncable like any other profile column
    'birth_year', 'relationship',
    -- #131: care mode, syncable like any other profile column
    'mode',
    -- tolerated but never read
    'user_id', 'server_version', 'transferred_at'];
  c_day_entry_keys constant text[] := array[
    'id', 'profile_id', 'local_date', 'tz', 'flow', 'tags', 'note',
    'updated_at', 'deleted_at',
    -- tolerated but never read
    'user_id', 'server_version', 'logged_by_user_id', 'last_modified_by_user_id'];
  -- Issue #240: observations' allowed keys.
  c_observation_keys constant text[] := array[
    'id', 'day_entry_id', 'profile_id', 'local_date', 'observed_at', 'tz',
    'category', 'code', 'value_num', 'value_text', 'unit', 'intensity',
    'excluded', 'source', 'source_id', 'raw', 'updated_at', 'deleted_at',
    -- tolerated but never read
    'user_id', 'server_version', 'logged_by_user_id', 'last_modified_by_user_id',
    'created_at'];

  v_uid uuid := (select auth.uid());
  v_row jsonb;
  v_resolved jsonb := '[]'::jsonb;
  v_rejected jsonb := '[]'::jsonb;

  -- parsed incoming row
  v_id text;
  v_updated_at timestamptz;
  v_deleted_at timestamptz;
  v_created_at timestamptz;
  v_archived_at timestamptz;
  v_display_name text;
  v_is_minor boolean;
  v_sort_order integer;
  v_birth_year smallint;
  v_relationship text;
  -- #131: care mode; absent key parses to the column default
  v_mode text;
  v_profile_id text;
  v_local_date date;
  v_tz text;
  v_flow text;
  v_tags jsonb;
  v_note text;

  v_stored_profile public.profiles%rowtype;
  v_stored public.day_entries%rowtype;
  v_other public.day_entries%rowtype;
  v_accept boolean;
  v_incoming_wins boolean;
  v_caller_role text;

  -- Issue #240: observations parsing/resolution state.
  v_day_entry_id text;
  v_observed_at timestamptz;
  v_category text;
  v_code text;
  v_value_num numeric;
  v_value_text text;
  v_unit text;
  v_intensity smallint;
  v_excluded boolean;
  v_source text;
  v_source_id text;
  v_raw jsonb;
  v_day_entry_profile_id text;
  v_stored_obs public.observations%rowtype;
  v_other_obs public.observations%rowtype;
  v_obs_incoming_wins boolean;
  v_obs_count integer;
begin
  if v_uid is null then
    raise exception 'sync_push requires an authenticated user'
      using errcode = 'insufficient_privilege';
  end if;

  -- Serialise pushes per-user so server_version commits monotonically per user (Issue #14).
  perform pg_advisory_xact_lock(hashtext(v_uid::text));

  if p_profiles is null or jsonb_typeof(p_profiles) <> 'array' then
    raise exception 'p_profiles must be a JSON array'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_day_entries is null or jsonb_typeof(p_day_entries) <> 'array' then
    raise exception 'p_day_entries must be a JSON array'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_observations is null or jsonb_typeof(p_observations) <> 'array' then
    raise exception 'p_observations must be a JSON array'
      using errcode = 'invalid_parameter_value';
  end if;
  if jsonb_array_length(p_profiles) > c_max_rows then
    raise exception 'p_profiles exceeds % rows', c_max_rows
      using errcode = 'invalid_parameter_value';
  end if;
  if jsonb_array_length(p_day_entries) > c_max_rows then
    raise exception 'p_day_entries exceeds % rows', c_max_rows
      using errcode = 'invalid_parameter_value';
  end if;
  if jsonb_array_length(p_observations) > c_max_rows then
    raise exception 'p_observations exceeds % rows', c_max_rows
      using errcode = 'invalid_parameter_value';
  end if;

  -- -------------------------------------------------------------------------
  -- profiles
  -- -------------------------------------------------------------------------
  for v_row in select value from jsonb_array_elements(p_profiles) loop
    begin
      if jsonb_typeof(v_row) <> 'object' then
        raise exception 'row is not an object';
      end if;
      if exists (select 1 from jsonb_object_keys(v_row) k where k <> all (c_profile_keys)) then
        raise exception 'row carries an unknown key';
      end if;

      v_id := v_row ->> 'id';
      if v_id is null or v_id !~ c_ulid then
        raise exception 'id is not a ULID';
      end if;
      v_updated_at := (v_row ->> 'updated_at')::timestamptz;
      if v_updated_at is null then
        raise exception 'updated_at is required';
      end if;
      v_deleted_at := (v_row ->> 'deleted_at')::timestamptz;
      v_created_at := coalesce((v_row ->> 'created_at')::timestamptz, v_updated_at);
      v_archived_at := (v_row ->> 'archived_at')::timestamptz;
      v_is_minor := coalesce((v_row ->> 'is_minor')::boolean, false);
      v_sort_order := coalesce((v_row ->> 'sort_order')::integer, 0);
      v_birth_year := (v_row ->> 'birth_year')::smallint;
      v_relationship := v_row ->> 'relationship';
      v_mode := coalesce(v_row ->> 'mode', 'standard');
      if v_deleted_at is not null then
        -- tombstones carry no payload
        v_display_name := '';
      else
        v_display_name := coalesce(v_row ->> 'display_name', '');
      end if;

      -- Check if profile already exists
      select * into v_stored_profile
        from public.profiles
       where id = v_id
       for update;

      if not found then
        -- New profile insertion: creator becomes primary_guardian via trigger
        insert into public.profiles
          (id, display_name, is_minor, sort_order, archived_at, created_at, updated_at, deleted_at,
           birth_year, relationship, mode)
        values
          (v_id, v_display_name, v_is_minor, v_sort_order, v_archived_at, v_created_at, v_updated_at, v_deleted_at,
           v_birth_year, v_relationship, v_mode);
      else
        -- Profile exists: check guardian role of caller
        select role into v_caller_role
          from public.profile_guardians
         where profile_id = v_id
           and user_id = v_uid
           and status = 'accepted';

        if v_caller_role is null then
          raise exception 'caller is not an accepted guardian of profile'
            using errcode = 'insufficient_privilege';
        end if;

        if v_caller_role not in ('primary_guardian', 'co_parent') then
          raise exception 'role % cannot edit profile metadata', v_caller_role
            using errcode = 'insufficient_privilege';
        end if;

        if (v_deleted_at is not null or v_archived_at is not null) and v_caller_role <> 'primary_guardian' then
          raise exception 'only primary_guardian can delete or archive profile'
            using errcode = 'insufficient_privilege';
        end if;

        v_accept := v_updated_at > v_stored_profile.updated_at
          or (v_updated_at = v_stored_profile.updated_at
              and v_deleted_at is not null
              and v_stored_profile.deleted_at is null);
        if v_accept then
          update public.profiles
             set display_name = v_display_name,
                 is_minor = v_is_minor,
                 sort_order = v_sort_order,
                 archived_at = v_archived_at,
                 created_at = v_created_at,
                 updated_at = v_updated_at,
                 deleted_at = v_deleted_at,
                 birth_year = case when v_row ? 'birth_year' then v_birth_year else v_stored_profile.birth_year end,
                 relationship = case when v_row ? 'relationship' then v_relationship else v_stored_profile.relationship end,
                 mode = case when v_row ? 'mode' then v_mode else v_stored_profile.mode end
           where id = v_id;
        elsif v_updated_at = v_stored_profile.updated_at
              and v_deleted_at is not null
              and v_stored_profile.deleted_at is not null then
          -- identical tombstone already stored: no-op, nothing to converge
          null;
        else
          -- declined (older, or equal-and-live): hand back the server copy
          v_resolved := v_resolved
            || (to_jsonb(v_stored_profile) || jsonb_build_object('table', 'profiles'));
        end if;
      end if;
    exception
      when sqlstate '40P01' or sqlstate '40001' or sqlstate '55P03' then
        raise;
      when others then
        v_rejected := v_rejected || jsonb_build_object('id', v_row -> 'id', 'rejected', true);
    end;
  end loop;

  -- -------------------------------------------------------------------------
  -- day entries
  -- -------------------------------------------------------------------------
  for v_row in select value from jsonb_array_elements(p_day_entries) loop
    -- per-row state the branches below test for
    v_stored := null;
    v_other := null;
    v_incoming_wins := null;
    begin
      if jsonb_typeof(v_row) <> 'object' then
        raise exception 'row is not an object';
      end if;
      if exists (select 1 from jsonb_object_keys(v_row) k where k <> all (c_day_entry_keys)) then
        raise exception 'row carries an unknown key';
      end if;

      v_id := v_row ->> 'id';
      if v_id is null or v_id !~ c_ulid then
        raise exception 'id is not a ULID';
      end if;
      v_profile_id := v_row ->> 'profile_id';
      if v_profile_id is null or v_profile_id !~ c_ulid then
        raise exception 'profile_id is not a ULID';
      end if;
      if (v_row ->> 'local_date') is null
         or (v_row ->> 'local_date') !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'local_date is not an ISO calendar date';
      end if;
      v_local_date := (v_row ->> 'local_date')::date;
      v_tz := coalesce(v_row ->> 'tz', 'UTC');
      v_flow := coalesce(v_row ->> 'flow', 'none');
      if v_flow not in ('none', 'spotting', 'light', 'medium', 'heavy') then
        raise exception 'flow is not a known level';
      end if;
      v_updated_at := (v_row ->> 'updated_at')::timestamptz;
      if v_updated_at is null then
        raise exception 'updated_at is required';
      end if;
      v_deleted_at := (v_row ->> 'deleted_at')::timestamptz;
      if v_deleted_at is not null then
        -- tombstones carry no payload (issue #224)
        v_tags := '[]'::jsonb;
        v_note := null;
        v_flow := 'none';
      else
        v_tags := coalesce(v_row -> 'tags', '[]'::jsonb);
        if jsonb_typeof(v_tags) <> 'array' then
          raise exception 'tags is not an array';
        end if;
        v_note := v_row ->> 'note';
      end if;

      select role into v_caller_role
        from public.profile_guardians
       where profile_id = v_profile_id
         and user_id = v_uid
         and status = 'accepted';

      if v_caller_role is null or v_caller_role = 'viewer' then
        raise exception 'caller is not authorized to write day entries for profile'
          using errcode = 'insufficient_privilege';
      end if;

      select * into v_stored
        from public.day_entries
       where id = v_id
       for update;

      if found then
        if v_stored.profile_id is distinct from v_profile_id then
          raise exception 'day entry cannot move between profiles'
            using errcode = 'insufficient_privilege';
        end if;

        v_accept := v_updated_at > v_stored.updated_at
          or (v_updated_at = v_stored.updated_at
              and v_deleted_at is not null
              and v_stored.deleted_at is null);
        if not v_accept then
          if not (v_updated_at = v_stored.updated_at
                  and v_deleted_at is not null
                  and v_stored.deleted_at is not null) then
            v_resolved := v_resolved
              || (to_jsonb(v_stored) || jsonb_build_object('table', 'day_entries'));
          end if;
          continue;
        end if;
      end if;

      if v_deleted_at is null then
        select * into v_other
          from public.day_entries
         where profile_id = v_profile_id
           and local_date = v_local_date
           and deleted_at is null
           and id <> v_id
         for update;

        if found then
          v_incoming_wins := v_updated_at > v_other.updated_at
            or (v_updated_at = v_other.updated_at
                and (v_id collate "C") < (v_other.id collate "C"));
          if v_incoming_wins then
            v_tags := public.merge_tag_arrays(v_tags, v_other.tags);
            update public.day_entries
               set deleted_at = v_updated_at,
                   updated_at = v_updated_at,
                   flow = 'none',
                   note = null,
                   tags = '[]'::jsonb,
                   last_modified_by_user_id = v_uid
             where id = v_other.id
             returning * into v_other;
            v_resolved := v_resolved
              || (to_jsonb(v_other) || jsonb_build_object('table', 'day_entries'));
          else
            update public.day_entries
               set tags = public.merge_tag_arrays(v_other.tags, v_tags),
                   last_modified_by_user_id = v_uid
             where id = v_other.id
             returning * into v_other;
            v_deleted_at := v_other.updated_at;
            v_updated_at := v_other.updated_at;
            v_tags := '[]'::jsonb;
            v_note := null;
            v_flow := 'none';
          end if;
        end if;
      end if;

      if v_stored.id is null then
        insert into public.day_entries
          (id, profile_id, local_date, tz, flow, tags, note, updated_at, deleted_at, logged_by_user_id, last_modified_by_user_id)
        values
          (v_id, v_profile_id, v_local_date, v_tz, v_flow, v_tags, v_note, v_updated_at, v_deleted_at, v_uid, v_uid)
        returning * into v_stored;
      else
        update public.day_entries
           set profile_id = v_profile_id,
               local_date = v_local_date,
               tz = v_tz,
               flow = v_flow,
               tags = v_tags,
               note = v_note,
               updated_at = v_updated_at,
               deleted_at = v_deleted_at,
               last_modified_by_user_id = v_uid
         where id = v_id
         returning * into v_stored;
      end if;

      if v_incoming_wins is false then
        v_resolved := v_resolved
          || (to_jsonb(v_stored) || jsonb_build_object('table', 'day_entries'));
      end if;
    exception
      when sqlstate '40P01' or sqlstate '40001' or sqlstate '55P03' then
        raise;
      when others then
        v_rejected := v_rejected || jsonb_build_object('id', v_row -> 'id', 'rejected', true);
    end;
  end loop;

  -- -------------------------------------------------------------------------
  -- observations (Issue #240)
  -- -------------------------------------------------------------------------
  for v_row in select value from jsonb_array_elements(p_observations) loop
    v_stored_obs := null;
    v_other_obs := null;
    v_obs_incoming_wins := null;
    begin
      if jsonb_typeof(v_row) <> 'object' then
        raise exception 'row is not an object';
      end if;
      if exists (select 1 from jsonb_object_keys(v_row) k where k <> all (c_observation_keys)) then
        raise exception 'row carries an unknown key';
      end if;

      v_id := v_row ->> 'id';
      if v_id is null or v_id !~ c_ulid then
        raise exception 'id is not a ULID';
      end if;
      v_day_entry_id := v_row ->> 'day_entry_id';
      if v_day_entry_id is null or v_day_entry_id !~ c_ulid then
        raise exception 'day_entry_id is not a ULID';
      end if;
      v_profile_id := v_row ->> 'profile_id';
      if v_profile_id is null or v_profile_id !~ c_ulid then
        raise exception 'profile_id is not a ULID';
      end if;
      if (v_row ->> 'local_date') is null
         or (v_row ->> 'local_date') !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'local_date is not an ISO calendar date';
      end if;
      v_local_date := (v_row ->> 'local_date')::date;
      v_tz := coalesce(v_row ->> 'tz', 'UTC');
      v_category := v_row ->> 'category';
      if v_category is null or char_length(v_category) < 1 then
        raise exception 'category is required';
      end if;
      v_updated_at := (v_row ->> 'updated_at')::timestamptz;
      if v_updated_at is null then
        raise exception 'updated_at is required';
      end if;
      v_deleted_at := (v_row ->> 'deleted_at')::timestamptz;

      -- The day entry this observation is attached to must exist and must
      -- belong to the same profile the caller is pushing under - a
      -- mismatched pair would smuggle an observation onto another
      -- profile's day entry past the role check below (mirrors the
      -- day_entries "cannot move between profiles" guard's intent, applied
      -- up front here since day_entry_id/profile_id are a pair on this
      -- table rather than a single reassignable column).
      select profile_id into v_day_entry_profile_id
        from public.day_entries
       where id = v_day_entry_id;
      if v_day_entry_profile_id is null then
        raise exception 'day_entry_id does not exist';
      end if;
      if v_day_entry_profile_id is distinct from v_profile_id then
        raise exception 'day_entry_id does not belong to profile_id'
          using errcode = 'insufficient_privilege';
      end if;

      if v_deleted_at is not null then
        -- tombstones carry no payload (issue #224 precedent) except
        -- category/local_date/tz/day_entry_id/profile_id -- see this
        -- migration's header "Judgement calls".
        v_code := null;
        v_value_num := null;
        v_value_text := null;
        v_unit := null;
        v_intensity := null;
        v_excluded := false;
        v_source := coalesce(v_row ->> 'source', 'manual');
        v_source_id := null;
        v_raw := null;
        v_observed_at := null;
      else
        v_code := v_row ->> 'code';
        v_value_num := (v_row ->> 'value_num')::numeric;
        v_value_text := v_row ->> 'value_text';
        v_unit := v_row ->> 'unit';
        v_intensity := (v_row ->> 'intensity')::smallint;
        v_excluded := coalesce((v_row ->> 'excluded')::boolean, false);
        v_source := coalesce(v_row ->> 'source', 'manual');
        v_source_id := v_row ->> 'source_id';
        v_raw := v_row -> 'raw';
        v_observed_at := (v_row ->> 'observed_at')::timestamptz;
      end if;

      -- Verify caller has write permissions for the profile (primary_guardian,
      -- co_parent, or caregiver) - identical role ladder to day_entries.
      select role into v_caller_role
        from public.profile_guardians
       where profile_id = v_profile_id
         and user_id = v_uid
         and status = 'accepted';

      if v_caller_role is null or v_caller_role = 'viewer' then
        raise exception 'caller is not authorized to write observations for profile'
          using errcode = 'insufficient_privilege';
      end if;

      select * into v_stored_obs
        from public.observations
       where id = v_id
       for update;

      if found then
        -- Immutable once created (mirrors day_entries' profile-move guard).
        if v_stored_obs.day_entry_id is distinct from v_day_entry_id
           or v_stored_obs.profile_id is distinct from v_profile_id then
          raise exception 'observation cannot move between day entries or profiles'
            using errcode = 'insufficient_privilege';
        end if;

        v_accept := v_updated_at > v_stored_obs.updated_at
          or (v_updated_at = v_stored_obs.updated_at
              and v_deleted_at is not null
              and v_stored_obs.deleted_at is null);
        if not v_accept then
          if not (v_updated_at = v_stored_obs.updated_at
                  and v_deleted_at is not null
                  and v_stored_obs.deleted_at is not null) then
            v_resolved := v_resolved
              || (to_jsonb(v_stored_obs) || jsonb_build_object('table', 'observations'));
          end if;
          continue;
        end if;
      else
        -- Brand-new row (never stored under this id before): the same-date
        -- collision dedup below and the per-day cap below both apply only
        -- to this branch (see this migration's header "Judgement calls").
        if v_deleted_at is null and v_code is not null then
          select * into v_other_obs
            from public.observations
           where profile_id = v_profile_id
             and local_date = v_local_date
             and category = v_category
             and code = v_code
             and deleted_at is null
             and id <> v_id
           for update;

          if found then
            v_obs_incoming_wins := v_updated_at > v_other_obs.updated_at
              or (v_updated_at = v_other_obs.updated_at
                  and (v_id collate "C") < (v_other_obs.id collate "C"));
            if v_obs_incoming_wins then
              -- The incoming row survives in the other's place; the
              -- previously-live sibling becomes a payload-free tombstone.
              update public.observations
                 set deleted_at = v_updated_at,
                     updated_at = v_updated_at,
                     code = null,
                     value_num = null,
                     value_text = null,
                     unit = null,
                     intensity = null,
                     excluded = false,
                     source_id = null,
                     raw = null,
                     observed_at = null,
                     last_modified_by_user_id = v_uid
               where id = v_other_obs.id
               returning * into v_other_obs;
              v_resolved := v_resolved
                || (to_jsonb(v_other_obs) || jsonb_build_object('table', 'observations'));
            else
              -- The incoming row loses: it is stored as a payload-free
              -- tombstone at the winner's (already-live) timestamp,
              -- exactly like day_entries' "incoming loses" branch.
              v_deleted_at := v_other_obs.updated_at;
              v_updated_at := v_other_obs.updated_at;
              v_code := null;
              v_value_num := null;
              v_value_text := null;
              v_unit := null;
              v_intensity := null;
              v_excluded := false;
              v_source_id := null;
              v_raw := null;
              v_observed_at := null;
            end if;
          end if;
        end if;

        -- Per-day cap (issue #240 acceptance criteria: enforced in the RPC,
        -- not a CHECK, since a CHECK cannot count sibling rows). Only
        -- counted when this row will actually land as a new *live* row --
        -- a tombstone, or a row that just lost the collision dedup above
        -- and became a tombstone itself, adds nothing to the day's live
        -- count. Counting inside the same transaction as every other row
        -- already inserted earlier in this same loop iteration/batch (all
        -- visible to this SELECT, since nothing has committed yet) bounds
        -- a single oversized batch too, not just the already-stored total.
        if v_deleted_at is null and v_obs_incoming_wins is not false then
          select count(*) into v_obs_count
            from public.observations
           where profile_id = v_profile_id
             and local_date = v_local_date
             and deleted_at is null;
          if v_obs_count >= c_max_observations_per_day then
            raise exception 'profile % already has % observations for %, at the % cap',
              v_profile_id, v_obs_count, v_local_date, c_max_observations_per_day
              using errcode = 'invalid_parameter_value';
          end if;
        end if;
      end if;

      if v_stored_obs.id is null then
        insert into public.observations
          (id, day_entry_id, profile_id, local_date, observed_at, tz, category, code,
           value_num, value_text, unit, intensity, excluded, source, source_id, raw,
           updated_at, deleted_at, logged_by_user_id, last_modified_by_user_id)
        values
          (v_id, v_day_entry_id, v_profile_id, v_local_date, v_observed_at, v_tz, v_category, v_code,
           v_value_num, v_value_text, v_unit, v_intensity, v_excluded, v_source, v_source_id, v_raw,
           v_updated_at, v_deleted_at, v_uid, v_uid)
        returning * into v_stored_obs;
      else
        update public.observations
           set local_date = v_local_date,
               observed_at = v_observed_at,
               tz = v_tz,
               category = v_category,
               code = v_code,
               value_num = v_value_num,
               value_text = v_value_text,
               unit = v_unit,
               intensity = v_intensity,
               excluded = v_excluded,
               source = v_source,
               source_id = v_source_id,
               raw = v_raw,
               updated_at = v_updated_at,
               deleted_at = v_deleted_at,
               last_modified_by_user_id = v_uid
         where id = v_id
         returning * into v_stored_obs;
      end if;

      if v_obs_incoming_wins is false then
        v_resolved := v_resolved
          || (to_jsonb(v_stored_obs) || jsonb_build_object('table', 'observations'));
      end if;
    exception
      when sqlstate '40P01' or sqlstate '40001' or sqlstate '55P03' then
        raise;
      when others then
        v_rejected := v_rejected || jsonb_build_object('id', v_row -> 'id', 'rejected', true);
    end;
  end loop;

  return jsonb_build_object(
    'resolved', v_resolved,
    'rejected', v_rejected,
    'server_now', now());
end;
$$;

comment on function public.sync_push(jsonb, jsonb, jsonb) is
  'Batch upsert of profiles, day entries, then observations (Issue #240) under guardian role permissions with authoritative attribution stamping. U1: profiles carries birth_year/relationship through this path; transferred_at is tolerated-but-never-read. #131: profiles carries mode through this path. Same-date day_entries collisions union tags onto the surviving row (R7, issue #3 gap-closure plan U4) while flow/note stay last-writer-wins - except that a tombstoned row always has flow forced to none, same as note/tags (issue #224). Observations: a brand-new row colliding with an already-live sibling on (profile_id, local_date, category, code) resolves head-to-head (newer updated_at wins, ulid tiebreak) with the loser becoming a payload-free tombstone - the child-table analogue of the day_entries tag union, since there is no array to union here (see the migration file''s header). A per-day (profile_id, local_date) cap of 200 live observations is enforced in this RPC, not a CHECK. p_observations defaults to an empty array so a pre-#240 2-argument call keeps working unchanged.';

revoke execute on function public.sync_push(jsonb, jsonb, jsonb) from public, anon;
grant execute on function public.sync_push(jsonb, jsonb, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. One-off backfill (issue #240 migration/backfill plan, step 3): every
--    existing day_entries.tags element becomes an observations row, with
--    `category` derived from the tag code's existing client-side
--    TagCategory (lib/domain/tags.dart's kTagTaxonomy, mirrored below as a
--    literal VALUES list since SQL cannot import a Dart const) and `code`
--    the tag code itself, unchanged (no renaming, per the plan). A tag code
--    outside that 17-item taxonomy (already possible after issue #237 -
--    unknown codes are stored, never rejected) falls back to category
--    'other' rather than being skipped, so no tag is silently dropped from
--    the mirror.
--
--    Idempotent by construction: `id` is derived deterministically from
--    (day_entry id, tag text) via an md5 digest - upper-cased hex is
--    entirely within the Crockford32 alphabet this schema's ULID CHECK
--    requires (digits plus A-F, and A-F is a subset of the allowed A-H),
--    so no separate encoding step is needed - and `on conflict (id) do
--    nothing` means re-running this migration (a local `db reset`
--    replaying every migration from scratch) never duplicates a row.
--    pgTAP asserts this directly (see supabase/tests/observations_test.sql).
--
--    Only live (deleted_at is null) day_entries are backfilled: a
--    tombstoned row's tags are already cleared to '[]' (issue #224
--    precedent), so this is naturally a no-op for tombstones without a
--    separate filter.
-- ---------------------------------------------------------------------------

insert into public.observations (
  id, day_entry_id, profile_id, local_date, tz, category, code, source,
  excluded, logged_by_user_id, last_modified_by_user_id, created_at, updated_at
)
select
  substr(upper(md5(de.id || ':' || tag.value)), 1, 26),
  de.id,
  de.profile_id,
  de.local_date,
  de.tz,
  coalesce(cat.category, 'other'),
  tag.value,
  'manual',
  false,
  de.logged_by_user_id,
  de.last_modified_by_user_id,
  de.updated_at,
  de.updated_at
from public.day_entries de
cross join lateral jsonb_array_elements_text(de.tags) as tag(value)
left join (values
  ('cramps', 'pain'), ('headache', 'pain'), ('back_pain', 'pain'), ('breast_tenderness', 'pain'),
  ('bloating', 'body'), ('acne', 'body'), ('nausea', 'body'), ('fatigue', 'body'), ('dizziness', 'body'),
  ('irritable', 'mood'), ('sad', 'mood'), ('anxious', 'mood'), ('calm', 'mood'), ('energetic', 'mood'), ('sensitive', 'mood'),
  ('sleep_trouble', 'other'), ('cravings', 'other')
) as cat(code, category) on cat.code = tag.value
where de.deleted_at is null
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- 7. delete_account_data(): create-or-replaced from its latest body
--    (20260908130000_account_deletion_feedback_tickets.sql) plus one new
--    step. Cascades alone (observations.day_entry_id -> day_entries(id) on
--    delete cascade, and observations.profile_id -> profiles(id) on delete
--    cascade) would already remove every observation this function's
--    existing day_entries/profiles deletes touch - but GET DIAGNOSTICS
--    ROW_COUNT only reports the top-level statement's own row count, never
--    cascaded rows, so an explicit delete (scoped identically to the
--    existing day_entries delete: profiles the caller *owns*, never
--    `observations.logged_by_user_id`, for the same R7 reason day_entries
--    itself is scoped by owned-profile rather than by attribution) is added
--    here purely so the returned jsonb can report a real count, run before
--    the day_entries delete so it has rows left to count.
-- ---------------------------------------------------------------------------

create or replace function public.delete_account_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_day_entries_rehomed bigint := 0;
  v_day_entries_deleted bigint := 0;
  v_observations_deleted bigint := 0;
  v_invitations_deleted bigint := 0;
  v_guardians_deleted bigint := 0;
  v_profiles_deleted bigint := 0;
  v_settings_deleted bigint := 0;
  v_notification_preferences_deleted bigint := 0;
  v_push_devices_deleted bigint := 0;
  v_notification_outbox_deleted bigint := 0;
  v_reminder_windows_deleted bigint := 0;
  v_missed_entry_alert_state_deleted bigint := 0;
  v_feedback_tickets_deleted bigint := 0;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  v_day_entries_rehomed := public.rehome_stray_day_entries(v_uid);

  -- Issue #240: observations on profiles the caller owns, deleted explicitly
  -- (before the day_entries delete below, which would cascade-remove the
  -- same rows anyway) purely so this function's own returned count reflects
  -- them - see this migration's header note above.
  delete from public.observations
   where profile_id in (
     select id from public.profiles where user_id = v_uid
   );
  get diagnostics v_observations_deleted = row_count;

  delete from public.day_entries
   where profile_id in (
     select id from public.profiles where user_id = v_uid
   );
  get diagnostics v_day_entries_deleted = row_count;

  delete from public.profile_reminder_windows
   where profile_id in (
     select id from public.profiles where user_id = v_uid
   );
  get diagnostics v_reminder_windows_deleted = row_count;

  delete from public.notification_outbox
   where recipient_user_id = v_uid;
  get diagnostics v_notification_outbox_deleted = row_count;

  delete from public.guardian_invitations
   where invited_by = v_uid;
  get diagnostics v_invitations_deleted = row_count;

  delete from public.profile_guardians
   where user_id = v_uid;
  get diagnostics v_guardians_deleted = row_count;

  delete from public.notification_preferences
   where user_id = v_uid;
  get diagnostics v_notification_preferences_deleted = row_count;

  delete from public.push_devices
   where user_id = v_uid;
  get diagnostics v_push_devices_deleted = row_count;

  delete from public.missed_entry_alert_state
   where user_id = v_uid;
  get diagnostics v_missed_entry_alert_state_deleted = row_count;

  delete from public.feedback_tickets
   where user_id = v_uid;
  get diagnostics v_feedback_tickets_deleted = row_count;

  delete from public.profiles
   where user_id = v_uid;
  get diagnostics v_profiles_deleted = row_count;

  delete from public.settings
   where user_id = v_uid;
  get diagnostics v_settings_deleted = row_count;

  return jsonb_build_object(
    'day_entries', v_day_entries_deleted,
    'day_entries_rehomed', v_day_entries_rehomed,
    'observations', v_observations_deleted,
    'guardian_invitations', v_invitations_deleted,
    'profile_guardians', v_guardians_deleted,
    'profiles', v_profiles_deleted,
    'settings', v_settings_deleted,
    'notification_preferences', v_notification_preferences_deleted,
    'push_devices', v_push_devices_deleted,
    'notification_outbox', v_notification_outbox_deleted,
    'profile_reminder_windows', v_reminder_windows_deleted,
    'missed_entry_alert_state', v_missed_entry_alert_state_deleted,
    'feedback_tickets', v_feedback_tickets_deleted
  );
end;
$$;

comment on function public.delete_account_data() is
  'Deletes every row the calling user (auth.uid()) owns across profiles, '
  'day_entries, observations (Issue #240 - explicit for an accurate '
  'returned count; the FK cascades would remove them regardless), '
  'settings, profile_guardians, guardian_invitations, '
  'notification_preferences, push_devices, notification_outbox, '
  'profile_reminder_windows, missed_entry_alert_state, and feedback_tickets '
  '(feedback_replies cascades from feedback_tickets, so no separate delete '
  'is needed for those), first calling '
  'public.rehome_stray_day_entries(auth.uid()) to re-home any day_entries '
  'this caller logged as a caregiver on a profile they do not own, so the '
  'auth.users on delete cascade the Edge Function triggers afterwards '
  'cannot reach them (#17 P0 fix). That call runs as this function''s own '
  'security-definer owner, so it succeeds regardless of '
  'rehome_stray_day_entries()''s own (revoked, #17 P1 round 2 fix) grants. '
  'Takes no parameters itself - the caller is always the subject, so no '
  'other account can be named in the call. Called by the delete-account '
  'Edge Function only after it has already removed the caller''s '
  'feedback-attachments Storage objects (Issue #243, D-24); that same '
  'function then revokes Apple and deletes the auth.users row (#17 '
  'KTD1/KTD4). It also calls rehome_stray_day_entries() a second time, '
  'standalone, on its service-role client with an explicit p_user_id, '
  'immediately before the auth.users deletion (#17 P1 item 5; round 2 fix).';

revoke all on function public.delete_account_data() from public, anon;
grant execute on function public.delete_account_data() to authenticated;
