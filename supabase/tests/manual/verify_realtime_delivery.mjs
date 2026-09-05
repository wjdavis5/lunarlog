// MANUAL, NOT CI (Issue #77 / PR #92 review, R5, KTD4).
//
// Local and CI Supabase both start with `-x realtime` (see AGENTS.md,
// .github/workflows/ci.yml), so there is no Realtime container for pgTAP or
// any other CI job to assert against -- `supabase/tests/realtime_publication_test.sql`
// proves catalog state and trigger behavior only. This script is the actual
// end-to-end proof: it starts a real websocket session against a real
// Supabase Realtime container and asserts what is *actually delivered*,
// which is the exact thing a publication column list on the source tables
// would not have controlled (see the migration's header comment).
//
// Run this against local Supabase (with realtime NOT excluded) before every
// merge that touches supabase/migrations/20260905100000_realtime_publication.sql
// or lib/data/sync/realtime_sync_coordinator.dart, or against the cloud
// project's Realtime the same way. It is intentionally not wired into CI:
// promoting it would mean adding the realtime/kong/auth containers to every
// pgTAP run for one migration's regression coverage, and this project's own
// database-test job explicitly avoids paying that cost (KTD4).
//
// Usage (PowerShell or bash), from a clean local Supabase:
//   cd supabase/tests/manual
//   npm install
//   npx --yes supabase@2.116.0 start -x storage-api,imgproxy,mailpit,studio,edge-runtime,logflare,vector,supavisor
//   npx --yes supabase@2.116.0 status   # copy ANON key and SERVICE_ROLE key
//   ANON_KEY=... SERVICE_ROLE_KEY=... node verify_realtime_delivery.mjs
//   npx --yes supabase@2.116.0 stop --no-backup
//
// Exit code 0 = PASS (sync_signals delivered a wake event containing only
// profile_id/updated_at; day_entries/profiles delivered nothing at all --
// Realtime itself refuses to subscribe to them with
// "RealtimeDisabledForConfiguration" since they are not publication
// members). Non-zero = FAIL; read the printed per-table results.
import { createClient } from '@supabase/supabase-js';

const API_URL = process.env.SUPABASE_API_URL ?? 'http://127.0.0.1:54321';
const ANON_KEY = process.env.ANON_KEY;
const SERVICE_ROLE_KEY = process.env.SERVICE_ROLE_KEY;
if (!ANON_KEY || !SERVICE_ROLE_KEY) {
  console.error(
    'ANON_KEY / SERVICE_ROLE_KEY env vars are required -- copy them from '
      + '`npx supabase@2.116.0 status` (or the cloud project settings).'
  );
  process.exit(2);
}

const admin = createClient(API_URL, SERVICE_ROLE_KEY);
const email = `verify-realtime-${Date.now()}@test.local`;
const password = 'correct horse battery staple 1!';

/** A 26-char ULID-shaped literal satisfying this schema's ULID check
 * constraints; only needs to be unique within one run of this script. */
function ulid(seed) {
  const base = '01ARZ3NDEKTSV4RRFFQ69G5';
  const s = seed.toString().padStart(3, '0').slice(-3);
  const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  const c = [...s].map((ch) => alphabet[Number(ch) % 32]).join('');
  return base + c;
}

/** Resolves with the channel's first `postgres_changes` system message
 * (Realtime's own "Subscribed to PostgreSQL" ok, or a
 * "RealtimeDisabledForConfiguration" error) -- a separate, slower async step
 * after the initial phx_reply ok -- or `null` if none arrives in time. A
 * fixed short delay races this and under-reports both false passes (writing
 * before the subscription is actually wired up) and false failures. */
function waitForPostgresSubscriptionSettled(channel, timeoutMs = 8000) {
  return new Promise((resolve) => {
    let settled = false;
    channel.on('system', {}, (payload) => {
      if (settled) return;
      if (payload.extension === 'postgres_changes') {
        settled = true;
        resolve(payload);
      }
    });
    setTimeout(() => {
      if (!settled) resolve(null);
    }, timeoutMs);
  });
}

