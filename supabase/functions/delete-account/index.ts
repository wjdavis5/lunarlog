// delete-account Edge Function (Issue #17, Unit U2; KTD1, KTD2, KTD4).
//
// The authenticated HTTP entry point for in-app account deletion. Thin by
// design: authenticate the caller from the Authorization header, check the
// Apple-code precondition (P1 fix below), remove the caller's
// feedback-attachments Storage objects (Issue #243/D-24 fix, reordered
// round 2 - see below), run U1's `delete_account_data()` RPC as the caller
// (so RLS/auth.uid() semantics hold), revoke Apple when the account has an
// Apple identity and hasn't already been revoked by a prior attempt (U3;
// Issue #527 below), re-home once more (P1 fix below), then delete the
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
//     profile they don't own and be reached by that row's `on delete cascade`.
//     Closing this fully would mean pausing this user's sync engine for the
//     whole flow, which is out of scope here; see
//     `20260906120000_account_deletion_final_rehome.sql` for the full
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
// Issue #559 fix (2026-09-13): the listing above paginated and recursed to
// any depth, but stayed *unbounded* in total object count and depth - a
// caller who PUTs a few thousand objects under their own uid prefix (nothing
// in the bucket's insert policy caps count, depth, or per-ticket size) could
// make listing alone exceed the function's wall clock, and every retry would
// fail identically: an in-app account deletion made permanently impossible
// by the account's own owner, entirely within policy. `listFolderPaths` now
// enforces MAX_ATTACHMENT_OBJECTS/MAX_ATTACHMENT_DEPTH caps, surfaced as a
// distinct `attachment_cleanup_unbounded` (422) code rather than the generic
// `attachment_cleanup_failed` - support-routed rather than silently
// unretryable, per the issue's fix.
//
// Issue #560 fix (2026-09-13): the Apple authorization code was exchanged
// and its refresh token revoked without ever checking *whose* Apple grant it
// belonged to - Apple's `client_id` binding on the token endpoint only
// proves the code was minted for this app, not for the calling user. An
// attacker holding a valid code for victim B could call delete-account
// authenticated as themselves while supplying B's code, revoking B's grant
// instead of their own. `getUser` now also resolves the caller's own Apple
// identity id (`identities[provider=="apple"].id`) and passes it to
// `revokeApple`, which (see `_shared/apple_revoke.ts`) decodes the
// exchanged `id_token`'s `sub` and refuses to revoke on a mismatch. A
// GoTrue response that omits `identities` entirely (as opposed to a
// present-but-empty array - a determination *failure*, not "no linked
// identities") now fails the whole deletion closed rather than silently
// treating the account as non-Apple and skipping revocation, the one
// non-fail-closed Apple branch this file used to have.
//
// Issue #527 fix (2026-09-13): a `deleteUser` failure (Step 8) used to
// strand the account permanently whenever it had an Apple identity - Apple
// authorization codes are one-time-use, so a retry's fresh code exchange
// still hits an already-revoked grant on Apple's side, resolving to
// `apple_rejected` -> `apple_revoke_failed` (409) -> a return *before*
// `deleteUser` is ever attempted again. `public.account_deletion_progress`
// (a new migration) now records `apple_revoked_at` the instant revocation
// actually succeeds, checked before Steps 3/6 run: once set, a retry skips
// both the Apple-code precondition and the revoke call entirely and goes
// straight back to `deleteUser` - the only step that could have failed and
// left the account stranded. Every supabase-js call in this file is also
// now wrapped with `withTimeout` (a hung call, unlike every third-party
// fetch in `_shared/apple_revoke.ts`/`_shared/push.ts`, previously had no
// bound of its own here).
//
// Issue #605 fix (2026-09-14, LLA-051, P1): the #527 marker above was keyed
// only by `user_id`, with no record of *which* Apple identity had actually
// been revoked. Reproduction: revoke identity A, persist the marker, then
// `deleteUser` fails (the account survives); the operator unlinks A and
// links a different Apple identity B to the same account, then retries.
// `appleAlreadyRevoked` used to ask only "does a marker exist for this
// user_id", so the retry skipped Steps 3/6 for B entirely and went straight
// to `deleteUser` - B's own Apple grant was never revoked, even though the
// call reported success. `account_deletion_progress` now also carries
// `apple_identity_id` (`20260914103000_account_deletion_cross_guardian_and_identity_fixes.sql`),
// stamped alongside `apple_revoked_at`; a retry's marker is honored only
// when that recorded identity still matches the caller's *current*
// `appleIdentityId` - a marker for a since-replaced identity no longer
// short-circuits anything, and the new identity gets its own code-and-revoke
// pass exactly like a first attempt would.
//
// Issue #599 fix (2026-09-14): Step 6's `apple_revoked_at` marker write used
// to be best-effort - a failure there was only logged, never surfaced. If
// that write then failed right after a real, successful Apple revocation,
// and the later `deleteUser` call also failed (e.g. a network blip), a
// retry would re-enter this function with no marker to find: Apple's
// one-time authorization code was already burned by the successful revoke,
// so the retry's *fresh* code would need to revoke a grant that no longer
// exists to revoke - a narrower re-entry of #527 with no way out. The
// marker write is now retried once in `buildDeps` (see `markAppleRevoked`),
// and if both attempts fail, Step 6 fails the whole call closed with its
// own `apple_revocation_marker_failed` (409) - distinct from
// `apple_revoke_failed` (Apple DID confirm the revocation here; only this
// durability write failed) - before `deleteUser` is ever attempted.
//
// Issue #599 fix, part 2 (2026-09-15) - the Storage-attachment-ordering
// residual (PR #664 only landed the markAppleRevoked half above): Issue
// #243's round-2 fix deliberately keeps the feedback-attachments Storage
// removal (Step 4) BEFORE the destructive RPC, so a Storage failure leaves
// the whole account untouched and retryable. That is still the right
// design (reversing it would reintroduce the exact orphaned-object problem
// #243 fixed) - but it means a LATER step's failure (Apple revoke,
// deleteUser) can leave a surviving account whose feedback_tickets rows
// still list `attachment_paths` pointing at objects that no longer exist,
// since D-25's `delete_account_data()` row deletion never ran. Step 4 now
// clears `feedback_tickets.attachment_paths` (to `[]`) for every one of the
// caller's own tickets immediately after Storage cleanup is confirmed
// complete - using the caller's own user-scoped client and the
// pre-existing owner-scoped `feedback_tickets_update` policy/column grant
// (`20260906130000_feedback_tickets.sql`), no new RPC or grant needed. This
// runs UNCONDITIONALLY, not only when this call itself found objects to
// remove: a retry after a PRIOR attempt's Storage removal succeeded but
// this same clear step then failed would otherwise see zero objects to
// list (they are already gone) and, if the clear were skipped whenever
// nothing was listed, would never revisit the stale references it left
// behind. Fails closed with the same `attachment_cleanup_failed` code as
// the listing/removal failures above (nothing else has run yet, so "nothing
// was deleted" is still true) - a failure here leaves a stale-but-harmless
// reference (the object really is gone; only the pointer to it survives)
// and the whole call stays retryable, exactly like every other Step 4
// failure.
//
// Never echoes Supabase/Apple error text, tokens, emails, or row content
// into the response or the log: only a stable error `code`, an HTTP status,
// and (server-side only) an error *type* or U1's row-count summary are ever
// recorded, mirroring the `debugPrint('... (${error.runtimeType})')`
// discipline in `lib/`.
//
// Issue #268 fix (2026-09-15): a new Step 2.5, run immediately after the
// identities check and before anything else is touched, requires an aal2
// session whenever the caller's account has a verified TOTP factor
// enrolled. This is a *server-side* enforcement point on top of the client
// UI's own AAL2 step-up dialog (`lib/ui/account/mfa_step_up_dialog.dart`) -
// a client that skipped or bypassed that dialog (a stale build, a direct
// API call) is refused here regardless, with its own `mfa_required` (401)
// code, before Step 3's Apple-code precondition or any destructive step.
// `aal` is read directly from the already-verified JWT's own claims
// (`decodeJwtAal` below) rather than from a second network round trip -
// `userClient.auth.getUser(jwt)` already proved the token's signature is
// valid, so this is a pure claim read, not a fresh trust decision. No
// runtime behavior changes for an account with no verified factor (the
// overwhelming majority today, since TOTP enrolment ships in this same
// issue) - see AGENTS.md/CLAUDE.md's note that this function's source hash
// changes as release evidence regardless.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { revokeAppleToken, type AppleRevokeResult } from "../_shared/apple_revoke.ts";

