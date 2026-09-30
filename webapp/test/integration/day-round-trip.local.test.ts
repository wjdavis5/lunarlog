import { afterEach, describe, expect, it } from 'vitest';

import { getSyncedDataCache } from '../../src/lib/domain';
import { createSupabaseClient, type AppSupabaseClient } from '../../src/lib/supabase';
import { fetchDayView, saveDay } from '../../src/lib/day/day-data';
import type { DayEdit, LoadedDayView } from '../../src/lib/day/payloads';

/**
 * Issue #1254's round-trip: the web day editor's write path (saveDay → the
 * real `sync_push` RPC via the #1252 data layer) against a REAL local
 * `supabase start` stack — the same discipline as the Dart round trip
 * (issue #102) and #1252's own suite above, and CI's `db-tests` job runs
 * the whole directory against the stack it boots for pgTAP. What only a
 * live run can catch is a drift between the editor's payload shapes and
 * the SQL: per-row rejections, LWW declines, the same-date merge, RLS,
 * and the #849 private-note masking — all answering for real.
 *
 * Runs ONLY when a local Supabase stack is reachable (skips visibly
 * otherwise, so `npm run test` on a plain checkout and CI's webapp job —
 * which starts no stack — stay green).
 *
 * The default keys are the universal local-development JWTs every
 * `supabase start` project issues (iss supabase-demo — not secrets). The
 * service-role key appears exactly twice: creating email-confirmed test
 * users, and arranging rows only a SECURITY DEFINER path writes in
 * production (an accepted viewer membership; the profile's designated
 * subject marker). Everything else runs as ordinary authenticated users.
 */

const url = process.env['LUNARLOG_LOCAL_SUPABASE_URL'] ?? 'http://127.0.0.1:54321';
const publishableKey =
  process.env['LUNARLOG_LOCAL_SUPABASE_PUBLISHABLE_KEY'] ??
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
const serviceRoleKey =
  process.env['LUNARLOG_LOCAL_SUPABASE_SERVICE_ROLE_KEY'] ??
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

const TEST_PASSWORD = 'WebRoundTrip#1254x';

async function stackReachable(): Promise<boolean> {
  try {
    // No AbortSignal.timeout: vitest's jsdom realm mints its own
    // AbortSignal, and Node's fetch rejects the cross-realm instance.
    const response = await Promise.race([
      fetch(`${url}/rest/v1/`, { headers: { apikey: publishableKey } }),
      new Promise<never>((_, reject) =>
        setTimeout(() => reject(new Error('probe timeout')), 2000),
      ),
    ]);
    return (response as Response).ok;
  } catch {
    return false;
  }
}

const reachable = await stackReachable();
const suite = reachable ? describe : describe.skip;

/** Minimal inline ULID mint for test rows: 10-char timestamp + random tail
 * in Crockford base32 — what the server's `c_ulid` pattern admits. */
function newUlidHere(): string {
  const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  let time = Date.now();
  let out = '';
  for (let i = 0; i < 10; i += 1) {
    out = alphabet[time % 32] + out;
    time = Math.floor(time / 32);
  }
  const bytes = new Uint8Array(10);
  crypto.getRandomValues(bytes);
  let buffer = 0;
  let bits = 0;
  for (const byte of bytes) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out += alphabet[(buffer >> bits) & 31];
    }
  }
  return out;
}

