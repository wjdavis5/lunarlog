// delete-account Edge Function (Issue #17, Unit U2; KTD1, KTD2, KTD4).
//
// The authenticated HTTP entry point for in-app account deletion. Thin by
// design: authenticate the caller from the Authorization header, check the
// Apple-code precondition (P1 fix below), remove the caller's
// feedback-attachments Storage objects (Issue #243/D-24 fix, reordered
// round 2 - see below), run U1's `delete_account_data()` RPC as the caller
// (so RLS/auth.uid() semantics hold), revoke Apple when the account has an
// Apple identity (U3), re-home once more (P1 fix below), then delete the
// `auth.users` row last - the only irreversible, non-retryable step (KTD4).
// An Apple identity with no authorization code supplied fails closed
// exactly like a failed revocation - it never falls through to deleting the
// user with revocation silently skipped. Either way, a revoke failure (or a
// missing code, or an attachment-cleanup failure) stops before that last
// step so the whole call stays retryable.
//
// #17 P1 fixes (2026-09-06), on top of the original U1-U4 implementation:
//   * The missing-Apple-code precondition now runs *before* the destructive
//     RPC (Step 3 below), not after it. Previously a client that omitted
//     the code (a stale/buggy client, or an attacker calling from a device
//     that never linked Apple) still triggered the row deletion before the
//     check failed - unrecoverable data loss for an account that could
//     never finish deleting from that device. A missing code now fails
//     closed with nothing touched at all.
//   * A second, best-effort call to `rehome_stray_day_entries()` runs
//     immediately before `auth.admin.deleteUser` (Step 7), narrowing - not
//     closing - the window between the RPC's one-time re-home and the
//     `auth.users` row actually being removed, during which a stray write
//     from this caller's own device could in principle still land on a
//     profile they don't own and be reached by that row's
//     `on delete cascade`. Closing this fully would mean pausing this
//     user's sync engine for the whole flow, which is out of scope here;
//     see `20260906120000_account_deletion_final_rehome.sql` for the full
//     writeup of the residual risk and why this pass is best-effort.
//   * A failure in the final `auth.admin.deleteUser` step now returns its
//     own `delete_user_failed` code rather than the generic `unknown` one.
//     By that point every server row this account owns is already gone
//     (Step 5 succeeded) - `unknown`'s client-side copy ("your account was
//     not deleted") is simply false there, and sending the operator to
//     "sign in again" is not the right guidance for a state this specific.
//
// #17 P1 round 2 fixes (2026-09-06), on top of the round-1 fixes above:
//   * Step 3's missing-Apple-code precondition used to return the same
//     `apple_revoke_failed` code as a real revocation failure. That code's
//     client-side copy says "your account data was deleted, but..." - true
//     for a real revoke failure (Step 3 already confirmed a code was
//     present, so Step 5's RPC has run by the time revocation is
//     attempted), but false here: this precondition fails *before* Step 5,
//     so nothing has been touched yet. It now returns its own
//     `apple_code_required` code with copy that accurately says nothing was
//     deleted and the operator just needs to retry with a fresh code.
//   * Step 7's re-home pass now calls `rehome_stray_day_entries` with an
//     explicit `p_user_id` on the service-role client, not the caller's own
//     `userClient`. The function's `EXECUTE` grant to `authenticated` has
//     been revoked (see the migration): a caller could otherwise invoke it
//     directly - including a guardian already revoked from a family - to
//     re-stamp `last_modified_by_user_id` on that family's `day_entries`
//     rows and wake their Realtime subscribers, exactly the
//     revocation-bypass class of bug this repo already closed elsewhere
//     (#81/#82). It is now reachable only from this service-role call and
//     from `delete_account_data()`'s own internal (security-definer) call.
//   * That Step 7 call now checks the `{ data, error }` result `rpc()`
//     actually returns instead of relying on a `catch` block: `rpc()`
//     resolves rather than throws for a Postgres-side error, so the old
//     `catch` alone could never observe a failed rehome and would log
//     nothing. The `catch` stays as a secondary net for a genuine thrown
//     exception (e.g. a network-level failure), but the primary path now
//     inspects `error` directly.
//
// Issue #243 fix (2026-09-08), on top of the round-2 fixes above (D-24):
//   * A new step lists and removes every Storage object under the caller's
//     `<uid>/` prefix in the `feedback-attachments` bucket (path convention:
//     `<uid>/<ticket_id>/<uuid>.<ext>`, see
//     `20260906140000_feedback_attachments_bucket.sql`). This step is
//     **fail-closed**: a listing or removal failure returns its own
//     `attachment_cleanup_failed` code (409, mirroring `apple_revoke_failed`'s
//     shape) - `storage.objects.owner` is `on delete set null` rather than a
//     hard FK, so once the auth.users row is gone the object would be
//     orphaned (reachable only by the service role) rather than actually
//     removed, and a bug report's screenshot can be health data.
//   * `delete_account_data()` itself now also deletes the caller's
//     `feedback_tickets` (and their cascaded `feedback_replies`) explicitly,
//     rather than relying on the `auth.users on delete cascade` this final
//     step triggers (D-25) - see
//     `20260908130000_account_deletion_feedback_tickets.sql`.
//   * Refactored to an injected-dependencies `handleDeleteAccount(req,
//     deps)` shape, mirroring `feedback-notify/index.ts`'s
//     `handleFeedbackNotify`/`buildDeps` split, so the new attachment-
//     removal step and its fail-closed path can be covered by `deno test`
//     with fakes (see index.test.ts) - previously this function had no
//     automated Deno coverage at all (Open Question Q2), only the manual
//     `supabase functions serve` + curl smoke tests in
//     docs/ops/supabase-go-live.md. This refactor moves the existing logic
//     behind `deps` without changing its behavior; it does not add coverage
//     for every branch (e.g. the Apple-revoke paths remain proven only by
//     the curl runbook) - only as much as the new attachment-removal step
//     and its fail-closed path need.
//
// Issue #243 round 2 fix (2026-09-08), on top of the fix above:
//   * The attachment-cleanup step (originally Step 7, between the
//     best-effort rehome pass and `auth.admin.deleteUser`) now runs as
//     **Step 4**, immediately after the apple_code_required precondition and
//     *before* `delete_account_data()` and Apple revocation, not after them.
//     Previously a `409 attachment_cleanup_failed` still meant every row was
//     already gone and Apple already revoked - retryable in name only, since
//     "nothing was deleted" was false. Now the same failure leaves every
//     row, the Apple grant, and the `auth.users` row itself untouched, so
//     the call is genuinely retryable and its client-side copy's "nothing
//     was deleted" claim is actually true.
//   * The Storage listing that backs this step now paginates: `list()` is
//     called in a loop with `offset`, at every level, until a page returns
//     fewer entries than the requested `limit` - the original single-call
//     `{ limit: 1000 }` silently truncated a caller with more than 1000
//     objects (or more than 1000 ticket folders) at any one level.
//   * The listing also now recurses into a nested folder entry (a null
//     `id`) to any depth, not just one level per ticket folder - the
//     bucket's insert policy (`20260906140000_feedback_attachments_bucket.sql`)
//     only constrains the *first* path segment (the uid), so a client
//     could in principle write `<uid>/a/b/c.png`, which the old one-level
//     listing would never see (and so would never remove).
//   * `removeAttachmentPaths` now calls Storage `remove()` in batches of
//     at most 100 paths, rather than one call carrying every path - keeping
//     each request to a bounded size regardless of how many attachments a
//     caller has.
//   * The `attachmentsRemoved` count is now included in the success log
//     line, at zero privacy cost (it is a count, never a path or filename).
//   * Restored `auth: { persistSession: false }` on both the user-scoped
//     and service-role clients in `buildDeps` - present in every version of
//     this function before the `handleDeleteAccount(req, deps)` refactor
//     above, and dropped by it. Neither client's `.auth.getUser`/`.rpc`/
//     `.auth.admin.*` calls carry a session worth persisting (Edge
//     Functions are stateless per invocation regardless), but leaving the
//     option at its library default rather than the explicit off this
//     function always used is a needless behavior change to carry forward.
//
// Never echoes Supabase/Apple error text, tokens, emails, or row content
// into the response or the log: only a stable error `code`, an HTTP status,
// and (server-side only) an error *type* or U1's row-count summary are ever
// recorded, mirroring the `debugPrint('... (${error.runtimeType})')`
// discipline in `lib/`.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { revokeAppleToken, type AppleRevokeResult } from "../_shared/apple_revoke.ts";

