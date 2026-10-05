import { describe, expect, it, afterEach } from 'vitest';

import { createSupabaseClient, type AppSupabaseClient } from '../../src/lib/supabase';
import {
  fetchGuardianNotes,
  fetchSettings,
  newCareNotePayload,
  newCycleOverridePayload,
  newDayEntryPayload,
  newGuardianNotePayload,
  newObservationPayload,
  newProfileModePayload,
  newProfilePayload,
  newVisitPrepItemPayload,
  pullSyncedData,
  pushSyncBatch,
} from '../../src/lib/domain';
import { setProfileArchived, updateProfile } from '../../src/lib/profiles/profile-actions';
import type { ProfileRow } from '../../src/lib/schemas';

/**
 * Issue #1252's integration suite: the web data layer against the real
 * local Supabase stack — real PostgREST, real GoTrue sessions, real
 * `sync_push`/`sync_pull`/sharing RPCs and RLS. This is the web sibling of
 * `test/data/sync/local_supabase_round_trip_test.dart` (issue #102) and
 * follows the same contract:
 *
 * - Runs ONLY when a local Supabase stack is reachable (skips visibly
 *   otherwise, so `npm run test` on a plain checkout and CI's webapp job —
 *   which starts no stack — stay green). CI's `db-tests` job already boots
 *   exactly the stack this suite needs (PostgREST + Auth; it starts for
 *   pgTAP) and runs it there.
 * - The stock local-dev JWTs are the universal keys every `supabase start`
 *   project issues (`iss: supabase-demo` — not secrets). A stack with a
 *   custom JWT secret overrides them via `LUNARLOG_LOCAL_SUPABASE_*`.
 * - The service-role key is used for exactly two calls per user —
 *   creating and deleting an email-confirmed test user (the local stack's
 *   `enable_confirmations = true` plus no mailpit means a plain signUp can
 *   never yield a session). Everything else runs as an ordinary
 *   authenticated user.
 * - The realtime container is deliberately NOT part of that stack
 *   (AGENTS.md's Migration Flow excludes it; realtime delivery itself is
 *   proven by supabase/tests/manual/verify_realtime_delivery.mjs), so the
 *   subscription wiring is pinned by the unit suite, not here.
 *
 * Every row is created under freshly created, fabricate-only test users
 * and deleted on teardown (the profile/user FK cascade removes the rest).
 */

const url = process.env.LUNARLOG_LOCAL_SUPABASE_URL ?? 'http://127.0.0.1:54321';

// The stock local-dev JWTs (role `anon` / `service_role`, issuer
// `supabase-demo`). Local development only; never production secrets.
const kLocalDevAnonKey =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
const kLocalDevServiceRoleKey =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

const publishableKey = process.env.LUNARLOG_LOCAL_SUPABASE_PUBLISHABLE_KEY ?? kLocalDevAnonKey;
const serviceRoleKey =
  process.env.LUNARLOG_LOCAL_SUPABASE_SERVICE_ROLE_KEY ?? kLocalDevServiceRoleKey;

const TEST_PASSWORD = 'Integration#1252x';

async function stackReachable(): Promise<boolean> {
  try {
    // No AbortSignal.timeout here: vitest's jsdom environment replaces the
    // global AbortSignal, and undici's fetch then rejects the jsdom
    // instance before the request ever starts. The stack is local — a hang
    // fails the runner's own timeout loudly instead.
    const response = await fetch(`${url}/rest/v1/`, {
      headers: { apikey: publishableKey },
    });
    return response.ok;
  } catch {
    return false;
  }
}

const reachable = await stackReachable();
const suite = reachable ? describe : describe.skip;

async function adminCreateUser(label: string): Promise<{ id: string; email: string }> {
  const email = `i1252-${label}-${Date.now()}-${Math.floor(Math.random() * 1_000_000)}@integration.local`;
  const response = await fetch(`${url}/auth/v1/admin/users`, {
    method: 'POST',
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ email, password: TEST_PASSWORD, email_confirm: true }),
  });
  if (!response.ok) {
    throw new Error(`admin createUser failed: ${response.status} ${await response.text()}`);
  }
  const body = (await response.json()) as { id: string };
  return { id: body.id, email };
}