async function adminCreateUser(label: string): Promise<{ id: string; email: string }> {
  const email = `i1254-${label}-${Date.now()}-${Math.floor(Math.random() * 1_000_000)}@integration.local`;
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

async function signInAs(email: string): Promise<AppSupabaseClient> {
  const client = createSupabaseClient(url, publishableKey);
  const { error } = await client.auth.signInWithPassword({ email, password: TEST_PASSWORD });
  if (error !== null) throw error;
  return client;
}

function edit(partial: Partial<DayEdit>): DayEdit {
  return {
    flow: 'none',
    flowExplicitlySet: false,
    spotting: false,
    pms: false,
    tags: [],
    note: null,
    notePrivate: false,
    bbt: null,
    weight: null,
    mode: null,
    manualCycleStart: false,
    excludeCycleFromAverage: false,
    ...partial,
  };
}

suite('web day editor against the live local stack (issue #1254)', () => {
  const createdUserIds: string[] = [];

  afterEach(async () => {
    // Drop the session cache between tests — each test signs in its own
    // users, and the cache must never leak rows across callers.
    getSyncedDataCache().reset();
    for (const userId of createdUserIds.splice(0)) {
      await fetch(`${url}/auth/v1/admin/users/${userId}`, {
        method: 'DELETE',
        headers: { apikey: serviceRoleKey, Authorization: `Bearer ${serviceRoleKey}` },
      });
    }
  });

  it(
    'saves every category and reads it back; both same-date races resolve by ' +
      "the server's rules; a viewer is refused client- and server-side; a " +
      'private note masks for a non-subject',
    { timeout: 120_000 },
    async () => {
      const owner = await adminCreateUser('owner');
      createdUserIds.push(owner.id);
      const ownerClient = await signInAs(owner.email);

      // The profile is created the way the app creates one — pushed through
      // sync_push's profiles array, so the on_profile_created_add_guardian
      // trigger gives the caller an accepted primary_guardian membership
      // exactly as in production.
      const profileId = newUlidHere();
      const nowIso = new Date().toISOString();
      const pushed = await ownerClient.rpc('sync_push', {
        p_profiles: [
          {
            id: profileId,
            display_name: 'Web Round Trip',
            is_minor: false,
            sort_order: 0,
            created_at: nowIso,
            updated_at: nowIso,
            deleted_at: null,
            mode: 'standard',
            birth_year: 1990,
            relationship: 'self',
            bbt_unit: 'celsius',
            weight_unit: 'kg',
          },
        ],
        p_day_entries: [],
      });
      expect(pushed.error).toBeNull();

      const date = '2026-09-10';
      const today = '2026-09-30';

      // -- The day editor loads an empty day for the owner ----------------
      const empty = await fetchDayView(ownerClient, { profileId, dateIso: date });
      expect(empty.entry).toBeNull();
      expect(empty.membership?.role).toBe('primary_guardian');

      // -- Save #1: every category in one push ----------------------------
      const ownerView = (await fetchDayView(ownerClient, {
        profileId,
        dateIso: date,
      })) as LoadedDayView;
      const firstSave = await saveDay(ownerClient, {
        profileId,
        dateIso: date,
        todayIso: today,
        tz: 'America/New_York',
        edit: edit({
          flow: 'medium',
          flowExplicitlySet: true,
          spotting: true,
          pms: true,
          tags: ['cramps', 'ovulation_peak'],
          note: 'logged on the web',
          notePrivate: true,
          bbt: 36.6,
          weight: 63.5,
          mode: 'tracking',
          manualCycleStart: true,
          excludeCycleFromAverage: false,
        }),
        view: ownerView,
        nowIso: '2026-09-30T08:00:00.000Z',
      });
      expect(firstSave.rejectedFields).toEqual([]);
      expect(firstSave.ourEntryDeclined).toBe(false);

      // -- The day reads back exactly as saved (the cache advanced too) ---
      const saved = await fetchDayView(ownerClient, { profileId, dateIso: date });
      expect(saved.entry?.flow).toBe('medium');
      expect(saved.entry?.note).toBe('logged on the web');
      expect(saved.entry?.note_private).toBe(true);
      expect(saved.entry?.pms).toBe(true);
      expect(saved.entry?.tags).toEqual(expect.arrayContaining(['cramps', 'ovulation_peak']));
      const categories = saved.observations.map((o) => o.category).sort();
      expect(categories).toEqual(['bbt', 'spotting', 'weight']);
      const bbt = saved.observations.find((o) => o.category === 'bbt');
      expect(bbt?.value_num).toBe(36.6);
      expect(bbt?.unit).toBe('celsius');
      expect(saved.cycleOverride?.manual_start).toBe(true);
      expect(saved.mode?.mode).toBe('tracking');

      // -- Same-date race #1: a phone pushes an OLDER write ---------------
      // Different ULID, same profile+date, older updated_at: the server's
      // resolver tombstones the loser (its tags union in), flow/note stay
      // last-writer-wins, and the web's read shows the resolution.
      const phoneId = newUlidHere();
      const phonePush = await ownerClient.rpc('sync_push', {
        p_profiles: [],
        p_day_entries: [
          {
            id: phoneId,
            profile_id: profileId,
            local_date: date,
            tz: 'America/New_York',
            flow: 'heavy',
            tags: ['headache'],
            note: 'typed on the phone earlier',
            updated_at: '2026-09-30T07:00:00.000Z', // one hour older
            source: 'manual',
          },
        ],
        p_observations: [],
      });
      expect(phonePush.error).toBeNull();

      const afterPhone = await fetchDayView(ownerClient, { profileId, dateIso: date });
      expect(afterPhone.entry?.id).not.toBe(phoneId);
      expect(afterPhone.entry?.note).toBe('logged on the web');

      // -- Same-date race #2: the phone wrote FIRST, the web saves LATER --
      const phoneFirstDate = '2026-09-11';
      const phoneWinId = newUlidHere();
      const phoneWins = await ownerClient.rpc('sync_push', {
        p_profiles: [],
        p_day_entries: [
          {
            id: phoneWinId,
            profile_id: profileId,
            local_date: phoneFirstDate,
            tz: 'America/New_York',
            flow: 'light',
            tags: [],
            note: 'phone got there first',
            updated_at: '2026-09-30T09:00:00.000Z',
            source: 'manual',
          },
        ],
        p_observations: [],
      });
      expect(phoneWins.error).toBeNull();

      const phoneFirstView = await fetchDayView(ownerClient, {
        profileId,
        dateIso: phoneFirstDate,
      });
      const webLoses = await saveDay(ownerClient, {
        profileId,
        dateIso: phoneFirstDate,
        todayIso: today,
        tz: 'America/New_York',
        edit: edit({ note: 'web writes later' }),
        view: phoneFirstView,
        nowIso: '2026-09-30T08:30:00.000Z', // older than the phone's 09:00
      });
      expect(webLoses.ourEntryDeclined).toBe(true);
      const afterDecline = await fetchDayView(ownerClient, {
        profileId,
        dateIso: phoneFirstDate,
      });
      expect(afterDecline.entry?.note).toBe('phone got there first');

      // -- Unknown payload keys are refused by the allowlist --------------
      // Per-row rejection, not a whole-call failure.
      const badKey = await ownerClient.rpc('sync_push', {
        p_profiles: [],
        p_day_entries: [
          {
            id: newUlidHere(),
            profile_id: profileId,
            local_date: date,
            tz: 'UTC',
            flow: 'none',
            some_future_key: true,
            updated_at: nowIso,
          },
        ],
        p_observations: [],
      });
      expect(badKey.error).toBeNull();
      const badKeyBody = badKey.data as { rejected: unknown[]; resolved: unknown[] };
      expect(badKeyBody.rejected).toHaveLength(1);
      expect(badKeyBody.resolved).toEqual([]);

      // -- A viewer is refused, and their read of the private note masked --
      const viewer = await adminCreateUser('viewer');
      createdUserIds.push(viewer.id);
      // Rows only a SECURITY DEFINER path writes in production: the
      // accepted viewer membership (an accepted invitation's product) and
      // the profile's designated subject (#802's is_subject — without a
      // subject, masking deliberately fails open to the owner).
      const memberInsert = await fetch(`${url}/rest/v1/profile_guardians`, {
        method: 'POST',
        headers: {
          apikey: serviceRoleKey,
          Authorization: `Bearer ${serviceRoleKey}`,
          'Content-Type': 'application/json',
          Prefer: 'return=minimal',
        },
        body: JSON.stringify({
          profile_id: profileId,
          user_id: viewer.id,
          role: 'viewer',
          status: 'accepted',
          is_subject: false,
        }),
      });
      expect(memberInsert.ok).toBe(true);
      const subjectStamp = await fetch(
        `${url}/rest/v1/profile_guardians?profile_id=eq.${profileId}&user_id=eq.${owner.id}`,
        {
          method: 'PATCH',
          headers: {
            apikey: serviceRoleKey,
            Authorization: `Bearer ${serviceRoleKey}`,
            'Content-Type': 'application/json',
            Prefer: 'return=minimal',
          },
          body: JSON.stringify({ is_subject: true }),
        },
      );
      expect(subjectStamp.ok).toBe(true);

      // The cache was fed by the OWNER's pulls; the viewer must not read
      // them — the reset mirrors the sign-out that separates users on the
      // web (resetWebDataForSignOut).
      getSyncedDataCache().reset();
      const viewerClient = await signInAs(viewer.email);
      const viewerView = await fetchDayView(viewerClient, { profileId, dateIso: date });
      // The viewer's read comes through sync_pull's mask: flag true, text gone.
      expect(viewerView.entry?.note_private).toBe(true);
      expect(viewerView.entry?.note).toBeNull();
      // The editor refuses to even build a payload for a viewer...
      await expect(
        saveDay(viewerClient, {
          profileId,
          dateIso: date,
          todayIso: today,
          tz: 'UTC',
          edit: edit({ note: 'the viewer tried' }),
          view: viewerView,
          nowIso: '2026-09-30T10:00:00.000Z',
        }),
      ).rejects.toThrowError(/viewer/);
      // ...and the server agrees with a direct push: the row lands in
      // `rejected`, never in day_entries.
      const viewerDirect = await viewerClient.rpc('sync_push', {
        p_profiles: [],
        p_day_entries: [
          {
            id: newUlidHere(),
            profile_id: profileId,
            local_date: date,
            tz: 'UTC',
            flow: 'none',
            note: 'the viewer tried directly',
            updated_at: '2026-09-30T10:00:00.000Z',
            source: 'manual',
          },
        ],
        p_observations: [],
      });
      expect(viewerDirect.error).toBeNull();
      const directBody = viewerDirect.data as {
        resolved: unknown[];
        rejected: { id: unknown; rejected: boolean }[];
      };
      expect(directBody.rejected).toHaveLength(1);
      expect(directBody.resolved).toEqual([]);

      // -- Back as the owner: the private note survived all of that -------
      getSyncedDataCache().reset();
      const ownerAgain = await signInAs(owner.email);
      const finalView = await fetchDayView(ownerAgain, { profileId, dateIso: date });
      expect(finalView.entry?.note).toBe('logged on the web');
      expect(finalView.entry?.note_private).toBe(true);
    },
  );
});
