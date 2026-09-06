// delete-account Edge Function (Issue #17, Unit U2; KTD1, KTD2, KTD4).
//
// The authenticated HTTP entry point for in-app account deletion. Thin by
// design: authenticate the caller from the Authorization header, run U1's
// `delete_account_data()` RPC as the caller (so RLS/auth.uid() semantics
// hold), revoke Apple when the account has an Apple identity (U3), then
// delete the `auth.users` row last - the only irreversible, non-retryable
// step (KTD4). An Apple identity with no authorization code supplied fails
// closed exactly like a failed revocation - it never falls through to
// deleting the user with revocation silently skipped. Either way, a revoke
// failure (or a missing code) stops before that last step so the whole call
// stays retryable.
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

type ErrorCode = "unauthorized" | "apple_revoke_failed" | "unknown";

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

  // Step 3: the row deletion (U1), run as the caller.
  let rowCounts: unknown;
  try {
    const { data, error } = await userClient.rpc("delete_account_data");
    if (error) throw error;
    rowCounts = data;
  } catch (error) {
    console.error(`delete-account: delete_account_data failed (${errorType(error)})`);
    return errorResponse("unknown", 500);
  }

  // Step 4: Apple revocation, required whenever the account has an Apple
  // identity. Fail closed: an Apple identity with no code supplied (e.g. a
  // client bug, or a stale request replayed without a fresh code) stops
  // here exactly like a failed revocation, rather than proceeding to delete
  // the user with no revocation attempted at all. Either way this stops
  // before the user row is touched - so the whole call is safe to retry
  // (KTD4). Rows are already gone at this point; retrying re-runs U1's RPC
  // idempotently (it reports zero counts the second time) and retries the
  // Apple step.
  const providers = (user.identities ?? []).map((identity) => identity.provider);
  const appleCode = body.appleAuthorizationCode;
  if (providers.includes("apple")) {
    if (!appleCode) {
      console.error(
        "delete-account: apple identity present but no authorization code supplied; rows already removed",
      );
      return errorResponse("apple_revoke_failed", 409);
    }
    const revoked = await revokeAppleToken(appleCode);
    if (revoked.kind !== "ok") {
      console.error(
        `delete-account: apple revoke failed (${revoked.kind}); rows already removed`,
      );
      return errorResponse("apple_revoke_failed", 409);
    }
  }

  // Step 5: the user row, last (KTD4) - the only irreversible step, on a
  // separate service-role client (auth.admin.* needs the service role).
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
  const { error: deleteUserError } = await adminClient.auth.admin.deleteUser(
    user.id,
  );
  if (deleteUserError) {
    console.error(
      `delete-account: auth.admin.deleteUser failed (${errorType(deleteUserError)})`,
    );
    return errorResponse("unknown", 500);
  }

  console.log("delete-account: succeeded", rowCounts);
  return jsonResponse({ ok: true }, 200);
});