/** The private Storage bucket feedback attachments live in (Issue #6, U2;
 * see `20260906140000_feedback_attachments_bucket.sql`). Object paths are
 * shaped `<uid>/<ticket_id>/<uuid>.<ext>`. */
const FEEDBACK_ATTACHMENTS_BUCKET = "feedback-attachments";

/** Issue #527: a hung supabase-js call (unlike every third-party fetch in
 * this file's `_shared` dependencies, which already carry their own
 * `AbortSignal.timeout`) previously had no bound at all here - a network
 * partition mid-call could park an invocation indefinitely between two
 * steps whose ordering this file's header comment depends on. */
const SUPABASE_CALL_TIMEOUT_MS = 10_000;

/** Issue #559: caps on the feedback-attachments listing this function does
 * before touching any row, so a caller who PUTs enough objects under their
 * own uid prefix (nothing in the bucket's insert policy bounds count or
 * depth) cannot make listing alone exceed the function's wall clock and so
 * make their own account permanently undeletable. Generous relative to the
 * product's own 3-attachments-per-ticket cap (a different CHECK, on
 * feedback_tickets) while still comfortably inside a single invocation's
 * time budget. */
const MAX_ATTACHMENT_OBJECTS = 2000;
const MAX_ATTACHMENT_DEPTH = 8;

