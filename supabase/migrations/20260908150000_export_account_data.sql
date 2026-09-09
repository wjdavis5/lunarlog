-- Migration: 20260908150000_export_account_data.sql
-- Issue #248: server-side public.export_account_data() RPC for
-- right-of-access completeness. The client's JSON export
-- (lib/domain/export/account_export.dart) reads the local Drift store
-- only, so it omits everything the server holds about a household:
-- guardian memberships/roles, invitations, ownership-transfer history,
-- notification preferences, registered devices, missed-entry alert state,
-- feedback tickets, and reminder windows. This RPC assembles all of that
-- into one jsonb document; the Flutter client merges it under the local
-- document's `server` key (see AccountExportRemoteSource /
-- MergedAccountExport in lib/domain/export/), never replacing the local
-- `profiles`/`dayEntries` shape.
--
-- Scoping mirrors public.delete_account_data()'s latest definition
-- (20260906240000_account_deletion_notifications.sql) table by table,
-- widened only where the acceptance criteria explicitly call for more (an
-- owned profile's full guardian/invitation list) and never another user's
-- data: the caller's own historical rows on profiles they have since left
-- (ownership transfers they accepted, notification preferences on a
-- revoked membership) are included even though RLS now hides them, because
-- right-of-access covers them -- this function is SECURITY DEFINER and
-- does not stop at what the caller's live RLS grants would return today:
--   - day_entries:            owned profile -> every live entry;
--                              shared profile -> only entries the caller
--                              authored (logged_by_user_id = caller),
--                              exactly the acceptance criteria's "the
--                              entries they authored".
--   - profile_guardians:      owned profile -> every membership row (the
--                              owner can already read these via
--                              profile_guardians_select); shared profile ->
--                              only the caller's own row (delete_account_
--                              data()'s exact `user_id = v_uid` predicate),
--                              never a co-guardian's row on a profile the
--                              caller merely guards.
--   - guardian_invitations:   owned profile -> every invitation for it (the
--                              owner can already read these via
--                              guardian_invitations_select); shared profile
--                              -> only invitations the caller personally
--                              created (delete_account_data()'s exact
--                              `invited_by = v_uid` predicate).
--   - ownership_transfers:    the caller's own -- initiated_by = v_uid or
--                              accepted_by = v_uid, on any profile. Not
--                              touched by delete_account_data() at all (no
--                              precedent there); scoped to the caller's own
--                              involvement, mirroring every other personal
--                              table below.
--   - notification_preferences,
--     missed_entry_alert_state: the caller's own rows only
--                              (`user_id = v_uid`, any profile), the exact
--                              delete_account_data() predicate. Never
--                              widened to "every guardian's row on an owned
--                              profile" -- ordinary RLS never lets even a
--                              primary_guardian read a co-guardian's
--                              notification_preferences row (see that
--                              table's own select policy), so doing so here
--                              would export another user's data (the
--                              never-another-user's-data bound this
--                              migration's header commits to), and the
--                              issue's own Assumptions section is explicit
--                              that this is the correct default, not a gap.
--   - push_devices:           the caller's own rows only (`user_id =
--                              v_uid`); not profile-scoped at all.
--                              `token` is never included verbatim -- see
--                              the redaction note below.
--   - feedback_tickets:       the caller's own tickets (`user_id = v_uid`),
--                              each with its full reply thread (the ticket
--                              owner can already read every reply via
--                              feedback_replies_select).
--   - profile_reminder_windows: owned profiles only, the exact
--                              delete_account_data() predicate (`profile_id
--                              in (select id from profiles where user_id =
--                              v_uid)`) -- the published prediction
--                              snapshot for a shared profile is not the
--                              caller's own row and carries no per-guardian
--                              distinction to narrow to anyway.
--
-- token_hash is never selected from guardian_invitations or
-- ownership_transfers -- both are the redeemable credential itself (see
-- 20260908000000_guardian_invitations_token_hash_unreadable.sql and
-- 20260908100000_ownership_transfers_token_hash_unreadable.sql), and this
-- function runs SECURITY DEFINER so it is not even protected by those
-- migrations' column-privilege revoke; the column is simply never named in
-- any query below.
--
-- push_devices.token redaction: the raw FCM registration token is not
-- itself a secret an attacker could use against the caller (only this
-- account's own service-role push-dispatch function can send through it),
-- but it is still a durable per-device identifier with no reason to leave
-- the server in full. Redacted to its last 4 characters (`token_last4`)
-- rather than omitted outright, so the export stays useful for "which of
-- my devices is this" without handing back a value long-lived enough to
-- misuse if the export file itself is later mishandled.
--
-- day_entries / profiles tombstones (deleted_at is not null) are excluded
-- throughout, matching the local export's own semantics (tombstoned rows
-- are filtered out by the repositories it reads, per that file's header) --
-- a soft-deleted row carries no payload and is not "data about you" in the
-- right-of-access sense.
--
-- Determinism (acceptance criterion: stable key/array ordering across
-- repeated exports of unchanged data): jsonb normalises object keys by
-- length then bytes when it is parsed, so jsonb_build_object's argument
-- order has no bearing on the output's key order either way -- it is
-- already stable for free. Array order is not free the same way, so every
-- jsonb_agg below carries an explicit ORDER BY on a stable key (id, or
-- profile_id/user_id); that ORDER BY, not source-text key order, is what
-- makes two calls against unchanged data produce byte-identical jsonb.
--
-- Filename ordering (AGENTS.md Migration Flow step 7): 20260908150000 is
-- reserved for this issue; 20260908130000/20260908140000 are owned by
-- other in-flight PRs sorting between this file and main's current tip
-- (20260908121000_revoke_anon_execute_guardian_feedback_functions.sql).

create or replace function public.export_account_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_profiles jsonb;
  v_profile_guardians jsonb;
  v_guardian_invitations jsonb;
  v_ownership_transfers jsonb;
  v_notification_preferences jsonb;
  v_push_devices jsonb;
  v_missed_entry_alert_state jsonb;
  v_feedback_tickets jsonb;
  v_profile_reminder_windows jsonb;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  -- ---------------------------------------------------------------------
  -- profiles + nested day_entries. Owned profiles carry every live entry;
  -- shared profiles (the caller is an accepted guardian but not the
  -- owner) carry only entries the caller authored.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', pr.id,
        'display_name', pr.display_name,
        'is_minor', pr.is_minor,
        'mode', pr.mode,
        'sort_order', pr.sort_order,
        'archived_at', pr.archived_at,
        'created_at', pr.created_at,
        'updated_at', pr.updated_at,
        'birth_year', pr.birth_year,
        'relationship', pr.relationship,
        'transferred_at', pr.transferred_at,
        'owned', (pr.user_id = v_uid),
        'day_entries', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', de.id,
              'local_date', de.local_date,
              'tz', de.tz,
              'flow', de.flow,
              'tags', de.tags,
              'note', de.note,
              'created_at', de.created_at,
              'updated_at', de.updated_at,
              'logged_by_user_id', de.logged_by_user_id,
              'last_modified_by_user_id', de.last_modified_by_user_id
            )
            order by de.local_date, de.id
          )
          from public.day_entries de
          where de.profile_id = pr.id
            and de.deleted_at is null
            and (pr.user_id = v_uid or de.logged_by_user_id = v_uid)
        ), '[]'::jsonb)
      )
      order by pr.id
    ), '[]'::jsonb
  )
  into v_profiles
  from public.profiles pr
  where pr.deleted_at is null
    and (
      pr.user_id = v_uid
      or exists (
        select 1 from public.profile_guardians g
         where g.profile_id = pr.id
           and g.user_id = v_uid
           and g.status = 'accepted'
      )
    );

  -- ---------------------------------------------------------------------
  -- profile_guardians: every membership on a profile the caller owns,
  -- plus the caller's own membership row on any profile (owned or
  -- shared) -- never a co-guardian's row on a shared profile.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', g.id,
        'profile_id', g.profile_id,
        'user_id', g.user_id,
        'role', g.role,
        'status', g.status,
        'display_name', g.display_name,
        -- Never another user's id on a shared (non-owned) profile: the
        -- caller's own row there is the only one returned, and its
        -- invited_by names whoever invited them (often the owner) --
        -- another user's identity, out of scope per this migration's
        -- never-another-user's-data bound. Owned profiles keep it: the
        -- owner already sees every guardian's invited_by via ordinary
        -- profile_guardians_select RLS.
        'invited_by', case
          when g.profile_id in (select id from public.profiles where user_id = v_uid)
            then g.invited_by
          else null
        end,
        'created_at', g.created_at,
        'updated_at', g.updated_at,
        'revoked_at', g.revoked_at
      )
      order by g.profile_id, g.user_id
    ), '[]'::jsonb
  )
  into v_profile_guardians
  from public.profile_guardians g
  where g.profile_id in (select id from public.profiles where user_id = v_uid)
     or g.user_id = v_uid;

  -- ---------------------------------------------------------------------
  -- guardian_invitations: every invitation for a profile the caller owns,
  -- plus invitations the caller personally created for any profile (owned
  -- or shared). token_hash is never selected (see header note).
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', i.id,
        'profile_id', i.profile_id,
        'invited_by', i.invited_by,
        'role', i.role,
        'recipient_label', i.recipient_label,
        'expires_at', i.expires_at,
        'accepted_at', i.accepted_at,
        'accepted_by', i.accepted_by,
        'revoked_at', i.revoked_at,
        'created_at', i.created_at
      )
      order by i.created_at, i.id
    ), '[]'::jsonb
  )
  into v_guardian_invitations
  from public.guardian_invitations i
  where i.profile_id in (select id from public.profiles where user_id = v_uid)
     or i.invited_by = v_uid;

  -- ---------------------------------------------------------------------
  -- ownership_transfers: the caller's own involvement only (initiated or
  -- accepted), on any profile. token_hash is never selected.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', t.id,
        'profile_id', t.profile_id,
        'initiated_by', t.initiated_by,
        'parent_post_transfer_role', t.parent_post_transfer_role,
        'recipient_label', t.recipient_label,
        'expires_at', t.expires_at,
        'accepted_at', t.accepted_at,
        'accepted_by', t.accepted_by,
        'cancelled_at', t.cancelled_at,
        'created_at', t.created_at
      )
      order by t.created_at, t.id
    ), '[]'::jsonb
  )
  into v_ownership_transfers
  from public.ownership_transfers t
  where t.initiated_by = v_uid
     or t.accepted_by = v_uid;

  -- ---------------------------------------------------------------------
  -- notification_preferences: the caller's own rows only (never a
  -- co-guardian's, on any profile -- see header note).
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profile_id', np.profile_id,
        'alert_on_log', np.alert_on_log,
        'alert_on_cycle_start_only', np.alert_on_cycle_start_only,
        'alert_on_high_severity', np.alert_on_high_severity,
        'missed_entry_days', np.missed_entry_days,
        'quiet_hours_start', np.quiet_hours_start,
        'quiet_hours_end', np.quiet_hours_end,
        'time_zone', np.time_zone,
        'log_cadence', np.log_cadence,
        'cycle_start_cadence', np.cycle_start_cadence,
        'high_severity_cadence', np.high_severity_cadence,
        'digest_local_time', np.digest_local_time,
        'updated_at', np.updated_at
      )
      order by np.profile_id
    ), '[]'::jsonb
  )
  into v_notification_preferences
  from public.notification_preferences np
  where np.user_id = v_uid;

  -- ---------------------------------------------------------------------
  -- push_devices: the caller's own devices; `token` redacted to its last
  -- 4 characters (see header note) rather than included verbatim.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', pd.id,
        'platform', pd.platform,
        'token_last4', right(pd.token, 4),
        'updated_at', pd.updated_at,
        'disabled_at', pd.disabled_at
      )
      order by pd.id
    ), '[]'::jsonb
  )
  into v_push_devices
  from public.push_devices pd
  where pd.user_id = v_uid;

  -- ---------------------------------------------------------------------
  -- missed_entry_alert_state: the caller's own dedupe markers only.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profile_id', s.profile_id,
        'last_enqueued_for', s.last_enqueued_for
      )
      order by s.profile_id
    ), '[]'::jsonb
  )
  into v_missed_entry_alert_state
  from public.missed_entry_alert_state s
  where s.user_id = v_uid;

  -- ---------------------------------------------------------------------
  -- feedback_tickets + their full reply thread (the ticket owner can
  -- already read every reply on their own ticket via
  -- feedback_replies_select).
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', ft.id,
        'reply_email', ft.reply_email,
        'category', ft.category,
        'message', ft.message,
        'device_info', ft.device_info,
        'attachment_paths', ft.attachment_paths,
        'status', ft.status,
        'created_at', ft.created_at,
        'updated_at', ft.updated_at,
        'replies', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', fr.id,
              'author_type', fr.author_type,
              'message', fr.message,
              'created_at', fr.created_at
            )
            order by fr.created_at, fr.id
          )
          from public.feedback_replies fr
          where fr.ticket_id = ft.id
        ), '[]'::jsonb)
      )
      order by ft.created_at, ft.id
    ), '[]'::jsonb
  )
  into v_feedback_tickets
  from public.feedback_tickets ft
  where ft.user_id = v_uid;

  -- ---------------------------------------------------------------------
  -- profile_reminder_windows: owned profiles only.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profile_id', w.profile_id,
        'estimated_next_start', w.estimated_next_start,
        'episode_open', w.episode_open,
        'updated_at', w.updated_at
      )
      order by w.profile_id
    ), '[]'::jsonb
  )
  into v_profile_reminder_windows
  from public.profile_reminder_windows w
  where w.profile_id in (select id from public.profiles where user_id = v_uid);

  return jsonb_build_object(
    'schema_version', 1,
    'exported_at', now(),
    'profiles', v_profiles,
    'profile_guardians', v_profile_guardians,
    'guardian_invitations', v_guardian_invitations,
    'ownership_transfers', v_ownership_transfers,
    'notification_preferences', v_notification_preferences,
    'push_devices', v_push_devices,
    'missed_entry_alert_state', v_missed_entry_alert_state,
    'feedback_tickets', v_feedback_tickets,
    'profile_reminder_windows', v_profile_reminder_windows
  );
end;
$$;

comment on function public.export_account_data() is
  'Right-of-access export (Issue #248): a single jsonb document assembled '
  'from every table keyed to auth.uid(), scoped table-by-table with the '
  'same owner-vs-caregiver split public.delete_account_data() uses (see '
  'this migration''s header for the exact predicate mirrored per table). '
  'Never selects guardian_invitations.token_hash or '
  'ownership_transfers.token_hash; push_devices.token is redacted to its '
  'last 4 characters. Merged client-side under the local export document''s '
  '`server` key by lib/domain/export/account_export.dart -- never replaces '
  'the local profiles/dayEntries shape.';

revoke all on function public.export_account_data() from public, anon;
grant execute on function public.export_account_data() to authenticated;
