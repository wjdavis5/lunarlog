// delete-account Edge Function (Issue #17, Unit U2; KTD1, KTD2, KTD4).
//
// The authenticated HTTP entry point for in-app account deletion. Thin by
// design: authenticate the caller from the Authorization header, check the
// Apple-code precondition (P1 fix below), run U1's `delete_account_data()`
// RPC as the caller (so RLS/auth.uid() semantics hold), revoke Apple when
// the account has an Apple identity (U3), re-home once more (P1 fix below),
// then delete the `auth.users` row last - the only irreversible,
// non-retryable step (KTD4). An Apple identity with no authorization code
// supplied fails closed exactly like a failed revocation - it never falls
// through to deleting the user with revocation silently skipped. Either
// way, a revoke failure (or a missing code) stops before that last step so
// the whole call stays retryable.
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
//     immediately before `auth.admin.deleteUser` (Step 6), narrowing - not
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
//     (Step 3 succeeded) - `unknown`'s client-side copy ("your account was
//     not deleted") is simply false there, and sending the operator to
//     "sign in again" is not the right guidance for a state this specific.
//
// #17 P1 round 2 fixes (2026-09-06), on top of the round-1 fixes above:
//   * Step 3's missing-Apple-code precondition used to return the same
//     `apple_revoke_failed` code as a real revocation failure. That code's
//     client-side copy says "your account data was deleted, but..." - true
//     for a real revoke failure (Step 3 already confirmed a code was
//     present, so Step 4's RPC has run by the time revocation is
//     attempted), but false here: this precondition fails *before* Step 4,
//     so nothing has been touched yet. It now returns its own
//     `apple_code_required` code with copy that accurately says nothing was
//     deleted and the operator just needs to retry with a fresh code.
//   * Step 6's re-home pass now calls `rehome_stray_day_entries` with an
//     explicit `p_user_id` on the service-role client, not the caller's own
//     `userClient`. The function's `EXECUTE` grant to `authenticated` has
//     been revoked (see the migration): a caller could otherwise invoke it
//     directly - including a guardian already revoked from a family - to
//     re-stamp `last_modified_by_user_id` on that family's `day_entries`
//     rows and wake their Realtime subscribers, exactly the
//     revocation-bypass class of bug this repo already closed elsewhere
//     (#81/#82). It is now reachable only from this service-role call and
//     from `delete_account_data()`'s own internal (security-definer) call.
//   * That Step 6 call now checks the `{ data, error }` result `rpc()`
//     actually returns instead of relying on a `catch` block: `rpc()`
//     resolves rather than throws for a Postgres-side error, so the old
//     `catch` alone could never observe a failed rehome and would log
//     nothing. The `catch` stays as a secondary net for a genuine thrown
//     exception (e.g. a network-level failure), but the primary path now
//     inspects `error` directly.
//
// Never echoes Supabase/Apple error text, tokens, emails, or row content
// into the response or the log: only a stable error `code`, an HTTP status,
// and (server-side only) an error *type* or U1's row-count summary are ever
// recorded, mirroring the `debugPrint('... (${error.runtimeType})')`
// discipline in `lib/`.
//
// This is the first Edge Function in the repo - there is no Deno tooling in
// CI yet (Open Question Q2). It is proven locally with
// `supabase functions serve` + curl (recorded in
// docs/ops/supabase-go-live.md) rather than an automated Deno test.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { revokeAppleToken } from "../_shared/apple_revoke.ts";

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

