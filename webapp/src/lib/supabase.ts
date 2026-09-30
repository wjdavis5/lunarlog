import { createClient } from '@supabase/supabase-js';
import type { SupabaseClient } from '@supabase/supabase-js';

import type { Database } from '../../../supabase/database.types';

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
 * The only session storage the web client allows: an in-memory adapter.
 * supabase-js would otherwise persist the session to localStorage —
 * exactly the at-rest state the nothing-stored rule bans. The session
 * lives in page memory and dies with the tab; the browser keeps nothing.
 *
 * Issue #1252: the scaffold's version stubbed every method to no-ops,
 * which dropped the session the instant supabase-js re-read it — every
 * request after a sign-in went out as `anon`, and the synced RPCs
 * (`sync_push`/`sync_pull` grant `EXECUTE` to `authenticated` only)
 * failed with "permission denied". This is a real in-memory store: reads
 * return what was written, nothing ever reaches the browser's at-rest
 * storage (the storage-empty e2e guard still holds).
 *
 * One adapter PER client: every client instance gets its own store, so
 * two clients (a test's multi-user scenario, or two accounts in one
 * process) can never read each other's session.
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

/** Creates the typed client with its own in-memory session storage wired in. */
export function createSupabaseClient(url: string, publishableKey: string): AppSupabaseClient {
  return createClient<Database>(url, publishableKey, {
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
    client = createSupabaseClient(supabaseUrl, supabasePublishableKey);
  }
  return client;
}

/** Test seam: drop the memoised client so a test re-creates it. */
export function resetSupabaseClientForTests(): void {
  client = null;
}
