-- Migration: 20260913012000_cascade_tombstone_lww_guard.sql
--
-- Issue #524 (P1): the day-entry tombstone cascade rewinds observations'
-- LWW clock, letting a tombstoned observation resurrect live under a
-- deleted day entry.
--
-- cascade_day_entry_tombstone_to_observations()
-- (20260911180000_cascade_day_entry_tombstone.sql:33-47) stamps
-- `updated_at = new.updated_at` - the DAY ENTRY's client-supplied timestamp
-- - onto every live child observation, unconditionally. sync_push's
-- observation branch resolves strictly by `v_updated_at >
-- v_stored_obs.updated_at` (20260912000000:883-886), so if the day entry's
-- own updated_at is OLDER than an observation's current updated_at (e.g. a
-- device offline since before the observation's last edit tombstones the
-- whole day), this cascade LOWERS the observation's stored updated_at.
-- Any later push of the observation at its true, newer timestamp (which is
-- now > the rewound stored value) is then accepted - a live observation
-- reappears attached to a day entry that is still tombstoned, a state no
-- CHECK forbids and nothing else repairs.
--
-- Fix (per the issue): `greatest()`-guard both stamps so the tombstone
-- strictly dominates - it can only move an observation's clock forward,
-- never backward. Since `new.deleted_at` will always be a value the
-- cascade WANTS the row to end up at least as new as, and the same is true
-- of `new.updated_at`, both use the SAME floor (the observation's own
-- pre-cascade updated_at) so the two stamps never diverge from each other
-- (deleted_at and updated_at are otherwise expected to match on every other
-- tombstone-producing path in this schema - sync_push's own branches always
-- set them equal for a tombstone).
--
-- Companion guard: this migration only fixes the cascade's LWW-rewind bug.
-- The issue's second half - "add a CHECK or sync_push guard rejecting a
-- live observation whose day_entry_id points at a tombstoned day entry" -
-- lands in 20260913019000_sync_push_hardening.sql (the consolidated
-- sync_push re-emission), since it needs sync_push's own row-fetch/role
-- lookups, not a standalone CHECK (a CHECK can't see the sibling
-- day_entries row for a cross-table condition without becoming a
-- constraint trigger, which would duplicate work sync_push already does
-- when it looks up v_day_entry_profile_id).
--
-- No table, policy, grant, or column change - this migration only
-- re-creates the trigger function body (same trigger wiring as
-- 20260911180000, untouched).
--
-- Coverage: supabase/tests/observations_test.sql (new behavioural cases -
-- the existing coverage was one assertion that the trigger merely exists).

create or replace function public.cascade_day_entry_tombstone_to_observations()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  -- Issue #524: greatest()-guarded so a day entry's OWN (possibly older,
  -- client-supplied) tombstone timestamp can never rewind a child
  -- observation's updated_at backward. `updated_at` (bare, unqualified) in
  -- the SET clause below refers to each observations row's CURRENT
  -- (pre-update) value, per ordinary UPDATE semantics - the same pattern
  -- sync_push itself relies on nowhere explicitly, but is standard SQL.
  update public.observations
     set deleted_at = greatest(new.deleted_at, updated_at),
         updated_at = greatest(new.updated_at, updated_at),
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
  'Issue #470: cascades a day_entries tombstone to live child observations, '
  'clearing payload and triggering server_version / sync_signals. Issue '
  '#524: deleted_at/updated_at are both greatest()-guarded against each '
  'affected observation''s own current updated_at, so a day entry whose '
  'own (client-supplied) tombstone timestamp is OLDER than a child '
  'observation''s last edit can never rewind that observation''s LWW clock '
  'backward - which would otherwise let a later push of the observation''s '
  'true (newer) timestamp win acceptance and resurrect it live under a '
  'still-tombstoned day entry.';

revoke execute on function public.cascade_day_entry_tombstone_to_observations() from public, anon;
