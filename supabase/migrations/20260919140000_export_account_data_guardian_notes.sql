-- ===========================================================================
-- 20260919140000_export_account_data_guardian_notes.sql
-- Issue #870 (P2, fix(export)): guardian notes missing from export_account_data()
--
-- Re-emits public.export_account_data() with public.guardian_notes included in
-- the nested `profiles[].guardian_notes` array (mirroring day_entries).
--
-- Scoping:
--   - owned profile -> every live guardian note (deleted_at is null);
--   - shared profile -> only guardian notes the caller authored
--     (logged_by_user_id = v_uid).
--
-- Attribution:
--   logged_by_user_id and last_modified_by_user_id are retained in the server
--   export document (mirroring day_entries' logged_by_user_id /
--   last_modified_by_user_id retention on the server export).
-- ===========================================================================

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
  v_import_jobs jsonb;
  -- Issue #292: the caller's own public.settings rows.
  v_settings jsonb;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  -- ---------------------------------------------------------------------
  -- profiles + nested day_entries and guardian_notes. Owned profiles carry
  -- every live entry and guardian note; shared profiles (the caller is an
  -- accepted guardian but not the owner) carry only entries and guardian
  -- notes the caller authored.
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
        -- Issue #255: the numeric-measurement display-unit preferences.
        'bbt_unit', pr.bbt_unit,
        'weight_unit', pr.weight_unit,
        -- Issue #648: the #259 per-profile tracking-preferences document --
        -- already jsonb, selected as-is like every other profiles column.
        'tracking_preferences', pr.tracking_preferences,
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
        ), '[]'::jsonb),
        -- Issue #870: guardian_notes for this profile. Owned profiles carry
        -- every live note; shared profiles carry only notes the caller authored.
        'guardian_notes', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', gn.id,
              'local_date', gn.local_date,
              'tz', gn.tz,
              'body', gn.body,
              'created_at', gn.created_at,
              'updated_at', gn.updated_at,
              'logged_by_user_id', gn.logged_by_user_id,
              'last_modified_by_user_id', gn.last_modified_by_user_id
            )
            order by gn.local_date, gn.id
          )
          from public.guardian_notes gn
          where gn.profile_id = pr.id
            and gn.deleted_at is null
            and (pr.user_id = v_uid or gn.logged_by_user_id = v_uid)
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

  -- ---------------------------------------------------------------------
  -- Issue #167: import_jobs -- every job on a profile the caller owns,
  -- plus every job the caller personally ran (created_by = v_uid) on any
  -- profile, mirroring guardian_invitations' scoping exactly. Progress
  -- metadata only (source label, counts, status, timestamps) -- no health
  -- content.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', j.id,
        'profile_id', j.profile_id,
        'source', j.source,
        'status', j.status,
        'total_rows', j.total_rows,
        'processed_rows', j.processed_rows,
        'error_kind', j.error_kind,
        'created_by', j.created_by,
        'created_at', j.created_at,
        'completed_at', j.completed_at
      )
      order by j.created_at, j.id
    ), '[]'::jsonb
  )
  into v_import_jobs
  from public.import_jobs j
  where j.profile_id in (select id from public.profiles where user_id = v_uid)
     or j.created_by = v_uid;

  -- ---------------------------------------------------------------------
  -- Issue #292: settings -- the caller's own per-user key/value rows.
  -- server_version stays out (sync bookkeeping, matching every other
  -- table's own projection above); key/value/updated_at only.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'key', st.key,
        'value', st.value,
        'updated_at', st.updated_at
      )
      order by st.key
    ), '[]'::jsonb
  )
  into v_settings
  from public.settings st
  where st.user_id = v_uid;

  -- schema_version stays 1 deliberately: this migration's new guardian_notes
  -- projection key is purely additive to the existing `profiles[]` element.
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
    'profile_reminder_windows', v_profile_reminder_windows,
    'import_jobs', v_import_jobs,
    'settings', v_settings
  );
end;
$$;

revoke execute on function public.export_account_data() from public, anon;
grant execute on function public.export_account_data() to authenticated;
