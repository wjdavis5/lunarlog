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
 */
export const inMemorySessionStorage = {
  getItem: (_key: string): Promise<string | null> => Promise.resolve(null),
  setItem: (_key: string, _value: string): Promise<void> => Promise.resolve(),
  removeItem: (_key: string): Promise<void> => Promise.resolve(),
};

/** Creates the typed client with the in-memory session storage wired in. */
export function createSupabaseClient(url: string, publishableKey: string): AppSupabaseClient {
  return createClient<Database>(url, publishableKey, {
    auth: { storage: inMemorySessionStorage },
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
