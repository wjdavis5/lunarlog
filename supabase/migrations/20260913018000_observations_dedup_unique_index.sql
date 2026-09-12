-- Migration: 20260913018000_observations_dedup_unique_index.sql
--
-- Issue #565 (P2): observations' same-date (category, code) dedup
-- (20260912000000_health_sync_export_marker.sql:923-984) is advisory-only -
-- a per-row `select ... for update` inside sync_push, backed by no unique
-- index. Two guardians holding different advisory locks (issue #14's
-- per-USER lock, not per-profile - see 20260913015000_sync_watermark.sql's
-- header for the same limitation applied to server_version) can each find
-- no live sibling and both insert, creating a permanent live duplicate that
-- sync_push's own dedup never revisits (it only fires again on a NEW
-- collision, not an already-inserted pair). day_entries already has a real
-- unique index behind its own same-date resolver
-- (`day_entries_live_profile_date_uq`); observations never got the
-- equivalent.
--
-- Fix (per the issue), with one deviation: the issue's suggested
-- `create unique index concurrently` cannot run inside a migration
-- transaction (same constraint #525's server_version indexes hit - see
-- that migration's header) - and this codebase's own precedent for a
-- unique index on this exact table
-- (`day_entries_live_profile_date_uq`, 20260904010000_multi_guardian_schema.sql;
-- `observations_profile_source_source_id_uq`, 20260908170000_import_provenance.sql)
-- already uses a plain (non-concurrent) `create unique index` inside its
-- migration, so this follows the same established pattern rather than
-- inventing a new one.
--
-- Backfill first (required before a VALIDATING unique index can be added
-- at all - a duplicate-violating row would make the `create unique index`
-- statement itself fail): for every existing group of live rows sharing
-- (profile_id, local_date, category, code), keep the one with the
-- greatest updated_at (ulid tiebreak, matching sync_push's own head-to-head
-- resolution order exactly - `updated_at desc, id collate "C" asc`) and
-- tombstone every other row in the group, payload-free, matching
-- observations_tombstone_payload_check and the exact clearing sync_push's
-- own collision-loser branch uses (source/source_id/import_id survive,
-- per issue #159's precedent - see that migration's header).

with ranked as (
  select id,
         row_number() over (
           partition by profile_id, local_date, category, code
           order by updated_at desc, (id collate "C") asc
         ) as rn
    from public.observations
   where deleted_at is null
     and code is not null
)
update public.observations o
   set deleted_at = o.updated_at,
       category = null,
       code = null,
       value_num = null,
       value_text = null,
       unit = null,
       intensity = null,
       excluded = false,
       raw = null,
       observed_at = null
  from ranked r
 where o.id = r.id
   and r.rn > 1;

create unique index observations_live_profile_date_category_code_uq
  on public.observations (profile_id, local_date, category, code)
  where deleted_at is null and code is not null;

comment on index public.observations_live_profile_date_category_code_uq is
  'Issue #565: structural backstop for the same-date (category, code) dedup '
  'sync_push''s own head-to-head resolution performs - closes the race where '
  'two guardians, holding different per-user advisory locks, each find no '
  'live sibling and both insert. A concurrent second insert that would '
  'violate this index surfaces as a 23505 unique_violation, which '
  'sync_push''s existing per-row `when others` exception handler already '
  'turns into a rejected row the client retries - no sync_push code change '
  'needed for this part.';
