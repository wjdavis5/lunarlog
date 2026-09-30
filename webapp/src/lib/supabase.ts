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
 * An inert storage adapter, wired as belt-and-braces under the `accessToken`
 * option (issue #1250): that option is what actually keeps supabase-js from
 * ever touching session storage — per its own contract, the `auth`
 * namespace is not usable on a client created with it, so no session is
 * ever persisted or read back. If a future change removed the option, this
 * adapter would keep the browser at-rest-empty rather than silently
 * reverting to localStorage.
 */
export const inMemorySessionStorage = {
  getItem: (_key: string): Promise<string | null> => Promise.resolve(null),
  setItem: (_key: string, _value: string): Promise<void> => Promise.resolve(),
  removeItem: (_key: string): Promise<void> => Promise.resolve(),
};

/**
 * Creates the typed client whose every request carries the in-memory
 * access token from the web auth client (issue #1250): the browser's only
 * credential, renewed through the same-origin Worker's /auth/session when
 * it nears expiry.
 */
export function createSupabaseClient(
  url: string,
  publishableKey: string,
  getAccessToken: () => Promise<string | null>,
): AppSupabaseClient {
  return createClient<Database>(url, publishableKey, {
    accessToken: getAccessToken,
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
