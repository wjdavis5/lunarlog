-- Migration: 20260914103000_account_deletion_cross_guardian_and_identity_fixes.sql
-- Bundled fixes for the account-deletion flow (Issues #605, #604), all
-- given this one reserved timestamp rather than one migration per issue.

-- =============================================================================
-- Part 1 - Issue #605 (LLA-051, P1): account_deletion_progress.apple_revoked_at
-- was keyed only by user_id, with no record of *which* Apple identity was
-- actually revoked.
--
-- Reproduction: delete-account revokes Apple identity A, persists the
-- marker, then auth.admin.deleteUser fails (the account survives). The
-- operator then unlinks identity A and links a different Apple identity B to
-- the same account, and retries deletion. The Edge Function's
-- appleAlreadyRevoked check (20260913021000_account_deletion_progress.sql)
-- only asked whether *a* marker existed for this user_id, never whether it
-- matched the caller's *current* Apple identity - so the retry skipped both
-- the apple_code_required precondition and the revoke call entirely, going
-- straight to auth.admin.deleteUser. Identity B's own Apple grant was never
-- revoked, even though the deletion as a whole reported success.
--
-- Fix: record the exact Apple identity id
-- (identities[provider=="apple"].id, equal to the exchanged id_token's own
-- `sub`) alongside apple_revoked_at. The Edge Function (see
-- supabase/functions/delete-account/index.ts) now treats a retry's marker as
-- satisfied only when apple_identity_id equals the caller's *current*
-- appleIdentityId - a marker left over from a since-replaced identity no
-- longer short-circuits the revoke, and the fresh identity gets its own
-- code-and-revoke pass exactly like a first attempt would.
--
-- No function is re-emitted for this part: this table has never been
-- written through an RPC (see the original migration's header for why) -
-- only the delete-account Edge Function's service-role client touches it
-- directly.
-- =============================================================================

alter table public.account_deletion_progress
  add column apple_identity_id text;

-- BLOCKING fix (found in review): a plain `add constraint ... check (...)`
-- validates every EXISTING row, not just future writes. This table's own
-- comment already says a never-retried failed attempt is harmless leftover
-- state - meaning a production row can genuinely have apple_revoked_at set
-- (a prior successful revoke) with apple_identity_id null (the column did
-- not exist before this migration, so every existing row gets null for it
-- by default). Adding the CHECK below without first neutralising such a row
-- would fail the ALTER outright on any environment that has one, aborting
-- this whole migration on deploy. Nulling apple_revoked_at on any row that
-- cannot satisfy the new rule loses nothing: under the new identity-bound
-- rule a marker with no recorded identity could never be honored by a
-- retry anyway (see the CHECK's own comment below), so this only ever
-- costs a future retry one more fresh Apple code - the same pre-#527 safe
-- default, never data loss.
update public.account_deletion_progress
   set apple_revoked_at = null
 where apple_revoked_at is not null
   and apple_identity_id is null;

-- A revoked marker without a recorded identity is meaningless - the Edge
-- Function would have nothing to compare a retry's current identity against,
-- so it could never safely be treated as "already revoked" for any identity
-- at all. Enforcing the two travel together removes any need to trust every
-- future writer to remember it.
alter table public.account_deletion_progress
  add constraint account_deletion_progress_identity_required_check
  check (apple_revoked_at is null or apple_identity_id is not null);

comment on column public.account_deletion_progress.apple_identity_id is
  'The caller''s Apple identity id (identities[provider=="apple"].id, equal '
  'to the exchanged id_token''s own `sub`) at the moment apple_revoked_at '
  'was stamped (Issue #605 / LLA-051). A retry''s marker is honored only '
  'when this still matches the account''s *current* Apple identity id - the '
  'account may have unlinked the revoked identity and linked a different '
  'one between attempts, and a stale match would let that new identity''s '
  'grant survive deletion unrevoked.';

comment on table public.account_deletion_progress is
  'Durable bookkeeping for in-app account deletion (Issue #527, tightened by '
  'Issue #605/LLA-051): apple_revoked_at/apple_identity_id are stamped '
  'together by the delete-account Edge Function the instant it confirms '
  'Apple has revoked the caller''s Sign in with Apple grant, immediately '
  'before the function''s own irreversible auth.admin.deleteUser call. A '
  'retry after a deleteUser failure checks this row first and, only when '
  'apple_revoked_at is set AND apple_identity_id still matches the caller''s '
  'current Apple identity, skips both the Apple-authorization-code '
  'precondition and the revocation call entirely - going straight back to '
  'auth.admin.deleteUser - rather than requiring a fresh one-time code to '
  'no-op-revoke a grant that is already gone. A marker for a *different* '
  '(since-replaced) Apple identity id is never honored: the account may '
  'have unlinked the revoked identity and linked a new one between '
  'attempts, and that new grant still needs its own revoke pass. Row '
  'lifetime is exactly one deletion attempt: it cascades away with the '
  '`auth.users` row on eventual success, and a never-retried failed attempt '
  'is harmless leftover state (the marker only ever narrows what a future '
  'retry does, never widens it). No authenticated policy exists at all - '
  'this is server-side bookkeeping only, written and read exclusively by '
  'the delete-account Edge Function''s service-role client, which carries '
  'BYPASSRLS.';

-- =============================================================================
-- Part 2 - Issue #604 (LLA-048, P1): import-job cleanup inside
-- delete_account_data() conflicts with cross-guardian attribution guards.
--
-- Reproduction: user A imports day_entries/observations under an
-- import_jobs row A owns; another guardian on the same (shared/transferred)
-- profile later edits one of those rows, so its last_modified_by_user_id is
-- no longer A. A then deletes their account: delete_account_data() deletes
-- `import_jobs where created_by = A`, and that table's FK from
-- day_entries.import_id/observations.import_id is `on delete set null` -
-- Postgres's own cascade UPDATE nulls import_id on the other guardian's row.
-- That implicit UPDATE runs inside the same authenticated call as A (auth.uid()
-- still resolves to A), so it hits
-- enforce_day_entry_attribution()/enforce_observation_attribution() - both
-- reject any UPDATE whose current last_modified_by_user_id is not the
-- calling user - and raises `42501 insufficient_privilege`. That exception
-- aborts delete_account_data() entirely (nothing in this SECURITY DEFINER
-- function has committed yet), so account-data deletion fails closed and a
-- bare retry hits the exact same state forever: the account can never
-- finish deleting while it owns an import job any shared/transferred entry
-- still points at.
--
-- Fix: delete_account_data() now nulls out import_id on every
-- day_entries/observations row tied to an import_jobs row it is about to
-- delete, itself, *before* deleting those import_jobs rows - so the FK's own
-- cascade UPDATE never has anything left to touch. This explicit UPDATE only
-- ever changes import_id, never last_modified_by_user_id or any other
-- attribution column, so a new transaction-local GUC
-- (lunarlog.import_cleanup, mirroring accept_ownership_transfer's own
-- lunarlog.ownership_transfer bypass, KTD4) tells both attribution guards to
-- allow exactly that column change and nothing else - narrower than
-- widening either guard's general permissiveness would be.
--
-- enforce_day_entry_attribution() is re-emitted from its
-- 20260906180000_ownership_transfer_rpcs.sql body (the KTD4
-- ownership-transfer bypass carried forward verbatim) plus this one new
-- bypass clause. enforce_observation_attribution() is re-emitted from its
-- 20260908160000_observations.sql body (which never had an
-- ownership-transfer-style bypass at all) plus the same new clause.
-- =============================================================================

create or replace function public.enforce_day_entry_attribution()
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
    -- NULL attribution (legacy rows, direct inserts) is allowed; a value
    -- other than the caller's own uid is a forgery.
    if (new.logged_by_user_id is not null
          and new.logged_by_user_id is distinct from v_uid)
       or (new.last_modified_by_user_id is not null
             and new.last_modified_by_user_id is distinct from v_uid) then
      raise exception 'attribution columns are server-authoritative'
        using errcode = 'insufficient_privilege';
    end if;
  else
    -- KTD4: ownership-transfer re-home bypass. Permitted only when the
    -- transaction-local GUC is on AND every column but user_id is
    -- unchanged - so this path can move the cascade anchor and nothing
    -- else, never attribution. See 20260906180000_ownership_transfer_rpcs.sql
    -- for the full reasoning and why `authenticated` cannot reach this GUC.
    if current_setting('lunarlog.ownership_transfer', true) = 'on'
       and (to_jsonb(new) - 'user_id') is not distinct from (to_jsonb(old) - 'user_id') then
      return new;
    end if;

    -- Issue #605/LLA-048: import-cleanup bypass, same shape as the one
    -- above - permitted only when the transaction-local GUC is on AND every
    -- column but import_id is unchanged, so this path can only null the
    -- provenance FK ahead of an import_jobs delete and can never touch
    -- attribution. Armed only by delete_account_data() below;
    -- `authenticated` cannot reach this GUC either.
    if current_setting('lunarlog.import_cleanup', true) = 'on'
       and (to_jsonb(new) - 'import_id') is not distinct from (to_jsonb(old) - 'import_id') then
      return new;
    end if;

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

comment on function public.enforce_day_entry_attribution() is
  'BEFORE INSERT/UPDATE guard on day_entries: attribution columns are
   server-authoritative for every path except accept_ownership_transfer''s
   re-home (KTD4, Issue #4, lunarlog.ownership_transfer, changes only
   user_id) and delete_account_data()''s pre-import_jobs-delete cleanup
   (Issue #605/LLA-048, lunarlog.import_cleanup, changes only import_id).
   authenticated holds no surface that can set either GUC.';

revoke execute on function public.enforce_day_entry_attribution() from public, anon;

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
    -- Issue #605/LLA-048: same import-cleanup bypass as
    -- enforce_day_entry_attribution() above - see that function's comment.
    if current_setting('lunarlog.import_cleanup', true) = 'on'
       and (to_jsonb(new) - 'import_id') is not distinct from (to_jsonb(old) - 'import_id') then
      return new;
    end if;

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

comment on function public.enforce_observation_attribution() is
  'BEFORE INSERT/UPDATE guard on observations, mirroring
   enforce_day_entry_attribution() exactly, including
   delete_account_data()''s pre-import_jobs-delete cleanup bypass
   (Issue #605/LLA-048, lunarlog.import_cleanup, changes only import_id).';

revoke execute on function public.enforce_observation_attribution() from public, anon;

-- =============================================================================
-- Part 3 - Issue #604 (LLA-047, P1): a checked visit_prep_items item whose
-- checker later deletes their own account fails the final auth.users
-- deletion.
--
-- Reproduction: a caregiver (never the profile's owner) checks a shared
-- profile's visit_prep_items row (is_checked = true,
-- checked_by_user_id = caregiver). The caregiver then deletes their own
-- account: delete_account_data() has nothing to do with this row today (it
-- lives on a profile the caregiver does not own, so the owned-profile
-- tombstone loop never reaches it), so it survives untouched. The later
-- auth.admin.deleteUser call's FK cascade
-- (checked_by_user_id references auth.users(id) on delete set null) then
-- tries to null checked_by_user_id while is_checked stays true, which
-- violates visit_prep_items_checked_stamp_check (`23514`) - a hard CHECK
-- constraint, not something any GUC or trigger can waive. That failure is
-- permanent: every retry re-enters the exact same state, since nothing
-- about the row changes on its own.
--
-- Fix: delete_account_data() now proactively unchecks (not tombstones -
-- the item and its text still belong to the family the caller is leaving)
-- every live visit_prep_items row the caller is the recorded checker of,
-- before the function returns - reverting to "unchecked" is the safe
-- default for a check no one can vouch for any more. This update sets
-- last_modified_by_user_id to the caller's own uid and clears the check
-- stamp exactly the way a normal client-initiated "uncheck" would, so it
-- satisfies enforce_prep_item_attribution() as an ordinary self-attributed
-- edit - no new bypass needed here. Items on profiles the caller DOES own
-- are unaffected by this new step: the owned-profile loop above already
-- tombstoned them (checked_by_user_id already null, deleted_at already
-- set), so this update's `deleted_at is null` filter never re-touches them.
-- =============================================================================

create or replace function public.delete_account_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_now timestamptz;
  v_profile_id text;
  v_guardian_user_ids uuid[];
  v_content_counts jsonb;
  v_day_entries_rehomed bigint := 0;
  v_day_entries_deleted bigint := 0;
  v_observations_deleted bigint := 0;
  v_profile_modes_deleted bigint := 0;
  v_care_notes_deleted bigint := 0;
  v_cycle_overrides_deleted bigint := 0;
  v_visit_prep_items_deleted bigint := 0;
  v_invitations_deleted bigint := 0;
  v_guardians_deleted bigint := 0;
  v_profiles_tombstoned bigint := 0;
  v_settings_deleted bigint := 0;
  v_notification_preferences_deleted bigint := 0;
  v_push_devices_deleted bigint := 0;
  v_notification_outbox_deleted bigint := 0;
  v_reminder_windows_deleted bigint := 0;
  v_missed_entry_alert_state_deleted bigint := 0;
  v_feedback_tickets_deleted bigint := 0;
  v_import_jobs_deleted bigint := 0;
  v_ownership_transfers_deleted bigint := 0;
  v_prediction_connections_deleted bigint := 0;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  -- Step 0 (P0 fix; #17 P1 item 5 follow-up): see
  -- public.rehome_stray_day_entries() - the delete-account Edge Function
  -- calls it a second time, standalone, immediately before
  -- auth.admin.deleteUser. Unchanged by Issue #522.
  v_day_entries_rehomed := public.rehome_stray_day_entries(v_uid);

  -- Issue #522: tombstone-then-purge every profile the caller OWNS. Must
  -- run before ANY delete below that could remove the caller's own
  -- profile_guardians row.
  v_now := clock_timestamp();
  for v_profile_id in
    select id from public.profiles where user_id = v_uid and deleted_at is null
  loop
    select array_agg(user_id) into v_guardian_user_ids
      from public.profile_guardians
     where profile_id = v_profile_id
       and status = 'accepted';

    v_content_counts := public.tombstone_profile_content(v_profile_id, v_now);
    v_day_entries_deleted := v_day_entries_deleted + (v_content_counts ->> 'day_entries')::bigint;
    v_observations_deleted := v_observations_deleted + (v_content_counts ->> 'observations')::bigint;
    v_care_notes_deleted := v_care_notes_deleted + (v_content_counts ->> 'care_notes')::bigint;
    v_visit_prep_items_deleted := v_visit_prep_items_deleted + (v_content_counts ->> 'visit_prep_items')::bigint;
    v_cycle_overrides_deleted := v_cycle_overrides_deleted + (v_content_counts ->> 'cycle_overrides')::bigint;

    update public.profiles
       set deleted_at = v_now,
           archived_at = coalesce(archived_at, v_now),
           display_name = '',
           is_minor = false,
           birth_year = null,
           relationship = null,
           mode = 'standard',
           last_period_start = null,
           typical_cycle_length_days = null,
           typical_period_length_days = null
     where id = v_profile_id;
    v_profiles_tombstoned := v_profiles_tombstoned + 1;

    insert into public.deleted_profiles (profile_id, deleted_at, guardian_user_ids)
    values (v_profile_id, v_now, coalesce(v_guardian_user_ids, '{}'));
  end loop;

  -- Issue #605/LLA-047: uncheck the caller's own checkmark on any still-live
  -- visit_prep_items row (see this migration's Part 3 header above) - items
  -- on profiles the caller owns are already tombstoned by the loop above
  -- and so no longer match `deleted_at is null`.
  update public.visit_prep_items
     set is_checked = false,
         checked_by_user_id = null,
         checked_at = null,
         updated_at = greatest(updated_at, v_now),
         last_modified_by_user_id = v_uid
   where checked_by_user_id = v_uid
     and deleted_at is null;

  -- Issue #188: profile_modes has no tombstone column and stays a hard delete,
  -- scoped to owned profiles.
  delete from public.profile_modes
   where profile_id in (
     select id from public.profiles where user_id = v_uid
   );
  get diagnostics v_profile_modes_deleted = row_count;

  -- Issue #5, U4: profile_reminder_windows for profiles the caller *owns*.
  delete from public.profile_reminder_windows
   where profile_id in (
     select id from public.profiles where user_id = v_uid
   );
  get diagnostics v_reminder_windows_deleted = row_count;

  -- Issue #5, U4: the caller's own pending caregiver alerts, on any
  -- profile (their own, or one they merely guard).
  delete from public.notification_outbox
   where recipient_user_id = v_uid;
  get diagnostics v_notification_outbox_deleted = row_count;

  -- Invitations the caller created, for any profile (their own or one they
  -- co-parent).
  delete from public.guardian_invitations
   where invited_by = v_uid;
  get diagnostics v_invitations_deleted = row_count;

  -- Issue #499: explicitly delete ownership_transfers initiated by the caller.
  delete from public.ownership_transfers
   where initiated_by = v_uid;
  get diagnostics v_ownership_transfers_deleted = row_count;

  -- Issue #499: explicitly delete prediction_connections where the caller is
  -- either the owner or the recipient.
  delete from public.prediction_connections
   where owner_user_id = v_uid
      or recipient_user_id = v_uid;
  get diagnostics v_prediction_connections_deleted = row_count;

  -- The caller's own guardian memberships. Safe only now that every owned
  -- profile has already been tombstoned above.
  delete from public.profile_guardians
   where user_id = v_uid;
  get diagnostics v_guardians_deleted = row_count;

  -- Issue #5, U4: the caller's own notification preferences, on any
  -- profile they guard.
  delete from public.notification_preferences
   where user_id = v_uid;
  get diagnostics v_notification_preferences_deleted = row_count;

  -- Issue #5, U4: the caller's own registered devices.
  delete from public.push_devices
   where user_id = v_uid;
  get diagnostics v_push_devices_deleted = row_count;

  -- Round-2 review #8: the caller's own missed-entry dedupe markers, on
  -- any profile.
  delete from public.missed_entry_alert_state
   where user_id = v_uid;
  get diagnostics v_missed_entry_alert_state_deleted = row_count;

  -- Issue #243 (D-25): the caller's own feedback tickets, explicitly.
  -- feedback_replies cascades from feedback_tickets.
  delete from public.feedback_tickets
   where user_id = v_uid;
  get diagnostics v_feedback_tickets_deleted = row_count;

  -- Issue #605/LLA-048: null the provenance FK on every day_entries/
  -- observations row tied to an import_jobs row about to be deleted below,
  -- ourselves, before deleting it - see this migration's Part 2 header
  -- above for why relying on the FK's own ON DELETE SET NULL cascade fails
  -- closed here whenever such a row was last modified by a different
  -- guardian.
  perform set_config('lunarlog.import_cleanup', 'on', true);

  update public.day_entries
     set import_id = null
   where import_id in (select id from public.import_jobs where created_by = v_uid);

  update public.observations
     set import_id = null
   where import_id in (select id from public.import_jobs where created_by = v_uid);

  -- Issue #167: the caller's own import jobs, on any profile.
  delete from public.import_jobs
   where created_by = v_uid;
  get diagnostics v_import_jobs_deleted = row_count;

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
    'profiles', v_profiles_tombstoned,
    'settings', v_settings_deleted,
    'notification_preferences', v_notification_preferences_deleted,
    'push_devices', v_push_devices_deleted,
    'notification_outbox', v_notification_outbox_deleted,
    'profile_reminder_windows', v_reminder_windows_deleted,
    'missed_entry_alert_state', v_missed_entry_alert_state_deleted,
    'feedback_tickets', v_feedback_tickets_deleted,
    'import_jobs', v_import_jobs_deleted,
    'ownership_transfers', v_ownership_transfers_deleted,
    'prediction_connections', v_prediction_connections_deleted
  );
end;
$$;

comment on function public.delete_account_data() is
  'Deletes every row the calling user (auth.uid()) owns across profiles, '
  'day_entries, observations, profile_modes and cycle_overrides, care_notes '
  'and visit_prep_items, settings, profile_guardians, guardian_invitations, '
  'ownership_transfers, prediction_connections, notification_preferences, '
  'push_devices, notification_outbox, profile_reminder_windows, '
  'missed_entry_alert_state, and feedback_tickets, first calling '
  'public.rehome_stray_day_entries(auth.uid()). Issue #522: day_entries, '
  'observations, care_notes, visit_prep_items, and cycle_overrides on every '
  'OWNED profile are now tombstoned rather than hard-deleted, and each owned '
  'profile itself is tombstoned and logged in public.deleted_profiles instead '
  'of physically deleted. Issue #499: explicitly deletes ownership_transfers '
  'initiated by the caller, and prediction_connections where the caller is '
  'owner or recipient, returning both counts. Issue #605/LLA-047: also '
  'unchecks any still-live visit_prep_items row the caller is the recorded '
  'checker of (on a profile they do not own), so the later '
  'auth.admin.deleteUser FK cascade never has a checked-but-uncheckable row '
  'left to trip visit_prep_items_checked_stamp_check. Issue #605/LLA-048: '
  'also nulls day_entries.import_id/observations.import_id for rows tied to '
  'an import_jobs row it is about to delete (under the transaction-local '
  'lunarlog.import_cleanup bypass), so that delete never trips '
  'enforce_day_entry_attribution()/enforce_observation_attribution() on a '
  'row a different guardian has since edited.';

revoke all on function public.delete_account_data() from public, anon;
grant execute on function public.delete_account_data() to authenticated;
