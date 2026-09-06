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
// Against the cloud project instead: pass SUPABASE_API_URL plus that
// project's anon/service-role keys the same way. The script creates exactly
// one throwaway auth user, one profile, and one day_entries row, and tears
// all three (plus the sync_signals row they generate) down again in a
// `finally` -- including on a thrown assertion failure -- so repeated runs
// against the cloud project do not accumulate test users or leave
// real-looking minor's-health-log content (`note`/`tags`/`flow`) behind.
// As a second line of defence against a run that dies without reaching
// `finally` at all (Ctrl-C, SIGKILL, a crashed container), step 0 sweeps the
// two fixed throwaway row ids before creating anything -- see `preclean()`.
//
// Exit code 0 = PASS (sync_signals delivered a wake event containing only
// profile_id/updated_at, on a channel that genuinely reached Realtime and
// was accepted; day_entries/profiles delivered nothing at all -- and their
// channels genuinely reached Realtime and were genuinely refused, not just
// silent). Non-zero = FAIL; read the printed per-table results.
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

/** Everything `teardown()` has to clean up, at MODULE scope and populated by
 * `main()` *as each resource is created* -- never returned from `main()`.
 *
 * This is load-bearing, not style. A thrown assertion skips every remaining
 * statement in `main()`, including any trailing `return`, so a context handed
 * over by return value is still empty when the `finally` below runs: teardown
 * would print "[teardown] done." while leaving the auth user, the profile,
 * and the day_entries row (real-looking minor's-health-log content) behind on
 * exactly the failure paths that need cleanup most. Worse, `ulid(1)` is a
 * fixed literal and `profiles.id` carries a global unique constraint
 * (`profiles_id_uq`), so one leaked profile row permanently wedges this gate
 * for every later run -- and each wedged run leaks another auth user.
 * (PR #92 review round 3; both behaviours were reproduced before this fix.) */
const ctx = {
  channels: [],
  authed: null,
  profileId: null,
  dayEntryId: null,
  userId: null,
};

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
 * "RealtimeDisabledForConfiguration"-shaped error) -- a separate, slower
 * async step after the initial phx_reply ok -- or `null` if none arrives in
 * time. A fixed short delay races this and under-reports both false passes
 * (writing before the subscription is actually wired up) and false
 * failures. `null` here must be treated as a failure by the caller: it means
 * Realtime never told us *anything* about the postgres_changes binding, so
 * "boundary held" and "the subscription never actually went through" are
 * indistinguishable without this settling first. */
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

/** Removes the two fixed-id throwaway rows before the run creates them, so a
 * previous run that was killed outright (Ctrl-C, SIGKILL, a container that
 * went away) cannot wedge this gate forever on `profiles_id_uq`. Deleting the
 * profile FK-cascades its day_entries and profile_guardians rows, and its
 * AFTER DELETE trigger (`profiles_after_change_signal`) drops the matching
 * sync_signals row -- sync_signals deliberately has no FK to profiles, see the
 * migration header. The explicit day_entries delete just avoids depending on
 * that cascade. Any row this actually removes is a leftover, so say so loudly
 * rather than quietly papering over it. */
async function preclean(profileId, dayEntryId) {
  for (const [table, column, value] of [
    ['day_entries', 'id', dayEntryId],
    ['profiles', 'id', profileId],
  ]) {
    const { data, error } = await admin.from(table).delete().eq(column, value).select(column);
    if (error) {
      console.error(`[0/8] pre-clean of ${table} failed:`, error.message);
    } else if (data?.length) {
      console.warn(
        `[0/8] WARNING: removed ${data.length} leftover ${table} row(s) from an earlier `
          + 'run that died before teardown -- investigate why that run was killed.'
      );
    }
  }
}

