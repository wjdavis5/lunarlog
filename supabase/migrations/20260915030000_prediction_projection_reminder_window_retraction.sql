-- Migration: 20260915030000_prediction_projection_reminder_window_retraction.sql
--
-- Issue LLA-061 (P2): suppression leaves previously published projections
-- and reminder windows active.
--
-- Neither `public.prediction_projections` nor `public.profile_reminder_
-- windows` is invalidated when a sharer's LOCAL prediction transitions to
-- a suppressed state (Pregnancy/Postpartum/Perimenopause life-stage mode,
-- a continuous birth-control method, or predictions turned off in
-- settings): the prediction algorithm itself is never recomputed
-- server-side (`prediction_projections`' own table comment), so there is
-- no server-side signal that a suppression happened at all -- the
-- existing garbage-collection trigger
-- (`prediction_connections_projection_gc`, 20260909200000) only fires on
-- `prediction_connections` mutations (revoke, cascade deletes), and the
-- minor gate (20260913019000) only re-checks `is_minor`/`birth_year`.
-- Neither covers a life-stage-mode or continuous-method switch, because
-- neither is visible to any RPC unless the client tells it.
--
-- Fix: `LocalPredictionProjectionPublisher`/`ReminderWindowPublisher`
-- (lib/data/sharing/prediction_projection_publisher.dart,
-- lib/data/notifications/reminder_window_publisher.dart) now call these
-- two new RPCs the moment they observe a suppression transition, so the
-- previously published snapshot/window stops being able to serve a stale
-- phase or feed scan_missed_entry_reminders() past that point. Both RPCs
-- are idempotent (retracting an already-absent row is a no-op) and
-- authorize the caller exactly like their upsert sibling:
--
--   - retract_prediction_projection(): SECURITY DEFINER, guardian-role
--     checked (mirrors upsert_prediction_projection, re-emitted verbatim
--     below from its current 20260913019000 body -- untouched, cited only
--     so this migration's diff shows the sibling it mirrors).
--   - retract_reminder_window(): SECURITY INVOKER (mirrors
--     upsert_reminder_window's posture -- RLS decides), which needs a new
--     DELETE policy on profile_reminder_windows since only SELECT/INSERT/
--     UPDATE existed before now.
--
-- Coverage: supabase/tests/prediction_connection_test.sql (retract_
-- prediction_projection) and supabase/tests/missed_entry_scan_test.sql
-- (retract_reminder_window).

begin;

-- ---------------------------------------------------------------------------
-- 1. profile_reminder_windows: a DELETE policy, mirroring the existing
--    INSERT/UPDATE policies exactly (same guardian-roles check).
-- ---------------------------------------------------------------------------

create policy "profile_reminder_windows_delete" on public.profile_reminder_windows
  for delete to authenticated
  using (
    public.is_guardian_with_roles(
      profile_id, (select auth.uid()),
      array['primary_guardian', 'co_parent', 'caregiver']
    )
  );

-- The table's original grant (20260906230000) only covers select/insert/
-- update -- a DELETE policy alone is not enough, since RLS only narrows
-- rows an already-granted operation can see; Postgres refuses DELETE
-- outright without the table-level privilege too.
grant delete on table public.profile_reminder_windows to authenticated;

-- ---------------------------------------------------------------------------
-- 2. retract_reminder_window: SECURITY INVOKER, same posture as
--    upsert_reminder_window -- the caller's own RLS grant (the policy
--    above) is what allows or refuses the delete.
-- ---------------------------------------------------------------------------

create or replace function public.retract_reminder_window(
  p_profile_id text
) returns void
language sql
security invoker
set search_path = ''
as $$
  delete from public.profile_reminder_windows
   where profile_id = p_profile_id;
$$;

comment on function public.retract_reminder_window(text) is
  'Issue LLA-061: deletes profile_id''s published reminder window, if '
  'any (idempotent). SECURITY INVOKER -- the profile_reminder_windows_ '
  'delete policy is what allows or refuses it. Called the moment a '
  'client observes its local prediction move to a suppressed state '
  '(life-stage mode, a continuous birth-control method, or predictions '
  'turned off), so scan_missed_entry_reminders()''s inner join on this '
  'table can never keep reading a stale window past that point.';

revoke all on function public.retract_reminder_window(text) from public, anon;
grant execute on function public.retract_reminder_window(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. retract_prediction_projection: SECURITY DEFINER, same posture and
--    guardian-role check as upsert_prediction_projection (current body,
--    20260913019000) -- prediction_projections carries no policies at
--    all (the notification_outbox posture), so only a SECURITY DEFINER
--    RPC that re-imposes the check itself can reach it.
-- ---------------------------------------------------------------------------

create or replace function public.retract_prediction_projection(
  p_profile_id text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  if not public.is_guardian_with_roles(
       p_profile_id, v_uid,
       array['primary_guardian', 'co_parent', 'caregiver']) then
    raise exception 'only an accepted guardian of this profile can retract its prediction projection'
      using errcode = 'insufficient_privilege';
  end if;

  delete from public.prediction_projections
   where profile_id = p_profile_id;
end;
$$;

comment on function public.retract_prediction_projection(text) is
  'Issue LLA-061: deletes profile_id''s stored prediction projection, if '
  'any (idempotent). SECURITY DEFINER with the same guardian-role check '
  'as upsert_prediction_projection, since prediction_projections carries '
  'no policies of its own. Called the moment a client observes its local '
  'prediction move to a suppressed state -- unlike revocation (handled '
  'by prediction_connections_projection_gc) or the minor gate (re-'
  'checked by upsert/get), nothing server-side notices a life-stage-mode '
  'or continuous-method switch on its own, because the prediction '
  'algorithm itself is never recomputed server-side.';

revoke all on function public.retract_prediction_projection(text) from public, anon;
grant execute on function public.retract_prediction_projection(text) to authenticated;

commit;
