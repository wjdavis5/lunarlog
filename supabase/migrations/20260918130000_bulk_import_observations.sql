-- Migration: 20260918130000_bulk_import_observations.sql
-- Issue #328 (epic: Import, follow-up to #167):
-- `public.bulk_import_observations(p_import_id uuid, p_rows jsonb)`.
--
-- `bulk_import_entries` (20260908190000_bulk_import.sql, last re-emitted by
-- 20260915020000_bulk_import_pms_tombstone.sql) is scoped to `day_entries`
-- only; an observations-shaped row is rejected as carrying unknown keys. A
-- Clue import (#190 parser -> #172 write path, end to end as of #452) also
-- produces `observations` rows (symptoms, BBT, spotting after #247), so those
-- otherwise went through `sync_push`'s per-row path -- the exact bottleneck
-- #167 existed to remove. This migration adds the observations half of the
-- bulk path, mirroring `bulk_import_entries`' shape exactly: SECURITY
-- DEFINER + pinned empty search_path, guardian-write-role check against the
-- job's profile (before the status check, so an unauthorised caller learns
-- nothing about a job's status), the `lunarlog.bulk_import` transaction-local
-- GUC, the row-count cap, the id-first + `(profile_id, source, source_id)`
-- ON CONFLICT arbiter write, tombstone revival, and one `sync_signals` touch
-- per profile.
--
-- Timestamp note: sorts after `20260918120000_pg_net_public_placement_guard.sql`
-- (the newest migration on `main` at dispatch time -- AGENTS.md Migration
-- Flow item 7).
--
-- Scope decisions (also in the PR body):
--   * `source`/`import_id` are NOT accepted per-row -- they come from the
--     `import_jobs` row (one job = one source + one id). A row carrying
--     either is rejected as an unknown key.
--   * `observations.source`'s closed set is widened additively to include
--     `file_import`. `import_jobs.source` is day_entries' vocabulary
--     (manual/clue_import/healthkit/health_connect/file_import) while
--     `observations.source` is a genuinely different one
--     (manual/apple_health/health_connect/wearable/clue_import). Because
--     this RPC stamps `v_job.source` onto every row it writes, a job whose
--     source is `healthkit` (a day_entries-only label) can never produce a
--     valid observation; that combination is rejected up front with a clear
--     typed error instead of letting the INSERT abort on
--     `observations_source_check`. `file_import` joins the observations set
--     so #140's own-export importer can label imported observations honestly
--     (the issue's own Proposed change), and because it is the only
--     import_jobs-valid source still missing from the observations set.
--   * Same-date `(category, code)` dedup / per-day 200 cap are enforced
--     set-based, by REJECTING the individual offending row with a per-row
--     reason -- not by reimplementing `sync_push`'s head-to-head LWW
--     resolver. Rationale: `sync_push` resolves same-date collisions with a
--     per-row `select ... for update` and a newer-wins/ulid-tiebreak merge,
--     which is inherently row-at-a-time; a set-based write cannot reproduce
--     that overlap-resolution without either a per-row loop (the bottleneck
--     this RPC exists to avoid) or a second pass that tombstones existing
--     rows. `bulk_import_entries` already made exactly this call for its own
--     date collision ("decision: no in-RPC resolver in this PR; the client
--     surfaces the conflict"), and this RPC mirrors it. The collision check
--     is deliberately source-AGNOSTIC (it keys on profile_id/local_date/
--     category/code alone), matching the structural backstop
--     `observations_live_profile_date_category_code_uq`
--     (20260913018000_observations_dedup_unique_index.sql) -- which is not
--     source-scoped -- so a rejected row can never instead abort the batch
--     on a 23505 from that index.
--   * Fully set-based, including validation: one SQL expression over the
--     whole batch via `jsonb_array_elements(...) with ordinality`, reusing
--     the existing `bulk_import_safe_date`/`bulk_import_safe_timestamptz`
--     helpers (the latter already rejects far-future/nonfinite values per
--     row, #641) so a malformed individual row is rejected (row_index,
--     reason) rather than aborting the chunk.
--   * A row whose `id` already exists in `observations` is resolved first,
--     by id, with last-writer-wins on `updated_at` (mirroring
--     `sync_push` and `bulk_import_entries`), so retrying an already-landed
--     chunk is a real idempotent update, not a primary-key collision. Every
--     other row requires a non-null `source_id` (rejected otherwise:
--     `source_id is required for idempotent import`) and goes through the
--     `on conflict (profile_id, source, source_id) where source_id is not
--     null do update` arbiter -- the raw shape that revives a tombstoned
--     imported row, which `sync_push` cannot do (it resolves strictly by
--     id).
--   * Within-batch duplicates: two rows sharing (profile_id, source,
--     source_id) resolve to the later row (by position) surviving; two live
--     rows sharing (profile_id, local_date, category, code) resolve to the
--     earlier row (by position) surviving. Both are rejections of the
--     superseded row, matching `bulk_import_entries`.
--   * `day_entry_id`/`profile_id` are immutable on the update-by-id path
--     (mirroring `sync_push`'s "observation cannot move between day entries
--     or profiles" guard). On the `(profile_id, source, source_id)` arbiter
--     path the import is treated as the source of truth and `day_entry_id`
--     is updated in place; the incoming parent is validated to exist and
--     belong to the job's profile either way.
--   * A live observation may never point at a tombstoned day entry (#524);
--     such a row is rejected per-row.
--   * Tombstone rows carry no payload except local_date/tz/day_entry_id/
--     profile_id/source/source_id/import_id (issue #224/#159 precedent):
--     category/code/value_num/value_text/unit/intensity/excluded/raw/
--     observed_at are forced empty here rather than validated or rejected.

-- ---------------------------------------------------------------------------
-- 1. observations_source_check: additively widened with `file_import`.
--    `not valid` + `validate` follows the repo's established pattern for
--    adding a CHECK to a populated table (20260908180000_timezone_contract.sql).
--    The new set is a strict superset of the old, so validation is trivially
--    satisfied by every existing row.
-- ---------------------------------------------------------------------------

alter table public.observations
  drop constraint observations_source_check;

alter table public.observations
  add constraint observations_source_check
  check (source in ('manual', 'apple_health', 'health_connect', 'wearable', 'clue_import', 'file_import'))
  not valid;

alter table public.observations
  validate constraint observations_source_check;

-- ---------------------------------------------------------------------------
-- 2. public.bulk_import_observations(uuid, jsonb)
-- ---------------------------------------------------------------------------

create or replace function public.bulk_import_observations(
  p_import_id uuid,
  p_rows jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c_max_rows constant integer := 2000;
  c_max_observations_per_day constant integer := 200;
  c_ulid constant text := '^[0-9A-HJKMNP-TV-Z]{26}$';
  -- source/import_id are deliberately NOT in this allowlist -- they come
  -- from the job record, never the payload (see this migration's header).
  c_row_keys constant text[] := array[
    'id', 'day_entry_id', 'profile_id', 'local_date', 'observed_at', 'tz',
    'category', 'code', 'value_num', 'value_text', 'unit', 'intensity',
    'excluded', 'source_id', 'raw', 'updated_at', 'deleted_at'];

  v_uid uuid := (select auth.uid());
  v_job public.import_jobs%rowtype;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_revived integer := 0;
  v_rejected jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'bulk_import_observations requires an authenticated user'
      using errcode = 'insufficient_privilege';
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'p_rows must be a JSON array'
      using errcode = 'invalid_parameter_value';
  end if;

  if jsonb_array_length(p_rows) > c_max_rows then
    raise exception 'p_rows exceeds % rows', c_max_rows
      using errcode = 'invalid_parameter_value';
  end if;

  select * into v_job from public.import_jobs where id = p_import_id for update;
  if not found then
    raise exception 'import job % does not exist', p_import_id
      using errcode = 'invalid_parameter_value';
  end if;

  -- Guardian check BEFORE the status check: an unauthorised caller must
  -- learn nothing about a job's status (or, via the exception message shape,
  -- its existence beyond "some row with this id exists") -- mirrors
  -- bulk_import_entries.
  if not public.is_guardian_with_roles(
    v_job.profile_id, v_uid, array['primary_guardian', 'co_parent', 'caregiver']
  ) then
    raise exception 'caller is not authorized to import observations for profile %', v_job.profile_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_job.status in ('completed', 'failed') then
    raise exception 'import job % is already %', p_import_id, v_job.status
      using errcode = 'invalid_parameter_value';
  end if;

  -- observations.source's own closed set. A job whose source is outside it
  -- (e.g. 'healthkit', a day_entries-only label) can never produce a valid
  -- observation write; reject the whole call clearly rather than let the
  -- INSERT abort the batch on a CHECK violation.
  if v_job.source not in ('manual', 'clue_import', 'apple_health', 'health_connect', 'wearable', 'file_import') then
    raise exception 'import job source % cannot write observations', v_job.source
      using errcode = 'invalid_parameter_value';
  end if;

  if jsonb_array_length(p_rows) = 0 then
    return jsonb_build_object('inserted', 0, 'updated', 0, 'revived', 0, 'rejected', '[]'::jsonb);
  end if;

  -- Skip touch_sync_signal()/enqueue_caregiver_alerts()'s per-row work for
  -- the duration of the write (this RPC touches sync_signals itself, once,
  -- at the end; a bulk import never pages a guardian). Transaction-local,
  -- the same pattern bulk_import_entries / the ownership-transfer RPCs use.
  perform set_config('lunarlog.bulk_import', 'on', true);

  begin
    with parsed as (
      -- One SQL expression over the whole batch, not a per-row plpgsql loop;
      -- ordinality gives each row its 0-based position for the `rejected`
      -- summary. A tombstone row carries no payload, mirroring sync_push's
      -- observations tombstone branch -- forced here unconditionally rather
      -- than validating whatever content keys a tombstone row happens to
      -- carry.
      select
        ord.idx - 1 as row_index,
        ord.value as raw,
        ord.value ->> 'id' as id,
        ord.value ->> 'day_entry_id' as day_entry_id,
        ord.value ->> 'profile_id' as row_profile_id,
        ord.value ->> 'local_date' as local_date_text,
        coalesce(ord.value ->> 'tz', 'UTC') as tz,
        ord.value ->> 'source_id' as source_id,
        ord.value ->> 'updated_at' as updated_at_text,
        ord.value ->> 'deleted_at' as deleted_at_text,
        ord.value ->> 'observed_at' as observed_at_text,
        case when (ord.value ->> 'deleted_at') is not null then null
          else ord.value ->> 'category' end as category,
        case when (ord.value ->> 'deleted_at') is not null then null
          else ord.value ->> 'code' end as code,
        case when (ord.value ->> 'deleted_at') is not null then null
          else ord.value ->> 'value_num' end as value_num_text,
        case when (ord.value ->> 'deleted_at') is not null then null
          else ord.value ->> 'value_text' end as value_text,
        case when (ord.value ->> 'deleted_at') is not null then null
          else ord.value ->> 'unit' end as unit,
        case
          when (ord.value ->> 'deleted_at') is not null then null
          when jsonb_typeof(ord.value -> 'intensity') = 'number' then ord.value ->> 'intensity'
          else null
        end as intensity_text,
        case
          when (ord.value ->> 'deleted_at') is not null then false
          when jsonb_typeof(ord.value -> 'excluded') = 'boolean' then (ord.value ->> 'excluded')::boolean
          else false
        end as excluded_flag,
        case when (ord.value ->> 'deleted_at') is not null then null
          else nullif(ord.value -> 'raw', 'null'::jsonb) end as raw_payload
      from jsonb_array_elements(p_rows) with ordinality as ord(value, idx)
    ),
    validated as (
      select
        p.*,
        public.bulk_import_safe_date(p.local_date_text) as supplied_local_date,
        public.bulk_import_safe_timestamptz(p.observed_at_text) as parsed_observed_at,
        public.bulk_import_safe_timestamptz(p.updated_at_text) as parsed_updated_at,
        public.bulk_import_safe_timestamptz(p.deleted_at_text) as parsed_deleted_at,
        -- Guarded casts: a malformed value must read as NULL here (and be
        -- rejected in `screened`) rather than raise and abort the statement.
        -- Rows with a non-'number' JSON type are rejected by `screened`, so
        -- this cast only ever runs on a real JSON number. Tombstones are
        -- forced to NULL so a stale payload never reaches the payload-free
        -- tombstone CHECK.
        case
          when (p.raw ->> 'deleted_at') is not null then null
          when jsonb_typeof(p.raw -> 'value_num') = 'number' then (p.raw ->> 'value_num')::numeric
          else null
        end as parsed_value_num,
        case
          when (p.raw ->> 'deleted_at') is not null then null
          when jsonb_typeof(p.raw -> 'intensity') = 'number'
               and (p.raw ->> 'intensity') ~ '^-?\d{1,4}$'
            then (p.raw ->> 'intensity')::smallint
          else null
        end as parsed_intensity
      from parsed p
    ),
    derived as (
      -- local_date derived from observed_at/tz the way sync_push and the
      -- observations_derive_local_date BEFORE trigger do (#180): whenever
      -- observed_at is a real instant, (observed_at at time zone tz)::date
      -- wins; otherwise (a date-only Clue import) the supplied local_date is
      -- kept verbatim. The is_valid_timezone() guard keeps an unrecognised
      -- zone from raising inside the AT TIME ZONE evaluation -- that row is
      -- rejected by `screened` regardless.
      select v.*,
        case
          when v.parsed_observed_at is not null and public.is_valid_timezone(v.tz)
            then (v.parsed_observed_at at time zone v.tz)::date
          else v.supplied_local_date
        end as effective_local_date
      from validated v
    ),
    screened as (
      select d.*,
        case
          when jsonb_typeof(d.raw) <> 'object' then 'row is not an object'
          when exists (select 1 from jsonb_object_keys(d.raw) k where k <> all (c_row_keys))
            then 'row carries an unknown key'
          when d.id is null or d.id !~ c_ulid then 'id is not a ULID'
          when d.day_entry_id is null or d.day_entry_id !~ c_ulid then 'day_entry_id is not a ULID'
          when d.row_profile_id is null or d.row_profile_id !~ c_ulid then 'profile_id is not a ULID'
          when d.row_profile_id is distinct from v_job.profile_id then 'profile_id does not match import job'
          when d.local_date_text is null or d.supplied_local_date is null
            then 'local_date is not an ISO calendar date'
          when char_length(d.tz) > 64 then 'tz exceeds 64 characters'
          when not public.is_valid_timezone(d.tz) then 'tz is not a known time zone'
          when d.updated_at_text is null then 'updated_at is required'
          when d.parsed_updated_at is null then 'updated_at is not a valid timestamp'
          when d.deleted_at_text is not null and d.parsed_deleted_at is null
            then 'deleted_at is not a valid timestamp'
          when d.observed_at_text is not null and d.parsed_observed_at is null
            then 'observed_at is not a valid timestamp'
          when d.source_id is not null and char_length(d.source_id) > 128
            then 'source_id exceeds 128 characters'
          when d.parsed_deleted_at is null and (d.category is null or char_length(d.category) < 1)
            then 'category is required'
          when d.parsed_deleted_at is null and char_length(d.category) > 64
            then 'category exceeds 64 characters'
          when d.parsed_deleted_at is null and d.code is not null and char_length(d.code) > 64
            then 'code exceeds 64 characters'
          when d.parsed_deleted_at is null and d.value_text is not null and char_length(d.value_text) > 2000
            then 'value_text exceeds 2000 characters'
          when d.parsed_deleted_at is null and d.unit is not null and char_length(d.unit) > 32
            then 'unit exceeds 32 characters'
          when d.parsed_deleted_at is null and (d.raw ? 'value_num')
               and jsonb_typeof(d.raw -> 'value_num') not in ('number', 'null')
            then 'value_num is not a number'
          when d.parsed_deleted_at is null and (d.raw ? 'intensity')
               and jsonb_typeof(d.raw -> 'intensity') not in ('number', 'null')
            then 'intensity is not a number'
          when d.parsed_deleted_at is null and d.intensity_text is not null
               and d.intensity_text !~ '^[1-5]$'
            then 'intensity is not between 1 and 5'
          when d.parsed_deleted_at is null and (d.raw ? 'excluded')
               and jsonb_typeof(d.raw -> 'excluded') not in ('boolean', 'null')
            then 'excluded is not a boolean'
          when d.parsed_deleted_at is null and d.raw_payload is not null
               and pg_column_size(d.raw_payload) > 8192
            then 'raw exceeds 8192 bytes'
          else null
        end as reason
      from derived d
    ),
    referenced as (
      -- Resolve each still-valid row against an existing observations id
      -- first (any provenance), against its day entry, and against the
      -- (profile_id, source, source_id) arbiter target in one pass. The
      -- source lookup is unique per (profile_id, source) because of
      -- observations_profile_source_source_id_uq.
      select s.*,
        d.id as existing_by_id_id,
        d.profile_id as existing_by_id_profile_id,
        d.day_entry_id as existing_by_id_day_entry_id,
        d.updated_at as existing_by_id_updated_at,
        d.deleted_at as existing_by_id_deleted_at,
        d.local_date as existing_by_id_local_date,
        de.id as de_id,
        de.profile_id as de_profile_id,
        de.deleted_at as de_deleted_at,
        o.id as conflict_id,
        o.deleted_at as conflict_deleted_at,
        o.local_date as conflict_local_date
      from screened s
      left join public.observations d on d.id = s.id
      left join public.day_entries de on de.id = s.day_entry_id
      left join public.observations o
        on s.source_id is not null
       and o.profile_id = s.row_profile_id
       and o.source = v_job.source
       and o.source_id = s.source_id
      where s.reason is null
    ),
    reasoned as (
      select r.*,
        case
          when r.de_id is null then 'day_entry_id does not exist'
          when r.de_profile_id is distinct from r.row_profile_id then 'day_entry_id does not belong to profile_id'
          when r.de_deleted_at is not null and r.parsed_deleted_at is null
            then 'day_entry_id is tombstoned; observation cannot be live'
          when r.existing_by_id_id is not null
               and r.existing_by_id_profile_id is distinct from r.row_profile_id
            then 'id belongs to another profile'
          when r.existing_by_id_id is not null
               and r.existing_by_id_day_entry_id is distinct from r.day_entry_id
            then 'observation cannot move between day entries'
          when r.existing_by_id_id is null and r.source_id is null
            then 'source_id is required for idempotent import'
          -- Source-agnostic same-date (category, code) collision against an
          -- already-live row -- see this migration's header for why there is
          -- no in-RPC head-to-head resolver, and why the check deliberately
          -- matches the non-source-scoped partial unique index.
          when r.parsed_deleted_at is null and r.code is not null and exists (
            select 1 from public.observations x
             where x.profile_id = r.row_profile_id
               and x.local_date = r.effective_local_date
               and x.category = r.category
               and x.code = r.code
               and x.deleted_at is null
               and x.id <> r.id
               and x.id is distinct from r.conflict_id
          ) then 'date already has a live observation for this (category, code)'
          else null
        end as combined_reason
      from referenced r
    ),
    source_ranked as (
      -- Within-batch duplicate resolution: two rows sharing (profile_id,
      -- source, source_id) cannot both be affected by one ON CONFLICT DO
      -- UPDATE (21000); the later row (by position) wins, the earlier is
      -- rejected as superseded. A null source_id gets its own singleton
      -- partition (it is already rejected by the source_id-required rule
      -- unless it resolves by id, in which case it is a distinct row).
      select r.*,
        row_number() over (
          partition by coalesce(r.source_id, 'row:' || r.row_index::text)
          order by r.row_index desc
        ) as source_dupe_rank
      from reasoned r
      where r.combined_reason is null
    ),
    content_ranked as (
      -- Two live rows in the same batch sharing (profile_id, local_date,
      -- category, code) both landing live: the earlier row (by position)
      -- wins, the later is rejected. Tombstones never contest content (they
      -- carry no payload), so they always pass through with rank 1 -- and
      -- are split into their own window partition so they cannot displace a
      -- live row's rank.
      select s.*,
        case
          when s.parsed_deleted_at is not null or s.code is null then 1
          else row_number() over (
            partition by s.row_profile_id, s.effective_local_date, s.category, s.code,
                         (s.parsed_deleted_at is not null)
            order by s.row_index asc
          )
        end as content_dupe_rank
      from source_ranked s
      where s.source_dupe_rank = 1
    ),
    to_write as (
      select c.* from content_ranked c where c.content_dupe_rank = 1
    ),
    planned as (
      -- "adds a net-new live row to effective_local_date": the row ends
      -- live AND is not merely an in-place update of an already-live row
      -- that stays on the same day. Brand-new rows, tombstone revivals and
      -- date moves all count (mirroring sync_push's
      -- v_obs_check_collision), so none of them can bypass the cap.
      select t.*,
        (t.parsed_deleted_at is null) and not (
          (t.existing_by_id_id is not null
            and t.existing_by_id_deleted_at is null
            and t.existing_by_id_local_date is not distinct from t.effective_local_date)
          or (t.existing_by_id_id is null
            and t.conflict_id is not null
            and t.conflict_deleted_at is null
            and t.conflict_local_date is not distinct from t.effective_local_date)
        ) as adds_live
      from to_write t
    ),
    add_ranked as (
      select p.*,
        case when p.adds_live then
          row_number() over (partition by p.row_profile_id, p.effective_local_date order by p.row_index)
        end as day_add_rank
      from planned p
    ),
    cap_checked as (
      -- Per-day 200 cap, set-based: existing live rows on the target day
      -- (excluding any this batch is moving away) plus this row's position
      -- among the batch's net-new live rows for that day. Bounds a single
      -- oversized batch as well as the already-stored total, since all the
      -- rows in a batch are visible to this one statement.
      select a.*,
        case when a.adds_live then (
          select count(*) from public.observations x
           where x.profile_id = a.row_profile_id
             and x.local_date = a.effective_local_date
             and x.deleted_at is null
             and not exists (
               select 1 from planned p2
                where p2.id = x.id
                  and p2.existing_by_id_id is not null
                  and p2.parsed_deleted_at is null
                  and p2.existing_by_id_local_date is distinct from p2.effective_local_date
             )
        ) else null end as day_base
      from add_ranked a
    ),
    writable as (
      select c.*,
        case when c.adds_live and c.day_base + c.day_add_rank > c_max_observations_per_day
          then 'day is at the 200-observation cap'
          else null end as cap_reason
      from cap_checked c
    ),
    -- -----------------------------------------------------------------
    -- Two disjoint, set-based write paths:
    --   (a) update_rows: the row's id already exists -- updated in place,
    --       last-writer-wins on updated_at; a row that loses LWW is
    --       silently skipped (not written, not counted, not rejected),
    --       exactly sync_push's own "declined" behaviour.
    --   (b) insert_rows: no existing id -- source_id is guaranteed not
    --       null here -- goes through the arbiter, which is how a
    --       tombstoned imported row is revived.
    -- -----------------------------------------------------------------
    update_rows as (
      select w.*,
        (w.parsed_updated_at > w.existing_by_id_updated_at
          or (w.parsed_updated_at = w.existing_by_id_updated_at
              and w.parsed_deleted_at is not null
              and w.existing_by_id_deleted_at is null)) as lww_accept
      from writable w
      where w.cap_reason is null and w.existing_by_id_id is not null
    ),
    updated as (
      update public.observations d set
        local_date = u.effective_local_date,
        observed_at = u.parsed_observed_at,
        tz = u.tz,
        category = u.category,
        code = u.code,
        value_num = u.parsed_value_num,
        value_text = u.value_text,
        unit = u.unit,
        intensity = u.parsed_intensity,
        "excluded" = u.excluded_flag,
        source = v_job.source,
        -- The `? key` containment guard: an update-by-id row that omits
        -- source_id must not null an already-stored idempotency key, and
        -- import_id moves together with it (a row not re-stamping source_id
        -- has no new provenance to record).
        source_id = case when u.raw ? 'source_id' then u.source_id else d.source_id end,
        import_id = case when u.raw ? 'source_id' then p_import_id else d.import_id end,
        raw = u.raw_payload,
        updated_at = u.parsed_updated_at,
        deleted_at = u.parsed_deleted_at,
        last_modified_by_user_id = v_uid
      from update_rows u
      where d.id = u.id
        -- Mirrors sync_push's "observation cannot move between profiles"
        -- guard; every surviving row's profile_id already equals
        -- v_job.profile_id, so this only ever excludes the
        -- cryptographically-negligible ULID-collision case.
        and d.profile_id = u.row_profile_id
        and u.lww_accept
      returning u.existing_by_id_deleted_at, u.parsed_deleted_at
    ),
    insert_rows as (
      select w.* from writable w
      where w.cap_reason is null and w.existing_by_id_id is null
    ),
    upserted as (
      insert into public.observations (
        id, day_entry_id, profile_id, local_date, observed_at, tz, category, code,
        value_num, value_text, unit, intensity, excluded, source, source_id, import_id, raw,
        updated_at, deleted_at, logged_by_user_id, last_modified_by_user_id
      )
      select
        il.id, il.day_entry_id, il.row_profile_id, il.effective_local_date, il.parsed_observed_at,
        il.tz, il.category, il.code, il.parsed_value_num, il.value_text, il.unit, il.parsed_intensity,
        il.excluded_flag, v_job.source, il.source_id, p_import_id, il.raw_payload,
        il.parsed_updated_at, il.parsed_deleted_at, v_uid, v_uid
      from insert_rows il
      on conflict (profile_id, source, source_id) where source_id is not null
      do update set
        day_entry_id = excluded.day_entry_id,
        local_date = excluded.local_date,
        observed_at = excluded.observed_at,
        tz = excluded.tz,
        category = excluded.category,
        code = excluded.code,
        value_num = excluded.value_num,
        value_text = excluded.value_text,
        unit = excluded.unit,
        intensity = excluded.intensity,
        "excluded" = excluded."excluded",
        import_id = excluded.import_id,
        raw = excluded.raw,
        updated_at = excluded.updated_at,
        -- Revives a tombstoned row a re-import's row carries live.
        deleted_at = excluded.deleted_at,
        last_modified_by_user_id = excluded.last_modified_by_user_id
      -- xmax = 0 identifies a row this command actually inserted (as opposed
      -- to one it found and updated via the arbiter) -- the standard
      -- Postgres idiom for telling the two branches apart from RETURNING.
      -- source_id is unique within insert_rows (source_ranked's dedup
      -- already guarantees it), so joining back on it is exact.
      returning source_id, (xmax = 0) as was_insert
    )
    select
      (select count(*) from upserted where was_insert),
      (select count(*) from upserted u
         join insert_rows il on il.source_id = u.source_id
        where not u.was_insert
          and il.conflict_deleted_at is not null and il.parsed_deleted_at is null)
        + (select count(*) from updated
            where existing_by_id_deleted_at is not null and parsed_deleted_at is null),
      (select count(*) from upserted u
         join insert_rows il on il.source_id = u.source_id
        where not u.was_insert
          and not (il.conflict_deleted_at is not null and il.parsed_deleted_at is null))
        + (select count(*) from updated
            where not (existing_by_id_deleted_at is not null and parsed_deleted_at is null)),
      (select coalesce(jsonb_agg(jsonb_build_object('row_index', x.row_index, 'reason', x.reason) order by x.row_index), '[]'::jsonb)
         from (
           select row_index, reason from screened where reason is not null
           union all
           select row_index, combined_reason as reason from reasoned where combined_reason is not null
           union all
           select row_index, 'superseded by a later row in the same batch with the same (profile_id, source, source_id)'
             from source_ranked where source_dupe_rank > 1
           union all
           select row_index, 'duplicate (category, code) in batch'
             from content_ranked where content_dupe_rank > 1
           union all
           select row_index, cap_reason from writable where cap_reason is not null
         ) x)
    into v_inserted, v_revived, v_updated, v_rejected;
  exception
    when unique_violation then
      raise exception 'a row in this batch collides with an existing observation under a different identity (its id resolves to one row, its (profile_id, source, source_id) to another) -- the client must ensure a row''s id and source_id always resolve to the same existing row before retrying'
        using errcode = 'invalid_parameter_value';
  end;

  -- touch sync_signals exactly once for the job's profile, only if something
  -- actually changed. now() (transaction start time), consistent with every
  -- other sync_signals writer.
  if (v_inserted + v_updated + v_revived) > 0 then
    insert into public.sync_signals (profile_id, updated_at)
    values (v_job.profile_id, now())
    on conflict (profile_id) do update set updated_at = excluded.updated_at;
  end if;

  return jsonb_build_object(
    'inserted', v_inserted,
    'updated', v_updated,
    'revived', v_revived,
    'rejected', v_rejected
  );
end;
$$;

comment on function public.bulk_import_observations(uuid, jsonb) is
  'Issue #328: set-based bulk upsert of observations for large imports (up '
  'to 2000 rows/call), the observations half of the bulk path #167 opened '
  'for day_entries. SECURITY DEFINER, guardian-write-role checked against '
  'the p_import_id job''s profile (before the job-status check, so an '
  'unauthorised caller learns nothing about a job''s status), every row''s '
  'profile_id must equal the job''s, and source/import_id come from the '
  'import_jobs row, never the payload. Two disjoint set-based write paths: a '
  'row whose id already exists in observations (any provenance) is UPDATEd '
  'in place with last-writer-wins on updated_at (a stale update is silently '
  'skipped, not rejected); every other row requires a non-null source_id '
  '(rejected otherwise -- `source_id is required for idempotent import`) and '
  'goes through `insert ... select ... on conflict (profile_id, source, '
  'source_id) where source_id is not null do update`, which is how a '
  'tombstoned imported row is revived. Validation is fully set-based '
  '(jsonb_array_elements ... with ordinality plus the bulk_import_safe_* '
  'helpers), so a malformed individual row is rejected (row_index, reason) '
  'rather than aborting the batch. local_date is derived from observed_at/tz '
  'when observed_at is present (#180), otherwise the supplied date is kept. '
  'The same-date (category, code) collision and the per-day 200 observation '
  'cap are enforced by REJECTING the individual offending row -- not by an '
  'in-RPC head-to-head resolver (same decision bulk_import_entries made for '
  'its own date collision); the collision check is source-agnostic to match '
  'observations_live_profile_date_category_code_uq. Within-batch duplicates '
  'resolve to the later row winning on (profile_id, source, source_id) and '
  'the earlier row winning on (profile_id, local_date, category, code). '
  'Tombstone rows carry no payload. Sets lunarlog.bulk_import = ''on'' '
  '(transaction-local) for the duration of the write so '
  'touch_sync_signal()/enqueue_caregiver_alerts() no-op per row -- this '
  'function touches sync_signals itself, once, at the end. Returns '
  '{inserted, updated, revived, rejected: [{row_index, reason}]}.';

revoke all on function public.bulk_import_observations(uuid, jsonb) from public, anon;
grant execute on function public.bulk_import_observations(uuid, jsonb) to authenticated;