/** The private Storage bucket feedback attachments live in (Issue #6, U2;
 * see `20260906140000_feedback_attachments_bucket.sql`). Object paths are
 * shaped `<uid>/<ticket_id>/<uuid>.<ext>`. */
const FEEDBACK_ATTACHMENTS_BUCKET = "feedback-attachments";

interface DeleteAccountRequestBody {
  /** A fresh Sign in with Apple authorization code, obtained by the client
   * at delete time (KTD3) - omitted for a non-Apple account. Any other
   * field (in particular a user id) is never read: the subject is always
   * the verified caller from the Authorization header (AE6). */
  appleAuthorizationCode?: string;
}

type ErrorCode =
  | "unauthorized"
  | "apple_code_required"
  | "apple_revoke_failed"
  | "attachment_cleanup_failed"
  | "delete_user_failed"
  | "unknown";

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function errorResponse(code: ErrorCode, status: number): Response {
  return jsonResponse({ ok: false, code }, status);
}

/** The error's type name only - never its message, which can embed a
 * Supabase/Apple response body, an email, or row content. */
function errorType(error: unknown): string {
  if (error instanceof Error) return error.constructor.name;
  return typeof error;
}

async function readBody(req: Request): Promise<DeleteAccountRequestBody> {
  try {
    const raw = await req.text();
    if (!raw) return {};
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    const code = parsed.appleAuthorizationCode;
    return typeof code === "string" ? { appleAuthorizationCode: code } : {};
  } catch {
    // A malformed body must not block deletion - it only ever supplies an
    // optional Apple code, never anything the delete depends on (AE6).
    return {};
  }
}