/** Races [promise] against a timeout so a hung supabase-js call cannot park
 * this invocation indefinitely (Issue #527). Rejects with a plain `Error` on
 * timeout; each call site below folds that into whatever failure shape it
 * already returns for any other error (null, `{ error }`, `false`, etc.),
 * so this stays one small, reusable primitive rather than a special case at
 * every call site. Untyped (`any` in, `any` out) rather than generic:
 * `clientFactory`'s own `any` return (see `SupabaseClientFactory` below)
 * already means every supabase-js call site this wraps was untyped before
 * this function existed - a generic signature here just relocates that
 * `any` into a type-parameter inference that, for an `any`-typed argument,
 * TypeScript resolves to `unknown` with nothing further to narrow it. */
// deno-lint-ignore no-explicit-any
function withTimeout(promise: Promise<any>, ms: number = SUPABASE_CALL_TIMEOUT_MS): Promise<any> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`supabase call timed out after ${ms}ms`)), ms);
    promise.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (error) => {
        clearTimeout(timer);
        reject(error);
      },
    );
  });
}

interface DeleteAccountRequestBody {
  /** A fresh Sign in with Apple authorization code, obtained by the client
   * at delete time (KTD3) - omitted for a non-Apple account. Any other
   * field (in particular a user id) is never read: the subject is always
   * the verified caller from the Authorization header (AE6). */
  appleAuthorizationCode?: string;
}

type ErrorCode =
  | "unauthorized"
  | "identity_check_failed"
  | "mfa_required"
  | "apple_code_required"
  | "apple_revoke_failed"
  | "apple_revocation_marker_failed"
  | "attachment_cleanup_failed"
  | "attachment_cleanup_unbounded"
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

/** Reads the `aal` claim from a JWT's payload segment (Issue #268) - a
 * plain base64url-JSON decode, not a signature verification: the caller
 * already passed `userClient.auth.getUser(jwt)` by the time this runs,
 * which is what actually establishes the token is genuine. Returns null on
 * any malformed token or a missing/non-string claim, rather than throwing -
 * a decode failure here fails the aal2 check closed (treated as "not
 * aal2") exactly like a missing claim would, never open. */