async function adminDeleteUser(userId: string): Promise<void> {
  const response = await fetch(`${url}/auth/v1/admin/users/${userId}`, {
    method: 'DELETE',
    headers: { apikey: serviceRoleKey, Authorization: `Bearer ${serviceRoleKey}` },
  });
  if (!response.ok && response.status !== 404) {
    throw new Error(`admin deleteUser failed: ${response.status} ${await response.text()}`);
  }
}

async function signInAs(email: string): Promise<AppSupabaseClient> {
  const client = createSupabaseClient(url, publishableKey);
  const { error } = await client.auth.signInWithPassword({
    email,
    password: TEST_PASSWORD,
  });
  if (error !== null) throw error;
  return client;
}

/** SHA-256 hex — the invitation token hash format the sharing RPCs take. */
async function sha256Hex(token: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

/** Yesterday's local date — safely inside the server's date bounds. */
function recentLocalDate(): string {
  const day = new Date(Date.now() - 24 * 60 * 60 * 1_000);
  return day.toISOString().slice(0, 10);
}

suite('web data layer against the live local stack (issue #1252)', () => {
  const createdUserIds: string[] = [];
  const createdProfileIds: string[] = [];

  afterEach(async () => {
    // Profiles FIRST, via the service role: deleting the owner user
    // directly cascades the profile, and any `visit_prep_items` row with a
    // checked stamp hits `visit_prep_items_checked_stamp_check` on the
    // `on delete set null` of checked_by_user_id (GoTrue answers 500).
    // Deleting the profile cascades its content tables cleanly instead.
    if (createdProfileIds.length > 0) {
      const admin = createSupabaseClient(url, serviceRoleKey);
      const { error } = await admin
        .from('profiles')
        .delete()
        .in('id', createdProfileIds.splice(0));
      if (error !== null) throw error;
    }
    for (const id of createdUserIds.splice(0)) {
      await adminDeleteUser(id);
    }
  });

  async function newUser(label: string): Promise<{ id: string; email: string }> {
    const user = await adminCreateUser(label);
    createdUserIds.push(user.id);
    return user;
  }

  async function inviteAndAccept(
    owner: AppSupabaseClient,
    guardian: AppSupabaseClient,
    profileId: string,
    role: string,
    subject = false,
  ): Promise<void> {
    const token = `token-${Math.random()}`;
    const tokenHash = await sha256Hex(token);
    const created = await owner.rpc('create_guardian_invitation', {
      p_profile_id: profileId,
      p_recipient_label: 'Co-guardian',
      p_role: role,
      p_token_hash: tokenHash,
      ...(subject ? { p_subject: true } : {}),
    });
    if (created.error !== null) throw created.error;
    const accepted = await guardian.rpc('accept_guardian_invitation', {
      p_token_hash: tokenHash,
      p_guardian_display_name: 'Co-guardian',
    });
    if (accepted.error !== null) throw accepted.error;
  }

  it('a guardian sees only their own profiles: the shared one arrives, the rest does not', async () => {
    const owner = await signInAs((await newUser('owner')).email);
    const guardian = await signInAs((await newUser('guardian')).email);
    const outsider = await signInAs((await newUser('outsider')).email);

    const shared = newProfilePayload({
      display_name: 'Shared',
      is_minor: false,
      sort_order: 0,
    });
    const privateOne = newProfilePayload({
      display_name: 'Private',
      is_minor: false,
      sort_order: 1,
    });
    const pushed = await pushSyncBatch(owner, { profiles: [shared, privateOne] });
    expect(pushed.rejected).toEqual([]);
    createdProfileIds.push(shared.id, privateOne.id);

    await inviteAndAccept(owner, guardian, shared.id, 'caregiver');

    const guardianView = await pullSyncedData(guardian);
    const guardianProfileIds = guardianView.data.profiles.map((row) => row.id);
    expect(guardianProfileIds).toContain(shared.id);
    expect(guardianProfileIds).not.toContain(privateOne.id);

    const outsiderView = await pullSyncedData(outsider);
    expect(outsiderView.data.profiles).toEqual([]);

    const ownerView = await pullSyncedData(owner);
    expect(new Set(ownerView.data.profiles.map((row) => row.id))).toEqual(
      new Set([shared.id, privateOne.id]),
    );
  }, 30_000);

  // Issue #1388: sync_push's profiles UPDATE writes display_name,
  // sort_order, archived_at and created_at from the payload unconditionally.
  // The web's archive and edit used to push partial rows, which blanked the
  // name and reset the rest for every guardian — only the real RPC shows it.
  it('a web archive and edit keep the stored name, order, creation date and archive state', async () => {
    const owner = await signInAs((await newUser('owner')).email);
    const coParent = await signInAs((await newUser('coparent')).email);

    const created = newProfilePayload({ display_name: 'Maya', is_minor: false, sort_order: 4 });
    expect((await pushSyncBatch(owner, { profiles: [created] })).rejected).toEqual([]);
    createdProfileIds.push(created.id);
    await inviteAndAccept(owner, coParent, created.id, 'co_parent');

    const read = async (client: AppSupabaseClient): Promise<ProfileRow> => {
      const row = (await pullSyncedData(client)).data.profiles.find(
        (profile) => profile.id === created.id,
      );
      if (row === undefined) throw new Error('the profile is missing from the pull');
      return row;
    };
    const stored = await read(owner);
    const expectUntouched = (row: ProfileRow, name: string): void => {
      expect(row.display_name).toBe(name);
      expect(row.sort_order).toBe(4);
      expect(Date.parse(row.created_at)).toBe(Date.parse(stored.created_at));
    };

    await setProfileArchived(owner, stored, true);
    const archived = await read(owner);
    expect(archived.archived_at).not.toBeNull();
    expectUntouched(archived, 'Maya');

    // The primary guardian's edit of an archived profile leaves it archived.
    const fields = { birthYear: 1990, relationship: 'daughter', mode: 'standard' };
    await updateProfile(owner, archived, { ...fields, displayName: 'Maya B' });
    const editedWhileArchived = await read(owner);
    expect(editedWhileArchived.archived_at).not.toBeNull();
    expectUntouched(editedWhileArchived, 'Maya B');

    // A co-parent cannot change the archive stamp in either direction (the
    // enforce_profile_guardian_only_deletion trigger): the push is rejected
    // and the row stays exactly as it was.
    await expect(setProfileArchived(coParent, await read(coParent), false)).rejects.toThrow(
      'rejected by sync_push',
    );
    expectUntouched(await read(owner), 'Maya B');
    expect((await read(owner)).archived_at).not.toBeNull();

    await setProfileArchived(owner, await read(owner), false);
    const live = await read(owner);
    expect(live.archived_at).toBeNull();
    expectUntouched(live, 'Maya B');

    // A co-parent's edit resets nothing the edit did not name.
    await updateProfile(coParent, await read(coParent), { ...fields, displayName: 'Maya C' });
    const edited = await read(owner);
    expect(edited.archived_at).toBeNull();
    expect(edited.birth_year).toBe(1990);
    expectUntouched(edited, 'Maya C');
  }, 30_000);

  it('a viewer’s write is rejected — through sync_push and through the revoked direct grant', async () => {
    const owner = await signInAs((await newUser('owner')).email);
    const viewer = await signInAs((await newUser('viewer')).email);

    const profile = newProfilePayload({
      display_name: 'Watched',
      is_minor: false,
      sort_order: 0,
    });
    expect((await pushSyncBatch(owner, { profiles: [profile] })).rejected).toEqual([]);
    createdProfileIds.push(profile.id);
    await inviteAndAccept(owner, viewer, profile.id, 'viewer');

    // Through sync_push — the sole write path: the row comes back rejected.
    const entry = newDayEntryPayload({
      profile_id: profile.id,
      local_date: recentLocalDate(),
      flow: 'light',
    });
    const outcome = await pushSyncBatch(viewer, { day_entries: [entry] });
    expect(outcome.rejected.map((rejection) => rejection.id)).toContain(entry.id);

    // Direct PostgREST: no UPDATE grant survives 20260915160000 — the
    // server refuses the request itself, before RLS even runs.
    const direct = await viewer
      .from('day_entries')
      .update({ note: 'smuggled' })
      .eq('id', entry.id);
    expect(direct.error).not.toBeNull();

    // Control: the owner's identical push is accepted.
    const ownerEntry = newDayEntryPayload({
      profile_id: profile.id,
      local_date: recentLocalDate(),
      flow: 'light',
    });
    const ownerOutcome = await pushSyncBatch(owner, { day_entries: [ownerEntry] });
    expect(ownerOutcome.rejected).toEqual([]);
  }, 30_000);

  it('web payloads match the shapes pinned by seed_sync_push_sample_test.sql and read back', async () => {
    const owner = await signInAs((await newUser('seeder')).email);

    const profile = newProfilePayload({
      display_name: 'Maya',
      is_minor: false,
      sort_order: 0,
      birth_year: 1988,
      relationship: 'self',
      mode: 'standard',
      last_period_start: '2026-08-29',
      typical_cycle_length_days: 28,
      typical_period_length_days: 5,
      bbt_unit: 'celsius',
      weight_unit: 'kg',
    });
    createdProfileIds.push(profile.id);
    const day = recentLocalDate();
    // Deterministic last-writer-wins: every stamp comes from an injected
    // clock ticking one second apart (60s in the past — inside every
    // server window), so the same-date resolver's winner never depends on
    // how fast the runner built the payloads. entryA carries the LATEST
    // stamp on purpose: it is the row the merge must keep.
    const stampBase = Date.now() - 60_000;
    let stampTick = 0;
    const stampedClock = (): Date => new Date(stampBase + stampTick++ * 1_000);
    const entryA = newDayEntryPayload(
      {
        profile_id: profile.id,
        local_date: day,
        tz: 'America/New_York',
        flow: 'light',
        tags: ['sad', 'irritable'],
        note: 'Mild cramps in the morning, gone by noon.',
        pms: true,
      },
      () => new Date(stampBase + 9_000),
    );
    const entryB = newDayEntryPayload(
      {
        profile_id: profile.id,
        local_date: day,
        tz: 'America/New_York',
        flow: 'medium',
      },
      () => new Date(stampBase + 5_000),
    );
    const observationBbt = newObservationPayload(
      {
        day_entry_id: entryA.id,
        profile_id: profile.id,
        local_date: day,
        tz: 'America/New_York',
        observed_at: new Date(stampBase).toISOString(),
        category: 'bbt',
        value_num: 36.33,
        unit: 'celsius',
      },
      stampedClock,
    );
    const observationPain = newObservationPayload(
      {
        day_entry_id: entryA.id,
        profile_id: profile.id,
        local_date: day,
        tz: 'America/New_York',
        category: 'pain',
        code: 'cramps',
        intensity: 3,
      },
      stampedClock,
    );

    const outcome = await pushSyncBatch(owner, {
      profiles: [profile],
      day_entries: [entryA, entryB],
      observations: [observationBbt, observationPain],
      profile_modes: [newProfileModePayload({ profile_id: profile.id, mode: 'tracking' })],
      cycle_overrides: [
        newCycleOverridePayload(
          {
            profile_id: profile.id,
            cycle_start_date: day,
            excluded_from_average: true,
            manual_start: false,
          },
          stampedClock,
        ),
      ],
      care_notes: [
        newCareNotePayload({ profile_id: profile.id, body: 'Heat pad helps.' }, stampedClock),
      ],
      visit_prep_items: [
        newVisitPrepItemPayload({
          profile_id: profile.id,
          body: 'Bring the temperature tracking chart',
          is_checked: true,
        }),
      ],
      guardian_notes: [
        newGuardianNotePayload(
          {
            profile_id: profile.id,
            local_date: day,
            tz: 'UTC',
            body: 'Write down sleep hours for the past week',
          },
          stampedClock,
        ),
      ],
    });
    // The acceptance criterion: zero rejections for the seed-shaped batch.
    // If the server rejects a row, name the payload it came from — a bare
    // id echo is undiagnosable in a CI log.
    if (outcome.rejected.length > 0) {
      const named = new Map<string, string>([
        [profile.id, 'profiles payload'],
        [entryA.id, 'day_entries payload (the merge winner, stamped +9s)'],
        [entryB.id, 'day_entries payload (the merge loser, stamped +5s)'],
        [observationBbt.id, 'observations payload (bbt)'],
        [observationPain.id, 'observations payload (pain)'],
      ]);
      const lines = outcome.rejected.map(
        (rejection) => named.get(rejection.id ?? '') ?? `unrecognised id ${rejection.id}`,
      );
      throw new Error(
        `seed-shape sync_push rejected ${outcome.rejected.length} row(s): ${lines.join('; ')}`,
      );
    }
    expect(outcome.rejected).toEqual([]);

    const view = (await pullSyncedData(owner)).data;
    const pulledProfile = view.profiles.find((row) => row.id === profile.id);
    expect(pulledProfile?.birth_year).toBe(1988);
    expect(pulledProfile?.typical_cycle_length_days).toBe(28);

    const pulledEntry = view.day_entries.find((row) => row.id === entryA.id);
    expect(pulledEntry?.flow).toBe('light');
    // jsonb round-trips may reorder the array; compare as sets, like the
    // seed fixture itself does (it counts tags, never their order).
    expect([...(pulledEntry?.tags ?? [])].sort()).toEqual(['irritable', 'sad']);
    expect(pulledEntry?.note).toBe('Mild cramps in the morning, gone by noon.');
    expect(pulledEntry?.pms).toBe(true);

    // The same-date resolver merged the two same-day entries: one survives.
    expect(view.day_entries.filter((row) => row.deleted_at === null)).toHaveLength(1);

    const pulledBbt = view.observations.find((row) => row.id === observationBbt.id);
    expect(pulledBbt?.value_num).toBeCloseTo(36.33);
    expect(pulledBbt?.unit).toBe('celsius');
    const pulledPain = view.observations.find((row) => row.id === observationPain.id);
    expect(pulledPain?.code).toBe('cramps');
    expect(pulledPain?.intensity).toBe(3);

    expect(view.profile_modes.find((row) => row.profile_id === profile.id)?.mode).toBe(
      'tracking',
    );
    expect(view.cycle_overrides[0]?.excluded_from_average).toBe(true);
    expect(view.care_notes[0]?.body).toBe('Heat pad helps.');
    expect(view.visit_prep_items[0]?.is_checked).toBe(true);

    // guardian_notes and settings ride their direct RLS-scoped selects.
    const notes = await fetchGuardianNotes(owner, { profileId: profile.id });
    expect(notes.map((row) => row.body)).toContain('Write down sleep hours for the past week');
    expect(await fetchSettings(owner)).toEqual([]);
  }, 30_000);

  it('a private day note arrives masked for every non-subject guardian (the sync_pull read path)', async () => {
    // Masking applies only when the profile HAS a designated subject
    // (profile_has_subject, 20260921130000): a subject-less profile fails
    // open by design. So this profile gets one: the subject joins through
    // a `p_subject: true` invitation (issue #802's marker), the way a
    // teen subject does, and the subject — not the owner — writes the
    // private note.
    const owner = await signInAs((await newUser('parent')).email);
    const subjectUser = await signInAs((await newUser('subject')).email);
    const coGuardian = await signInAs((await newUser('coguardian')).email);

    const profile = newProfilePayload({ display_name: 'Diary', is_minor: true, sort_order: 0 });
    expect((await pushSyncBatch(owner, { profiles: [profile] })).rejected).toEqual([]);
    createdProfileIds.push(profile.id);
    await inviteAndAccept(owner, subjectUser, profile.id, 'caregiver', true);
    await inviteAndAccept(owner, coGuardian, profile.id, 'caregiver');

    const entry = newDayEntryPayload({
      profile_id: profile.id,
      local_date: recentLocalDate(),
      flow: 'light',
      note: 'A private note.',
      note_private: true,
    });
    expect((await pushSyncBatch(subjectUser, { day_entries: [entry] })).rejected).toEqual([]);

    const subjectView = (await pullSyncedData(subjectUser)).data;
    expect(subjectView.day_entries.find((row) => row.id === entry.id)?.note).toBe(
      'A private note.',
    );

    for (const viewer of [coGuardian, owner]) {
      const view = (await pullSyncedData(viewer)).data;
      const masked = view.day_entries.find((row) => row.id === entry.id);
      expect(masked?.note).toBeNull();
      expect(masked?.note_private).toBe(true);
    }
  }, 30_000);
});
