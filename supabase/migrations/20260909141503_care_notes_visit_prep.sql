-- Migration: 20260909141503_care_notes_visit_prep.sql
--
-- Issue #128 (P2): shared care notes and visit-prep list per profile.
--
-- Everything two guardians can record today is attached to a single
-- calendar date (day_entries). This migration adds the two per-profile,
-- non-date-bound surfaces the issue scopes, following the
-- 20260908160000_observations.sql precedent exactly (new tables, not spare
-- columns on an existing table):
--
--   1. `public.care_notes`: one standing free-text note per row
--      (id, profile_id, body, attribution, updated_at/deleted_at).
--   2. `public.visit_prep_items`: one checklist item per row
--      (id, profile_id, body, is_checked + who-checked/when-checked,
--      attribution, updated_at/deleted_at).
--
--   3. `sync_push`: two new parameters, `p_care_notes jsonb default '[]'`
--      and `p_visit_prep_items jsonb default '[]'`, so a pre-#128 client
--      keeps working unchanged (the #240/#188 defaulted-parameter pattern).
--   4. `delete_account_data()`: explicit, count-only deletes for the two
--      new tables on owned profiles (the R7 scoping observations uses).
--   5. `reconcile_realtime_publication()`: both new tables join the
--      must-never-be-published list.
--   6. `export_account_data()` is deliberately untouched, on the #188
--      precedent (client-synced tables are the local JSON export's
--      responsibility — Issue #128's clinician-facing export is the
--      client's own `buildAccountExport`, extended to v6 with
--      `profiles[].careNotes`/`visitPrepItems`).
--
-- Concurrent-edit resolution rule (stated up front, per the issue's design
-- constraints): the checklist converges as a set of independent per-id
-- rows — add and remove are commutative on distinct ULIDs, so two
-- guardians adding items concurrently offline both keep their items after
-- sync (AC7); a check-off races only against another write to the *same*
-- item id, resolved per-id last-writer-wins by `updated_at` (remote wins
-- ties). A care note resolves per-note last-writer-wins by `updated_at`
-- (remote wins ties) — the day-entries KTD5 rule minus the same-date
-- resolver, which has no meaning for non-date-bound rows. No cross-row
-- merge anywhere: this is not chat, not threading, and neither surface
-- enqueues a notification (no trigger into `notification_outbox`, no
-- column the outbox could carry — AC5).
--
-- Write ladder: the day_entries/observations ladder, NOT the stricter
-- #188 profile-metadata ladder — a care note / prep item is logging, like
-- a day entry ("the same role gating as day entries" in the issue). Any
-- accepted guardian reads; primary_guardian/co_parent/caregiver write; a
-- viewer write is rejected in-RPC (`42501`, like day_entries) and denied
-- by RLS on a direct write (AC2). No DELETE policy or grant anywhere —
-- removals are tombstones, like every other synced table.
--
-- Health-content posture (the issue's design constraints): the new columns
-- ride the device-credential gate (they live in the same Drift store),
-- are scrubbed from crash reports (the `body`/table/payload keys join
-- `sentryDenyListedKeys`), never enter a notification payload
-- (structurally: `notification_outbox` gains no column and no trigger
-- fires from these tables into it), and are length-bounded server-side by
-- CHECK (`care_notes_body_length_check` 2000, mirroring day_entries.note;
-- `visit_prep_items_body_length_check` 500), rejected — never truncated
-- (AC4).
--
-- Tombstone shape: `body` is `not null default ''` (never null, so the
-- #240 raw-null-literal class cannot recur) and the tombstone CHECKs
-- require the cleared state (`care_notes_tombstone_payload_check`:
-- deleted or body <> '' is false — i.e. a tombstone carries `''`;
-- `visit_prep_items_tombstone_payload_check`: additionally
-- `is_checked = false`, `checked_by`/`checked_at` null). An empty live
-- note (`''` with `deleted_at` null) is allowed past the CHECK — the
-- client refuses to save one (the day-note precedent bounds only the
-- maximum too), but the server does not invent a minimum.
--
-- `checked_by_user_id`/`checked_at` are server-stamped, never
-- client-sent: the `sync_push` key allowlists exclude them, the column
-- grants withhold them from direct UPDATE (they are granted for UPDATE
-- but guarded — see below), and `sync_push` derives them from the caller
-- (`is_checked` true → `checked_by = caller`, `checked_at = write time`;
-- false → both null). `enforce_prep_item_attribution()` pins the same
-- rule for a direct PostgREST write, so a guardian cannot forge another
-- guardian's check via PATCH: a check must name the acting user, an
-- uncheck must clear both, and a text edit must leave an already-checked
-- row's stamp untouched.
--
-- Migration ordering (AGENTS.md Migration Flow item 7): created with
-- `npx supabase@2.116.0 migration new care_notes_visit_prep`, timestamped
-- after 20260909000000_profile_modes_and_cycle_overrides.sql (the tip of
-- `main` at dispatch), which it re-emits `sync_push`,
-- `delete_account_data()`, and `reconcile_realtime_publication()` from.
-- No merged migration is edited in place.

-- ---------------------------------------------------------------------------
-- 1. public.care_notes
-- ---------------------------------------------------------------------------

create table public.care_notes (
  id text not null
    constraint care_notes_id_ulid_check
    check (id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'),
  profile_id text not null
    references public.profiles (id) on delete cascade,
  -- Free text (health content about a minor). Not null with an '' tombstone
  -- sentinel (see the tombstone CHECK below) — never null, so no
  -- null-vs-cleared ambiguity.
  body text not null default ''
    constraint care_notes_body_length_check
    check (char_length(body) <= 2000),
  logged_by_user_id uuid references auth.users (id) on delete set null,
  last_modified_by_user_id uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_version bigint not null default 0,
  primary key (id),
  -- Structural backstop (issue #224 precedent: the table CHECK is the
  -- enforcement mechanism that survives a future sync_push re-emission
  -- that forgets to clear a field in-RPC). A tombstone carries the '' body
  -- sentinel and nothing else.
  constraint care_notes_tombstone_payload_check
    check (
      deleted_at is null
      or (body = '')
    )
);

comment on table public.care_notes is
  'Issue #128: one standing, non-date-bound care note per row on a profile. Tombstones (deleted_at not null) carry the '''' body sentinel and nothing else (see care_notes_tombstone_payload_check). Length-bounded by care_notes_body_length_check (2000, mirroring day_entries.note) — rejected, never truncated.';

create index care_notes_profile_id_idx
  on public.care_notes (profile_id);
create index care_notes_server_version_idx
  on public.care_notes (server_version);

create trigger care_notes_set_server_version
  before insert or update on public.care_notes
  for each row execute function public.set_server_version();

-- Realtime: no new publication membership. care_notes reuses the existing
-- content-free public.sync_signals wake-signal exactly like day_entries /
-- observations -- touch_sync_signal() already branches on
-- `new.profile_id` / `old.profile_id` for anything that isn't literally
-- the profiles table, so care_notes needs no change there, only this
-- trigger wiring it in.
create trigger care_notes_after_change_signal
  after insert or update or delete on public.care_notes
  for each row execute function public.touch_sync_signal();

-- ---------------------------------------------------------------------------
-- 2. public.visit_prep_items
-- ---------------------------------------------------------------------------

create table public.visit_prep_items (
  id text not null
    constraint visit_prep_items_id_ulid_check
    check (id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'),
  profile_id text not null
    references public.profiles (id) on delete cascade,
  -- The item/question text (health content about a minor). Same '' tombstone
  -- sentinel shape as care_notes.body above.
  body text not null default ''
    constraint visit_prep_items_body_length_check
    check (char_length(body) <= 500),
  -- Check state. Checked items stay visible until explicitly cleared (the
  -- clear is a tombstone, issued per checked row by the client).
  is_checked boolean not null default false,
  -- Who checked the item (AC3) and when. Server-stamped from the caller —
  -- never client-sent (absent from the sync_push allowlist below) and
  -- guarded on a direct write by enforce_prep_item_attribution().
  checked_by_user_id uuid references auth.users (id) on delete set null,
  checked_at timestamptz,
  logged_by_user_id uuid references auth.users (id) on delete set null,
  last_modified_by_user_id uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_version bigint not null default 0,
  primary key (id),
  -- A checked row must name who checked it and when (a bare is_checked with
  -- no stamp is a half-written check); an unchecked row carries no stamp.
  constraint visit_prep_items_checked_stamp_check
    check (
      (is_checked and checked_by_user_id is not null and checked_at is not null)
      or (not is_checked and checked_by_user_id is null and checked_at is null)
    ),
  -- Structural backstop (issue #224 precedent, same as care_notes above):
  -- a tombstone carries the '' body sentinel, is unchecked, and carries no
  -- check stamp.
  constraint visit_prep_items_tombstone_payload_check
    check (
      deleted_at is null
      or (
        body = ''
        and is_checked = false
        and checked_by_user_id is null
        and checked_at is null
      )
    )
);

comment on table public.visit_prep_items is
  'Issue #128: one visit-prep checklist item per row on a profile. Checked items stay visible until explicitly cleared (the clear tombstones each checked row). Tombstones carry the '''' body sentinel, are unchecked, and carry no check stamp (see visit_prep_items_tombstone_payload_check). Length-bounded by visit_prep_items_body_length_check (500) — rejected, never truncated. checked_by_user_id/checked_at are server-stamped from the caller, never client-sent.';

create index visit_prep_items_profile_id_idx
  on public.visit_prep_items (profile_id);
create index visit_prep_items_server_version_idx
  on public.visit_prep_items (server_version);

create trigger visit_prep_items_set_server_version
  before insert or update on public.visit_prep_items
  for each row execute function public.set_server_version();

-- Realtime: same wake-signal wiring as care_notes above (no new
-- publication membership).
create trigger visit_prep_items_after_change_signal
  after insert or update or delete on public.visit_prep_items
  for each row execute function public.touch_sync_signal();

-- ---------------------------------------------------------------------------
-- 3. Attribution guards, mirroring enforce_observation_attribution() exactly
--    (Issue #240: "attribution stamping via the same guard pattern").
--    enforce_prep_item_attribution() additionally pins the check-stamp rule
--    so a direct PostgREST write cannot forge another guardian's check
--    (see this migration's header).
-- ---------------------------------------------------------------------------

create or replace function public.enforce_care_note_attribution()
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

create trigger care_notes_attribution_insert_guard
  before insert on public.care_notes
  for each row execute function public.enforce_care_note_attribution();

create trigger care_notes_attribution_update_guard
  before update on public.care_notes
  for each row execute function public.enforce_care_note_attribution();

revoke execute on function public.enforce_care_note_attribution() from public, anon;

create or replace function public.enforce_prep_item_attribution()
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
    -- A directly-inserted check must name the acting user (sync_push
    -- stamps v_uid itself, so it always satisfies this).
    if new.is_checked then
      if new.checked_by_user_id is distinct from v_uid then
        raise exception 'checked_by_user_id must be the calling user'
          using errcode = 'insufficient_privilege';
      end if;
      if new.checked_at is null then
        raise exception 'checked_at is required when is_checked'
          using errcode = 'invalid_parameter_value';
      end if;
    else
      if new.checked_by_user_id is not null or new.checked_at is not null then
        raise exception 'an unchecked item carries no check stamp'
          using errcode = 'invalid_parameter_value';
      end if;
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
    -- A text edit on an already-checked row must leave the stamp untouched
    -- (otherwise editing a co-guardian's checked item would silently
    -- re-stamp or clear it); a (re-)check must name the acting user; an
    -- uncheck must clear both.
    if new.is_checked then
      if (new.checked_by_user_id is distinct from old.checked_by_user_id
          or new.checked_at is distinct from old.checked_at)
        and new.checked_by_user_id is distinct from v_uid then
        raise exception 'checked_by_user_id must be the calling user'
          using errcode = 'insufficient_privilege';
      end if;
      if new.checked_at is null then
        raise exception 'checked_at is required when is_checked'
          using errcode = 'invalid_parameter_value';
      end if;
    else
      if new.checked_by_user_id is not null or new.checked_at is not null then
        raise exception 'an unchecked item carries no check stamp'
          using errcode = 'invalid_parameter_value';
      end if;
    end if;
  end if;
  return new;
end;
$$;

create trigger visit_prep_items_attribution_insert_guard
  before insert on public.visit_prep_items
  for each row execute function public.enforce_prep_item_attribution();

create trigger visit_prep_items_attribution_update_guard
  before update on public.visit_prep_items
  for each row execute function public.enforce_prep_item_attribution();

revoke execute on function public.enforce_prep_item_attribution() from public, anon;

-- ---------------------------------------------------------------------------
-- 4. Row-Level Security -- mirrors observations' guardian-role predicates
--    exactly, with the day_entries/observations write ladder (any of
--    primary_guardian/co_parent/caregiver writes; viewer reads only), NOT
--    the stricter #188 profile-metadata ladder. No client DELETE anywhere
--    (tombstone-only, like every other synced table).
-- ---------------------------------------------------------------------------

alter table public.care_notes enable row level security;
alter table public.care_notes force row level security;

create policy "care_notes_select_guardians" on public.care_notes
  for select to authenticated
  using (
    public.is_profile_guardian(profile_id, (select auth.uid()))
  );

create policy "care_notes_insert_guardians" on public.care_notes
  for insert to authenticated
  with check (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent', 'caregiver'])
  );

create policy "care_notes_update_guardians" on public.care_notes
  for update to authenticated
  using (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent', 'caregiver'])
  )
  with check (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent', 'caregiver'])
  );

alter table public.visit_prep_items enable row level security;
alter table public.visit_prep_items force row level security;

create policy "visit_prep_items_select_guardians" on public.visit_prep_items
  for select to authenticated
  using (
    public.is_profile_guardian(profile_id, (select auth.uid()))
  );

create policy "visit_prep_items_insert_guardians" on public.visit_prep_items
  for insert to authenticated
  with check (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent', 'caregiver'])
  );

create policy "visit_prep_items_update_guardians" on public.visit_prep_items
  for update to authenticated
  using (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent', 'caregiver'])
  )
  with check (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent', 'caregiver'])
  );

-- ---------------------------------------------------------------------------
-- 5. Privileges (KTD15): column-list grants, no DELETE, matching
--    observations/day_entries. profile_id is granted (a client's own row
--    still needs to round-trip it in an UPDATE) but sync_push itself refuses
--    any change to it on an existing row (see below) -- exactly the same
--    "grant the column, enforce immutability in the RPC" shape day_entries
--    already uses for profile_id. checked_by_user_id/checked_at are
--    granted for UPDATE (sync_push, a security-invoker RPC running as the
--    caller, must be able to stamp them) but fenced by
--    enforce_prep_item_attribution() above, so the grant cannot be used to
--    forge another guardian's check.
-- ---------------------------------------------------------------------------

revoke all on table public.care_notes from public, anon, authenticated;

grant select, insert on table public.care_notes to authenticated;
grant update (
  profile_id, body, updated_at, deleted_at
) on table public.care_notes to authenticated;
grant update (last_modified_by_user_id) on table public.care_notes to authenticated;

revoke all on table public.visit_prep_items from public, anon, authenticated;

grant select, insert on table public.visit_prep_items to authenticated;
grant update (
  profile_id, body, is_checked, checked_by_user_id, checked_at,
  updated_at, deleted_at
) on table public.visit_prep_items to authenticated;
grant update (last_modified_by_user_id) on table public.visit_prep_items to authenticated;

-- ---------------------------------------------------------------------------
-- 6. sync_push: create-or-replaced from its latest body
--    (20260909000000_profile_modes_and_cycle_overrides.sql, the current tip
--    on main), copied verbatim, with a sixth and seventh parameter
--    (p_care_notes jsonb default '[]', p_visit_prep_items jsonb default
--    '[]') and two new per-table sections appended after the
--    cycle_overrides section. Nothing about the profiles/day_entries/
--    observations/profile_modes/cycle_overrides handling changes:
--    winner/loser selection, tombstone stamps, role checks, attribution
--    stamping, the advisory lock, the row-count caps, and the key
--    allow-lists are all untouched.
--
--    Postgres identifies a function by name + parameter TYPE LIST, so
--    adding parameters does not `CREATE OR REPLACE` the existing 5-argument
--    `sync_push(jsonb, jsonb, jsonb, jsonb, jsonb)` in place - it would sit
--    alongside it as a second, distinct overload (the exact-arity match
--    winning over a default-substituted one), silently forking the
--    function in two, exactly the trap #240's migration header documents.
--    The explicit drop below removes the 5-arg overload first so there is
--    exactly one sync_push afterwards and a 2- through 5-argument call
--    resolves to *this* body with the new parameters taking their
--    '[]'::jsonb defaults.
-- ---------------------------------------------------------------------------
drop function if exists public.sync_push(jsonb, jsonb, jsonb, jsonb, jsonb);

create or replace function public.sync_push(
  p_profiles jsonb,
  p_day_entries jsonb,
  p_observations jsonb default '[]'::jsonb,
  p_profile_modes jsonb default '[]'::jsonb,
  p_cycle_overrides jsonb default '[]'::jsonb,
  p_care_notes jsonb default '[]'::jsonb,
  p_visit_prep_items jsonb default '[]'::jsonb
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
    -- Issue #159: import-dedup provenance columns.
    'source', 'source_id', 'import_id',
    'updated_at', 'deleted_at',
    -- tolerated but never read
    'user_id', 'server_version', 'logged_by_user_id', 'last_modified_by_user_id'];
  -- Issue #240: observations' allowed keys.
  c_observation_keys constant text[] := array[
    'id', 'day_entry_id', 'profile_id', 'local_date', 'observed_at', 'tz',
    'category', 'code', 'value_num', 'value_text', 'unit', 'intensity',
    'excluded', 'source', 'source_id',
    -- Issue #159: import-dedup provenance column (day_entries gets the
    -- same three columns; observations already had source/source_id from
    -- #240 -- this adds only import_id here).
    'import_id', 'raw', 'updated_at', 'deleted_at',
    -- tolerated but never read
    'user_id', 'server_version', 'logged_by_user_id', 'last_modified_by_user_id',
    'created_at'];
  -- Issue #188: profile_modes' allowed keys.
  c_profile_mode_keys constant text[] := array[
    'profile_id', 'mode', 'mode_started_on', 'birth_control_method',
    'birth_control_started_on', 'birth_control_stopped_on',
    'health_sync_consent', 'updated_at',
    -- tolerated but never read
    'server_version'];
  -- Issue #188: cycle_overrides' allowed keys.
  c_cycle_override_keys constant text[] := array[
    'id', 'profile_id', 'cycle_start_date', 'excluded_from_average',
    'manual_start', 'note_id', 'updated_at', 'deleted_at',
    -- tolerated but never read
    'server_version'];
  -- Issue #128: care_notes' allowed keys. checked_by_user_id/checked_at
  -- are deliberately absent -- the server stamps them from the caller and
  -- never accepts them per-row (see this migration's header).
  c_care_note_keys constant text[] := array[
    'id', 'profile_id', 'body', 'updated_at', 'deleted_at',
    -- tolerated but never read
    'user_id', 'server_version', 'logged_by_user_id', 'last_modified_by_user_id',
    'created_at'];
  -- Issue #128: visit_prep_items' allowed keys (same checked_by/checked_at
  -- exclusion as care_notes above).
  c_visit_prep_item_keys constant text[] := array[
    'id', 'profile_id', 'body', 'is_checked', 'updated_at', 'deleted_at',
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
  -- Issue #159: shared by the day_entries loop and the observations loop
  -- below, exactly like v_profile_id/v_local_date/v_tz already are --
  -- the two loops run sequentially, never concurrently.
  v_import_id uuid;
  v_raw jsonb;
  v_day_entry_profile_id text;
  v_stored_obs public.observations%rowtype;
  v_other_obs public.observations%rowtype;
  v_obs_incoming_wins boolean;
  v_obs_count integer;
  -- Review finding (item 4): true whenever this push will land the row
  -- live under a (profile_id, local_date) that isn't already guaranteed
  -- to have counted it -- a brand-new row, a tombstone being revived
  -- (deleted_at: null on an already-tombstoned id), or a live row's
  -- local_date moving to a different day. The per-day cap and the
  -- same-date (category, code) dedup below both key off this, not just
  -- "brand new", so a revive or a date-move cannot bypass either.
  v_obs_check_collision boolean;
  -- Issue #188: profile_modes parsing state.
  v_mode_started_on date;
  v_birth_control_method text;
  v_birth_control_started_on date;
  v_birth_control_stopped_on date;
  v_health_sync_consent boolean;
  v_stored_mode public.profile_modes%rowtype;
  -- Issue #188: cycle_overrides parsing state.
  v_cycle_start_date date;
  v_excluded_from_average boolean;
  v_manual_start boolean;
  v_note_id text;
  v_stored_override public.cycle_overrides%rowtype;
  -- Issue #128: care_notes parsing state.
  v_body text;
  v_stored_note public.care_notes%rowtype;
  -- Issue #128: visit_prep_items parsing state.
  v_is_checked boolean;
  v_checked_by_user_id uuid;
  v_checked_at timestamptz;
  v_stored_prep_item public.visit_prep_items%rowtype;
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
  if p_profile_modes is null or jsonb_typeof(p_profile_modes) <> 'array' then
    raise exception 'p_profile_modes must be a JSON array'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_cycle_overrides is null or jsonb_typeof(p_cycle_overrides) <> 'array' then
    raise exception 'p_cycle_overrides must be a JSON array'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_care_notes is null or jsonb_typeof(p_care_notes) <> 'array' then
    raise exception 'p_care_notes must be a JSON array'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_visit_prep_items is null or jsonb_typeof(p_visit_prep_items) <> 'array' then
    raise exception 'p_visit_prep_items must be a JSON array'
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
  if jsonb_array_length(p_profile_modes) > c_max_rows then
    raise exception 'p_profile_modes exceeds % rows', c_max_rows
      using errcode = 'invalid_parameter_value';
  end if;
  if jsonb_array_length(p_cycle_overrides) > c_max_rows then
    raise exception 'p_cycle_overrides exceeds % rows', c_max_rows
      using errcode = 'invalid_parameter_value';
  end if;
  if jsonb_array_length(p_care_notes) > c_max_rows then
    raise exception 'p_care_notes exceeds % rows', c_max_rows
      using errcode = 'invalid_parameter_value';
  end if;
  if jsonb_array_length(p_visit_prep_items) > c_max_rows then
    raise exception 'p_visit_prep_items exceeds % rows', c_max_rows
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
      -- U1: birth_year/relationship are ordinary optional profile metadata,
      -- validated by the table's own CHECK constraints (an invalid value
      -- lands this row in `rejected` via the exception handler below, same
      -- as an over-length display_name). These two parsed values feed the
      -- INSERT path unconditionally (a brand-new row has nothing to
      -- preserve) and the UPDATE path guarded by a jsonb `?` containment
      -- check below (review item #3) so an old client that omits these keys
      -- entirely does not silently null out an already-stored value.
      v_birth_year := (v_row ->> 'birth_year')::smallint;
      v_relationship := v_row ->> 'relationship';
      -- #131: mode gets the same treatment except that the column is not
      -- null with a default - an absent key parses to 'standard' (which the
      -- INSERT path needs), and an out-of-set value is rejected by
      -- profiles_mode_check into `rejected` like any other CHECK failure.
      -- The UPDATE path applies the same `?` containment guard so a
      -- pre-#131 client's push never touches a stored mode.
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

        -- Only primary_guardian or co_parent can edit profiles
        if v_caller_role not in ('primary_guardian', 'co_parent') then
          raise exception 'role % cannot edit profile metadata', v_caller_role
            using errcode = 'insufficient_privilege';
        end if;

        -- Only primary_guardian can delete/archive profiles
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
                 -- Review item #3 (P1): an old client that predates U1 omits
                 -- birth_year/relationship from its payload entirely, rather
                 -- than sending them as null - v_row ->> 'key' cannot tell
                 -- "omitted" from "explicitly cleared" apart, and both parse
                 -- to the same null in v_birth_year/v_relationship above. The
                 -- jsonb `?` containment operator can tell them apart: only
                 -- overwrite the stored value when the incoming row actually
                 -- carries the key, so an old client's push preserves
                 -- whatever birth_year/relationship the profile already has
                 -- instead of silently nulling it on every metadata edit.
                 -- #131: mode gets the identical guard, so a pre-#131
                 -- client's push never clobbers a stored mode.
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
      -- Issue #159: parsed unconditionally, ahead of the tombstone
      -- if/else below (like tz) -- provenance is not health content and
      -- survives a tombstone by design (see the migration header's
      -- "tombstone payload" decision), so it is never cleared on delete.
      v_source := coalesce(v_row ->> 'source', 'manual');
      v_source_id := v_row ->> 'source_id';
      v_import_id := (v_row ->> 'import_id')::uuid;
      v_flow := coalesce(v_row ->> 'flow', 'none');
      -- Issue #247 (flow model, carried over verbatim from
      -- 20260908200000_flow_model.sql -- the sync_push definition this
      -- file re-extends): super_heavy/not_bleeding are known levels.
      if v_flow not in ('none', 'spotting', 'not_bleeding', 'light', 'medium', 'heavy', 'super_heavy') then
        raise exception 'flow is not a known level';
      end if;
      v_updated_at := (v_row ->> 'updated_at')::timestamptz;
      if v_updated_at is null then
        raise exception 'updated_at is required';
      end if;
      v_deleted_at := (v_row ->> 'deleted_at')::timestamptz;
      if v_deleted_at is not null then
        -- tombstones carry no payload (issue #224: flow joins tags/note -
        -- it was the one field this branch left the incoming value in,
        -- the most sensitive single column on the row)
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

      -- Verify caller has write permissions for profile (primary_guardian, co_parent, or caregiver)
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
        -- An entry never legitimately changes profiles: the role check
        -- above ran against v_profile_id only, so a re-pointed row would
        -- smuggle another profile's entry past that check.
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
            -- declined (older, or equal-and-live): hand back the server copy
            v_resolved := v_resolved
              || (to_jsonb(v_stored) || jsonb_build_object('table', 'day_entries'));
          end if;
          continue;
        end if;
      end if;

      -- Same-date resolver: runs on every write that would leave a live row.
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
            -- R7: union the loser's tags onto the incoming (surviving) row
            -- before tombstoning it - the loser's tags would otherwise be
            -- destroyed outright. flow/note stay last-writer-wins (KTD4)
            -- for the surviving row; the *loser* being tombstoned here
            -- clears its own flow to 'none' alongside note/tags (issue
            -- #224 - this direct UPDATE previously left the loser's old
            -- flow value in place forever).
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
            -- The incoming row loses: it is stored as a tombstone at the
            -- winner's time (unchanged). R7/R11: the union of both rows'
            -- tags is written onto the surviving v_other row in the same
            -- statement that already touches it, leaving v_other.updated_at
            -- alone so the merge does not disturb the winner's timestamp.
            -- last_modified_by_user_id must still be stamped to the caller
            -- here (enforce_day_entry_attribution requires it on every
            -- update while auth.uid() is set) even though this row's
            -- content otherwise belongs to whoever logged it.
            update public.day_entries
               set tags = public.merge_tag_arrays(v_other.tags, v_tags),
                   last_modified_by_user_id = v_uid
             where id = v_other.id
             returning * into v_other;
            v_deleted_at := v_other.updated_at;
            v_updated_at := v_other.updated_at;
            v_tags := '[]'::jsonb;
            v_note := null;
            -- issue #224: the incoming row is the one becoming a tombstone
            -- here (stored via the insert/update below) - it must carry no
            -- payload either, same as every other tombstone.
            v_flow := 'none';
          end if;
        end if;
      end if;

      if v_stored.id is null then
        insert into public.day_entries
          (id, profile_id, local_date, tz, flow, tags, note,
           source, source_id, import_id,
           updated_at, deleted_at, logged_by_user_id, last_modified_by_user_id)
        values
          (v_id, v_profile_id, v_local_date, v_tz, v_flow, v_tags, v_note,
           v_source, v_source_id, v_import_id,
           v_updated_at, v_deleted_at, v_uid, v_uid)
        returning * into v_stored;
      else
        update public.day_entries
           set profile_id = v_profile_id,
               local_date = v_local_date,
               tz = v_tz,
               flow = v_flow,
               tags = v_tags,
               note = v_note,
               -- Issue #159 (acceptance criteria): an old client that omits
               -- source/source_id/import_id entirely must not silently null
               -- an already-stored value on a later edit -- the same
               -- v_row ? 'key' containment guard U1 established for
               -- profiles.birth_year/relationship (20260906160000, PR #108
               -- review item #3) and #131 established for profiles.mode.
               source = case when v_row ? 'source' then v_source else v_stored.source end,
               source_id = case when v_row ? 'source_id' then v_source_id else v_stored.source_id end,
               import_id = case when v_row ? 'import_id' then v_import_id else v_stored.import_id end,
               updated_at = v_updated_at,
               deleted_at = v_deleted_at,
               last_modified_by_user_id = v_uid
         where id = v_id
         returning * into v_stored;
      end if;

      if v_incoming_wins is false then
        -- the incoming row was tombstoned by resolution: return its server copy
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
    v_obs_check_collision := false;
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
      -- Issue #180 review fix: derive v_local_date from observed_at/tz
      -- right here, ahead of every check below (the stored-row lookup,
      -- the same-date (category, code) collision dedup, and the per-day
      -- cap), so the value this RPC checks against and the value
      -- observations_derive_local_date's BEFORE trigger will
      -- independently recompute on the same row are identical -- the
      -- trigger becomes a pure backstop, never the sole source of truth
      -- for a value this RPC already used to make an accept/reject
      -- decision. Without this fix, a push whose observed_at derived to
      -- a different local day than the client-supplied local_date key
      -- evaded both the per-day cap and the same-date dedup below (they
      -- ran against the stale client-supplied local_date, not the day
      -- the row actually lands on once the trigger fires), and an
      -- UPDATE that changed only observed_at moved a row across days
      -- without ever tripping v_obs_check_collision, since
      -- v_stored_obs.local_date was being compared against that same
      -- stale value. Parsed unconditionally here, ahead of the tombstone
      -- if/else below, since every downstream check needs the corrected
      -- value regardless of tombstone status; the tombstone branch below
      -- still nulls v_observed_at itself (tombstones carry no payload --
      -- issue #224 precedent), it just no longer gets a second say over
      -- v_local_date, which is already derived here.
      v_observed_at := (v_row ->> 'observed_at')::timestamptz;
      if v_observed_at is not null then
        v_local_date := (v_observed_at at time zone v_tz)::date;
      end if;
      -- Issue #159: parsed unconditionally, ahead of the tombstone
      -- if/else below -- import_id is provenance, not health content, and
      -- survives a tombstone by design (see this migration's header).
      v_import_id := (v_row ->> 'import_id')::uuid;
      -- category's required-unless-tombstoned check moves below, once
      -- v_deleted_at is known (review finding: a tombstone push must not
      -- be forced to carry a category just to satisfy this validation --
      -- see observations_category_required_unless_tombstoned_check).
      v_category := v_row ->> 'category';
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
        -- local_date/tz/day_entry_id/profile_id -- category is cleared
        -- too (review finding; see this migration's header "Judgement
        -- calls" and observations_tombstone_payload_check).
        v_category := null;
        v_code := null;
        v_value_num := null;
        v_value_text := null;
        v_unit := null;
        v_intensity := null;
        v_excluded := false;
        v_source := coalesce(v_row ->> 'source', 'manual');
        -- Issue #159 (review decision, this migration's header): unlike
        -- every other value column, source_id now SURVIVES a tombstone --
        -- a deleted row must stay recognisable to a future re-import so it
        -- can be skipped rather than resurrected as a duplicate. Reverses
        -- #240's original "v_source_id := null" here.
        v_source_id := v_row ->> 'source_id';
        v_raw := null;
        v_observed_at := null;
      else
        if v_category is null or char_length(v_category) < 1 then
          raise exception 'category is required';
        end if;
        v_code := v_row ->> 'code';
        v_value_num := (v_row ->> 'value_num')::numeric;
        v_value_text := v_row ->> 'value_text';
        v_unit := v_row ->> 'unit';
        v_intensity := (v_row ->> 'intensity')::smallint;
        v_excluded := coalesce((v_row ->> 'excluded')::boolean, false);
        v_source := coalesce(v_row ->> 'source', 'manual');
        v_source_id := v_row ->> 'source_id';
        -- Review finding: `->` on a `"raw": null` key yields the *jsonb*
        -- literal `null` (`jsonb_typeof = 'null'`), not a SQL NULL -- left
        -- as-is this would store a real (non-NULL) jsonb `null` value,
        -- which is distinct from the column actually being NULL (and would
        -- fail `observations_tombstone_payload_check`'s `raw is null` arm
        -- on a tombstone push that explicitly sent `"raw": null`). `nullif`
        -- collapses the jsonb `null` literal to a genuine SQL NULL; a
        -- missing `raw` key already parses to SQL NULL via `->`'s own
        -- semantics, so this is a no-op for that case.
        v_raw := nullif(v_row -> 'raw', 'null'::jsonb);
        -- v_observed_at already parsed above, ahead of this if/else (see
        -- the Issue #180 review-fix comment by the v_tz assignment).
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

        -- Review finding (item 4): a revive (tombstone -> live) or a
        -- local_date move on an already-live row must run through the
        -- same per-day cap / same-date dedup as a brand-new row -
        -- otherwise either is a way to land a 201st observation on a day,
        -- or a second live (category, code) sibling, without ever going
        -- through the "brand new" branch below.
        -- Issue #180 review fix: v_local_date is now the *derived*
        -- value (from observed_at/tz, above), so an UPDATE that changes
        -- only observed_at -- moving the row to a different local day
        -- while leaving the client-supplied local_date key untouched --
        -- is correctly detected here too: v_stored_obs.local_date
        -- (the day the row currently lives on) is distinct from the
        -- freshly-derived v_local_date (the day it is moving to), so
        -- this still evaluates true and the move goes through the same
        -- cap/dedup gate as any other collision.
        v_obs_check_collision := v_deleted_at is null
          and (
            v_stored_obs.deleted_at is not null
            or v_stored_obs.local_date is distinct from v_local_date
          );
      else
        -- Brand-new row (never stored under this id before): always
        -- subject to the same-date collision dedup / per-day cap below.
        v_obs_check_collision := v_deleted_at is null;
      end if;

      if v_obs_check_collision then
        if v_code is not null then
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
              -- Issue #159: source_id (and import_id, never touched by
              -- this statement) survive this tombstoning -- only
              -- category/code/value/etc are cleared, matching the
              -- tombstone-parse branch's decision above.
              update public.observations
                 set deleted_at = v_updated_at,
                     updated_at = v_updated_at,
                     category = null,
                     code = null,
                     value_num = null,
                     value_text = null,
                     unit = null,
                     intensity = null,
                     excluded = false,
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
              v_category := null;
              v_code := null;
              v_value_num := null;
              v_value_text := null;
              v_unit := null;
              v_intensity := null;
              v_excluded := false;
              -- Issue #159: v_source_id (and v_import_id, never cleared
              -- here) are left as originally parsed -- the incoming row
              -- keeps its own provenance even as it becomes a tombstone.
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
        -- count. Runs for a brand-new row, a revive (v_obs_check_collision
        -- above), and a local_date move (same) -- not just inserts --
        -- since the stored copy is either not-yet-live (revive: still a
        -- tombstone in the database) or live at a *different* local_date
        -- (a move) at this point, so this SELECT never double-counts the
        -- row against itself without needing an explicit `id <>` filter.
        -- Counting inside the same transaction as every other row already
        -- inserted earlier in this same loop iteration/batch (all visible
        -- to this SELECT, since nothing has committed yet) bounds a single
        -- oversized batch too, not just the already-stored total.
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
           value_num, value_text, unit, intensity, excluded, source, source_id, import_id, raw,
           updated_at, deleted_at, logged_by_user_id, last_modified_by_user_id)
        values
          (v_id, v_day_entry_id, v_profile_id, v_local_date, v_observed_at, v_tz, v_category, v_code,
           v_value_num, v_value_text, v_unit, v_intensity, v_excluded, v_source, v_source_id, v_import_id, v_raw,
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
               -- Issue #159 review finding: the original header rationale
               -- ("source always has a value via the coalesce, so there is
               -- no null-vs-omitted ambiguity") was wrong -- the coalesce
               -- resolves an *omitted* key to 'manual' just as surely as an
               -- explicit null would, so an old client, or a tombstone push
               -- that omits `source` entirely, silently reset an
               -- already-stored non-manual source back to 'manual' on
               -- update. `source` now gets the same v_row ? 'key'
               -- containment guard as day_entries.source
               -- (:~657 in this file) and observations.source_id/import_id
               -- below.
               source = case when v_row ? 'source' then v_source else v_stored_obs.source end,
               -- source_id and import_id get the identical containment
               -- guard (an old client, or a tombstone push that omits the
               -- key, must not null an already-stored value) -- required
               -- for "provenance survives a tombstone" to actually hold
               -- when a tombstone push carries only identity fields, not
               -- the full payload. This closes the one piece of #240's
               -- original source_id handling that was a pre-existing gap
               -- (no containment guard at all).
               source_id = case when v_row ? 'source_id' then v_source_id else v_stored_obs.source_id end,
               import_id = case when v_row ? 'import_id' then v_import_id else v_stored_obs.import_id end,
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


  -- -------------------------------------------------------------------------
  -- profile_modes (Issue #188): one row per profile, no tombstone -- a
  -- newer write replaces the older under strict LWW; an equal-timestamp
  -- push is declined with the server copy handed back (a retry of an
  -- already-applied write converges instead of duplicating).
  -- -------------------------------------------------------------------------
  for v_row in select value from jsonb_array_elements(p_profile_modes) loop
    begin
      if jsonb_typeof(v_row) <> 'object' then
        raise exception 'row is not an object';
      end if;
      if exists (select 1 from jsonb_object_keys(v_row) k where k <> all (c_profile_mode_keys)) then
        raise exception 'row carries an unknown key';
      end if;

      v_profile_id := v_row ->> 'profile_id';
      if v_profile_id is null or v_profile_id !~ c_ulid then
        raise exception 'profile_id is not a ULID';
      end if;
      -- Issue #188: the life-stage mode; an absent key parses to the
      -- column default 'tracking' (which the INSERT path needs), and an
      -- out-of-set value is rejected by profile_modes_mode_check into
      -- `rejected` like any other CHECK failure. The UPDATE path applies
      -- the `?` containment guard so a pre-#188-aware client's push never
      -- clobbers a stored mode (the #131 profiles.mode pattern).
      v_mode := coalesce(v_row ->> 'mode', 'tracking');
      v_updated_at := (v_row ->> 'updated_at')::timestamptz;
      if v_updated_at is null then
        raise exception 'updated_at is required';
      end if;
      -- Optional dates/method/consent: parsed with the column defaults an
      -- INSERT needs; the UPDATE path below only overwrites a stored
      -- value when the incoming row actually carries the key, so an older
      -- client that omits birth_control_* or health_sync_consent never
      -- silently nulls/reset them (the U1/#108 containment pattern).
      if (v_row ->> 'mode_started_on') is not null
         and (v_row ->> 'mode_started_on') !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'mode_started_on is not an ISO calendar date';
      end if;
      v_mode_started_on := (v_row ->> 'mode_started_on')::date;
      v_birth_control_method := v_row ->> 'birth_control_method';
      if (v_row ->> 'birth_control_started_on') is not null
         and (v_row ->> 'birth_control_started_on') !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'birth_control_started_on is not an ISO calendar date';
      end if;
      v_birth_control_started_on := (v_row ->> 'birth_control_started_on')::date;
      if (v_row ->> 'birth_control_stopped_on') is not null
         and (v_row ->> 'birth_control_stopped_on') !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'birth_control_stopped_on is not an ISO calendar date';
      end if;
      v_birth_control_stopped_on := (v_row ->> 'birth_control_stopped_on')::date;
      v_health_sync_consent := coalesce((v_row ->> 'health_sync_consent')::boolean, false);

      -- The profile must exist (FK backstop turned into a typed, opaque
      -- rejection -- and enumeration-parity with the day_entries path:
      -- a nonexistent profile and a foreign profile both reject).
      if not exists (select 1 from public.profiles p where p.id = v_profile_id) then
        raise exception 'profile does not exist';
      end if;

      -- Issue #188's write ladder: accepted guardian required, and only
      -- primary_guardian or co_parent may edit profile metadata (mode,
      -- birth-control state) -- the same ladder as a profile edit, and
      -- deliberately stricter than day_entries/observations.
      select role into v_caller_role
        from public.profile_guardians
       where profile_id = v_profile_id
         and user_id = v_uid
         and status = 'accepted';

      if v_caller_role is null or v_caller_role not in ('primary_guardian', 'co_parent') then
        raise exception 'caller is not authorized to write profile mode for profile'
          using errcode = 'insufficient_privilege';
      end if;

      select * into v_stored_mode
        from public.profile_modes
       where profile_id = v_profile_id
       for update;

      if not found then
        insert into public.profile_modes
          (profile_id, mode, mode_started_on, birth_control_method,
           birth_control_started_on, birth_control_stopped_on,
           health_sync_consent, updated_at)
        values
          (v_profile_id, v_mode, v_mode_started_on, v_birth_control_method,
           v_birth_control_started_on, v_birth_control_stopped_on,
           v_health_sync_consent, v_updated_at);
      elsif v_updated_at > v_stored_mode.updated_at then
        update public.profile_modes
           set mode = case when v_row ? 'mode' then v_mode else v_stored_mode.mode end,
               mode_started_on = case when v_row ? 'mode_started_on' then v_mode_started_on else v_stored_mode.mode_started_on end,
               birth_control_method = case when v_row ? 'birth_control_method' then v_birth_control_method else v_stored_mode.birth_control_method end,
               birth_control_started_on = case when v_row ? 'birth_control_started_on' then v_birth_control_started_on else v_stored_mode.birth_control_started_on end,
               birth_control_stopped_on = case when v_row ? 'birth_control_stopped_on' then v_birth_control_stopped_on else v_stored_mode.birth_control_stopped_on end,
               health_sync_consent = case when v_row ? 'health_sync_consent' then v_health_sync_consent else v_stored_mode.health_sync_consent end,
               updated_at = v_updated_at
         where profile_id = v_profile_id;
      else
        -- declined (older or equal): hand back the server copy so the
        -- caller converges; an equal-timestamp retry is a no-op, which is
        -- what makes a mode switch idempotent from a client's point of
        -- view (the row is never duplicated or half-updated).
        v_resolved := v_resolved
          || (to_jsonb(v_stored_mode) || jsonb_build_object('table', 'profile_modes'));
      end if;
    exception
      when sqlstate '40P01' or sqlstate '40001' or sqlstate '55P03' then
        raise;
      when others then
        v_rejected := v_rejected || jsonb_build_object('id', v_row -> 'profile_id', 'rejected', true);
    end;
  end loop;

  -- -------------------------------------------------------------------------
  -- cycle_overrides (Issue #188): per-id LWW with tombstones, mirroring
  -- the day_entries accept/decline shape minus the same-date resolver
  -- (see the migration header's judgement calls). Keyed by the full
  -- composite (id, profile_id), so a row can never move between profiles.
  -- -------------------------------------------------------------------------
  for v_row in select value from jsonb_array_elements(p_cycle_overrides) loop
    begin
      if jsonb_typeof(v_row) <> 'object' then
        raise exception 'row is not an object';
      end if;
      if exists (select 1 from jsonb_object_keys(v_row) k where k <> all (c_cycle_override_keys)) then
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
      if (v_row ->> 'cycle_start_date') is null
         or (v_row ->> 'cycle_start_date') !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'cycle_start_date is not an ISO calendar date';
      end if;
      v_cycle_start_date := (v_row ->> 'cycle_start_date')::date;
      v_updated_at := (v_row ->> 'updated_at')::timestamptz;
      if v_updated_at is null then
        raise exception 'updated_at is required';
      end if;
      v_deleted_at := (v_row ->> 'deleted_at')::timestamptz;

      if v_deleted_at is not null then
        -- Tombstones carry no payload (issue #224 precedent): the flags
        -- reset and note_id clears UNCONDITIONALLY here -- no containment
        -- guard on this branch, because a tombstone push carrying only
        -- identity fields must still reach the cleared state
        -- cycle_overrides_tombstone_payload_check demands.
        v_excluded_from_average := false;
        v_manual_start := false;
        v_note_id := null;
      else
        v_excluded_from_average := coalesce((v_row ->> 'excluded_from_average')::boolean, false);
        v_manual_start := coalesce((v_row ->> 'manual_start')::boolean, false);
        v_note_id := v_row ->> 'note_id';
      end if;

      -- The profile must exist (FK backstop turned into a typed, opaque
      -- rejection; same enumeration-parity as profile_modes above).
      if not exists (select 1 from public.profiles p where p.id = v_profile_id) then
        raise exception 'profile does not exist';
      end if;

      -- Issue #188's write ladder: identical to profile_modes (profile
      -- metadata -- a manual cycle correction reshapes the averages).
      select role into v_caller_role
        from public.profile_guardians
       where profile_id = v_profile_id
         and user_id = v_uid
         and status = 'accepted';

      if v_caller_role is null or v_caller_role not in ('primary_guardian', 'co_parent') then
        raise exception 'caller is not authorized to write cycle overrides for profile'
          using errcode = 'insufficient_privilege';
      end if;

      select * into v_stored_override
        from public.cycle_overrides
       where id = v_id
         and profile_id = v_profile_id
       for update;

      if found then
        v_accept := v_updated_at > v_stored_override.updated_at
          or (v_updated_at = v_stored_override.updated_at
              and v_deleted_at is not null
              and v_stored_override.deleted_at is null);
        if not v_accept then
          if not (v_updated_at = v_stored_override.updated_at
                  and v_deleted_at is not null
                  and v_stored_override.deleted_at is not null) then
            -- declined (older, or equal-and-live): hand back the server copy
            v_resolved := v_resolved
              || (to_jsonb(v_stored_override) || jsonb_build_object('table', 'cycle_overrides'));
          end if;
          continue;
        end if;
      end if;

      if v_stored_override.id is null then
        insert into public.cycle_overrides
          (id, profile_id, cycle_start_date, excluded_from_average,
           manual_start, note_id, updated_at, deleted_at)
        values
          (v_id, v_profile_id, v_cycle_start_date, v_excluded_from_average,
           v_manual_start, v_note_id, v_updated_at, v_deleted_at);
      else
        update public.cycle_overrides
           set cycle_start_date = v_cycle_start_date,
               -- Containment guards on the optional payload columns for a
               -- LIVE write (the U1/#131/#159 pattern): a client that omits
               -- a key never silently resets an already-stored value. A
               -- TOMBSTONE write must bypass the guards and clear
               -- unconditionally -- a tombstone push carries only identity
               -- fields, so guarding it would preserve the stored payload
               -- onto a row the structural CHECK requires payload-free
               -- (rejected wholesale, and the tombstone never landed).
               -- The tombstone parse branch above already set the cleared
               -- values, so the `v_deleted_at is not null` arms simply
               -- write them through.
               excluded_from_average = case
                 when v_deleted_at is not null then false
                 when v_row ? 'excluded_from_average' then v_excluded_from_average
                 else v_stored_override.excluded_from_average end,
               manual_start = case
                 when v_deleted_at is not null then false
                 when v_row ? 'manual_start' then v_manual_start
                 else v_stored_override.manual_start end,
               note_id = case
                 when v_deleted_at is not null then null
                 when v_row ? 'note_id' then v_note_id
                 else v_stored_override.note_id end,
               updated_at = v_updated_at,
               deleted_at = v_deleted_at
         where id = v_id
           and profile_id = v_profile_id;
      end if;
    exception
      when sqlstate '40P01' or sqlstate '40001' or sqlstate '55P03' then
        raise;
      when others then
        v_rejected := v_rejected || jsonb_build_object('id', v_row -> 'id', 'rejected', true);
    end;
  end loop;

  -- -------------------------------------------------------------------------
  -- care_notes (Issue #128): per-id LWW with tombstones, mirroring the
  -- cycle_overrides accept/decline shape (see this migration's header for
  -- the stated resolution rule). Keyed by id alone (the table's primary
  -- key); like day_entries, a row can never move between profiles.
  -- -------------------------------------------------------------------------
  for v_row in select value from jsonb_array_elements(p_care_notes) loop
    begin
      if jsonb_typeof(v_row) <> 'object' then
        raise exception 'row is not an object';
      end if;
      if exists (select 1 from jsonb_object_keys(v_row) k where k <> all (c_care_note_keys)) then
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
      v_body := v_row ->> 'body';
      if v_body is null then
        raise exception 'body is required';
      end if;
      v_updated_at := (v_row ->> 'updated_at')::timestamptz;
      if v_updated_at is null then
        raise exception 'updated_at is required';
      end if;
      v_deleted_at := (v_row ->> 'deleted_at')::timestamptz;

      if v_deleted_at is not null then
        -- Tombstones carry no payload (issue #224 precedent): body clears
        -- UNCONDITIONALLY here, so a tombstone push carrying a stale
        -- non-empty body still lands payload-free, as
        -- care_notes_tombstone_payload_check demands. Over-length bodies
        -- are rejected by that CHECK into `rejected`, never truncated.
        v_body := '';
      end if;

      -- The profile must exist (FK backstop turned into a typed, opaque
      -- rejection -- and enumeration-parity with the day_entries path:
      -- a nonexistent profile and a foreign profile both reject).
      if not exists (select 1 from public.profiles p where p.id = v_profile_id) then
        raise exception 'profile does not exist';
      end if;

      -- Issue #128's write ladder: the day_entries ladder (any accepted
      -- guardian except a viewer may log), NOT the stricter #188
      -- profile-metadata ladder -- a care note is logging, like a day
      -- entry.
      select role into v_caller_role
        from public.profile_guardians
       where profile_id = v_profile_id
         and user_id = v_uid
         and status = 'accepted';

      if v_caller_role is null or v_caller_role = 'viewer' then
        raise exception 'caller is not authorized to write care notes for profile'
          using errcode = 'insufficient_privilege';
      end if;

      select * into v_stored_note
        from public.care_notes
       where id = v_id
       for update;

      if found then
        -- A note never legitimately changes profiles: the role check above
        -- ran against v_profile_id only, so a re-pointed row would smuggle
        -- another profile's note past that check (the day_entries
        -- cannot-move-between-profiles pattern).
        if v_stored_note.profile_id is distinct from v_profile_id then
          raise exception 'care note cannot move between profiles'
            using errcode = 'insufficient_privilege';
        end if;
        v_accept := v_updated_at > v_stored_note.updated_at
          or (v_updated_at = v_stored_note.updated_at
              and v_deleted_at is not null
              and v_stored_note.deleted_at is null);
        if not v_accept then
          if not (v_updated_at = v_stored_note.updated_at
                  and v_deleted_at is not null
                  and v_stored_note.deleted_at is not null) then
            -- declined (older, or equal-and-live): hand back the server copy
            v_resolved := v_resolved
              || (to_jsonb(v_stored_note) || jsonb_build_object('table', 'care_notes'));
          end if;
          continue;
        end if;
      end if;

      if v_stored_note.id is null then
        insert into public.care_notes
          (id, profile_id, body, updated_at, deleted_at,
           logged_by_user_id, last_modified_by_user_id)
        values
          (v_id, v_profile_id, v_body, v_updated_at, v_deleted_at, v_uid, v_uid)
        returning * into v_stored_note;
      else
        update public.care_notes
           set body = v_body,
               updated_at = v_updated_at,
               deleted_at = v_deleted_at,
               last_modified_by_user_id = v_uid
         where id = v_id
        returning * into v_stored_note;
      end if;
    exception
      when sqlstate '40P01' or sqlstate '40001' or sqlstate '55P03' then
        raise;
      when others then
        v_rejected := v_rejected || jsonb_build_object('id', v_row -> 'id', 'rejected', true);
    end;
  end loop;

  -- -------------------------------------------------------------------------
  -- visit_prep_items (Issue #128): per-id LWW with tombstones, mirroring
  -- the care_notes loop above (same resolution rule: the checklist
  -- converges as a set; a check-off races only against another write to
  -- the same item id). checked_by_user_id/checked_at are derived from the
  -- caller here -- never accepted per-row (absent from
  -- c_visit_prep_item_keys, so a row carrying them is rejected as
  -- unknown-key rather than silently accepted).
  -- -------------------------------------------------------------------------
  for v_row in select value from jsonb_array_elements(p_visit_prep_items) loop
    begin
      if jsonb_typeof(v_row) <> 'object' then
        raise exception 'row is not an object';
      end if;
      if exists (select 1 from jsonb_object_keys(v_row) k where k <> all (c_visit_prep_item_keys)) then
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
      v_body := v_row ->> 'body';
      if v_body is null then
        raise exception 'body is required';
      end if;
      v_is_checked := coalesce((v_row ->> 'is_checked')::boolean, false);
      v_updated_at := (v_row ->> 'updated_at')::timestamptz;
      if v_updated_at is null then
        raise exception 'updated_at is required';
      end if;
      v_deleted_at := (v_row ->> 'deleted_at')::timestamptz;

      if v_deleted_at is not null then
        -- Tombstones carry no payload and no check state (the
        -- visit_prep_items_tombstone_payload_check mirror): body clears
        -- and the item lands unchecked with no stamp, UNCONDITIONALLY.
        v_body := '';
        v_is_checked := false;
        v_checked_by_user_id := null;
        v_checked_at := null;
      elsif v_is_checked then
        -- A check names the acting user (AC3); the stamp time is the
        -- write's own time.
        v_checked_by_user_id := v_uid;
        v_checked_at := v_updated_at;
      else
        v_checked_by_user_id := null;
        v_checked_at := null;
      end if;

      -- The profile must exist (same FK-backstop rejection as care_notes).
      if not exists (select 1 from public.profiles p where p.id = v_profile_id) then
        raise exception 'profile does not exist';
      end if;

      -- Issue #128's write ladder: identical to care_notes (logging, not
      -- profile metadata).
      select role into v_caller_role
        from public.profile_guardians
       where profile_id = v_profile_id
         and user_id = v_uid
         and status = 'accepted';

      if v_caller_role is null or v_caller_role = 'viewer' then
        raise exception 'caller is not authorized to write visit prep items for profile'
          using errcode = 'insufficient_privilege';
      end if;

      select * into v_stored_prep_item
        from public.visit_prep_items
       where id = v_id
       for update;

      if found then
        -- An item never legitimately changes profiles (the care_notes
        -- cannot-move-between-profiles pattern).
        if v_stored_prep_item.profile_id is distinct from v_profile_id then
          raise exception 'visit prep item cannot move between profiles'
            using errcode = 'insufficient_privilege';
        end if;
        v_accept := v_updated_at > v_stored_prep_item.updated_at
          or (v_updated_at = v_stored_prep_item.updated_at
              and v_deleted_at is not null
              and v_stored_prep_item.deleted_at is null);
        if not v_accept then
          if not (v_updated_at = v_stored_prep_item.updated_at
                  and v_deleted_at is not null
                  and v_stored_prep_item.deleted_at is not null) then
            -- declined (older, or equal-and-live): hand back the server copy
            v_resolved := v_resolved
              || (to_jsonb(v_stored_prep_item) || jsonb_build_object('table', 'visit_prep_items'));
          end if;
          continue;
        end if;
      end if;

      if v_stored_prep_item.id is null then
        insert into public.visit_prep_items
          (id, profile_id, body, is_checked, checked_by_user_id, checked_at,
           updated_at, deleted_at, logged_by_user_id, last_modified_by_user_id)
        values
          (v_id, v_profile_id, v_body, v_is_checked, v_checked_by_user_id, v_checked_at,
           v_updated_at, v_deleted_at, v_uid, v_uid)
        returning * into v_stored_prep_item;
      else
        update public.visit_prep_items
           set body = v_body,
               is_checked = v_is_checked,
               -- A text edit that leaves the check state unchanged keeps
               -- the stored stamp (editing a co-guardian's checked item
               -- must not silently re-stamp who checked it); only a real
               -- check/uncheck transition -- or a tombstone -- rewrites
               -- it. A tombstone always clears (the
               -- visit_prep_items_tombstone_payload_check mirror).
               checked_by_user_id = case
                 when v_deleted_at is not null then null
                 when v_is_checked is distinct from v_stored_prep_item.is_checked
                   then v_checked_by_user_id
                 else v_stored_prep_item.checked_by_user_id end,
               checked_at = case
                 when v_deleted_at is not null then null
                 when v_is_checked is distinct from v_stored_prep_item.is_checked
                   then v_checked_at
                 else v_stored_prep_item.checked_at end,
               updated_at = v_updated_at,
               deleted_at = v_deleted_at,
               last_modified_by_user_id = v_uid
         where id = v_id
        returning * into v_stored_prep_item;
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

comment on function public.sync_push(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) is
  'Batch upsert of profiles, day entries, then observations under guardian role permissions with authoritative attribution stamping. U1: profiles carries birth_year/relationship through this path; transferred_at is tolerated-but-never-read. #131: profiles carries mode through this path. Same-date day_entries collisions union tags onto the surviving row (R7, issue #3 gap-closure plan U4) while flow/note stay last-writer-wins - except that a tombstoned row always has flow forced to none, same as note/tags (issue #224). Observations: a brand-new row colliding with an already-live sibling on (profile_id, local_date, category, code) resolves head-to-head (newer updated_at wins, ulid tiebreak) with the loser becoming a payload-free tombstone - the child-table analogue of the day_entries tag union, since there is no array to union here (see 20260908160000_observations.sql''s header). A per-day (profile_id, local_date) cap of 200 live observations is enforced in this RPC, not a CHECK. p_observations defaults to an empty array so a pre-#240 2-argument call keeps working unchanged. Issue #159: day_entries now carries source/source_id/import_id (client-authored provenance, closed-set source check, partial-unique (profile_id, source, source_id) index for import dedup) through this path exactly like every other day_entries column, with a v_row ? ''key'' containment guard on all three so an old client omitting them never nulls an already-stored value (the U1/#131 pattern); observations gains import_id with the same containment guard, and source_id now gets it too (closing a pre-existing #240 gap); source itself now gets the same guard as day_entries.source (review finding: an omitted key coalescing to ''manual'' is not distinguishable from an explicit ''manual'' without one). Provenance is never cleared on a tombstone on either table (source_id/import_id survive a day_entries or observations delete, reversing #240''s original source_id-clearing on an observations tombstone) so a deleted row stays recognisable to a future re-import. Issue #180 review fix: v_local_date is now derived from observed_at/tz (when observed_at is present) immediately after v_tz is resolved, ahead of the stored-row lookup, the same-date (category, code) collision dedup, and the per-day cap, so those checks -- and v_obs_check_collision''s own date-move detection -- always run against the same local_date the observations_derive_local_date trigger will independently recompute; previously they ran against the stale client-supplied local_date key, letting a push (or an observed_at-only update) land on a different day than what was checked. Issue #188: p_profile_modes and p_cycle_overrides (both defaulting to empty arrays so every older-arity call keeps working) carry the life-stage mode row (one per profile, no tombstone, strict LWW with every optional column guarded by the same v_row ? ''key'' containment check so an older client never clobbers birth-control state or health_sync_consent) and manual cycle corrections (per-id LWW with #224-style payload-free tombstones; cycle_overrides_tombstone_payload_check is the structural backstop). Both new sections enforce the issue''s write ladder: any accepted guardian reads, only primary_guardian/co_parent writes. A mode switch never touches day_entries/observations. Issue #128: p_care_notes/p_visit_prep_items carry the per-profile care notes and visit-prep checklist (per-id LWW with #224-style payload-free tombstones; care_notes_tombstone_payload_check/visit_prep_items_tombstone_payload_check are the structural backstops), both under the day_entries write ladder (any accepted guardian reads; primary_guardian/co_parent/caregiver writes; viewer rejected).';

revoke execute on function public.sync_push(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) from public, anon;
grant execute on function public.sync_push(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. delete_account_data(): create-or-replaced from its latest body
--    (20260909000000_profile_modes_and_cycle_overrides.sql, still the
--    current definition -- no later migration on main has touched it) plus
--    two count-only deletes. Both tables cascade from the profiles delete
--    below anyway (profile_id references profiles(id) on delete cascade);
--    the explicit deletes exist purely so the returned jsonb reports real
--    counts, on the exact precedent of #240's observations step and #188's
--    mode-table steps, and run before the profiles delete so there are rows
--    left to count. Scoped to profiles the caller *owns* -- never to
--    anything attribution-like: rows on a shared profile are the owning
--    family's care content and survive a caregiver's account deletion (the
--    same R7 reasoning as day_entries/observations), while the caller's own
--    authorship of a row elsewhere does not spare it when the caller owns
--    the profile (ownership scoping, not authorship scoping, like every
--    sibling step here).
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
  v_profile_modes_deleted bigint := 0;
  v_care_notes_deleted bigint := 0;
  v_cycle_overrides_deleted bigint := 0;
  v_visit_prep_items_deleted bigint := 0;
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
  v_import_jobs_deleted bigint := 0;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  -- Step 0 (P0 fix; #17 P1 item 5 follow-up): see
  -- public.rehome_stray_day_entries() above - the delete-account Edge
  -- Function calls it a second time, standalone (on its service-role
  -- client, with an explicit p_user_id - #17 P1 round 2 fix), immediately
  -- before auth.admin.deleteUser. This call runs inside a security-definer
  -- function, so it executes as the function owner regardless of
  -- rehome_stray_day_entries()'s own (now-revoked) grants to authenticated.
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

  -- Issue #188: profile_modes/cycle_overrides on profiles the caller
  -- owns, deleted explicitly (like observations above) purely so this
  -- function's returned count reflects them -- the profiles delete's own
  -- cascades would remove them regardless. Scoped to owned profiles only:
  -- rows on a *shared* profile are the owning family's metadata, not this
  -- caller's, and survive (the same R7 scoping observations uses).
  delete from public.profile_modes
   where profile_id in (
     select id from public.profiles where user_id = v_uid
   );
  get diagnostics v_profile_modes_deleted = row_count;

  delete from public.cycle_overrides
   where profile_id in (
     select id from public.profiles where user_id = v_uid
   );
  get diagnostics v_cycle_overrides_deleted = row_count;

  -- Issue #128: care_notes/visit_prep_items on profiles the caller
  -- owns, deleted explicitly (like observations and the mode tables
  -- above) purely so this function''s returned count reflects them --
  -- the profiles delete''s own cascades would remove them regardless.
  -- Scoped to owned profiles only: rows on a *shared* profile are the
  -- owning family''s care content, not this caller''s, and survive (the
  -- same R7 scoping observations uses).
  delete from public.care_notes
   where profile_id in (
     select id from public.profiles where user_id = v_uid
   );
  get diagnostics v_care_notes_deleted = row_count;

  delete from public.visit_prep_items
   where profile_id in (
     select id from public.profiles where user_id = v_uid
   );
  get diagnostics v_visit_prep_items_deleted = row_count;

  -- day_entries on profiles the caller owns. Deliberately not
  -- `day_entries.user_id = v_uid`: that column is stamped from auth.uid()
  -- at insert time (see 20260903014208_initial_sync_schema.sql), so a
  -- caregiver's own device syncing an entry for someone else's shared
  -- profile sets it to the caregiver, not the profile owner. Deleting by
  -- that column would destroy another family's data out from under them
  -- when the caregiver's account is removed - exactly what R7 forbids.
  delete from public.day_entries
   where profile_id in (
     select id from public.profiles where user_id = v_uid
   );
  get diagnostics v_day_entries_deleted = row_count;

  -- Issue #5, U4: profile_reminder_windows for profiles the caller *owns*.
  -- Explicit (rather than relying on the profiles delete's cascade below)
  -- so this function's own returned count reflects it, and so it is gone
  -- before the profiles delete rather than depending on cascade ordering.
  delete from public.profile_reminder_windows
   where profile_id in (
     select id from public.profiles where user_id = v_uid
   );
  get diagnostics v_reminder_windows_deleted = row_count;

  -- Issue #5, U4: the caller's own pending caregiver alerts, on any
  -- profile (their own, or one they merely guard). Not scoped to owned
  -- profiles - the caller may be the *recipient* of alerts for a profile
  -- someone else owns, and those rows belong to the caller (R20), not the
  -- profile owner.
  delete from public.notification_outbox
   where recipient_user_id = v_uid;
  get diagnostics v_notification_outbox_deleted = row_count;

  -- Invitations the caller created, for any profile (their own or one they
  -- co-parent).
  delete from public.guardian_invitations
   where invited_by = v_uid;
  get diagnostics v_invitations_deleted = row_count;

  -- The caller's own guardian memberships. No status filter: a revoked
  -- membership row is still the caller's row and must go too.
  delete from public.profile_guardians
   where user_id = v_uid;
  get diagnostics v_guardians_deleted = row_count;

  -- Issue #5, U4: the caller's own notification preferences, on any
  -- profile they guard (their own, or someone else's). A co-guardian's
  -- preference row for a profile the caller also guards is not the
  -- caller's row and is untouched by this delete.
  delete from public.notification_preferences
   where user_id = v_uid;
  get diagnostics v_notification_preferences_deleted = row_count;

  -- Issue #5, U4: the caller's own registered devices.
  delete from public.push_devices
   where user_id = v_uid;
  get diagnostics v_push_devices_deleted = row_count;

  -- Round-2 review #8: the caller's own missed-entry dedupe markers, on any
  -- profile (their own, or one they merely guard) -- same scoping as
  -- notification_preferences and push_devices above. Not covered by the
  -- profiles delete's cascade below when the caller does not own the
  -- profile (e.g. a caregiver deleting their own account while remaining a
  -- guardian elsewhere is not this path, but a co-guardian's marker on a
  -- profile the caller owns is a different row and must not be touched
  -- here regardless).
  delete from public.missed_entry_alert_state
   where user_id = v_uid;
  get diagnostics v_missed_entry_alert_state_deleted = row_count;

  -- Issue #243 (D-25): the caller's own feedback tickets, explicitly -
  -- rather than depending on feedback_tickets.user_id's `on delete cascade`
  -- to fire only once the Edge Function's later, separately-failable
  -- auth.admin.deleteUser call succeeds (see this migration's header).
  -- feedback_replies cascades from feedback_tickets (`on delete cascade`,
  -- see 20260906130000_feedback_tickets.sql), so no separate delete is
  -- needed for replies here.
  delete from public.feedback_tickets
   where user_id = v_uid;
  get diagnostics v_feedback_tickets_deleted = row_count;

  -- Issue #167: the caller's own import jobs, on any profile (their own,
  -- or one they merely guard) -- `created_by = v_uid`, mirroring
  -- guardian_invitations' `invited_by = v_uid` predicate immediately
  -- above. A job on a profile the caller owns is deleted here whenever the
  -- caller is also who ran the import (the common case); it is also
  -- caught by the profiles delete's own cascade below regardless of who
  -- ran it, via import_jobs.profile_id's `on delete cascade`.
  delete from public.import_jobs
   where created_by = v_uid;
  get diagnostics v_import_jobs_deleted = row_count;

  -- The caller's own profiles. Cascades any day_entries,
  -- guardian_invitations, and profile_guardians rows still tied to these
  -- specific profiles (e.g. a co-parent's membership, or an invitation
  -- someone else sent for it) - intended for an owner (R7). Also cascades
  -- any remaining notification_preferences/notification_outbox/
  -- profile_reminder_windows/import_jobs rows scoped to these profiles
  -- (Issue #5, Issue #167) - e.g. a co-guardian's own preference row for a
  -- profile the caller owned, or an import job someone else ran on a
  -- profile the caller owned, both correct: once the profile itself is
  -- gone there is nothing left to alert anyone about or import into.
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
    'profile_modes', v_profile_modes_deleted,
    'cycle_overrides', v_cycle_overrides_deleted,
    'care_notes', v_care_notes_deleted,
    'visit_prep_items', v_visit_prep_items_deleted,
    'guardian_invitations', v_invitations_deleted,
    'profile_guardians', v_guardians_deleted,
    'profiles', v_profiles_deleted,
    'settings', v_settings_deleted,
    'notification_preferences', v_notification_preferences_deleted,
    'push_devices', v_push_devices_deleted,
    'notification_outbox', v_notification_outbox_deleted,
    'profile_reminder_windows', v_reminder_windows_deleted,
    'missed_entry_alert_state', v_missed_entry_alert_state_deleted,
    'feedback_tickets', v_feedback_tickets_deleted,
    'import_jobs', v_import_jobs_deleted
  );
end;
$$;

comment on function public.delete_account_data() is
  'Deletes every row the calling user (auth.uid()) owns across profiles, '
  'day_entries, observations (Issue #240), profile_modes and '
  'cycle_overrides (Issue #188), care_notes and visit_prep_items (Issue #128 - all five explicit for an accurate '
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

-- ---------------------------------------------------------------------------
-- 8. reconcile_realtime_publication(): create-or-replaced from its latest
--    body (20260909000000_profile_modes_and_cycle_overrides.sql) with
--    care_notes and visit_prep_items guard blocks added alongside
--    day_entries/profiles/observations/import_jobs/profile_modes/
--    cycle_overrides -- both carry the same category of sensitive health
--    content about a minor and must never reach a client any way other
--    than sync_signals + an authenticated pull. Checks *and corrects*
--    rather than only checking membership, mirroring the sibling blocks
--    exactly. Re-run at the end of this migration so a local `db reset`
--    replaying every migration from scratch leaves the publication correct
--    regardless of what came before.
-- ---------------------------------------------------------------------------
create or replace function public.reconcile_realtime_publication()
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_signals_col_list name[] := array['profile_id', 'updated_at']::name[];
  v_current_cols name[];
  v_all_tables boolean;
begin
  if not exists (
    select 1 from pg_catalog.pg_publication where pubname = 'supabase_realtime'
  ) then
    raise exception
      'supabase_realtime publication does not exist -- expected to already '
      'exist, created by the Supabase platform''s own base migrations';
  end if;

  -- Never let day_entries or profiles be published, in any form. Checks
  -- *and corrects* rather than only checking membership, so a whole-row
  -- publication left behind by Supabase Studio's "Enable Realtime" toggle
  -- (or a future edit that widens this migration) is actively reverted
  -- instead of being treated as already-correct and skipped.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'day_entries'
  ) then
    alter publication supabase_realtime drop table public.day_entries;
  end if;

  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'profiles'
  ) then
    alter publication supabase_realtime drop table public.profiles;
  end if;

  -- Issue #240 review finding: observations joins day_entries/profiles on
  -- this must-never-be-published list -- it carries the same category of
  -- sensitive per-entry content (symptom/option detail) that day_entries
  -- was excluded for, and nothing about this table was ever meant to reach
  -- the client any way other than the existing sync_signals wake-signal +
  -- an authenticated sync_push/read.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'observations'
  ) then
    alter publication supabase_realtime drop table public.observations;
  end if;

  -- Issue #167: import_jobs joins this must-never-be-published list --
  -- no health content, but a per-user tracking table with no reason to
  -- reach the client any way other than an authenticated read.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'import_jobs'
  ) then
    alter publication supabase_realtime drop table public.import_jobs;
  end if;

  -- Issue #188: profile_modes and cycle_overrides join this
  -- must-never-be-published list -- a profile's reproductive-life-stage
  -- state and cycle corrections are exactly the category of sensitive
  -- content day_entries/profiles/observations were excluded for.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'profile_modes'
  ) then
    alter publication supabase_realtime drop table public.profile_modes;
  end if;

  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'cycle_overrides'
  ) then
    alter publication supabase_realtime drop table public.cycle_overrides;
  end if;

  -- Issue #128: care_notes and visit_prep_items join this
  -- must-never-be-published list -- standing care notes and visit-prep
  -- checklists are exactly the category of sensitive health content
  -- about a minor that day_entries/profiles/observations were excluded
  -- for.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'care_notes'
  ) then
    alter publication supabase_realtime drop table public.care_notes;
  end if;

  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'visit_prep_items'
  ) then
    alter publication supabase_realtime drop table public.visit_prep_items;
  end if;

  -- If `supabase_realtime` was ever switched to FOR ALL TABLES (which would
  -- silently republish day_entries/profiles/observations/import_jobs
  -- whole-row regardless of the per-table checks above), that is a
  -- platform-level misconfiguration this function cannot safely undo (it
  -- would also drop unrelated tables this repo does not own). Fail loudly
  -- instead of pretending the guard above was sufficient.
  select puballtables into v_all_tables
    from pg_catalog.pg_publication
   where pubname = 'supabase_realtime';

  if v_all_tables then
    raise exception
      'supabase_realtime is FOR ALL TABLES -- this publishes public.profiles, '
      'public.day_entries, public.observations, public.import_jobs, '
      'public.profile_modes, public.cycle_overrides, public.care_notes, and public.visit_prep_items whole-row and must be '
      'fixed manually before this migration can proceed (see the migration '
      'header comment)';
  end if;

  -- public.sync_signals: the only table this app publishes to Realtime.
  -- Correct both membership and the published column list -- not just
  -- membership -- so a Studio toggle (which would publish every column) is
  -- detected and repaired rather than skipped as "already there".
  select attnames
    into v_current_cols
    from pg_catalog.pg_publication_tables
   where pubname = 'supabase_realtime'
     and schemaname = 'public'
     and tablename = 'sync_signals';

  if v_current_cols is null then
    alter publication supabase_realtime
      add table public.sync_signals (profile_id, updated_at);
  elsif (select array_agg(c order by c) from unnest(v_current_cols) as c)
        is distinct from (
          select array_agg(c order by c) from unnest(v_signals_col_list) as c
        ) then
    -- Column set drifted from what this function intends (e.g. a Studio
    -- toggle re-added the table whole-row) -- correct it rather than skip.
    alter publication supabase_realtime drop table public.sync_signals;
    alter publication supabase_realtime
      add table public.sync_signals (profile_id, updated_at);
  end if;
end;
$$;

comment on function public.reconcile_realtime_publication() is
  'Ensures supabase_realtime publishes only public.sync_signals (with '
  'exactly profile_id, updated_at) and never public.profiles/day_entries/'
  'observations/profile_modes/cycle_overrides/care_notes/visit_prep_items (Issue #240 added '
  'observations to this list; Issue #188 added the two mode tables; Issue #128 added care_notes/visit_prep_items), '
  'drift (e.g. a Studio "Enable Realtime" toggle) rather than skipping an '
  'already-published table (Issue #77 P1 fix). Not an API function -- runs '
  'only from this migration and from pgTAP (as an unrestricted role); '
  'execute is revoked from every app role below.';

revoke execute on function public.reconcile_realtime_publication()
  from public, anon, authenticated;

select public.reconcile_realtime_publication();