/** The verified caller, resolved from their own Authorization header. */
export interface DeleteAccountCaller {
  id: string;
  /** Every identity provider linked to this account (e.g. "apple", "google",
   * "email"). Used only to detect an Apple-linked account (AE6). */
  providers: string[];
}

/** Every real I/O call `handleDeleteAccount` needs, injected so tests can
 * supply fakes instead of a live Supabase project / Apple credentials. */
export interface DeleteAccountDeps {
  /** Resolves the caller from their forwarded Authorization header. Null on
   * any invalid/failed lookup. */
  getUser(authHeader: string): Promise<DeleteAccountCaller | null>;
  /** Lists every object path under `<uid>/` in the feedback-attachments
   * bucket, paginating and recursing into nested folders to any depth
   * (Issue #243/D-24; round 2 fix). Null on any listing failure - the
   * caller must treat that the same as a removal failure and fail the
   * whole deletion closed, before any row is touched. */
  listAttachmentPaths(uid: string): Promise<string[] | null>;
  /** Removes the given object paths from the feedback-attachments bucket,
   * batching internally. Resolves false on any removal failure. Never
   * called with an empty array. */
  removeAttachmentPaths(paths: string[]): Promise<boolean>;
  /** Runs `delete_account_data()` as the caller (user-scoped client, so
   * RLS/auth.uid() semantics hold) - the row-deletion half of account
   * deletion (U1). */
  deleteAccountData(authHeader: string): Promise<{ data: unknown; error: unknown }>;
  /** Exchanges and revokes a Sign in with Apple authorization code (U3). */
  revokeApple(authorizationCode: string): Promise<AppleRevokeResult>;
  /** Best-effort re-home pass on the service-role client with an explicit
   * caller id (#17 P1 round 2 fix - see the header comment). */
  rehomeStrayDayEntries(uid: string): Promise<{ error: unknown }>;
  /** Deletes the `auth.users` row - the only irreversible step (KTD4). */
  deleteUser(uid: string): Promise<{ error: unknown }>;
}

/** The full request-handling logic (Issue #17 U2/U3; Issue #243/D-24
 * attachment cleanup). See the header comment for the full step-by-step
 * contract and the fixes layered onto it over time. */
