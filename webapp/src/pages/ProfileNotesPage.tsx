import { useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Link, useParams } from 'react-router';

import { useT } from '../i18n/t';
import { serverAdjustedNow } from '../lib/domain';
import {
  careNotesQueryKey,
  guardianNotesQueryKey,
  useCareNotes,
  useCurrentUserId,
  useGuardianNotes,
  useGuardians,
  useLiveProfiles,
} from '../lib/queries';
import {
  noteIdGenerator,
  pushCareNotes,
  pushGuardianNotes,
  type CareNoteRow,
  type GuardianNoteRow,
} from '../lib/sharing';
import { isCivilDate, isoDateFormatter, profileHomePath } from '../lib/profiles/profile-views';
import { roleCanLog } from '../lib/roles';
import { getSupabaseClient } from '../lib/supabase';

/**
 * Guardian and care notes on the web (issue #1255), with the app's author
 * rules (#867/#868): every accepted guardian reads both; the writing roles
 * write through `sync_push` — the phones' sole write path — and a guardian
 * note is edited or removed only by its author, server-checked and mirrored
 * here by which row the editor adopts. Care notes stay the shared list they
 * are in the app: any writing role may add or remove any of them.
 */

/** The chosen day in words ("Monday, October 5, 2026"), never as an ISO string. */
const formatNotesDate = isoDateFormatter('en', { dateStyle: 'full' });