Deno.serve(async (req: Request) => {
  // Step 1: no Authorization header -> 401 without touching the database.
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return errorResponse("unauthorized", 401);
  }
  const jwt = authHeader.replace(/^Bearer\s+/i, "");

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // Step 1 (cont.): a user-scoped client. Every request it makes (including
  // the RPC below) carries the caller's own Authorization header, so
  // PostgREST evaluates delete_account_data() with auth.uid() = the caller
  // and RLS holds - this is what lets the RPC trust no id from the body.
  const userClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false },
    global: { headers: { Authorization: authHeader } },
  });

  // Step 2: resolve the caller. The body's only field is the optional Apple
  // code (AE6) - read after auth so an unauthenticated request never has
  // its body parsed.
  const { data: userData, error: userError } = await userClient.auth.getUser(
    jwt,
  );
  if (userError || !userData?.user) {
    return errorResponse("unauthorized", 401);
  }
  const user = userData.user;
  const body = await readBody(req);

  const providers = (user.identities ?? []).map((identity) => identity.provider);
  const appleCode = body.appleAuthorizationCode;
  const hasAppleIdentity = providers.includes("apple");

  // Step 3 (#17 P1 fix - moved ahead of the destructive RPC): an Apple
  // identity with no authorization code supplied fails closed here, before
  // any data is touched. This is reachable without any client bug: Apple
  // can be linked from a *different* device than the one calling delete,
  // and a stale/buggy client on this device would omit the code it was
  // never told to fetch. Previously this check ran after Step 4 below, so
  // it still let the row deletion happen first - unrecoverable, since a
  // deleted account can never supply a code to finish deleting itself.
  //
  // #17 P1 round 2 fix: a distinct `apple_code_required` code, not
  // `apple_revoke_failed`. That code is also used below (Step 5) for a real
  // revocation failure, where Step 4's RPC has already run and its
  // client-side copy correctly says "your account data was deleted, but...".
  // Reusing it here would say the same false thing about a call that never
  // touched a single row.
  if (hasAppleIdentity && !appleCode) {
    console.error(
      "delete-account: apple identity present but no authorization code supplied; nothing touched",
    );
    return errorResponse("apple_code_required", 400);
  }

  // Step 4: the row deletion (U1), run as the caller.
  let rowCounts: unknown;
  try {
    const { data, error } = await userClient.rpc("delete_account_data");
    if (error) throw error;
    rowCounts = data;
  } catch (error) {
    console.error(`delete-account: delete_account_data failed (${errorType(error)})`);
    return errorResponse("unknown", 500);
  }

  // Step 5: Apple revocation itself, now that Step 3 has already confirmed
  // a code was supplied whenever one is required. A revoke failure here
  // (as opposed to a missing code) stops before the user row is touched -
  // so the whole call is safe to retry (KTD4). Rows are already gone at
  // this point; retrying re-runs U1's RPC idempotently (it reports zero
  // counts the second time) and retries the Apple step.
  if (hasAppleIdentity) {
    const revoked = await revokeAppleToken(appleCode!);
    if (revoked.kind !== "ok") {
      console.error(
        `delete-account: apple revoke failed (${revoked.kind}); rows already removed`,
      );
      return errorResponse("apple_revoke_failed", 409);
    }
  }

  // A separate service-role client (auth.admin.* needs the service role;
  // Step 6 below also uses it now - see that step's comment).
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  // Step 6 (#17 P1 fix; round 2 fix on top): a second, best-effort re-home
  // pass immediately before the one irreversible step below.
  // delete_account_data() already ran this once (as its own step 0); Apple
  // revocation's network round trip (when applicable) is the main source of
  // the gap since. This narrows - it cannot fully close, see the
  // migration's comment - the window in which a stray write from this
  // caller's own device could still land on a profile they don't own and be
  // reached by that row's `on delete cascade` once Step 7 removes their
  // `auth.users` row.
  //
  // Round 2 fix: called on `adminClient` (service role) with an explicit
  // `p_user_id`, not on `userClient`. The function's `EXECUTE` grant to
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
  // (the account stays undeleted indefinitely). The `error` result is
  // checked directly (round 2 fix) - `rpc()` resolves with `{ data, error }`
  // rather than throwing on a Postgres-side failure, so a bare `catch` alone
  // could never have observed one; the `catch` here is only a secondary net
  // for a genuine thrown exception (e.g. a network-level failure).
  try {
    const { error: rehomeError } = await adminClient.rpc(
      "rehome_stray_day_entries",
      { p_user_id: user.id },
    );
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

  // Step 7: the user row, last (KTD4) - the only irreversible step.
  const { error: deleteUserError } = await adminClient.auth.admin.deleteUser(
    user.id,
  );
  if (deleteUserError) {
    // #17 P1 fix: a distinct code, not "unknown" - every server row this
    // account owns is already gone by this point (Step 4 succeeded), so
    // "your account was not deleted" (unknown's client-side copy) would be
    // false, and telling the operator to sign in again is not the right
    // guidance for this specific, narrow failure.
    console.error(
      `delete-account: auth.admin.deleteUser failed (${errorType(deleteUserError)}); rows already removed`,
    );
    return errorResponse("delete_user_failed", 500);
  }

  console.log("delete-account: succeeded", rowCounts);
  return jsonResponse({ ok: true }, 200);
});
