import { createClient } from '@supabase/supabase-js';
import type { SupabaseClient } from '@supabase/supabase-js';

import type { Database } from '../../../supabase/database.types';

import { webAuth } from './auth';
import { hasSupabase, supabasePublishableKey, supabaseUrl } from './config';

/**
 * The web client's Supabase client, typed against the committed schema
 * snapshot `supabase/database.types.ts` — the web client is that file's
 * first consumer (issue #1249): a migration that changes a shape this
 * client reads fails this project's typecheck, and CI's `db-tests` job
 * fails the other direction when the snapshot drifts from the migrations.
 */
export type AppSupabaseClient = SupabaseClient<Database>;

/**
 * A real in-memory session store, one fresh adapter per client instance.
 *
 * Under the `accessToken` option (issue #1250) this is belt-and-braces:
 * that option is what actually keeps supabase-js from ever touching
 * session storage — per its own contract the `auth` namespace is unusable
 * on a client created with it, so no session is ever persisted or read
 * back. If a future change removed the option, this adapter keeps the
 * browser at-rest-empty rather than silently reverting to localStorage.
 *
 * For clients created without the option (issue #1252's integration
 * fakes) it is the session store itself, and it must be a REAL store:
 * the scaffold's no-op stub dropped the session the instant supabase-js
 * re-read it, so every request after a sign-in went out as `anon` and the
 * synced RPCs (granted to `authenticated` only) failed with "permission
 * denied". Reads return what was written, nothing ever reaches the
 * browser's at-rest storage, and one adapter PER client means two clients
 * (a test's multi-user scenario, or two accounts in one process) can
 * never read each other's session.
 */
export function createInMemorySessionStorage() {
  const store = new Map<string, string>();
  return {
    getItem: (key: string): Promise<string | null> => Promise.resolve(store.get(key) ?? null),
    setItem: (key: string, value: string): Promise<void> => {
      store.set(key, value);
      return Promise.resolve();
    },
    removeItem: (key: string): Promise<void> => {
      store.delete(key);
      return Promise.resolve();
    },
  };
}
/**
 * Creates the typed client. The app client (issue #1250) passes
 * `getAccessToken`: every request then carries the in-memory access token
 * from the web auth client, renewed through the same-origin Worker's
 * `/auth/session` when it nears expiry. Callers that omit it (issue
 * #1252's integration fakes) get a storage-backed client over its own
 * per-instance in-memory adapter.
 */
export function createSupabaseClient(
  url: string,
  publishableKey: string,
  getAccessToken?: () => Promise<string | null>,
): AppSupabaseClient {
  return createClient<Database>(url, publishableKey, {
    ...(getAccessToken === undefined ? {} : { accessToken: getAccessToken }),
    auth: { storage: createInMemorySessionStorage() },
  });
}

let client: AppSupabaseClient | null = null;

/**
 * The memoised app client, or `null` while the build is unconfigured
 * (no `VITE_SUPABASE_*` defines — the default for every PR build).
 */
export function getSupabaseClient(): AppSupabaseClient | null {
  if (!hasSupabase) {
    return null;
  }
  if (client === null) {
    client = createSupabaseClient(supabaseUrl, supabasePublishableKey, () =>
      webAuth.getToken(),
    );
  }
  return client;
}

/** Test seam: drop the memoised client so a test re-creates it. */
export function resetSupabaseClientForTests(): void {
  client = null;
}
