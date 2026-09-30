import { createClient } from '@supabase/supabase-js';
import { describe, expect, it } from 'vitest';

import type { Database } from '../../supabase/database.types';

import { fetchDayView, saveDay } from '../src/lib/day/day-data';
import type { DayEdit, LoadedDayView } from '../src/lib/day/payloads';
import type { AppSupabaseClient } from '../src/lib/supabase';

/**
 * Issue #1254's round-trip: the web day editor's write path (saveDay → the
 * real sync_push RPC) against a REAL local `supabase start` stack — the
 * same discipline as the Dart round trip (issue #102, CI's db-tests job
 * runs that right before this one). What only this test can catch is a
 * drift between the web payload shapes and the live SQL: per-row
 * rejections, LWW declines, the same-date merge, RLS, and the note-privacy
 * masking all answer for real.
 *
 * Runs ONLY when a local Supabase stack is reachable (skips otherwise, so
 * plain `npm run test` on a plain checkout stays green and visibly skips).
 * CI's db-tests job runs it for real against the same booted stack, right
 * after the Dart round trip.
 *
 * The default keys are the universal local-development JWTs every
 * `supabase start` project issues (iss supabase-demo — not secrets; see
 * `supabase status -o env`). The service-role key is used for exactly two
 * calls: creating email-confirmed test users (the local stack's
 * enable_confirmations means a plain signUp yields no session), and
 * installing an accepted-viewer profile_guardians row (production creates
 * it through the SECURITY DEFINER invitation path; the row shape is what
 * that path writes). Everything else runs as ordinary authenticated users.
 */

const stackUrl = process.env['LUNARLOG_LOCAL_SUPABASE_URL'] ?? 'http://127.0.0.1:54321';
const publishableKey =
  process.env['LUNARLOG_LOCAL_SUPABASE_PUBLISHABLE_KEY'] ??
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
const serviceRoleKey =
  process.env['LUNARLOG_LOCAL_SUPABASE_SERVICE_ROLE_KEY'] ??
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

type AdminClient = ReturnType<typeof createClient<Database, 'public'>>;

