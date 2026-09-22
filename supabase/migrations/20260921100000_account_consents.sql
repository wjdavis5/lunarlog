-- ===========================================================================
-- 20260921100000_account_consents.sql
-- Issue #845: the minimum-age acknowledgement becomes a synced, owner-only
-- consent record.
--
-- Today the acknowledgement is a single device-local string
-- (`SettingsKeys.minimumAgeAcknowledged`), so a second signed-in device or a
-- reinstall has no record it ever happened. The owner's 2026-09-20 decision:
-- record `{acknowledged_at, app_version, policy_version}` locally AND as an
-- owner-only account row, include it in `export_account_data()` and
-- `delete_account_data()`, and re-prompt when `policy_version` changes. The
-- row also carries a `consent_via` discriminator (`self_13_plus` today;
-- `parent_invite` lands with Issue #957) so the two consent paths are one
-- coherent record.
--
-- What this migration owns:
--   1. `public.account_consents`, one row per user, owner-only RLS
--      (select/insert/update; no delete for authenticated -- the row expires
--      only with `auth.users` or through account deletion).
--   2. `public.record_minimum_age_acknowledgement(...)`, a SECURITY DEFINER
--      upsert-by-user_id RPC with a pinned search_path, EXECUTE to
--      authenticated only. Deliberately a dedicated RPC rather than a
--      `sync_push` table: the consent row is account-scoped (not
--      profile-scoped) and never rides the sync engine's payload, so
--      `sync_push` is NOT re-emitted by this migration.
--   3. `export_account_data()` re-emitted with a new top-level
--      `account_consents` key (the caller's own row only).
--   4. `delete_account_data()` re-emitted to delete the caller's own row and
--      report its count.
--
-- No RLS change to any existing table; no `sync_push` change.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. Table
-- ---------------------------------------------------------------------------

create table public.account_consents (
  user_id uuid primary key
    references auth.users (id) on delete cascade,
  consent_via text not null
    constraint account_consents_consent_via_check
    check (consent_via in ('self_13_plus', 'parent_invite')),
  acknowledged_at timestamptz not null,
  app_version text not null,
  policy_version text not null,
  updated_at timestamptz not null default now()
);

comment on table public.account_consents is
  'Issue #845: the account-level minimum-age acknowledgement, one row per '
  'auth.users. Replaces the device-local-only boolean with a synced, '
  'versioned record so a second device or a reinstall can see it, the '
  'account export includes it, account deletion removes it, and a policy '
  'change (a new policy_version) can re-prompt. consent_via discriminates '
  'the two consent paths (#957''s parent-created-account invite will write '
  '''parent_invite''). Owner-only RLS: a user reads and writes only their '
  'own row, and there is no delete policy -- the row leaves only with the '
  'account (auth.users cascade) or through delete_account_data().';

comment on column public.account_consents.consent_via is
  'Issue #845 / #957: ''self_13_plus'' (the operator acknowledged the 13+ '
  'statement during first run) or ''parent_invite'' (a guardian-created '
  'account''s invite is itself the parental-consent record).';

comment on column public.account_consents.policy_version is
  'Issue #845: the minimum-age policy version in force when the '
  'acknowledgement was made. A change to this value is what re-prompts.';

-- ---------------------------------------------------------------------------
-- 2. RLS: owner-only, select/insert/update, no delete.
-- ---------------------------------------------------------------------------

alter table public.account_consents enable row level security;
alter table public.account_consents force row level security;

create policy "account_consents_select_own" on public.account_consents
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy "account_consents_insert_own" on public.account_consents
  for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy "account_consents_update_own" on public.account_consents
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- No delete policy for authenticated (deliberate): a consent record is not
-- something a client should be able to erase at will; it goes with the
-- account. delete_account_data() removes it server-side.
revoke all on table public.account_consents from public, anon, authenticated;
grant select, insert, update on table public.account_consents to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Upsert RPC. SECURITY DEFINER because the same statement must work
--    whether the caller already has a row (update path) or not (insert
--    path); a plain client upsert would be two RLS decisions the client has
--    to get right, and the function is the single audited write path.
--    Only authenticated may execute it; anon is refused.
-- ---------------------------------------------------------------------------

create or replace function public.record_minimum_age_acknowledgement(
  p_consent_via text,
  p_app_version text,
  p_policy_version text
)
returns void
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

  if p_consent_via is null
     or p_consent_via not in ('self_13_plus', 'parent_invite') then
    raise exception 'consent_via is not a known value'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_app_version is null or p_app_version = '' then
    raise exception 'app_version is required'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_policy_version is null or p_policy_version = '' then
    raise exception 'policy_version is required'
      using errcode = 'invalid_parameter_value';
  end if;

  insert into public.account_consents
    (user_id, consent_via, acknowledged_at, app_version, policy_version, updated_at)
  values
    (v_uid, p_consent_via, now(), p_app_version, p_policy_version, now())
  on conflict (user_id) do update
    set consent_via = excluded.consent_via,
        acknowledged_at = excluded.acknowledged_at,
        app_version = excluded.app_version,
        policy_version = excluded.policy_version,
        updated_at = now();
end;
$$;

comment on function public.record_minimum_age_acknowledgement(text, text, text) is
  'Issue #845: upsert the caller''s own account_consents row (one per user, '
  'keyed by auth.uid()). SECURITY DEFINER so the insert/update is a single '
  'audited statement with the caller derived from the JWT, never a client-'
  'supplied user_id. Called by the client when a signed-in operator '
  'acknowledges the minimum-age statement, and later by #957''s '
  'parent-invite path.';

revoke execute on function
  public.record_minimum_age_acknowledgement(text, text, text)
  from public, anon;
grant execute on function
  public.record_minimum_age_acknowledgement(text, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 4. export_account_data(): re-emitted from 20260919140000's definition,
--    adding the caller's own account_consents row as a new top-level key.
--    schema_version stays 1 (an additive top-level key, the same reasoning
--    20260908190000_bulk_import.sql's header gives).
-- ---------------------------------------------------------------------------

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
  -- Issue #845: the caller's own account-level minimum-age consent row.
  v_account_consents jsonb;
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

  -- ---------------------------------------------------------------------
  -- Issue #845: the caller's own account-level minimum-age consent row
  -- (zero or one). The consent is a fact about the account, not a profile,
  -- so it is a top-level key rather than nested under `profiles`.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'user_id', ac.user_id,
        'consent_via', ac.consent_via,
        'acknowledged_at', ac.acknowledged_at,
        'app_version', ac.app_version,
        'policy_version', ac.policy_version,
        'updated_at', ac.updated_at
      )
      order by ac.user_id
    ), '[]'::jsonb
  )
  into v_account_consents
  from public.account_consents ac
  where ac.user_id = v_uid;

  -- schema_version stays 1: the new account_consents key is purely
  -- additive, the same reasoning 20260908190000_bulk_import.sql's header
  -- gives.
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
    'settings', v_settings,
    'account_consents', v_account_consents
  );
end;
$$;

revoke execute on function public.export_account_data() from public, anon;
grant execute on function public.export_account_data() to authenticated;

-- ---------------------------------------------------------------------------
-- 5. delete_account_data(): re-emitted from 20260914103000's definition,
--    adding an explicit delete of the caller's own account_consents row and
--    its count in the returned document. (The row also cascades with
--    auth.users, but the RPC's contract is to remove every caller-owned row
--    itself, and this keeps the return document complete.)
-- ---------------------------------------------------------------------------

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
  -- Issue #845
  v_account_consents_deleted bigint := 0;
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

  -- Issue #845: the caller's own minimum-age consent record.
  delete from public.account_consents
   where user_id = v_uid;
  get diagnostics v_account_consents_deleted = row_count;

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
    'prediction_connections', v_prediction_connections_deleted,
    'account_consents', v_account_consents_deleted
  );
end;
$$;

comment on function public.delete_account_data() is
  'Deletes every row the calling user (auth.uid()) owns across profiles, '
  'day_entries, observations, profile_modes and cycle_overrides, care_notes '
  'and visit_prep_items, settings, profile_guardians, guardian_invitations, '
  'ownership_transfers, prediction_connections, notification_preferences, '
  'push_devices, notification_outbox, profile_reminder_windows, '
  'missed_entry_alert_state, feedback_tickets, and account_consents (Issue '
  '#845''s minimum-age consent record), first calling '
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
