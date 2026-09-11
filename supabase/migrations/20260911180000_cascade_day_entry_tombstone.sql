-- Migration: 20260911180000_cascade_day_entry_tombstone.sql
-- Issue #470: Cascade tombstoning to observations when soft-deleting a day entry.
--
-- Background:
-- When a day entry is soft-deleted (deleted_at is not null), its attached
-- child rows in public.observations must also be soft-deleted (tombstoned).
-- Because lunarlog uses soft deletes (deleted_at timestamps) rather than
-- hard SQL DELETEs, the table-level ON DELETE CASCADE foreign key constraint
-- does not fire.
--
-- This trigger ensures that whenever a day_entries row is tombstoned
-- (inserted or updated with deleted_at IS NOT NULL), any live observations
-- attached to that day_entry_id are atomically tombstoned:
-- - deleted_at is stamped with new.deleted_at
-- - updated_at is stamped with new.updated_at
-- - all payload fields are cleared (category, code, value_num, value_text,
--   unit, intensity, excluded = false, raw, observed_at) matching
--   observations_tombstone_payload_check.
-- - source, source_id, import_id survive (Issue #159 precedent).
-- - last_modified_by_user_id is stamped with auth.uid() or caller.
-- - downstream triggers (observations_set_server_version,
--   observations_after_change_signal) fire normally to advance sync.

create or replace function public.cascade_day_entry_tombstone_to_observations()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  update public.observations
     set deleted_at = new.deleted_at,
         updated_at = new.updated_at,
         category = null,
         code = null,
         value_num = null,
         value_text = null,
         unit = null,
         intensity = null,
         excluded = false,
         raw = null,
         observed_at = null,
         last_modified_by_user_id = coalesce(v_uid, new.last_modified_by_user_id)
   where day_entry_id = new.id
     and deleted_at is null;

  return new;
end;
$$;

comment on function public.cascade_day_entry_tombstone_to_observations() is
  'Issue #470: Cascades day_entries tombstone to live child observations, clearing payload and triggering server_version / sync_signals.';

revoke execute on function public.cascade_day_entry_tombstone_to_observations() from public, anon;

drop trigger if exists day_entries_after_tombstone_cascade_observations on public.day_entries;

create trigger day_entries_after_tombstone_cascade_observations
  after insert or update on public.day_entries
  for each row
  when (new.deleted_at is not null)
  execute function public.cascade_day_entry_tombstone_to_observations();