/** Today in the operator's zone, as the `local_date` column wants it. */
export function localDateToday(now: Date = new Date()): string {
  // en-CA formats as YYYY-MM-DD in the runtime's local zone.
  const iso = new Intl.DateTimeFormat('en-CA', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(now);
  return iso;
}

function requireClient(): NonNullable<ReturnType<typeof getSupabaseClient>> {
  const client = getSupabaseClient();
  if (client === null) {
    throw new Error('Supabase is not configured in this build');
  }
  return client;
}

export function ProfileNotesPage() {
  const { profileId } = useParams();
  const t = useT();
  const client = getSupabaseClient();
  const profiles = useLiveProfiles();
  const profile = profiles.find((candidate) => candidate.id === profileId) ?? null;
  const guardians = useGuardians(profileId, profile !== null);

  const [localDate, setLocalDate] = useState(() => localDateToday());
  const guardianNotes = useGuardianNotes(profileId, localDate, profile !== null);
  const careNotes = useCareNotes(profileId, profile !== null);

  const me = useCurrentUserId(client !== null).data ?? null;
  const myRole =
    guardians.data?.find((row) => row.user_id === me && row.status === 'accepted')?.role ??
    null;
  const canWrite = myRole !== null && roleCanLog(myRole);

  if (profileId === undefined || (profiles.length > 0 && profile === null)) {
    return (
      <main className="page">
        <section className="card">
          <p className="card-title">{t('sharingFailureNotFound')}</p>
        </section>
      </main>
    );
  }

  const guardianName = (userId: string | null): string => {
    if (userId !== null && userId === me) return t('guardianNotesYou');
    const row = guardians.data?.find((candidate) => candidate.user_id === userId);
    // An empty name is no name (issue #1464): `??` kept it, and the note
    // was then signed by nobody.
    const name = row?.display_name ?? '';
    return name !== '' ? name : t('guardianNotesGuardianFallback');
  };

  const notes = guardianNotes.data ?? [];
  const mine = [...notes]
    .filter((row) => row.logged_by_user_id !== null && row.logged_by_user_id === me)
    .sort((a, b) => b.updated_at.localeCompare(a.updated_at))[0];
  const others = notes.filter((row) => row !== mine);

  return (
    <main className="page">
      {/* The page is reached by its own address, so it says whose notes
          these are. It used to be titled "Notes from guardians" for any
          profile, with the care notes underneath that heading too. */}
      <h1 className="display">
        {profile !== null ? t('webNotesTitle', { profileName: profile.display_name }) : ''}
      </h1>
      <p className="page-back">
        <Link className="nav-link" to={profileHomePath(profileId)}>
          {t('webDayBackToToday')}
        </Link>
      </p>

      <h2 className="section-title">{t('guardianNotesSectionTitle')}</h2>
      <div className="field">
        <label htmlFor="notes-date">
          {t('sharingActivityFeedForDate', { date: formatNotesDate(localDate) })}
        </label>
        <input
          id="notes-date"
          type="date"
          value={localDate}
          // Four-digit years only. The field itself allows more, and the
          // check below is what holds: a value that is not a real date
          // never becomes the page's date (issue #1473).
          max="9999-12-31"
          onChange={(event) => {
            if (isCivilDate(event.target.value)) setLocalDate(event.target.value);
          }}
        />
      </div>

      {guardianNotes.error instanceof Error ? (
        <p className="error">{t('commonSomethingWentWrong')}</p>
      ) : null}

      <ul className="row-list">
        {others.map((row) => (
          <li key={row.id} className="row">
            <div className="row-main">
              <p className="row-title">{guardianName(row.logged_by_user_id)}</p>
              <p className="row-sub">{row.body}</p>
            </div>
          </li>
        ))}
      </ul>
      {notes.length === 0 && guardianNotes.data !== undefined ? (
        <p className="card-body">{t('guardianNotesEmpty')}</p>
      ) : null}

      {canWrite && client !== null ? (
        <MyNoteEditor
          key={`${profileId}-${localDate}-${mine?.id ?? 'none'}`}
          profileId={profileId}
          localDate={localDate}
          tz={timeZone()}
          existing={mine ?? null}
        />
      ) : null}

      <section className="card" aria-labelledby="care-notes-title">
        <h2 className="card-title" id="care-notes-title">
          {t('careNotesSectionTitle')}
        </h2>
        <p className="card-body">{t('careNotesDisclosure')}</p>
        {careNotes.error instanceof Error ? (
          <p className="error">{t('careNotesSaveError')}</p>
        ) : null}
        {careNotes.data !== undefined && careNotes.data.length === 0 ? (
          <p className="card-body">{t('careNotesEmpty')}</p>
        ) : null}
        <ul className="row-list">
          {(careNotes.data ?? []).map((row) => (
            <CareNoteRowItem
              key={row.id}
              row={row}
              authorName={guardianName(row.logged_by_user_id)}
              canWrite={canWrite && client !== null}
              profileId={profileId}
            />
          ))}
        </ul>
        {canWrite && client !== null ? <CareNoteComposer profileId={profileId} /> : null}
      </section>
    </main>
  );
}

/** The author's IANA zone (bounded to 64 chars by the server's tz CHECKs). */
export function timeZone(): string {
  const zone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  return zone === undefined || zone.length > 64 ? 'UTC' : zone;
}

function MyNoteEditor(props: {
  profileId: string;
  localDate: string;
  tz: string;
  existing: GuardianNoteRow | null;
}) {
  const t = useT();
  const queryClient = useQueryClient();
  const [body, setBody] = useState(props.existing?.body ?? '');
  const [failed, setFailed] = useState(false);

  const save = useMutation({
    mutationFn: async (deleted: boolean) => {
      const client = requireClient();
      const id = props.existing?.id ?? noteIdGenerator.next();
      const rejections = await pushGuardianNotes(client, [
        {
          id,
          profileId: props.profileId,
          localDate: props.localDate,
          tz: props.tz,
          body,
          updatedAt: serverAdjustedNow(),
          deleted,
        },
      ]);
      if (rejections.includes(id)) {
        // The server refused the row (an author or bounds check) — the
        // per-row rejection surfaces as the same save failure copy.
        throw new Error('rejected');
      }
    },
    onSuccess: () => {
      setFailed(false);
      void queryClient.invalidateQueries({
        queryKey: guardianNotesQueryKey(props.profileId, props.localDate),
      });
    },
    onError: () => setFailed(true),
  });

  return (
    <section className="card">
      <div className="field field-titled">
        <label className="card-title" htmlFor="my-guardian-note">
          {t('guardianNotesFieldLabel')}
        </label>
        <textarea
          id="my-guardian-note"
          value={body}
          maxLength={2000}
          disabled={save.isPending}
          onChange={(event) => setBody(event.target.value)}
        />
      </div>
      <p className="card-body">{t('careGuardianNoteDisclosure')}</p>
      {failed ? <p className="error">{t('careNotesSaveError')}</p> : null}
      <div className="actions">
        {props.existing !== null ? (
          <button
            type="button"
            className="button danger"
            disabled={save.isPending}
            onClick={() => save.mutate(true)}
          >
            {t('guardianNotesRemove')}
          </button>
        ) : null}
        <button
          type="button"
          className="button"
          disabled={save.isPending || body.trim() === ''}
          onClick={() => save.mutate(false)}
        >
          {props.existing === null ? t('guardianNotesAdd') : t('guardianNotesUpdate')}
        </button>
      </div>
    </section>
  );
}

function CareNoteRowItem(props: {
  row: CareNoteRow;
  authorName: string;
  canWrite: boolean;
  profileId: string;
}) {
  const t = useT();
  const queryClient = useQueryClient();
  const [confirming, setConfirming] = useState(false);
  const [failed, setFailed] = useState(false);

  const remove = useMutation({
    mutationFn: async () => {
      const client = requireClient();
      const rejections = await pushCareNotes(client, [
        {
          id: props.row.id,
          profileId: props.profileId,
          body: '',
          updatedAt: serverAdjustedNow(),
          deleted: true,
        },
      ]);
      if (rejections.includes(props.row.id)) {
        throw new Error('rejected');
      }
    },
    onSuccess: () => {
      setFailed(false);
      setConfirming(false);
      void queryClient.invalidateQueries({ queryKey: careNotesQueryKey(props.profileId) });
    },
    onError: () => setFailed(true),
  });

  return (
    <li className="row">
      <div className="row-main">
        <p className="row-title">{props.authorName}</p>
        <p className="row-sub">{props.row.body}</p>
        {failed ? <p className="error">{t('careNotesRemoveNoteError')}</p> : null}
      </div>
      <div className="actions">
        {confirming ? (
          <>
            <p className="row-sub">{t('careNotesDeleteBody')}</p>
            <button
              type="button"
              className="button danger"
              disabled={remove.isPending}
              onClick={() => remove.mutate()}
            >
              {t('careNotesDeleteConfirm')}
            </button>
            <button
              type="button"
              className="button secondary"
              disabled={remove.isPending}
              onClick={() => setConfirming(false)}
            >
              {t('careNotesDeleteCancel')}
            </button>
          </>
        ) : props.canWrite ? (
          <button
            type="button"
            className="button danger"
            disabled={remove.isPending}
            aria-label={t('careNotesRemoveNoteTooltip')}
            onClick={() => setConfirming(true)}
          >
            {t('careNotesRemoveNoteTooltip')}
          </button>
        ) : null}
      </div>
    </li>
  );
}

function CareNoteComposer(props: { profileId: string }) {
  const t = useT();
  const queryClient = useQueryClient();
  const [body, setBody] = useState('');
  const [failed, setFailed] = useState(false);

  const add = useMutation({
    mutationFn: async () => {
      const client = requireClient();
      const id = noteIdGenerator.next();
      const rejections = await pushCareNotes(client, [
        {
          id,
          profileId: props.profileId,
          body,
          updatedAt: serverAdjustedNow(),
          deleted: false,
        },
      ]);
      if (rejections.includes(id)) {
        throw new Error('rejected');
      }
    },
    onSuccess: () => {
      setBody('');
      setFailed(false);
      void queryClient.invalidateQueries({ queryKey: careNotesQueryKey(props.profileId) });
    },
    onError: () => setFailed(true),
  });

  return (
    <>
      <div className="field">
        <label htmlFor="care-note-body">{t('careNotesAddLabel')}</label>
        <textarea
          id="care-note-body"
          value={body}
          maxLength={2000}
          disabled={add.isPending}
          placeholder={t('careNotesAddHint')}
          onChange={(event) => setBody(event.target.value)}
        />
      </div>
      {failed ? <p className="error">{t('careNotesSaveError')}</p> : null}
      <div className="actions">
        <button
          type="button"
          className="button"
          disabled={add.isPending || body.trim() === ''}
          onClick={() => add.mutate()}
        >
          {t('careNotesAddButton')}
        </button>
      </div>
    </>
  );
}