export async function handleDeleteAccount(req: Request, deps: DeleteAccountDeps): Promise<Response> {
  // Step 1: no Authorization header -> 401 without touching the database.
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return errorResponse("unauthorized", 401);
  }

  // Step 2: resolve the caller. The body's only field is the optional Apple
  // code (AE6) - read after auth so an unauthenticated request never has
  // its body parsed.
  const user = await deps.getUser(authHeader);
  if (!user) {
    return errorResponse("unauthorized", 401);
  }
  const body = await readBody(req);

  const appleCode = body.appleAuthorizationCode;
  const hasAppleIdentity = user.providers.includes("apple");

  // Step 3 (#17 P1 fix - moved ahead of the destructive RPC): an Apple
  // identity with no authorization code supplied fails closed here, before
  // any data is touched. This is reachable without any client bug: Apple
  // can be linked from a *different* device than the one calling delete,
  // and a stale/buggy client on this device would omit the code it was
  // never told to fetch. Previously this check ran after Step 5 below, so
  // it still let the row deletion happen first - unrecoverable, since a
  // deleted account can never supply a code to finish deleting itself.
  //
  // #17 P1 round 2 fix: a distinct `apple_code_required` code, not
  // `apple_revoke_failed`. That code is also used below (Step 6) for a real
  // revocation failure, where Step 5's RPC has already run and its
  // client-side copy correctly says "your account data was deleted, but...".
  // Reusing it here would say the same false thing about a call that never
  // touched a single row.
  if (hasAppleIdentity && !appleCode) {
    console.error(
      "delete-account: apple identity present but no authorization code supplied; nothing touched",
    );
    return errorResponse("apple_code_required", 400);
  }

  // Step 4 (Issue #243/D-24; reordered ahead of row deletion by the round 2
  // fix, 2026-09-08): remove the caller's feedback-attachments Storage
  // objects. Fail-closed - see the header comment for why
  // (storage.objects.owner is `on delete set null`, not a hard FK, so a
  // deleted auth.users row would leave the object orphaned rather than
  // removed, and it can hold a screenshot of a family's cycle data). This
  // now runs *before* delete_account_data() and Apple revocation, not after
  // them: a listing or removal failure here leaves every row, the Apple
  // grant, and the auth.users row itself untouched, so "nothing was
  // deleted" (the client's attachmentCleanupFailed copy) is actually true,
  // and a retry starts completely fresh rather than re-running an
  // already-idempotent RPC.
  const attachmentPaths = await deps.listAttachmentPaths(user.id);
  if (attachmentPaths === null) {
    console.error(
      "delete-account: attachment listing failed; nothing touched, so the whole account stays untouched and retryable",
    );
    return errorResponse("attachment_cleanup_failed", 409);
  }
  if (attachmentPaths.length > 0) {
    const removed = await deps.removeAttachmentPaths(attachmentPaths);
    if (!removed) {
      console.error(
        "delete-account: attachment removal failed; nothing touched, so the whole account stays untouched and retryable",
      );
      return errorResponse("attachment_cleanup_failed", 409);
    }
  }

  // Step 5: the row deletion (U1), run as the caller.
  let rowCounts: unknown;
  try {
    const { data, error } = await deps.deleteAccountData(authHeader);
    if (error) throw error;
    rowCounts = data;
  } catch (error) {
    console.error(`delete-account: delete_account_data failed (${errorType(error)})`);
    return errorResponse("unknown", 500);
  }

  // Step 6: Apple revocation itself, now that Step 3 has already confirmed
  // a code was supplied whenever one is required. A revoke failure here
  // (as opposed to a missing code) stops before the user row is touched -
  // so the whole call is safe to retry (KTD4). Rows are already gone at
  // this point; retrying re-runs U1's RPC idempotently (it reports zero
  // counts the second time) and retries the Apple step.
  if (hasAppleIdentity) {
    const revoked = await deps.revokeApple(appleCode!);
    if (revoked.kind !== "ok") {
      console.error(
        `delete-account: apple revoke failed (${revoked.kind}); rows already removed`,
      );
      return errorResponse("apple_revoke_failed", 409);
    }
  }

  // Step 7 (#17 P1 fix; round 2 fix on top): a second, best-effort re-home
  // pass immediately before the irreversible step below.
  // delete_account_data() already ran this once (as its own step 0); Apple
  // revocation's network round trip (when applicable) is the main source of
  // the gap since. This narrows - it cannot fully close, see the
  // migration's comment - the window in which a stray write from this
  // caller's own device could still land on a profile they don't own and be
  // reached by that row's `on delete cascade` once Step 8 removes their
  // `auth.users` row.
  //
  // Round 2 fix: called with an explicit `p_user_id` on the service-role
  // client, not the caller's own client. The function's `EXECUTE` grant to
  // `authenticated` has been revoked (see the migration) precisely so a
  // client - including a guardian already revoked from a family - cannot
  // call it directly to re-stamp `last_modified_by_user_id` on rows in a
  // family they no longer have access to. It is now reachable only from
  // here and from `delete_account_data()`'s own internal call.
  //
  // Best-effort on purpose: the RPC already covers the overwhelming
  // majority of the risk surface, and failing an otherwise-successful,
  // already-confirmed deletion over this purely defensive extra pass would
  // trade a small, already-narrow residual risk for a certain bad outcome
  // (the account stays undeleted indefinitely).
  try {
    const { error: rehomeError } = await deps.rehomeStrayDayEntries(user.id);
    if (rehomeError) {
      console.error(
        `delete-account: final rehome pass failed (${errorType(rehomeError)}); proceeding to delete the user anyway`,
      );
    }
  } catch (error) {
    console.error(
      `delete-account: final rehome pass threw unexpectedly (${errorType(error)}); proceeding to delete the user anyway`,
    );
  }

  // Step 8: the user row, last (KTD4) - the only irreversible step.
  const { error: deleteUserError } = await deps.deleteUser(user.id);
  if (deleteUserError) {
    // #17 P1 fix: a distinct code, not "unknown" - every server row this
    // account owns is already gone by this point (Step 5 succeeded), so
    // "your account was not deleted" (unknown's client-side copy) would be
    // false, and telling the operator to sign in again is not the right
    // guidance for this specific, narrow failure.
    console.error(
      `delete-account: auth.admin.deleteUser failed (${errorType(deleteUserError)}); rows already removed`,
    );
    return errorResponse("delete_user_failed", 500);
  }

  console.log("delete-account: succeeded", rowCounts, { attachmentsRemoved: attachmentPaths.length });
  return jsonResponse({ ok: true }, 200);
}