async function main() {
  console.log('[1/7] creating a test user and signing in ...');
  const { data: created, error: createErr } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (createErr) throw createErr;
  void created;

  const anon = createClient(API_URL, ANON_KEY);
  const { data: signIn, error: signInErr } = await anon.auth.signInWithPassword({ email, password });
  if (signInErr) throw signInErr;

  const authed = createClient(API_URL, ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${signIn.session.access_token}` } },
    accessToken: async () => signIn.session.access_token,
    realtime: {
      log_level: 'info',
      logger: (kind, msg, data) => console.log('[rt]', kind, msg, JSON.stringify(data)),
    },
  });

  const profileId = ulid(1);
  const dayEntryId = ulid(2);

  console.log('[2/7] inserting a profile as the authenticated user (creates guardian membership via trigger) ...');
  const { error: profileErr } = await authed.from('profiles').insert({
    id: profileId,
    display_name: 'Verification Child',
    is_minor: true,
    sort_order: 0,
    updated_at: new Date().toISOString(),
  });
  if (profileErr) throw profileErr;

  const received = { sync_signals: [], day_entries: [], profiles: [] };

  console.log(
    '[3/7] subscribing on three SEPARATE channels, one table each -- this mirrors '
      + 'RealtimeSyncCoordinator exactly (one table per channel). Mixing an '
      + 'unpublished table into the same join as sync_signals was observed to abort '
      + 'setup for the whole channel, silently swallowing the valid subscription too, '
      + 'so this script never does that.'
  );

  const syncSignalsChannel = authed
    .channel(`verify:sync_signals:${profileId}`)
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'sync_signals', filter: `profile_id=eq.${profileId}` },
      (payload) => received.sync_signals.push(payload)
    );
  const dayEntriesChannel = authed
    .channel(`verify:day_entries:${profileId}`)
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'day_entries', filter: `profile_id=eq.${profileId}` },
      (payload) => received.day_entries.push(payload)
    );
  const profilesChannel = authed
    .channel(`verify:profiles:${profileId}`)
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'profiles', filter: `id=eq.${profileId}` },
      (payload) => received.profiles.push(payload)
    );

  const settleResults = {};
  await Promise.all(
    [
      ['sync_signals', syncSignalsChannel],
      ['day_entries', dayEntriesChannel],
      ['profiles', profilesChannel],
    ].map(
      ([name, ch]) =>
        new Promise((resolve, reject) => {
          const settlePromise = waitForPostgresSubscriptionSettled(ch).then((r) => {
            settleResults[name] = r;
          });
          ch.subscribe((status, err) => {
            if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
              reject(err ?? new Error(`${name}: ${status}`));
            }
            if (status === 'SUBSCRIBED') {
              resolve(settlePromise);
            }
          });
        })
    )
  );
  console.log('[4/7] per-table postgres_changes settle results (informational -- the real proof is step 7):');
  console.log(JSON.stringify(settleResults, null, 2));

  console.log('[5/7] inserting a day_entries row with note/tags/flow set ...');
  const { error: dayErr } = await authed.from('day_entries').insert({
    id: dayEntryId,
    profile_id: profileId,
    local_date: '2026-09-05',
    tz: 'UTC',
    flow: 'heavy',
    tags: ['cramps', 'headache'],
    note: 'PRIVATE-CONTENT-MARKER-should-never-reach-the-websocket',
    updated_at: new Date().toISOString(),
  });
  if (dayErr) throw dayErr;

  console.log('[6/7] waiting for Realtime delivery (6s) ...');
  await new Promise((r) => setTimeout(r, 6000));

  console.log('[7/7] results:');
  console.log('  sync_signals events:', JSON.stringify(received.sync_signals, null, 2));
  console.log('  day_entries events:', JSON.stringify(received.day_entries, null, 2));
  console.log('  profiles events:', JSON.stringify(received.profiles, null, 2));

  const noteLeaked = JSON.stringify(received).includes('PRIVATE-CONTENT-MARKER');

  let ok = true;
  if (received.sync_signals.length === 0) {
    console.error('FAIL: expected at least one sync_signals event, got none');
    ok = false;
  }
  if (received.day_entries.length !== 0) {
    console.error('FAIL: day_entries is not supposed to be published, but received', received.day_entries.length, 'event(s)');
    ok = false;
  }
  if (received.profiles.length !== 0) {
    console.error('FAIL: profiles is not supposed to be published, but received', received.profiles.length, 'event(s)');
    ok = false;
  }
  if (noteLeaked) {
    console.error('FAIL: entry note content leaked into a Realtime payload');
    ok = false;
  }
  const syncSignalsKeys = new Set(
    received.sync_signals.flatMap((e) => Object.keys(e.new ?? {}).concat(Object.keys(e.old ?? {})))
  );
  const allowed = new Set(['profile_id', 'updated_at']);
  for (const k of syncSignalsKeys) {
    if (!allowed.has(k)) {
      console.error('FAIL: unexpected column in sync_signals payload:', k);
      ok = false;
    }
  }

  await Promise.all(
    [syncSignalsChannel, dayEntriesChannel, profilesChannel].map((ch) => authed.removeChannel(ch))
  );

  if (!ok) {
    console.error('\nRESULT: FAIL');
    process.exit(1);
  }
  console.log(
    '\nRESULT: PASS -- sync_signals delivered a wake event (only profile_id/updated_at); '
      + 'day_entries/profiles delivered nothing, against a real local Supabase Realtime container.'
  );
}

main().catch((e) => {
  console.error('verify_realtime_delivery.mjs crashed:', e);
  process.exit(2);
});
