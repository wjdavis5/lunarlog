-- Migration: 20260918140000_bulk_import_entries_same_date_conflict.sql
-- Issue #332 (epic: Import, follow-up to #167/#328):
-- public.bulk_import_entries(uuid, jsonb, text) -- the opt-in
-- `p_on_date_conflict` mode for same-date collisions.
--
-- Context. `bulk_import_entries` (20260908190000_bulk_import.sql, last
-- re-emitted by 20260915130000_data_consistency_bundle.sql) rejects any
-- imported row that would land LIVE on a (profile_id, local_date) an
-- existing LIVE row of different provenance already occupies
-- (`'date already has a live entry'`). `sync_push` resolves that exact
-- collision instead: newest `updated_at` wins (lexicographically smaller
-- ULID on a tie), the loser is tombstoned with the winner's timestamp and
-- an empty payload, tags are unioned onto the survivor, and -- Issue #130
-- -- any `flow`/`note` value the loser carried that differs from the
-- survivor's is disclosed as a `day_entry_merge_events` row before it is
-- discarded. #167 deliberately chose per-row rejection so the import UI
-- (#325/#177) could surface the conflict; Issue #332 asked for the merge
-- mode to be added.
--
-- Scope decision (PR body carries the full rationale). This migration adds
-- the `p_on_date_conflict` parameter and its validation, but does NOT
-- implement merge semantics. `'merge'` raises a typed
-- `invalid_parameter_value` (22023) before anything is written, rather
-- than guessing at a resolution. The reason is that a same-date merge in
-- this set-based RPC is not a local change: sync_push's resolver is a
-- per-row `SELECT ... FOR UPDATE` whose correctness depends on a
-- statement-ordered sequence (emit the disclosure while the loser's
-- pre-tombstone payload is still readable -> reparent the loser's live
-- observations, #639 -> tombstone the loser so
-- `day_entries_live_profile_date_uq` frees the date -> only then write the
-- survivor live/union the winner's tags). A data-modifying-CTE rewrite
-- cannot preserve that order (all sub-statements share one snapshot), so
-- landing it safely requires the full resolver to be extracted into a
-- helper both `sync_push` and this RPC call -- a re-emit of the ~2500-line
-- SECURITY DEFINER `sync_push` whose only behaviour change should be
-- "call the helper". Doing that refactor in the same PR as a new
-- write-path semantics change is exactly the large, unreviewable,
-- data-loss-prone change the issue's own scope note warns against. The
-- conservative half is landed here; the resolver extraction and the
-- `'merge'` implementation are tracked as the follow-up (see the PR body's
-- "Not done").
--
-- Timestamp note: sorts after `20260918130000_bulk_import_observations.sql`
-- (the newest migration on `main` at dispatch time -- AGENTS.md Migration
-- Flow item 7).
--
-- Additive/non-destructive: this drops and recreates only the
-- `bulk_import_entries` FUNCTION (Postgres identifies a function by name +
-- parameter TYPE LIST, so adding `p_on_date_conflict` would otherwise
-- leave the current 2-argument function in place as a second overload --
-- the exact-arity match winning over a default-substituted one, silently
-- forking the function in two; 20260916100000_day_entry_merge_events.sql's
-- `sync_push` re-emit documents the same technique). No table, column,
-- row, policy, or grant is touched.

-- ---------------------------------------------------------------------------
-- 1. Drop the 2-argument overload, then create the 3-argument function with
--    the new parameter defaulted to the pre-existing behaviour.
-- ---------------------------------------------------------------------------

drop function if exists public.bulk_import_entries(uuid, jsonb);

create or replace function public.bulk_import_entries(
  p_import_id uuid,
  p_rows jsonb,
  p_on_date_conflict text default 'reject'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c_max_rows constant integer := 2000;
  c_ulid constant text := '^[0-9A-HJKMNP-TV-Z]{26}$';
  -- Issue #167: source/import_id are deliberately NOT in this allowlist --
  -- they come from the job record, never the payload (see this
  -- migration's header).
  c_row_keys constant text[] := array[
    'id', 'profile_id', 'local_date', 'tz', 'flow', 'tags', 'note',
    'source_id', 'updated_at', 'deleted_at'];

  v_uid uuid := (select auth.uid());
  v_job public.import_jobs%rowtype;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_revived integer := 0;
  v_rejected jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'bulk_import_entries requires an authenticated user'
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

  -- Guardian check: the caller must be an accepted guardian of the job's
  -- profile with a *writing* role -- mirrors sync_push's day_entries check
  -- (v_caller_role is null or = 'viewer' => reject) via the same
  -- is_guardian_with_roles() helper the ownership-transfer RPCs use.
  -- Review fix: this must run BEFORE the status check below -- an
  -- unauthorised caller must learn nothing about a job's status (or, via
  -- the exception message shape, its existence beyond "some row with this
  -- id exists"), so a non-guardian probing a real job id gets the same
  -- 42501 regardless of whether that job is pending or already
  -- completed/failed.
  if not public.is_guardian_with_roles(
    v_job.profile_id, v_uid, array['primary_guardian', 'co_parent', 'caregiver']
  ) then
    raise exception 'caller is not authorized to import entries for profile %', v_job.profile_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_job.status in ('completed', 'failed') then
    raise exception 'import job % is already %', p_import_id, v_job.status
      using errcode = 'invalid_parameter_value';
  end if;

  -- Issue #332, the opt-in same-date mode. Validated after the guardian
  -- check (an unauthorised caller learns nothing, and gets 42501 first)
  -- and before the empty-rows early return (so a bad mode is reported
  -- even for a zero-row call). `'reject'` is the pre-existing, unchanged
  -- behaviour; `'merge'` is not implemented yet -- see the dedicated
  -- collision check below -- and is never silently downgraded to reject.
  if p_on_date_conflict is null
     or p_on_date_conflict not in ('reject', 'merge') then
    raise exception 'p_on_date_conflict must be ''reject'' or ''merge'' (got %)', p_on_date_conflict
      using errcode = 'invalid_parameter_value';
  end if;

  if jsonb_array_length(p_rows) = 0 then
    return jsonb_build_object('inserted', 0, 'updated', 0, 'revived', 0, 'rejected', '[]'::jsonb);
  end if;

  -- Issue #332, conservative `'merge'` policy: the same-date resolver is
  -- NOT implemented here yet (see this migration's header). A conflict-free
  -- merge-mode import is indistinguishable from reject mode and is allowed
  -- straight through -- but the moment ANY row would need an actual
  -- same-date merge (an incoming live row landing on a (profile_id,
  -- local_date) an existing live row of different provenance already
  -- occupies), the whole batch is refused with a typed error rather than
  -- guessed at. This is deliberately broader than the reject-mode
  -- per-row check (it also fires on a row that would later be rejected for
  -- an unrelated validation reason); refusing the batch is the safe
  -- direction, and the caller can re-issue the same rows with
  -- `p_on_date_conflict = ''reject''` to get the per-row reasons.
  --
  -- `bulk_import_safe_date` returning null (a malformed local_date) makes
  -- the EXISTS false here, so such a row is not mistaken for a collision;
  -- it is rejected per-row by the ordinary path below.
  if p_on_date_conflict = 'merge' then
    if exists (
      select 1
      from jsonb_array_elements(p_rows) as e(value)
      where jsonb_typeof(e.value) = 'object'
        and e.value ->> 'deleted_at' is null
        and e.value ->> 'profile_id' = v_job.profile_id
        and public.bulk_import_safe_date(e.value ->> 'local_date') is not null
        and exists (
          select 1 from public.day_entries d
           where d.profile_id = v_job.profile_id
             and d.local_date = public.bulk_import_safe_date(e.value ->> 'local_date')
             and d.deleted_at is null
             and d.id is distinct from (e.value ->> 'id')
             and (d.source, d.source_id)
                 is distinct from (v_job.source, e.value ->> 'source_id')
        )
    ) then
      raise exception 'p_on_date_conflict = ''merge'' is not implemented yet: the batch contains a row that would need a same-date merge, whose semantics must match sync_push exactly (issue #332); re-issue with ''reject'' to get per-row conflict reasons'
        using errcode = 'invalid_parameter_value';
    end if;
  end if;

  -- Issue #167: skip touch_sync_signal()/enqueue_caregiver_alerts()'s
  -- per-row work for the duration of the write below (this RPC touches
  -- sync_signals itself, once, at the end; a bulk import never pages a
  -- guardian) -- transaction-local, per the same transaction-local-GUC
  -- pattern the ownership-transfer RPC set in
  -- 20260906180000_ownership_transfer_rpcs.sql uses.
  --
  -- Review fix: this function does NOT (and cannot) raise its own
  -- statement_timeout. `set local statement_timeout = '60s'` used to sit
  -- here, but `statement_timeout` is sampled once when a statement starts
  -- and a mid-statement `set local` on it is a documented Postgres no-op --
  -- it has no effect on the currently-executing statement, and there is no
  -- second statement in this call for it to apply to before the
  -- transaction (and the GUC's `local` scope) ends. So this call has
  -- always run under whatever statement_timeout the caller's role already
  -- had -- the platform's ordinary 8s timeout for `authenticated` -- not a
  -- 60s allowance. Every claim of a 60s bound in this migration's comments
  -- was wrong; see the pgTAP 2000-row latency case, which now measures
  -- against that real 8s ceiling instead.
  perform set_config('lunarlog.bulk_import', 'on', true);

  begin
    with parsed as (
      -- One SQL expression over the whole batch, not a per-row plpgsql
      -- loop (see this migration's header) -- ordinality gives each row
      -- its 0-based position for the `rejected` summary.
      select
        ord.idx - 1 as row_index,
        ord.value as raw,
        ord.value ->> 'id' as id,
        ord.value ->> 'profile_id' as row_profile_id,
        ord.value ->> 'local_date' as local_date_text,
        coalesce(ord.value ->> 'tz', 'UTC') as tz,
        ord.value ->> 'source_id' as source_id,
        ord.value ->> 'updated_at' as updated_at_text,
        ord.value ->> 'deleted_at' as deleted_at_text,
        -- Review fix: a tombstone row carries no payload, mirroring
        -- sync_push's identical day_entries branch
        -- (20260908180000_timezone_contract.sql) -- forced here
        -- unconditionally rather than validating whatever flow/tags/note
        -- keys a tombstone row happens to carry, so a client that sends a
        -- tombstone with a stale (non-empty) payload is not rejected for
        -- it; the payload is simply discarded, same as a live row's would
        -- be validated.
        case when (ord.value ->> 'deleted_at') is not null then 'none'
          else coalesce(ord.value ->> 'flow', 'none') end as flow,
        case when (ord.value ->> 'deleted_at') is not null then '[]'::jsonb
          else coalesce(ord.value -> 'tags', '[]'::jsonb) end as tags,
        case when (ord.value ->> 'deleted_at') is not null then null
          else ord.value ->> 'note' end as note
      from jsonb_array_elements(p_rows) with ordinality as ord(value, idx)
    ),
    validated as (
      select
        p.*,
        public.bulk_import_safe_date(p.local_date_text) as parsed_local_date,
        public.bulk_import_safe_timestamptz(p.updated_at_text) as parsed_updated_at,
        public.bulk_import_safe_timestamptz(p.deleted_at_text) as parsed_deleted_at,
        case
          when jsonb_typeof(p.raw) <> 'object' then 'row is not an object'
          when exists (select 1 from jsonb_object_keys(p.raw) k where k <> all (c_row_keys))
            then 'row carries an unknown key'
          when p.id is null or p.id !~ c_ulid then 'id is not a ULID'
          when p.row_profile_id is null or p.row_profile_id !~ c_ulid then 'profile_id is not a ULID'
          when p.row_profile_id is distinct from v_job.profile_id then 'profile_id does not match import job'
          when public.bulk_import_safe_date(p.local_date_text) is null then 'local_date is not an ISO calendar date'
          when char_length(p.tz) > 64 then 'tz exceeds 64 characters'
          -- Review fix: a syntactically-plausible but unrecognized zone
          -- (e.g. 'Mars/Cydonia') previously passed straight through to
          -- the day_entries CHECK constraint added by
          -- 20260908180000_timezone_contract.sql, which would abort the
          -- whole batch's write statement (caught only by the
          -- unique_violation backstop's cousin, a check_violation, not
          -- handled at all) instead of rejecting just this row.
          when not public.is_valid_timezone(p.tz) then 'tz is not a known time zone'
          -- Issue #303: routed through the same public.is_valid_flow_level()
          -- the flow_level domain's own CHECK and sync_push's validation
          -- now share, instead of a third hand-kept copy of the
          -- allow-list. Still a plain boolean predicate (never a domain
          -- cast), so this set-based CASE keeps rejecting one bad row
          -- instead of aborting the whole batch on a check_violation --
          -- see this migration's header.
          when not public.is_valid_flow_level(p.flow) then 'flow is not a known level'
          when not public.is_valid_tags_array(p.tags) then 'tags failed validation'
          when p.note is not null and char_length(p.note) > 2000 then 'note exceeds 2000 characters'
          when p.source_id is not null and char_length(p.source_id) > 128 then 'source_id exceeds 128 characters'
          when p.updated_at_text is null then 'updated_at is required'
          when public.bulk_import_safe_timestamptz(p.updated_at_text) is null then 'updated_at is not a valid timestamp'
          when p.deleted_at_text is not null and public.bulk_import_safe_timestamptz(p.deleted_at_text) is null
            then 'deleted_at is not a valid timestamp'
          else null
        end as reason
      from parsed p
    ),
    by_id as (
      -- Review fix: resolve every still-valid row against an existing
      -- day_entries id FIRST, regardless of provenance -- mirrors
      -- sync_push's own id-first resolution and is what makes a retry of
      -- an already-landed chunk idempotent: a row whose id already exists
      -- (from a prior successful chunk of this same job, or any other
      -- write) is updated in place below rather than re-attempting an
      -- insert that would collide on the primary key.
      select
        v.*,
        d.id as existing_by_id_id,
        d.profile_id as existing_by_id_profile_id,
        d.updated_at as existing_by_id_updated_at,
        d.deleted_at as existing_by_id_deleted_at
      from validated v
      left join public.day_entries d on d.id = v.id
      where v.reason is null
    ),
    collision_checked as (
      -- Review fix (decision: no in-RPC resolver in this PR -- the client
      -- surfaces the conflict): a row that would land LIVE is rejected
      -- outright if (profile_id, local_date) already belongs to a
      -- different LIVE row under different provenance (e.g. a manual
      -- entry, or a different import's row) -- sync_push's own same-date
      -- merge algorithm is deliberately not reimplemented here. Exempt:
      -- only a tombstone (nothing is landing live). An update-by-id row
      -- is NOT exempt -- day_entries_live_profile_date_uq
      -- (20260904010000_multi_guardian_schema.sql) is a real partial
      -- unique index on (profile_id, local_date) where deleted_at is
      -- null, so an update that moves an existing row onto an
      -- already-occupied live date would otherwise raise a genuine
      -- unique_violation (23505) from the UPDATE statement itself and
      -- abort the whole chunk via the backstop below -- exactly the
      -- per-row-not-per-chunk failure this migration exists to prevent.
      -- `d.id <> b.id` correctly excludes the row's own currently-stored
      -- self when its date is not actually changing.
      --
      -- Review fix (blocking): compare only (source, source_id), never
      -- import_id. import_id is a job-scoped surrogate, not part of a
      -- row's provenance identity -- re-importing the same source_id under
      -- a brand-new import_jobs row (a legitimate resume/retry with a
      -- fresh job id) previously compared as "different provenance" purely
      -- because the two jobs' ids differed, rejecting every row of an
      -- otherwise-idempotent re-import. (source, source_id) alone is what
      -- actually identifies "the same imported thing" -- see
      -- import_provenance_test.sql's partial unique index on exactly that
      -- pair.
      --
      -- Issue #332: when the caller opted into `'merge'`, this branch is
      -- unreachable -- the function already raised before any parsing --
      -- but the reason string stays the reject-mode text so a 2-argument
      -- (defaulted) call's response is byte-for-byte what it was before
      -- this migration.
      select
        b.*,
        case
          when b.parsed_deleted_at is not null then null
          when exists (
            select 1 from public.day_entries d
             where d.profile_id = b.row_profile_id
               and d.local_date = b.parsed_local_date
               and d.deleted_at is null
               and d.id <> b.id
               and (d.source, d.source_id)
                   is distinct from (v_job.source, b.source_id)
          ) then 'date already has a live entry'
          else null
        end as collision_reason
      from by_id b
    ),
    reasoned as (
      select
        c.*,
        coalesce(
          c.collision_reason,
          -- Review fix (blocking): a row whose id already exists in
          -- day_entries but on a DIFFERENT profile is rejected outright,
          -- not silently dropped. Previously by_id's `d.id = v.id` join
          -- ignores profile_id, so a cross-profile id match still set
          -- existing_by_id_id and the row was routed into update_rows --
          -- but the actual UPDATE statement's `d.profile_id =
          -- u.row_profile_id` guard (day entries never move between
          -- profiles, mirroring sync_push) then matched zero rows,
          -- discarding the row without writing it, counting it as
          -- inserted/updated/revived, or rejecting it. It never reaches
          -- insert_rows either (existing_by_id_id is not null), so it
          -- vanished from the response entirely.
          case
            when c.existing_by_id_id is not null
              and c.existing_by_id_profile_id is distinct from c.row_profile_id
              then 'id belongs to another profile'
            else null
          end,
          -- Review fix: a row not already resolved by id needs a
          -- source_id to reach an idempotent write path at all -- the
          -- `on conflict (profile_id, source, source_id)` arbiter below
          -- is the only other route to one, and it requires source_id is
          -- not null. Without this, a brand-new row with no source_id
          -- would insert successfully once and then hit the day_entries
          -- primary key on every subsequent retry of the same chunk,
          -- aborting the whole batch -- the idempotency bug this
          -- restructuring exists to close. Documented as a hard
          -- requirement in BulkImportRow (lib/domain/import/bulk_importer.dart).
          case
            when c.existing_by_id_id is null and c.source_id is null
              then 'source_id is required for idempotent import'
            else null
          end
        ) as combined_reason
      from collision_checked c
    ),
    source_ranked as (
      -- Within-batch duplicate resolution (this migration's header): two
      -- rows sharing (profile_id, source, source_id) cannot both be
      -- affected by one ON CONFLICT DO UPDATE (21000), and would collide
      -- with each other's write regardless of which path either takes --
      -- the later row (by position) wins, the earlier is rejected as
      -- superseded. A null source_id gets its own singleton partition
      -- (never superseded here -- see the source_id-required rejection
      -- above, which already removes every row that would otherwise need
      -- one).
      select
        r.*,
        row_number() over (
          partition by coalesce(r.source_id, 'row:' || r.row_index::text)
          order by r.row_index desc
        ) as source_dupe_rank
      from reasoned r
      where r.combined_reason is null
    ),
    date_ranked as (
      -- Review fix: two rows in the same batch sharing (profile_id,
      -- local_date) under different source_id both landing live is a
      -- second, independent within-batch conflict (decision: no in-RPC
      -- resolver, same as the live-row collision check above) -- the
      -- earlier row (by position) wins, the later is rejected. Tombstones
      -- never contest a date (nothing is landing live), so they always
      -- pass through with rank 1.
      --
      -- Review fix (blocking): the row_number() window is partitioned by
      -- (profile_id, local_date, is-a-tombstone) rather than just
      -- (profile_id, local_date) -- a window function still evaluates over
      -- every row in its partition even when the CASE above discards a
      -- tombstone's computed value and hardcodes 1 instead, so a tombstone
      -- sharing a live row's date previously occupied rank 1 in the
      -- shared partition and pushed the live row (or an earlier live row)
      -- to rank 2+, rejecting it as a spurious "duplicate date" even
      -- though a tombstone never actually contests the date. Splitting
      -- tombstones into their own partition bucket means a live row's
      -- rank depends only on other live rows sharing its date, exactly as
      -- intended -- a tombstone for date D and a live row for date D in
      -- one batch now both proceed.
      select
        s.*,
        case
          when s.parsed_deleted_at is not null then 1
          else row_number() over (
            partition by s.row_profile_id, s.parsed_local_date, (s.parsed_deleted_at is not null)
            order by s.row_index asc
          )
        end as date_dupe_rank
      from source_ranked s
      where s.source_dupe_rank = 1
    ),
    to_write as (
      select d.* from date_ranked d where d.date_dupe_rank = 1
    ),
    -- -----------------------------------------------------------------
    -- Two disjoint, set-based write paths from here (review fix -- see
    -- the migration header's restructuring note):
    --   (a) update_rows: the row's id already exists in day_entries (any
    --       provenance) -- updated in place, last-writer-wins on
    --       updated_at, mirroring sync_push's own resolution. A row that
    --       loses last-writer-wins is silently skipped (not written, not
    --       counted, not rejected) -- exactly sync_push's own "declined"
    --       behaviour for a stale push.
    --   (b) insert_rows: no existing id -- source_id is guaranteed not
    --       null here (every row that would otherwise need one and lacks
    --       it was already rejected above) -- goes through the
    --       pre-existing `on conflict (profile_id, source, source_id)`
    --       upsert, which is how a tombstoned imported row gets revived.
    -- -----------------------------------------------------------------
    update_rows as (
      select
        tw.*,
        (tw.parsed_updated_at > tw.existing_by_id_updated_at
          or (tw.parsed_updated_at = tw.existing_by_id_updated_at
              and tw.parsed_deleted_at is not null
              and tw.existing_by_id_deleted_at is null)) as lww_accept
      from to_write tw
      where tw.existing_by_id_id is not null
    ),
    updated as (
      -- Review fix: apply sync_push's own `v_row ? 'key'` containment
      -- guard (20260908170000_import_provenance.sql /
      -- 20260908180000_timezone_contract.sql) to source_id/import_id here
      -- too -- `source_id` is an ordinary optional payload key (see
      -- c_row_keys above), so an update-by-id row that omits it (editing
      -- flow/tags/note only, say) must not null out the row's already-
      -- stored idempotency key. import_id is guarded by the same
      -- condition rather than its own -- it is never a payload key (it
      -- comes from p_import_id, not the row), so its only sensible update
      -- rule is "moves together with source_id": a row that isn't
      -- (re)stamping source_id has no new provenance to record either.
      update public.day_entries d set
        local_date = u.parsed_local_date,
        tz = u.tz,
        flow = u.flow,
        tags = u.tags,
        note = u.note,
        -- Issue #140 review, LLA-060: pms is not a bulk-import-carried
        -- field (it stays outside c_row_keys -- Clue and similar bulk
        -- sources have no PMS concept to import), so there is never an
        -- incoming value to apply here, only a stored one to either clear
        -- (the row is becoming a tombstone, mirroring flow's 'none'
        -- treatment above) or leave untouched (an ordinary live update).
        -- Without this, a chunk that tombstones an existing pms = true row
        -- by id violated day_entries_tombstone_pms_check -- a
        -- check_violation this function's unique_violation handler below
        -- does not catch -- aborting the WHOLE CHUNK, not just this row.
        pms = case when u.parsed_deleted_at is not null then false else d.pms end,
        source = v_job.source,
        source_id = case when u.raw ? 'source_id' then u.source_id else d.source_id end,
        import_id = case when u.raw ? 'source_id' then p_import_id else d.import_id end,
        updated_at = u.parsed_updated_at,
        deleted_at = u.parsed_deleted_at,
        last_modified_by_user_id = v_uid
      from update_rows u
      where d.id = u.id
        -- Mirrors sync_push's own "day entry cannot move between
        -- profiles" guard -- every surviving row's profile_id already
        -- equals v_job.profile_id (validated above), so this only ever
        -- excludes the cryptographically-negligible case of a ULID
        -- collision landing on a different profile's row; profile_id
        -- itself is deliberately left out of the SET list above, same as
        -- sync_push never moves it either.
        and d.profile_id = u.row_profile_id
        and u.lww_accept
      returning u.existing_by_id_deleted_at, u.parsed_deleted_at
    ),
    insert_rows as (
      select tw.* from to_write tw where tw.existing_by_id_id is null
    ),
    insert_lookup as (
      -- Pre-classify against the live table before writing, so the
      -- inserted/revived/updated split doesn't need to be
      -- reverse-engineered from RETURNING (which only ever shows the
      -- post-write row).
      select
        ir.*,
        d.id as conflict_id,
        d.deleted_at as conflict_deleted_at
      from insert_rows ir
      left join public.day_entries d
        on d.profile_id = ir.row_profile_id
       and d.source = v_job.source
       and d.source_id = ir.source_id
       and ir.source_id is not null
    ),
    upserted as (
      insert into public.day_entries (
        id, profile_id, local_date, tz, flow, tags, note,
        source, source_id, import_id,
        updated_at, deleted_at, logged_by_user_id, last_modified_by_user_id
      )
      select
        il.id, il.row_profile_id, il.parsed_local_date, il.tz, il.flow, il.tags, il.note,
        v_job.source, il.source_id, p_import_id,
        il.parsed_updated_at, il.parsed_deleted_at, v_uid, v_uid
      from insert_lookup il
      on conflict (profile_id, source, source_id) where source_id is not null
      do update set
        local_date = excluded.local_date,
        tz = excluded.tz,
        flow = excluded.flow,
        tags = excluded.tags,
        note = excluded.note,
        -- Issue #140 review, LLA-060: same rule as the by-id UPDATE above
        -- -- pms is never an incoming value on this path either (a fresh
        -- INSERT gets the column's own `not null default false`, since
        -- pms is deliberately absent from the column list above), so a
        -- conflict that revives/updates an EXISTING row only ever clears
        -- it (becoming a tombstone) or keeps it (an ordinary live update);
        -- `public.day_entries.pms` reads the pre-update stored value, same
        -- as `excluded.<col>` reads the proposed INSERT's. Without this,
        -- the source-conflict path had the identical
        -- day_entries_tombstone_pms_check failure the by-id path did.
        pms = case when excluded.deleted_at is not null then false else public.day_entries.pms end,
        import_id = excluded.import_id,
        updated_at = excluded.updated_at,
        -- Revives a tombstoned row that a re-import's rows carry live
        -- (deleted_at is null in the incoming row): the ordinary
        -- deleted_at-clearing path, exactly as the on_conflict shape
        -- import_provenance_test.sql already pins.
        deleted_at = excluded.deleted_at,
        last_modified_by_user_id = excluded.last_modified_by_user_id
      -- xmax = 0 identifies a row this command actually inserted (as
      -- opposed to one it found and updated via the arbiter) -- the
      -- standard Postgres INSERT ... ON CONFLICT idiom for telling the
      -- two branches apart from RETURNING alone. source_id is unique
      -- within insert_lookup (source_ranked's dedup above already
      -- guarantees it), so joining back to insert_lookup on it below is
      -- exact, not approximate.
      returning source_id, (xmax = 0) as was_insert
    )
    select
      (select count(*) from upserted where was_insert),
      (select count(*) from upserted u
         join insert_lookup il on il.source_id = u.source_id
        where not u.was_insert
          and il.conflict_deleted_at is not null and il.parsed_deleted_at is null)
        + (select count(*) from updated
            where existing_by_id_deleted_at is not null and parsed_deleted_at is null),
      (select count(*) from upserted u
         join insert_lookup il on il.source_id = u.source_id
        where not u.was_insert
          and not (il.conflict_deleted_at is not null and il.parsed_deleted_at is null))
        + (select count(*) from updated
            where not (existing_by_id_deleted_at is not null and parsed_deleted_at is null)),
      (select coalesce(jsonb_agg(jsonb_build_object('row_index', x.row_index, 'reason', x.reason) order by x.row_index), '[]'::jsonb)
         from (
           select row_index, reason from validated where reason is not null
           union all
           select row_index, combined_reason as reason from reasoned where combined_reason is not null
           union all
           select row_index, 'superseded by a later row in the same batch with the same (profile_id, source, source_id)'
             from source_ranked where source_dupe_rank > 1
           union all
           select row_index, 'duplicate date in batch'
             from date_ranked where date_dupe_rank > 1
         ) x)
    into v_inserted, v_revived, v_updated, v_rejected;
  exception
    when unique_violation then
      raise exception 'a row in this batch collides with an existing day_entries row under a different identity (its id resolves to one row, its (profile_id, source, source_id) to another) -- the client must ensure a row''s id and source_id always resolve to the same existing row before retrying'
        using errcode = 'invalid_parameter_value';
  end;

  -- Issue #167: touch sync_signals exactly once for the job's profile,
  -- rather than once per row (touch_sync_signal() no-op'd above) -- only
  -- if something actually changed. now() (transaction start time), not
  -- clock_timestamp() -- consistent with touch_sync_signal() itself and
  -- every other sync_signals writer in this schema, none of which have a
  -- same-transaction reason to need statement-time precision.
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

comment on function public.bulk_import_entries(uuid, jsonb, text) is
  'Issue #167: set-based bulk upsert of day_entries for large imports (up '
  'to 2000 rows/call), bypassing sync_push entirely -- SECURITY DEFINER, '
  'guardian-write-role checked against the p_import_id job''s profile '
  '(before the job-status check below it, so an unauthorised caller learns '
  'nothing about a job''s status), every row''s profile_id must equal the '
  'job''s. source/import_id come from the import_jobs row, never the '
  'payload. Two disjoint set-based write paths: a row whose id already '
  'exists in day_entries (any provenance) is UPDATEd in place with '
  'last-writer-wins on updated_at, mirroring sync_push''s own resolution '
  '(a stale update is silently skipped, not rejected); every other row '
  'requires a non-null source_id (rejected otherwise -- '
  '`source_id is required for idempotent import`, documented on '
  'BulkImportRow) and goes through '
  '`insert ... select ... on conflict (profile_id, source, source_id) '
  'where source_id is not null do update` -- the same raw shape '
  'import_provenance_test.sql pins as the way to revive a tombstoned '
  'imported row, which sync_push cannot do (it resolves strictly by id; '
  'see this migration''s header and AGENTS.md Migration Flow item 8). This '
  'two-path split is what makes a retry of an already-landed chunk '
  'idempotent instead of aborting on a primary-key collision. Validation '
  'is fully set-based (jsonb_array_elements ... with ordinality plus two '
  'safe-cast helpers and public.is_valid_timezone()), not a per-row loop, '
  'so a malformed individual row is rejected (row_index, reason) rather '
  'than aborting the batch -- covering every day_entries CHECK the row '
  'shape can violate (id/profile_id ULID, local_date, tz, flow, tags, '
  'note length, source_id length, updated_at). Issue #303: the flow check '
  'now calls public.is_valid_flow_level() (the same predicate the '
  'flow_level domain''s own CHECK and sync_push''s validation both use) '
  'instead of a third hand-kept copy of the allow-list -- still a plain '
  'boolean predicate, never a domain cast, so this set-based CASE keeps '
  'rejecting one bad row instead of aborting the whole batch. A tombstone '
  'row (deleted_at '
  'present) has its flow/tags/note/pms forced to the empty payload rather '
  'than validated or rejected, mirroring sync_push (Issue #140 review, '
  'LLA-060: pms joined this treatment after predating #220 entirely -- see '
  'this migration''s own header). Two independent '
  'within-batch duplicate rules: two rows sharing (profile_id, source, '
  'source_id) resolve to the later row (by position) winning; two rows '
  'sharing (profile_id, local_date) with different source_id resolve to '
  'the earlier row winning (`duplicate date in batch`) -- no in-RPC '
  'resolver for either kind of ambiguity. A row landing live on a date a '
  'different, differently-provenanced LIVE row already occupies is '
  'likewise rejected (`date already has a live entry`) rather than merged '
  '-- decision: no in-RPC resolver in this PR; the client surfaces the '
  'conflict. Issue #332 adds the opt-in `p_on_date_conflict` parameter '
  '(`''reject''` default | `''merge''`): `''reject''` is the unchanged '
  'behaviour above; `''merge''` is validated but NOT implemented yet and is '
  'refused with a typed invalid_parameter_value before any write, rather '
  'than guessing at sync_push''s same-date merge semantics (see that '
  'migration''s header). Sets lunarlog.bulk_import = ''on'' '
  '(transaction-local) for the duration of the write so touch_sync_signal()/'
  'enqueue_caregiver_alerts() no-op per row -- this function touches '
  'sync_signals itself, once, at the end, and never enqueues a caregiver '
  'alert for an imported row. Must complete within the caller''s ordinary '
  '8s role statement_timeout, like any other RPC -- an earlier draft''s '
  '`set local statement_timeout = ''60s''` was removed as a documented '
  'no-op (that GUC is sampled once at statement start; a mid-statement '
  '`set local` cannot retroactively widen it). Returns '
  '{inserted, updated, revived, rejected: [{row_index, reason}]}. Scoped '
  'to day_entries only (issue''s Proposed change is day_entries-first) -- '
  'an observations-shaped row is rejected as carrying unknown keys. The '
  'unique_violation backstop below is not purely theoretical: this '
  'function takes no day_entries row locks, so it can still fire on a '
  'genuine concurrent race with sync_push writing the same row(s) '
  '(unlike sync_push, which serialises per-user via '
  'pg_advisory_xact_lock), as well as on the id/source_id split '
  'resolution its own message describes -- either way, the client should '
  'retry the whole chunk.';

revoke all on function public.bulk_import_entries(uuid, jsonb, text) from public, anon;
grant execute on function public.bulk_import_entries(uuid, jsonb, text) to authenticated;