/** The environment `buildDeps` needs. A plain object (rather than reading
 * `Deno.env` itself) so tests can supply fixed values with no `--allow-env`
 * permission, mirroring `feedback-notify/index.ts`'s `FeedbackNotifyEnv`. */
export interface DeleteAccountEnv {
  supabaseUrl: string | undefined;
  anonKey: string | undefined;
  serviceRoleKey: string | undefined;
}

/** Matches `feedback-notify/index.ts`'s `SupabaseClientFactory` shape so a
 * test's fake client can satisfy both. `any` return is deliberate: this
 * seam exists so `buildDeps` never needs the full `SupabaseClient` generic
 * surface, only the handful of calls it actually makes below. */
// deno-lint-ignore no-explicit-any
export type SupabaseClientFactory = (url: string, key: string, options?: Record<string, unknown>) => any;

/** Page size for each Storage `list()` call (Issue #243 round 2 fix,
 * 2026-09-08) - matches the fixed `{ limit: 1000 }` this listing used
 * before pagination was added. `listFolderPaths` below loops on `offset`
 * until a page returns fewer than this many entries, at every level, so a
 * caller with more objects (or more ticket folders) than this at any one
 * level is no longer silently truncated. */
const LIST_PAGE_SIZE = 1000;

/** The maximum number of paths passed to a single Storage `remove()` call
 * (Issue #243 round 2 fix) - keeps each request to a bounded size
 * regardless of how many attachments a caller has, rather than one call
 * carrying every path. */
const REMOVE_BATCH_SIZE = 100;

/** Lists every object path under `prefix` in `bucket`, paginating with
 * `offset` until a page returns fewer than `LIST_PAGE_SIZE` entries, and
 * recursing into any nested folder entry (Supabase Storage marks a folder
 * with a null `id`; a real object has a non-null one) to any depth - not
 * just one level per ticket folder (Issue #243 round 2 fix). The
 * `feedback-attachments` bucket's insert policy only constrains the first
 * path segment (the uid), so `<uid>/a/b/c.png` is a possible path a
 * one-level-deep listing would miss. Returns null - rather than throwing -
 * on any listing failure at any depth or page, so the whole cleanup fails
 * closed (Issue #243/D-24).
 */
async function listFolderPaths(
  // deno-lint-ignore no-explicit-any
  bucket: any,
  prefix: string,
): Promise<string[] | null> {
  const paths: string[] = [];
  let offset = 0;
  for (;;) {
    const { data: entries, error } = await bucket.list(prefix, {
      limit: LIST_PAGE_SIZE,
      offset,
    });
    if (error) return null;
    const page: Array<{ id: string | null; name: string }> = entries ?? [];
    for (const entry of page) {
      if (entry.id === null) {
        const sub = await listFolderPaths(bucket, `${prefix}/${entry.name}`);
        if (sub === null) return null;
        paths.push(...sub);
      } else {
        paths.push(`${prefix}/${entry.name}`);
      }
    }
    if (page.length < LIST_PAGE_SIZE) break;
    offset += LIST_PAGE_SIZE;
  }
  return paths;
}

