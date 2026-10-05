import { useMemo, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router';

import { useT } from '../i18n/t';
import {
  createProfile,
  deleteProfile,
  setProfileArchived,
  updateProfile,
  validateProfileFields,
  MAX_DISPLAY_NAME_LENGTH,
  MIN_BIRTH_YEAR,
  MAX_BIRTH_YEAR,
  type ProfileFields,
} from '../lib/profiles/profile-actions';
import {
  fetchMinimumAgeAcknowledgement,
  needsMinimumAgeAcknowledgement,
} from '../lib/profiles/consent';
import {
  callerRoleFor,
  canEditProfile,
  profileListsFromSyncedData,
  type ProfileLists,
} from '../lib/profiles/profile-views';
import {
  SYNCED_DATA_QUERY_KEY,
  useCurrentUserId,
  useHasSyncSession,
  useSyncedData,
} from '../lib/queries';
import type { ProfileRow } from '../lib/schemas';
import type { GuardianRole } from '../lib/roles';
import { emptySyncedData, type SyncedData } from '../lib/domain';
import { getSupabaseClient } from '../lib/supabase';
import { SignedOutHome } from './SignedOutHome';

/**
 * The web profiles page (issue #1253): the profile picker's management
 * half — list, create, edit, archive/unarchive, and the two-step
 * permanent delete, over the same write paths the app uses (`sync_push`
 * for metadata and the archive stamp, `delete_profile_data` for the
 * purge). Creating the first profile records the minimum-age
 * acknowledgement exactly like `first_run_screen.dart` (issue #845): the
 * account's own `account_consents` row decides whether the statement
 * shows, and the write is best-effort after the creation succeeds.
 *
 * What the UI offers keys on the caller's guardian role (edit: primary/
 * co-parent; archive, unarchive and delete: primary only) — the server
 * re-authorises every change, exactly as the app's client-side mirror
 * does. An archived profile is read-only until it is unarchived, as it is
 * in the app.
 */

const kLocale = 'en';

const kCreatedDateFormat = new Intl.DateTimeFormat(kLocale, {
  dateStyle: 'medium',
  timeZone: 'UTC',
});

type RelationshipValue = '' | 'self' | 'daughter' | 'son' | 'child' | 'partner' | 'other';

const RELATIONSHIPS: Exclude<RelationshipValue, ''>[] = [
  'self',
  'daughter',
  'son',
  'child',
  'partner',
  'other',
];

function relationshipLabelId(value: Exclude<RelationshipValue, ''>) {
  switch (value) {
    case 'self':
      return 'webProfilesRelationshipSelf' as const;
    case 'daughter':
      return 'webProfilesRelationshipDaughter' as const;
    case 'son':
      return 'webProfilesRelationshipSon' as const;
    case 'child':
      return 'webProfilesRelationshipChild' as const;
    case 'partner':
      return 'webProfilesRelationshipPartner' as const;
    case 'other':
      return 'webProfilesRelationshipOther' as const;
  }
}

interface FormState {
  displayName: string;
  isMinor: boolean;
  birthYear: string;
  relationship: RelationshipValue;
  mode: 'standard' | 'teen';
  /** `undefined` = untouched = preserve the stored tri-state (#853). */
  irregularFraming?: boolean;
}

function formStateFor(profile: ProfileRow | null): FormState {
  if (profile === null) {
    return {
      displayName: '',
      isMinor: false,
      birthYear: '',
      relationship: '',
      mode: 'standard',
    };
  }
  return {
    displayName: profile.display_name,
    isMinor: profile.is_minor,
    birthYear: profile.birth_year !== null ? String(profile.birth_year) : '',
    relationship: (profile.relationship ?? '') as RelationshipValue,
    mode: profile.mode === 'teen' ? 'teen' : 'standard',
    irregularFraming: profile.irregular_framing ?? undefined,
  };
}

function fieldsFromForm(form: FormState): ProfileFields {
  const parsedYear = form.birthYear.trim() === '' ? null : Number(form.birthYear);
  return {
    displayName: form.displayName,
    isMinor: form.isMinor,
    birthYear: parsedYear !== null && Number.isFinite(parsedYear) ? parsedYear : null,
    relationship: form.relationship === '' ? null : form.relationship,
    mode: form.mode,
    irregularFraming: form.irregularFraming,
  };
}

/** The configure-build seam the mutation bodies share. */
function requireClient(): NonNullable<ReturnType<typeof getSupabaseClient>> {
  const client = getSupabaseClient();
  if (client === null) {
    throw new Error('Supabase is not configured in this build');
  }
  return client;
}

export function ProfilesPage() {
  const t = useT();
  const queryClient = useQueryClient();
  const signedIn = useHasSyncSession();
  const synced = useSyncedData();
  const me = useCurrentUserId(signedIn).data ?? null;
  const data: SyncedData | undefined = synced.data;

  const [creating, setCreating] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [form, setForm] = useState<FormState>(formStateFor(null));
  const [formError, setFormError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [confirmingArchiveId, setConfirmingArchiveId] = useState<string | null>(null);
  const [confirmingDeleteId, setConfirmingDeleteId] = useState<string | null>(null);
  const [deleteStep2, setDeleteStep2] = useState(false);
  // The account's acknowledgement record; fetched once per page mount,
  // when a create form first opens.
  const [consentRecord, setConsentRecord] = useState<Awaited<
    ReturnType<typeof fetchMinimumAgeAcknowledgement>
  > | null>(null);
  const [consentChecked, setConsentChecked] = useState(false);
  const [ageAcked, setAgeAcked] = useState(false);
  const [ageAckError, setAgeAckError] = useState(false);

  const lists = useMemo(
    () => profileListsFromSyncedData(data ?? emptySyncedData(), me),
    [data, me],
  );
  const roles = useMemo(() => {
    const map = new Map<string, GuardianRole | null>();
    if (data === undefined) return map;
    for (const profile of data.profiles) {
      map.set(profile.id, callerRoleFor(data, profile.id, me));
    }
    return map;
  }, [data, me]);

  const profileCount = lists.mine.length + lists.shared.length + lists.archived.length;

  const openCreate = () => {
    setNotice(null);
    setFormError(null);
    setForm(formStateFor(null));
    setEditingId(null);
    setCreating(true);
    setAgeAckError(false);
    if (!consentChecked) {
      const client = getSupabaseClient();
      if (client !== null) {
        void fetchMinimumAgeAcknowledgement(client).then((record) => {
          setConsentRecord(record);
          setAgeAcked(!needsMinimumAgeAcknowledgement(record));
          setConsentChecked(true);
        });
      }
    }
  };

  const openEdit = (profile: ProfileRow) => {
    setNotice(null);
    setFormError(null);
    setForm(formStateFor(profile));
    setCreating(false);
    setEditingId(profile.id);
  };

  const closeForm = () => {
    setCreating(false);
    setEditingId(null);
    setFormError(null);
    setAgeAckError(false);
  };

  const invalidate = async () => {
    await queryClient.invalidateQueries({ queryKey: SYNCED_DATA_QUERY_KEY });
  };

  const createMutation = useMutation({
    mutationFn: async (): Promise<
      | { ok: true }
      | { ok: false; reason: 'validation'; violation: string }
      | { ok: false; reason: 'ageAck' }
    > => {
      const client = requireClient();
      const fields = fieldsFromForm(form);
      const validation = validateProfileFields(fields);
      if (!validation.valid) {
        return { ok: false, reason: 'validation', violation: validation.violation };
      }
      const ackNeeded = needsMinimumAgeAcknowledgement(consentRecord);
      if (ackNeeded && !ageAcked) {
        setAgeAckError(true);
        return { ok: false, reason: 'ageAck' };
      }
      await createProfile(client, {
        fields,
        existingSortOrders: [...lists.mine, ...lists.shared].map((p) => p.sort_order),
        recordMinimumAgeAck: ackNeeded,
      });
      return { ok: true };
    },
    onSuccess: async (result) => {
      if (!result.ok) {
        if (result.reason === 'validation') setFormError(result.violation);
        return;
      }
      await invalidate();
      closeForm();
    },
    onError: () => setFormError('actionFailed'),
  });

  const updateMutation = useMutation({
    mutationFn: async (
      profile: ProfileRow,
    ): Promise<{ ok: true } | { ok: false; reason: 'validation'; violation: string }> => {
      const client = requireClient();
      const fields = fieldsFromForm(form);
      const validation = validateProfileFields(fields);
      if (!validation.valid) {
        return { ok: false, reason: 'validation', violation: validation.violation };
      }
      await updateProfile(client, profile, fields);
      return { ok: true };
    },
    onSuccess: async (result) => {
      if (!result.ok) {
        setFormError(result.violation);
        return;
      }
      await invalidate();
      closeForm();
    },
    onError: () => setFormError('actionFailed'),
  });

  const archiveMutation = useMutation({
    mutationFn: async ({ profile, archived }: { profile: ProfileRow; archived: boolean }) => {
      await setProfileArchived(requireClient(), profile, archived);
    },
    onSuccess: async () => {
      setConfirmingArchiveId(null);
      await invalidate();
    },
  });

  const deleteMutation = useMutation({
    mutationFn: async (profile: ProfileRow) => {
      await deleteProfile(requireClient(), profile.id);
    },
    onSuccess: async () => {
      setConfirmingDeleteId(null);
      setDeleteStep2(false);
      setNotice('deleted');
      await invalidate();
    },
  });

  if (!signedIn) return <SignedOutHome />;

  const editing = editingId !== null ? findProfile(lists, editingId) : null;
  const showForm = creating || editing !== null;
  const formTitle = creating ? t('profileDialogAddTitle') : t('webProfilesEditTitle');
  const busy =
    createMutation.isPending ||
    updateMutation.isPending ||
    archiveMutation.isPending ||
    deleteMutation.isPending;
  const formViolation = formError !== null && formError !== 'actionFailed' ? formError : null;
  const ackNeeded = needsMinimumAgeAcknowledgement(consentRecord);

  const sectionProps = {
    lists,
    roles,
    onEdit: openEdit,
    confirmingArchiveId,
    setConfirmingArchiveId,
    confirmingDeleteId,
    setConfirmingDeleteId,
    deleteStep2,
    setDeleteStep2,
    archiveMutation,
    deleteMutation,
  };

  return (
    <main className="page">
      <h1 className="display">{t('profilePickerTitle')}</h1>

      {notice === 'deleted' ? (
        <p className="card-body" role="status">
          {t('webProfilesDeleted')}
        </p>
      ) : null}

      {showForm && (
        <section className="card" aria-labelledby="profile-form-title">
          <h2 className="card-title" id="profile-form-title">
            {formTitle}
          </h2>
          <form
            onSubmit={(event) => {
              event.preventDefault();
              if (busy) return;
              if (creating) createMutation.mutate();
              else if (editing !== null) updateMutation.mutate(editing);
            }}
          >
            <div className="form-row">
              <label htmlFor="profile-name">{t('firstRunNameLabel')}</label>
              <input
                id="profile-name"
                value={form.displayName}
                maxLength={MAX_DISPLAY_NAME_LENGTH}
                onChange={(event) => setForm({ ...form, displayName: event.target.value })}
              />
              {formViolation === 'nameEmpty' ? (
                <p className="form-error" role="alert">
                  {t('profileDialogNameEmpty')}
                </p>
              ) : null}
              {formViolation === 'nameTooLong' ? (
                <p className="form-error" role="alert">
                  {t('profileDialogNameTooLong', { maxLength: MAX_DISPLAY_NAME_LENGTH })}
                </p>
              ) : null}
            </div>

            {creating ? (
              <div className="form-row">
                <label htmlFor="profile-minor">
                  <input
                    id="profile-minor"
                    type="checkbox"
                    checked={form.isMinor}
                    onChange={(event) => setForm({ ...form, isMinor: event.target.checked })}
                  />{' '}
                  {t('firstRunMinorLabel')}
                </label>
                <p className="form-hint">{t('firstRunMinorHint')}</p>
              </div>
            ) : null}

            <div className="form-row">
              <label htmlFor="profile-birth-year">{t('profileDialogBirthYearLabel')}</label>
              <input
                id="profile-birth-year"
                type="number"
                inputMode="numeric"
                min={MIN_BIRTH_YEAR}
                max={MAX_BIRTH_YEAR}
                value={form.birthYear}
                onChange={(event) => setForm({ ...form, birthYear: event.target.value })}
              />
              {formViolation === 'birthYearInvalid' ? (
                <p className="form-error" role="alert">
                  {t('profileDialogBirthYearInvalid')}
                </p>
              ) : null}
              {formViolation === 'birthYearOutOfRange' ? (
                <p className="form-error" role="alert">
                  {t('profileDialogBirthYearOutOfRange', {
                    minYear: MIN_BIRTH_YEAR,
                    maxYear: MAX_BIRTH_YEAR,
                  })}
                </p>
              ) : null}
            </div>

            <div className="form-row">
              <label htmlFor="profile-relationship">{t('firstRunRelationshipLabel')}</label>
              <select
                id="profile-relationship"
                value={form.relationship}
                onChange={(event) =>
                  setForm({ ...form, relationship: event.target.value as RelationshipValue })
                }
              >
                <option value="">{t('profileDialogRelationshipNone')}</option>
                {RELATIONSHIPS.map((value) => (
                  <option key={value} value={value}>
                    {t(relationshipLabelId(value))}
                  </option>
                ))}
              </select>
            </div>

            <div className="form-row">
              <label htmlFor="profile-care-mode">{t('firstRunCareModeLabel')}</label>
              <select
                id="profile-care-mode"
                value={form.mode}
                onChange={(event) =>
                  setForm({ ...form, mode: event.target.value as FormState['mode'] })
                }
              >
                <option value="standard">{t('webProfilesModeStandard')}</option>
                <option value="teen">{t('webProfilesModeTeen')}</option>
              </select>
            </div>

            {editing !== null ? (
              <div className="form-row">
                <label htmlFor="profile-irregular">
                  <input
                    id="profile-irregular"
                    type="checkbox"
                    checked={form.irregularFraming ?? form.mode === 'teen'}
                    onChange={(event) =>
                      setForm({ ...form, irregularFraming: event.target.checked })
                    }
                  />{' '}
                  {t('profileIrregularFramingLabel')}
                </label>
                <p className="form-hint">{t('profileIrregularFramingHint')}</p>
              </div>
            ) : null}

            {creating && ackNeeded ? (
              <div className="form-row">
                <label htmlFor="profile-age-ack">
                  <input
                    id="profile-age-ack"
                    type="checkbox"
                    checked={ageAcked}
                    onChange={(event) => {
                      setAgeAcked(event.target.checked);
                      if (event.target.checked) setAgeAckError(false);
                    }}
                  />{' '}
                  {t('firstRunAgeAcknowledgementLabel')}
                </label>
                <p className="form-hint">
                  {ageAckError
                    ? t('firstRunAgeAcknowledgementRequired')
                    : t('firstRunAgeAcknowledgementHint')}
                </p>
              </div>
            ) : null}

            {formError === 'actionFailed' ? (
              <p className="form-error" role="alert">
                {t('webProfilesActionFailed')}
              </p>
            ) : null}

            <div className="actions">
              <button type="submit" className="btn btn-primary" disabled={busy}>
                {busy
                  ? t('webProfilesSaving')
                  : creating
                    ? t('profileDialogCreate')
                    : t('profileDialogSave')}
              </button>
              <button type="button" className="btn" onClick={closeForm}>
                {t('profileDialogCancel')}
              </button>
            </div>
          </form>
        </section>
      )}

      {synced.isError ? (
        <section className="card">
          <p className="card-body">{t('webProfilesLoadFailed')}</p>
        </section>
      ) : null}

      {!showForm && !synced.isError ? (
        <div className="actions">
          <button type="button" className="btn btn-primary" onClick={openCreate}>
            {t('profilePickerAddProfileTooltip')}
          </button>
        </div>
      ) : null}

      <ProfileSection
        title={t('profilePickerMyProfilesHeader')}
        profiles={lists.mine}
        {...sectionProps}
      />
      <ProfileSection
        title={t('profilePickerSharedWithMeHeader')}
        profiles={lists.shared}
        {...sectionProps}
      />
      {lists.archived.length > 0 ? (
        <ProfileSection
          title={t('profilePickerArchivedHeader', { count: lists.archived.length })}
          profiles={lists.archived}
          {...sectionProps}
        />
      ) : null}

      {profileCount === 0 && !synced.isError ? (
        <section className="card">
          <p className="card-title">{t('profilePickerEmptyTitle')}</p>
          <p className="card-body">{t('profilePickerEmptyBody')}</p>
        </section>
      ) : null}
    </main>
  );
}

function findProfile(lists: ProfileLists, id: string): ProfileRow | null {
  return [...lists.mine, ...lists.shared, ...lists.archived].find((p) => p.id === id) ?? null;
}

interface SectionProps {
  lists: ProfileLists;
  roles: Map<string, GuardianRole | null>;
  onEdit: (profile: ProfileRow) => void;
  confirmingArchiveId: string | null;
  setConfirmingArchiveId: (id: string | null) => void;
  confirmingDeleteId: string | null;
  setConfirmingDeleteId: (id: string | null) => void;
  deleteStep2: boolean;
  setDeleteStep2: (value: boolean) => void;
  archiveMutation: {
    isPending: boolean;
    mutate: (args: { profile: ProfileRow; archived: boolean }) => void;
  };
  deleteMutation: { isPending: boolean; mutate: (profile: ProfileRow) => void };
}

/**
 * One list section. Actions key on the caller's role: edit for primary and
 * co-parent (`roleCanEditProfile`, the server's own rule for profile
 * metadata); archive, unarchive and delete for the accepted primary
 * guardian only (the `enforce_profile_guardian_only_deletion` trigger
 * rejects anyone else's change to the archive stamp, and
 * `delete_profile_data`'s authority rule, 20260910110000). An archived
 * profile offers no edit: the app shows it read-only too.
 */
function ProfileSection(props: SectionProps & { title: string; profiles: ProfileRow[] }) {
  const t = useT();
  if (props.profiles.length === 0) return null;
  return (
    <section className="card" aria-label={props.title}>
      <h2 className="card-title">{props.title}</h2>
      <ul className="profile-list">
        {props.profiles.map((profile) => {
          const role = props.roles.get(profile.id) ?? null;
          const canEdit = canEditProfile(role);
          const canDelete = role === 'primary_guardian';
          const confirmingArchive = props.confirmingArchiveId === profile.id;
          const confirmingDelete = props.confirmingDeleteId === profile.id;
          const isArchived = profile.archived_at !== null;
          return (
            <li key={profile.id} className="profile-row">
              <div className="profile-row-main">
                <span className="profile-row-name">{profile.display_name}</span>
                <span className="profile-row-created">
                  {t('profilePickerCreated', {
                    date: kCreatedDateFormat.format(
                      new Date(`${profile.created_at.slice(0, 10)}T00:00:00Z`),
                    ),
                  })}
                </span>
              </div>
              <div className="actions">
                <Link className="nav-link" to={`/?profile=${profile.id}`}>
                  {t('webProfilesOpenAction')}
                </Link>
                {canEdit && !isArchived ? (
                  <button type="button" className="btn" onClick={() => props.onEdit(profile)}>
                    {t('webProfilesEditAction')}
                  </button>
                ) : null}
                {canDelete ? (
                  <>
                    {confirmingArchive ? (
                      <span
                        className="confirm-inline"
                        role="alertdialog"
                        aria-label={t('profileArchiveConfirmTitle', {
                          name: profile.display_name,
                        })}
                      >
                        <span className="confirm-text">
                          {t('profileArchiveConfirmTitle', { name: profile.display_name })}{' '}
                          {t('profileArchiveConfirmBody')}
                        </span>
                        <button
                          type="button"
                          className="btn btn-primary"
                          disabled={props.archiveMutation.isPending}
                          onClick={() =>
                            props.archiveMutation.mutate({ profile, archived: !isArchived })
                          }
                        >
                          {isArchived
                            ? t('profilePickerUnarchiveTooltip')
                            : t('profileArchiveConfirmButton')}
                        </button>
                        <button
                          type="button"
                          className="btn"
                          onClick={() => props.setConfirmingArchiveId(null)}
                        >
                          {t('profileArchiveConfirmCancel')}
                        </button>
                      </span>
                    ) : (
                      <button
                        type="button"
                        className="btn"
                        onClick={() => {
                          props.setConfirmingDeleteId(null);
                          props.setDeleteStep2(false);
                          props.setConfirmingArchiveId(profile.id);
                        }}
                      >
                        {isArchived ? t('profilePickerUnarchiveTooltip') : t('profileArchive')}
                      </button>
                    )}
                  </>
                ) : null}
                {canDelete ? (
                  confirmingDelete ? (
                    <span
                      className="confirm-inline"
                      role="alertdialog"
                      aria-label={t(
                        props.deleteStep2
                          ? 'sharingManageGuardiansDeleteProfileStep2Title'
                          : 'sharingManageGuardiansDeleteProfileTitle',
                        props.deleteStep2 ? undefined : { profileName: profile.display_name },
                      )}
                    >
                      <span className="confirm-text">
                        {props.deleteStep2
                          ? `${t('sharingManageGuardiansDeleteProfileStep2Title')} ${t(
                              'sharingManageGuardiansDeleteProfileStep2Body',
                              { profileName: profile.display_name },
                            )}`
                          : `${t('sharingManageGuardiansDeleteProfileTitle', {
                              profileName: profile.display_name,
                            })} ${t('sharingManageGuardiansDeleteProfileStep1Body')}`}
                      </span>
                      {props.deleteStep2 ? (
                        <button
                          type="button"
                          className="btn btn-danger"
                          disabled={props.deleteMutation.isPending}
                          onClick={() => props.deleteMutation.mutate(profile)}
                        >
                          {t('sharingManageGuardiansDeleteProfileAction')}
                        </button>
                      ) : (
                        <button
                          type="button"
                          className="btn btn-danger"
                          onClick={() => props.setDeleteStep2(true)}
                        >
                          {t('sharingManageGuardiansDeleteProfileAction')}
                        </button>
                      )}
                      <button
                        type="button"
                        className="btn"
                        onClick={() => {
                          props.setConfirmingDeleteId(null);
                          props.setDeleteStep2(false);
                        }}
                      >
                        {t('profileArchiveConfirmCancel')}
                      </button>
                    </span>
                  ) : (
                    <button
                      type="button"
                      className="btn"
                      onClick={() => {
                        props.setConfirmingArchiveId(null);
                        props.setDeleteStep2(false);
                        props.setConfirmingDeleteId(profile.id);
                      }}
                    >
                      {t('webProfilesDeleteAction')}
                    </button>
                  )
                ) : null}
              </div>
            </li>
          );
        })}
      </ul>
    </section>
  );
}