async function main() {
  const profileId = ulid(1);
  const dayEntryId = ulid(2);

  console.log('[0/8] pre-cleaning any leftover throwaway rows from a killed earlier run ...');
  await preclean(profileId, dayEntryId);

  console.log('[1/8] creating a test user and signing in ...');
  const { data: created, error: createErr } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (createErr) throw createErr;
  ctx.userId = created.user.id;

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
  ctx.authed = authed;

  // Registered BEFORE the inserts, not after: if an insert half-succeeds or a
  // later step throws, teardown still knows which ids to delete.
  ctx.profileId = profileId;
  ctx.dayEntryId = dayEntryId;

  console.log('[2/8] inserting a profile as the authenticated user (creates guardian membership via trigger) ...');
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
    '[3/8] subscribing on three SEPARATE channels, one table each -- this mirrors '
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
  // Registered before `subscribe()`, so a channel that errors during
  // subscription is still removed by teardown.
  ctx.channels.push(syncSignalsChannel, dayEntriesChannel, profilesChannel);

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
  console.log('[4/8] per-table postgres_changes settle results:');
  console.log(JSON.stringify(settleResults, null, 2));

  // Every channel above must have genuinely reached Realtime and gotten a
  // real answer about its postgres_changes binding -- `null` (timeout, no
  // system message at all) means we cannot tell "Realtime correctly
  // refused this table" from "this subscription never actually went
  // through", which is exactly the false-pass PR #92 review round 2 found:
  // previously these settle results were only logged, never asserted on,
  // so a channel that silently never subscribed looked identical to one
  // that subscribed and correctly received nothing.
  for (const name of ['sync_signals', 'day_entries', 'profiles']) {
    if (!settleResults[name]) {
      throw new Error(
        `${name} channel produced no postgres_changes settle message at all `
          + 'within the timeout -- the subscription never genuinely connected, '
          + 'so nothing below can be trusted as a real privacy boundary check'
      );
    }
  }
  if (settleResults.sync_signals.status !== 'ok') {
    throw new Error(
      'sync_signals postgres_changes subscription did not settle "ok" -- '
        + `got: ${JSON.stringify(settleResults.sync_signals)}`
    );
  }

  console.log(
    '[5/8] updating the profile AFTER subscribing -- this is the actual test of the '
      + 'profiles boundary. (The insert in step 2 happened before any channel '
      + 'subscribed, so on its own it could never have proven the profiles channel '
      + 'delivers nothing; PR #92 review round 2.)'
  );
  const { error: profileUpdateErr } = await authed
    .from('profiles')
    .update({ display_name: 'Verification Child (updated)', updated_at: new Date().toISOString() })
    .eq('id', profileId);
  if (profileUpdateErr) throw profileUpdateErr;

  console.log('[6/8] inserting a day_entries row with note/tags/flow set ...');
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

  console.log('[7/8] waiting for Realtime delivery (6s) ...');
  await new Promise((r) => setTimeout(r, 6000));

  console.log('[8/8] results:');
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
    console.error('FAIL: profiles is not supposed to be published, but received', received.profiles.length, 'event(s) (from the post-subscribe update in step 5)');
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

  if (!ok) {
    throw new Error('RESULT: FAIL -- see printed FAIL lines above');
  }
  console.log(
    '\nRESULT: PASS -- both subscriptions genuinely connected; sync_signals delivered '
      + 'a wake event (only profile_id/updated_at) for the post-subscribe profile '
      + 'update and the day_entries insert; day_entries/profiles delivered nothing, '
      + 'against a real local Supabase Realtime container.'
  );
}

async function teardown({ channels, authed, profileId, dayEntryId, userId }) {
  console.log('\n[teardown] removing channels and deleting test data ...');
  if (channels?.length && authed) {
    await Promise.all(channels.map((ch) => authed.removeChannel(ch).catch(() => {})));
  }
  // Deletes run as the service-role admin client, not the authenticated
  // test user: the schema deliberately grants no DELETE privilege to
  // `authenticated` on day_entries/profiles (soft-delete only, KTD15), so
  // cleanup here has to bypass that the same way an admin/service-role
  // action would. Order matters only for tidiness (profiles delete already
  // cascades day_entries via the FK; deleting the day_entries row first
  // just avoids relying on that cascade for this script's own cleanup).
  //
  // A cleanup failure is a FAILURE OF THE RUN, not a footnote: it means a
  // day_entries row carrying `note`/`tags`/`flow` (or the profile it hangs
  // off) is still sitting in the target project -- against the cloud project
  // that is exactly the outcome this script's header promises cannot happen.
  // Logging it while exiting 0 would let a PASS banner sit on top of leaked
  // content, so each failed delete forces a distinct non-zero exit code
  // instead (PR #92 review round 3, #10).
  let cleanupFailed = false;
  const failed = (what, error) => {
    cleanupFailed = true;
    console.error(`[teardown] failed to delete ${what}:`, error.message);
  };
  if (dayEntryId) {
    const { error } = await admin.from('day_entries').delete().eq('id', dayEntryId);
    if (error) failed('day_entries row', error);
  }
  if (profileId) {
    const { error } = await admin.from('profiles').delete().eq('id', profileId);
    if (error) failed('profile row', error);
  }
  if (userId) {
    const { error } = await admin.auth.admin.deleteUser(userId);
    if (error) failed('auth user', error);
  }
  if (cleanupFailed) {
    console.error(
      '[teardown] INCOMPLETE -- throwaway rows may still be present in the target '
        + 'project; delete them by hand before re-running.'
    );
    process.exitCode = process.exitCode || 3;
    return;
  }
  console.log('[teardown] done.');
}

main()
  .catch((e) => {
    console.error('verify_realtime_delivery.mjs failed:', e);
    process.exitCode = process.exitCode || 1;
  })
  .finally(async () => {
    try {
      await teardown(ctx);
    } catch (teardownErr) {
      console.error('[teardown] crashed:', teardownErr);
      process.exitCode = process.exitCode || 2;
    }
    process.exit(process.exitCode ?? 0);
  });