async function stackReachable(): Promise<boolean> {
  try {
    // No AbortSignal.timeout here: vitest's jsdom realm mints its own
    // AbortSignal, and Node's fetch rejects the cross-realm instance.
    const response = await Promise.race([
      fetch(`${stackUrl}/rest/v1/`, { headers: { apikey: publishableKey } }),
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
if (!reachable) {
  console.log(
    `[skip] ${stackUrl} unreachable — start a local stack (AGENTS.md Migration Flow) to run the issue #1254 round trip`,
  );
}

/** Minimal inline ULID mint for test data: 10-char timestamp + random tail
 * in Crockford base32 — the same shape the server's c_ulid pattern admits. */
function generateUlidHere(): string {
  const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  let time = Date.now();
  let out = '';
  for (let i = 0; i < 10; i++) {
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

async function createUser(admin: AdminClient, label: string) {
  const email = `${label}-${Date.now()}-${Math.floor(Math.random() * 1e6)}@roundtrip.local`;
  const password = 'WebRoundTrip#1254x';
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (error !== null || data.user === null) {
    throw new Error(`createUser failed: ${error?.message ?? 'no user'}`);
  }
  // persistSession: false keeps every test client's session in its own
  // memory — under vitest's jsdom the default storage is a SHARED
  // localStorage, and a client picking up another client's stored session
  // would run its PostgREST calls as the wrong user.
  const client = createClient<Database>(stackUrl, publishableKey, {
    auth: { persistSession: false },
  }) as AppSupabaseClient;
  const { error: signInError } = await client.auth.signInWithPassword({ email, password });
  if (signInError !== null)
    throw new Error(`signInWithPassword failed: ${signInError.message}`);
  return { client, uid: data.user.id };
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

describe.skipIf(!reachable)(
  'issue #1254: the web day editor round-trips through the live sync_push',
  () => {
    it(
      'saves every category and reads it back; the same-date races resolve by ' +
        "the server's rules; a viewer is refused; a private note is masked",
      { timeout: 120_000 },
      async () => {
        const admin = createClient<Database>(stackUrl, serviceRoleKey, {
          auth: { persistSession: false },
        }) as unknown as AdminClient;
        const owner = await createUser(admin, 'webday-owner');

        // The profile is created the way the app creates one — pushed through
        // sync_push's profiles array, so the on_profile_created_add_guardian
        // trigger gives the caller an accepted primary_guardian membership
        // exactly as in production.
        const profileId = generateUlidHere();
        const nowIso = new Date().toISOString();
        const pushed = await owner.client.rpc('sync_push', {
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
        const empty = await fetchDayView(owner.client, { profileId, dateIso: date });
        expect(empty.entry).toBeNull();
        expect(empty.membership?.role).toBe('primary_guardian');

        // -- Save #1: every category in one push ----------------------------
        const ownerView = (await fetchDayView(owner.client, {
          profileId,
          dateIso: date,
        })) as LoadedDayView;
        const firstSave = await saveDay(owner.client, {
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

        // -- The day reads back exactly as saved ----------------------------
        const saved = await fetchDayView(owner.client, { profileId, dateIso: date });
        expect(saved.entry?.flow).toBe('medium'); // flow chip was set explicitly
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
        const phoneId = generateUlidHere();
        const phonePush = await owner.client.rpc('sync_push', {
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

        const afterPhone = await fetchDayView(owner.client, { profileId, dateIso: date });
        expect(afterPhone.entry?.id).not.toBe(phoneId);
        expect(afterPhone.entry?.note).toBe('logged on the web');

        // -- Same-date race #2: the phone wrote FIRST, the web saves LATER --
        const phoneFirstDate = '2026-09-11';
        const phoneWinId = generateUlidHere();
        const phoneWins = await owner.client.rpc('sync_push', {
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

        const phoneFirstView = await fetchDayView(owner.client, {
          profileId,
          dateIso: phoneFirstDate,
        });
        const webLoses = await saveDay(owner.client, {
          profileId,
          dateIso: phoneFirstDate,
          todayIso: today,
          tz: 'America/New_York',
          edit: edit({ note: 'web writes later' }),
          view: phoneFirstView,
          nowIso: '2026-09-30T08:30:00.000Z', // older than the phone's 09:00
        });
        expect(webLoses.ourEntryDeclined).toBe(true);
        const afterDecline = await fetchDayView(owner.client, {
          profileId,
          dateIso: phoneFirstDate,
        });
        expect(afterDecline.entry?.note).toBe('phone got there first');

        // -- Unknown payload keys are refused by the allowlist --------------
        const badKey = await owner.client.rpc('sync_push', {
          p_profiles: [],
          p_day_entries: [
            {
              id: generateUlidHere(),
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
        // Per-row rejection, not a whole-call failure: the handler puts the
        // row in `rejected` and the call succeeds.
        const badKeyBody = badKey.data as { rejected: unknown[]; resolved: unknown[] };
        expect(badKey.error).toBeNull();
        expect(badKeyBody.rejected).toHaveLength(1);
        expect(badKeyBody.resolved).toEqual([]);

        // -- A viewer is refused, and their read of the private note masked --
        const viewer = await createUser(admin, 'webday-viewer');
        // The membership row an accepted viewer invitation produces.
        const inserted = await (
          admin as unknown as {
            from: (table: string) => {
              insert: (
                row: Record<string, unknown>,
              ) => Promise<{ error: { message: string } | null }>;
            };
          }
        )
          .from('profile_guardians')
          .insert({
            profile_id: profileId,
            user_id: viewer.uid,
            role: 'viewer',
            status: 'accepted',
            is_subject: false,
          });
        expect(inserted.error).toBeNull();

        // A profile only masks once it HAS a designated subject (#802: the
        // marker rides the accepted invitation's is_subject; a fresh
        // self-created profile fails open to the owner by design). The
        // service role stamps the owner's membership into the state an
        // accepted subject-invitation produces.
        const stamped = await (
          admin as unknown as {
            from: (table: string) => {
              update: (row: Record<string, unknown>) => {
                eq: (
                  column: string,
                  value: unknown,
                ) => {
                  eq: (
                    column: string,
                    value: unknown,
                  ) => Promise<{ error: { message: string } | null }>;
                };
              };
            };
          }
        )
          .from('profile_guardians')
          .update({ is_subject: true })
          .eq('profile_id', profileId)
          .eq('user_id', owner.uid);
        expect(stamped.error).toBeNull();

        const viewerView = await fetchDayView(viewer.client, { profileId, dateIso: date });
        // The viewer's read comes through sync_pull's mask: flag true, text gone.
        expect(viewerView.entry?.note_private).toBe(true);
        expect(viewerView.entry?.note).toBeNull();
        // The editor refuses to even build a payload for a viewer...
        await expect(
          saveDay(viewer.client, {
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
        const viewerDirect = await viewer.client.rpc('sync_push', {
          p_profiles: [],
          p_day_entries: [
            {
              id: generateUlidHere(),
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

        // -- And the owner's private note is untouched by all of that -------
        const finalView = await fetchDayView(owner.client, { profileId, dateIso: date });
        expect(finalView.entry?.note).toBe('logged on the web');
        expect(finalView.entry?.note_private).toBe(true);
      },
    );
  },
);