function decodeJwtAal(jwt: string): string | null {
  try {
    const payloadSegment = jwt.split(".")[1];
    if (!payloadSegment) return null;
    // atob expects standard base64; JWTs use base64url (`-`/`_`, no
    // padding) - translate before decoding.
    const base64 = payloadSegment.replace(/-/g, "+").replace(/_/g, "/");
    const padded = base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), "=");
    const json = atob(padded);
    const claims = JSON.parse(json) as Record<string, unknown>;
    return typeof claims.aal === "string" ? claims.aal : null;
  } catch {
    return null;
  }
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
  /** The caller's own Apple identity id (`identities[provider=="apple"].id`,
   * equal to Apple's `sub` claim) if this account has one linked - null
   * otherwise. Bound against the revoked id_token's own `sub` before any
   * revocation call is made (Issue #560). */
  appleIdentityId: string | null;
  /** False only when GoTrue's response omitted `identities` entirely (as
   * opposed to a present-but-empty array) - a determination *failure* that
   * must fail the whole deletion closed rather than silently treating the
   * account as having no linked Apple identity (Issue #560: this used to be
   * the one non-fail-closed Apple branch in this file). */
  identitiesKnown: boolean;
  /** True when any of the account's MFA factors (`user.factors`) has
   * `status: "verified"` (Issue #268). Gates the aal2 requirement below -
   * an account with no enrolled factor is unaffected by it. */
  hasVerifiedMfaFactor: boolean;
  /** The `aal` claim from the caller's own (already signature-verified)
   * JWT - `"aal1"` or `"aal2"`, or null if the claim is missing/unreadable
   * (Issue #268). Read directly from the token rather than a second network
   * call; see the header comment. */
  aal: string | null;
}

/** The account's Apple-revocation progress (Issue #527; identity-bound by
 * Issue #605/LLA-051), read before Steps 3/6 run and written immediately
 * after a successful revoke. */
export interface DeletionProgress {
  /** Set once Apple revocation has actually succeeded for this account. A
   * retry that sees this already set - *and* whose current Apple identity
   * still matches [appleIdentityId] below - skips straight past the
   * Apple-code precondition and the revoke call to `deleteUser` - the only
   * step that could have failed and left the account stranded. */
  appleRevokedAt: string | null;
  /** The Apple identity id (`identities[provider=="apple"].id`) that was
   * actually revoked when [appleRevokedAt] was stamped (Issue #605/LLA-051).
   * Null whenever [appleRevokedAt] is null. A retry's marker is honored only
   * when this still equals the caller's *current* Apple identity id - the
   * account may have unlinked the revoked identity and linked a different
   * one between attempts, and a stale match would let that new identity's
   * grant survive deletion unrevoked. */
  appleIdentityId: string | null;
}

/** Bounded/failed listing outcome (Issue #559). */
export type ListAttachmentsResult =
  | { ok: true; paths: string[] }
  | { ok: false; reason: "list_failed" }
  | { ok: false; reason: "too_many_objects" | "too_deep" };

/** Every real I/O call `handleDeleteAccount` needs, injected so tests can
 * supply fakes instead of a live Supabase project / Apple credentials. */
export interface DeleteAccountDeps {
  /** Resolves the caller from their forwarded Authorization header. Null on
   * any invalid/failed lookup. */
  getUser(authHeader: string): Promise<DeleteAccountCaller | null>;
  /** Reads this account's Apple-revocation progress marker (Issue #527). */
  getDeletionProgress(uid: string): Promise<DeletionProgress>;
  /** Records that Apple revocation has succeeded for this account, and
   * *which* Apple identity [appleIdentityId] it was for (Issue #605/LLA-051),
   * so a later retry (after a `deleteUser` failure) skips straight back to
   * `deleteUser` (Issue #527) only for that same identity. Resolves `true`
   * on success, `false` if the write could not be persisted (Issue #599: no
   * longer best-effort - the production wiring below retries once itself
   * before giving up). A `false` result stops the whole call closed, before
   * `deleteUser`, with its own `apple_revocation_marker_failed` code: Apple
   * has already burned the caller's one-time authorization code revoking
   * the grant, so silently proceeding to a `deleteUser` failure would leave
   * a retry needing a *fresh* code to re-enter a narrower version of #527 -
   * this fails the whole deletion closed at the one point that can still
   * choose to stop before that happens. */
  markAppleRevoked(uid: string, appleIdentityId: string): Promise<boolean>;
  /** Lists every object path under `<uid>/` in the feedback-attachments
   * bucket, paginating and recursing into nested folders (Issue #243/D-24;
   * round 2 fix), bounded by MAX_ATTACHMENT_OBJECTS/MAX_ATTACHMENT_DEPTH
   * (Issue #559) so a caller with an unbounded number of objects under
   * their own prefix cannot make listing alone exceed this function's wall
   * clock. */
  listAttachmentPaths(uid: string): Promise<ListAttachmentsResult>;
  /** Removes the given object paths from the feedback-attachments bucket,
   * batching internally. Resolves false on any removal failure. Never
   * called with an empty array. */
  removeAttachmentPaths(paths: string[]): Promise<boolean>;
  /** Issue #599: clears `attachment_paths` (to `[]`) on every one of the
   * caller's own `feedback_tickets` rows, run unconditionally once Storage
   * cleanup for this call is confirmed complete (whether this call found
   * zero objects or just finished removing some) - see the header comment
   * for why this must not be skipped merely because this call's own
   * listing was empty. Resolves false on any write failure. */
  clearAttachmentPaths(uid: string, authHeader: string): Promise<boolean>;
  /** Runs `delete_account_data()` as the caller (user-scoped client, so
   * RLS/auth.uid() semantics hold) - the row-deletion half of account
   * deletion (U1). */
  deleteAccountData(authHeader: string): Promise<{ data: unknown; error: unknown }>;
  /** Exchanges and revokes a Sign in with Apple authorization code, binding
   * it to [expectedAppleUserId] before revoking (U3; Issue #560). */
  revokeApple(authorizationCode: string, expectedAppleUserId: string): Promise<AppleRevokeResult>;
  /** Best-effort re-home pass on the service-role client with an explicit
   * caller id (#17 P1 round 2 fix - see the header comment). */
  rehomeStrayDayEntries(uid: string): Promise<{ error: unknown }>;
  /** Deletes the `auth.users` row - the only irreversible step (KTD4). */
  deleteUser(uid: string): Promise<{ error: unknown }>;
}