/** Lists every object path under `<uid>/` in the feedback-attachments
 * bucket (see `listFolderPaths` above for the pagination/recursion
 * contract). */
async function listFeedbackAttachmentPaths(
  // deno-lint-ignore no-explicit-any
  adminClient: any,
  uid: string,
): Promise<string[] | null> {
  const bucket = adminClient.storage.from(FEEDBACK_ATTACHMENTS_BUCKET);
  return listFolderPaths(bucket, uid);
}

/** Builds the production `DeleteAccountDeps` as a plain function of its
 * environment and a client factory, independent of `import.meta.main`/
 * `Deno.serve` - mirroring `feedback-notify/index.ts`'s `buildDeps`, so
 * `deno test` can actually evaluate this production wiring (including the
 * real Storage list/remove calls) rather than only ever exercising a
 * hand-rolled test double for it. */
export function buildDeps(env: DeleteAccountEnv, clientFactory: SupabaseClientFactory): DeleteAccountDeps {
  const { supabaseUrl, anonKey, serviceRoleKey } = env;
  // Issue #243 round 2 fix: `persistSession: false` restored - present on
  // every client this function created before the `handleDeleteAccount`
  // refactor above, and dropped by it. Neither client below carries a
  // session worth persisting across an Edge Function invocation, but this
  // keeps the explicit-off behavior the function always had rather than
  // silently falling back to the library default.
  const adminClient = clientFactory(supabaseUrl!, serviceRoleKey!, {
    auth: { persistSession: false },
  });

  return {
    getUser: async (authHeader) => {
      const jwt = authHeader.replace(/^Bearer\s+/i, "");
      const userClient = clientFactory(supabaseUrl!, anonKey!, {
        auth: { persistSession: false },
        global: { headers: { Authorization: authHeader } },
      });
      const { data, error } = await userClient.auth.getUser(jwt);
      if (error || !data?.user) return null;
      const providers = (data.user.identities ?? []).map(
        // deno-lint-ignore no-explicit-any
        (identity: any) => identity.provider,
      );
      return { id: data.user.id, providers };
    },
    listAttachmentPaths: (uid) => listFeedbackAttachmentPaths(adminClient, uid),
    removeAttachmentPaths: async (paths) => {
      for (let i = 0; i < paths.length; i += REMOVE_BATCH_SIZE) {
        const batch = paths.slice(i, i + REMOVE_BATCH_SIZE);
        const { error } = await adminClient.storage.from(FEEDBACK_ATTACHMENTS_BUCKET).remove(batch);
        if (error) return false;
      }
      return true;
    },
    deleteAccountData: async (authHeader) => {
      const userClient = clientFactory(supabaseUrl!, anonKey!, {
        auth: { persistSession: false },
        global: { headers: { Authorization: authHeader } },
      });
      const { data, error } = await userClient.rpc("delete_account_data");
      return { data, error };
    },
    revokeApple: (authorizationCode) => revokeAppleToken(authorizationCode),
    rehomeStrayDayEntries: async (uid) => {
      const { error } = await adminClient.rpc("rehome_stray_day_entries", { p_user_id: uid });
      return { error };
    },
    deleteUser: async (uid) => {
      const { error } = await adminClient.auth.admin.deleteUser(uid);
      return { error };
    },
  };
}

// Guarded so `index.test.ts` can import `handleDeleteAccount`/`buildDeps`
// without this module trying to bind a real network listener (which
// `deno test` runs with no `--allow-net`), and without reading `Deno.env`
// (`deno test` runs with no `--allow-env` either) - `import.meta.main` is
// true only when Deno runs this file directly, which is how the Supabase
// Edge Runtime invokes it in production, mirroring
// `feedback-notify/index.ts`'s same guard.
if (import.meta.main) {
  Deno.serve(async (req) => {
    const deps = buildDeps(
      {
        supabaseUrl: Deno.env.get("SUPABASE_URL"),
        anonKey: Deno.env.get("SUPABASE_ANON_KEY"),
        serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
      },
      createClient,
    );
    return handleDeleteAccount(req, deps);
  });
}