/** The full request-handling logic (Issue #17 U2/U3; Issue #243/D-24
 * attachment cleanup; Issue #526's neighbours #527/#559/#560). See the
 * header comment for the full step-by-step contract and the fixes layered
 * onto it over time. */
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

  // Issue #560: a GoTrue response that omitted `identities` entirely means
  // this function cannot determine whether the account has a linked Apple
  // identity at all - previously that degraded to "treat as non-Apple,
  // skip revocation", the one Apple branch in this file that was not
  // fail-closed. Fail the whole deletion closed instead; nothing has been
  // touched yet.
  if (!user.identitiesKnown) {
    console.error(
      "delete-account: caller's identity list could not be determined (GoTrue response omitted " +
        "`identities`); failing closed before anything is touched",
    );
    return errorResponse("identity_check_failed", 500);
  }

  // Step 2.5 (Issue #268 D-6): server-side AAL2 enforcement, on top of the
  // client's own step-up dialog - see the header comment above. A no-op for
  // an account with no verified MFA factor (`hasVerifiedMfaFactor` false),
  // matching the client-side `requiresMfaStepUp` gate's same unaffected-path
  // behavior.
  if (user.hasVerifiedMfaFactor && user.aal !== "aal2") {
    console.error(
      "delete-account: aal2 required (account has a verified MFA factor) but session is not aal2; nothing touched",
    );
    return errorResponse("mfa_required", 401);
  }

  const body = await readBody(req);
  const appleCode = body.appleAuthorizationCode;
  const hasAppleIdentity = user.appleIdentityId !== null;

  // Issue #527: an account whose Apple grant was already confirmed revoked
  // by an earlier attempt (deletion progress marker set) needs neither a
  // fresh code nor another revoke call - a retry after a `deleteUser`
  // failure goes straight through Steps 3/6 to Step 8.
  //
  // Issue #605/LLA-051: that marker is honored only when it was stamped for
  // the caller's *current* Apple identity. Between attempts the account may
  // have unlinked the revoked identity and linked a different one - a
  // marker keyed only by user_id would then skip revocation entirely for an
  // identity that was never actually revoked.
  const progress = hasAppleIdentity
    ? await deps.getDeletionProgress(user.id)
    : { appleRevokedAt: null, appleIdentityId: null };
  const appleAlreadyRevoked =
    hasAppleIdentity &&
    progress.appleRevokedAt !== null &&
    progress.appleIdentityId === user.appleIdentityId;

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
  //
  // Issue #527: skipped entirely once `appleAlreadyRevoked` - a retry needs
  // no code at all once revocation has already succeeded.
  if (hasAppleIdentity && !appleAlreadyRevoked && !appleCode) {
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
  const listResult = await deps.listAttachmentPaths(user.id);
  if (!listResult.ok) {
    if (listResult.reason === "too_many_objects" || listResult.reason === "too_deep") {
      // Issue #559: a distinct, support-routed code - this is not a
      // transient failure a bare retry can ever fix (the caller's own
      // object count/depth is what tripped the bound), unlike
      // `attachment_cleanup_failed` below.
      console.error(
        `delete-account: attachment listing exceeded the ${listResult.reason} bound for uid ${user.id}; ` +
          "nothing touched - routed to support rather than retried automatically (Issue #559)",
      );
      return errorResponse("attachment_cleanup_unbounded", 422);
    }
    console.error(
      "delete-account: attachment listing failed; nothing touched, so the whole account stays untouched and retryable",
    );
    return errorResponse("attachment_cleanup_failed", 409);
  }
  const attachmentPaths = listResult.paths;
  if (attachmentPaths.length > 0) {
    const removed = await deps.removeAttachmentPaths(attachmentPaths);
    if (!removed) {
      console.error(
        "delete-account: attachment removal failed; nothing touched, so the whole account stays untouched and retryable",
      );
      return errorResponse("attachment_cleanup_failed", 409);
    }
  }

  // Issue #599 (part 2): Storage cleanup for this account is now confirmed
  // complete - either nothing was ever there, or the removal above just
  // succeeded. Clear feedback_tickets.attachment_paths for every one of the
  // caller's own tickets so no surviving row can reference a deleted
  // object, should a later step fail and leave the account (and its
  // tickets) in place. Unconditional - not only when attachmentPaths.length
  // > 0 - so a retry recovers a dangling reference left by a PRIOR attempt
  // whose Storage removal succeeded but this clear step then failed: that
  // retry's own listing legitimately finds zero objects and must not skip
  // this step on that account.
  const pathsCleared = await deps.clearAttachmentPaths(user.id, authHeader);
  if (!pathsCleared) {
    console.error(
      "delete-account: clearing feedback_tickets.attachment_paths failed; nothing else touched, so the whole account stays untouched and retryable",
    );
    return errorResponse("attachment_cleanup_failed", 409);
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
  //
  // Issue #527: skipped entirely once `appleAlreadyRevoked` - re-running it
  // would exchange a fresh code against an already-revoked grant for no
  // reason. On success here, the deletion-progress marker is stamped
  // *before* proceeding, so a `deleteUser` failure below can retry straight
  // through to Step 8 next time without repeating this step.
  //
  // Issue #599: the marker write is no longer best-effort. Apple has
  // already burned the caller's one-time authorization code revoking the
  // grant by this point - if the marker write then fails and a later
  // `deleteUser` failure sends the caller back through this function, a
  // retry would need a *fresh* Apple code to re-run a revoke whose grant no
  // longer exists to revoke, re-entering a narrower version of #527 with no
  // way out. Fail the whole call closed here instead, before `deleteUser`,
  // with a code distinct from `apple_revoke_failed` (Apple DID confirm the
  // revocation here - only this durability write failed).
  if (hasAppleIdentity && !appleAlreadyRevoked) {
    const revoked = await deps.revokeApple(appleCode!, user.appleIdentityId!);
    if (revoked.kind !== "ok") {
      console.error(
        `delete-account: apple revoke failed (${revoked.kind}); rows already removed`,
      );
      return errorResponse("apple_revoke_failed", 409);
    }
    const marked = await deps.markAppleRevoked(user.id, user.appleIdentityId!);
    if (!marked) {
      console.error(
        "delete-account: apple_revoked_at marker could not be persisted after a successful revoke " +
          "(both attempts failed); stopping before deleteUser rather than risking an unrecorded revoke",
      );
      return errorResponse("apple_revocation_marker_failed", 409);
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
    // guidance for this specific, narrow failure. Issue #527: a retry from
    // here re-enters this function with `appleAlreadyRevoked` now true (the
    // marker was stamped above before this step ever ran), so it skips
    // straight back to this exact step rather than repeating Steps 3/6.
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
 * with a null `id`; a real object has a non-null one) up to
 * MAX_ATTACHMENT_DEPTH levels deep (Issue #559 - not "any depth" as before:
 * an unbounded recursion is itself part of the same wall-clock risk this
 * bound closes). `counter` is a running total shared across the whole
 * recursion tree (not just this call's own subtree), so
 * MAX_ATTACHMENT_OBJECTS bounds the *total* number of objects found under
 * the top-level prefix, not merely the count at any one level. Returns a
 * discriminated failure - rather than throwing - on any listing failure, a
 * depth bound trip, or an object-count bound trip, so the whole cleanup
 * fails closed with a code that distinguishes "try again later" from "this
 * account needs support" (Issue #259/#559).
 */
async function listFolderPaths(
  // deno-lint-ignore no-explicit-any
  bucket: any,
  prefix: string,
  depth: number,
  counter: { count: number },
): Promise<ListAttachmentsResult> {
  if (depth > MAX_ATTACHMENT_DEPTH) {
    return { ok: false, reason: "too_deep" };
  }
  const paths: string[] = [];
  let offset = 0;
  for (;;) {
    let entries: Array<{ id: string | null; name: string }> | null;
    let error: unknown;
    try {
      const result = await withTimeout(bucket.list(prefix, { limit: LIST_PAGE_SIZE, offset }));
      entries = result.data ?? null;
      error = result.error;
    } catch (thrown) {
      error = thrown;
      entries = null;
    }
    if (error) return { ok: false, reason: "list_failed" };
    const page = entries ?? [];
    for (const entry of page) {
      if (entry.id === null) {
        const sub = await listFolderPaths(bucket, `${prefix}/${entry.name}`, depth + 1, counter);
        if (!sub.ok) return sub;
        paths.push(...sub.paths);
      } else {
        counter.count++;
        if (counter.count > MAX_ATTACHMENT_OBJECTS) {
          return { ok: false, reason: "too_many_objects" };
        }
        paths.push(`${prefix}/${entry.name}`);
      }
    }
    if (page.length < LIST_PAGE_SIZE) break;
    offset += LIST_PAGE_SIZE;
  }
  return { ok: true, paths };
}

/** Lists every object path under `<uid>/` in the feedback-attachments
 * bucket (see `listFolderPaths` above for the pagination/recursion/bound
 * contract). */
async function listFeedbackAttachmentPaths(
  // deno-lint-ignore no-explicit-any
  adminClient: any,
  uid: string,
): Promise<ListAttachmentsResult> {
  const bucket = adminClient.storage.from(FEEDBACK_ATTACHMENTS_BUCKET);
  return listFolderPaths(bucket, uid, 0, { count: 0 });
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
      let data: { user: Record<string, unknown> | null } | undefined;
      let error: unknown;
      try {
        const result = await withTimeout(userClient.auth.getUser(jwt));
        data = result.data;
        error = result.error;
      } catch (thrown) {
        error = thrown;
      }
      if (error || !data?.user) return null;
      // Issue #560: `identities` omitted entirely (undefined/null) is a
      // determination *failure*, distinct from a present-but-empty array
      // (an account with genuinely no linked third-party identity). Only
      // the latter means "no Apple identity" - the former must fail the
      // whole deletion closed (see handleDeleteAccount).
      const rawIdentities = data.user.identities;
      const identitiesKnown = Array.isArray(rawIdentities);
      // deno-lint-ignore no-explicit-any
      const identities = (identitiesKnown ? rawIdentities : []) as any[];
      const providers = identities.map((identity) => identity.provider as string);
      // deno-lint-ignore no-explicit-any
      const appleIdentity = identities.find((identity: any) => identity.provider === "apple");
      // Issue #268: `user.factors` is GoTrue's own MFA-factor list on the
      // user object (distinct from `identities`, which is sign-in
      // providers) - present whenever any factor was ever enrolled.
      // deno-lint-ignore no-explicit-any
      const factors = (data.user.factors ?? []) as any[];
      const hasVerifiedMfaFactor = factors.some((factor) => factor?.status === "verified");
      return {
        id: data.user.id as string,
        providers,
        appleIdentityId: appleIdentity ? (appleIdentity.id as string) : null,
        identitiesKnown,
        hasVerifiedMfaFactor,
        aal: decodeJwtAal(jwt),
      };
    },
    getDeletionProgress: async (uid) => {
      try {
        const { data, error } = await withTimeout(
          adminClient
            .from("account_deletion_progress")
            .select("apple_revoked_at, apple_identity_id")
            .eq("user_id", uid)
            .maybeSingle(),
        );
        if (error || !data) return { appleRevokedAt: null, appleIdentityId: null };
        return {
          appleRevokedAt: (data.apple_revoked_at as string | null) ?? null,
          // Issue #605/LLA-051: read alongside apple_revoked_at so a retry
          // can confirm the marker was stamped for this same Apple identity,
          // not merely for this user_id.
          appleIdentityId: (data.apple_identity_id as string | null) ?? null,
        };
      } catch (error) {
        // Issue #527: unable to determine progress - treat as "not yet
        // revoked" (the safe default: at worst this asks the caller for one
        // more Apple code it didn't strictly need, never data loss).
        console.error(
          `delete-account: failed to read deletion progress marker (${errorType(error)}); treating as not yet revoked`,
        );
        return { appleRevokedAt: null, appleIdentityId: null };
      }
    },
    markAppleRevoked: async (uid, appleIdentityId) => {
      // Issue #599: a single write attempt, factored out so the call site
      // below can retry it exactly once - a lost write here is no longer
      // best-effort (see this function's own DeleteAccountDeps doc comment
      // for why).
      const attemptWrite = async (): Promise<boolean> => {
        try {
          const { error } = await withTimeout(
            adminClient
              .from("account_deletion_progress")
              .upsert({
                user_id: uid,
                apple_revoked_at: new Date().toISOString(),
                // Issue #605/LLA-051: stamped together so a later retry can
                // tell whether this marker still applies to the caller's
                // current Apple identity.
                apple_identity_id: appleIdentityId,
              }),
          );
          if (error) {
            console.error(
              `delete-account: apple_revoked_at marker write failed (${error.message ?? "unknown error"})`,
            );
            return false;
          }
          return true;
        } catch (error) {
          console.error(`delete-account: apple_revoked_at marker write threw unexpectedly (${errorType(error)})`);
          return false;
        }
      };
      if (await attemptWrite()) return true;
      console.error("delete-account: retrying the apple_revoked_at marker write once");
      return attemptWrite();
    },
    listAttachmentPaths: (uid) => listFeedbackAttachmentPaths(adminClient, uid),
    removeAttachmentPaths: async (paths) => {
      for (let i = 0; i < paths.length; i += REMOVE_BATCH_SIZE) {
        const batch = paths.slice(i, i + REMOVE_BATCH_SIZE);
        try {
          const { error } = await withTimeout(
            adminClient.storage.from(FEEDBACK_ATTACHMENTS_BUCKET).remove(batch),
          );
          if (error) return false;
        } catch {
          return false;
        }
      }
      return true;
    },
    clearAttachmentPaths: async (uid, authHeader) => {
      // Issue #599: run as the caller (user-scoped client, RLS holds) via
      // the pre-existing owner-scoped feedback_tickets_update policy and
      // its attachment_paths column grant - no service-role bypass and no
      // new RPC needed. Scoped to `uid` defensively; RLS already limits the
      // write to the caller's own rows.
      const userClient = clientFactory(supabaseUrl!, anonKey!, {
        auth: { persistSession: false },
        global: { headers: { Authorization: authHeader } },
      });
      try {
        const { error } = await withTimeout(
          userClient
            .from("feedback_tickets")
            .update({ attachment_paths: [] })
            .eq("user_id", uid),
        );
        return !error;
      } catch {
        return false;
      }
    },
    deleteAccountData: async (authHeader) => {
      const userClient = clientFactory(supabaseUrl!, anonKey!, {
        auth: { persistSession: false },
        global: { headers: { Authorization: authHeader } },
      });
      try {
        const { data, error } = await withTimeout(userClient.rpc("delete_account_data"));
        return { data, error };
      } catch (error) {
        return { data: null, error };
      }
    },
    revokeApple: (authorizationCode, expectedAppleUserId) =>
      revokeAppleToken(authorizationCode, expectedAppleUserId),
    rehomeStrayDayEntries: async (uid) => {
      const { error } = await withTimeout(adminClient.rpc("rehome_stray_day_entries", { p_user_id: uid }));
      return { error };
    },
    deleteUser: async (uid) => {
      try {
        const { error } = await withTimeout(adminClient.auth.admin.deleteUser(uid));
        return { error };
      } catch (error) {
        return { error };
      }
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
