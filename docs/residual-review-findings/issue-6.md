# Residual Review Findings — `issue-6`

**Source:** `ce-code-review` rounds 1–8 on PR #105 (Issue #6, in-app feedback/
support), branch `issue-6`, plan
[`docs/plans/2026-09-05-001-feat-in-app-feedback-support-plan.md`](../plans/2026-09-05-001-feat-in-app-feedback-support-plan.md).
Round 8 is the most authoritative on current state; earlier rounds are
cited for a finding's history where it recurred under a different number.

Round 7 verdict was "changes requested" on five blockers (B1–B5). B1–B4
were fixed in the session that produced this file:

1. `lib/ui/feedback/attachment_field.dart` — added a test for the
   `_duringSystemUi` gate-suppression wiring (was mutation-dead per round
   7's own check).
2. `lib/ui/feedback/attachment_field.dart` + `lib/app_lifecycle.dart` — the
   picker now captures the gate's `generation` (new public getter) before
   the pick starts and discards a picked result if the gate re-locked
   underneath it, mirroring `unlock()`/`reauthenticate()`'s own guard.
3. `lib/observability/breadcrumbs.dart` + `lib/app_lifecycle.dart` —
   `defaultBreadcrumbLog` is now cleared inside `resetDevice()`, so one
   family member's breadcrumbs can no longer ride a later ticket filed
   under a different account on a shared device.
4. `lib/ui/settings/settings_screen.dart` — `hasFeedback` now also requires
   a signed-in `AuthController`, so a signed-out session gets the
   `contact-support-tile` email fallback (R23) instead of a form that
   fails with a permission error. This closes the same finding rounds 1–7
   raised repeatedly (#16/#12/#20/#12).

B5 was the process finding itself — "~20 findings have carried unchanged
through six rounds with nothing formally deferred, and there is no
`issue-6.md`" — which this file resolves.

Three mechanical doc/comment corrections were also made while compiling
this file (see the note at the end); none change behavior.

The feature's authorization model, RLS design, and the replay/ownership
guards on `feedback-notify` are sound — round 7 verified all of that by
mutation testing, not by reading. Everything below is P2/P3: real, but
narrower than a merge blocker, and tracked here rather than applied.

## Round 8 — completing round 7's adjudication

Round 7's own findings included three `SupabaseFeedbackService`/schema
mutants this file did not actually record a decision for when it was first
written. Each is adjudicated for real below, not carried forward again.

- **`lib/observability/breadcrumbs.dart` — `defaultBreadcrumbLog.clear()`
  was only wired into `resetDevice()`.** Two other real session-ending
  paths never cleared it: `AccountMismatchScreen._switchAccount`
  (`lib/ui/account/account_mismatch_screen.dart`) — a local sign-out
  documented as "and nothing else" that still ends the device's session —
  and `SupabaseAuthService._handleSignedOutEvent`
  (`lib/data/auth/supabase_auth_service.dart`), which is what actually
  fires for every `AuthChangeEvent.signedOut` gotrue delivers: a remote
  "sign out everywhere" landing here from another device, and gotrue's own
  expired/missing-session detection, neither of which goes through
  `resetDevice` at all. **Fixed** — `defaultBreadcrumbLog.clear()` now runs
  in both, with tests: `test/ui/account_test.dart` covers the mismatch
  screen's switch-account path (both the plain case and the "local
  sign-out reports a failure" case, since the comment there says the
  session ends either way), and `test/data/supabase_auth_service_test.dart`
  covers `_handleSignedOutEvent` for both an involuntary
  (`sessionExpired`) and a voluntary (`userInitiated`) reason.
- **`supabase/functions/_shared/email.ts` — the `!response.ok` branch and
  the `missing_email_config` branch were both mutation-dead**: deleting
  either left all 21 (now 23) Deno tests green, meaning a Resend 4xx/5xx
  response could read as success and silently drop the ticket's admin
  alert forever — the same failure mode rounds 4-7 closed different
  aspects of. **Fixed** — two new tests in
  `supabase/functions/_shared/email.test.ts` pin the result *shape*
  (`{ ok: false, reason: ... }`) rather than merely checking a return
  value: one mocks a Resend 401 and asserts the function reports failure,
  not success; one asserts `missing_email_config` when `apiKey`/`from` is
  absent and that `fetch` is never called. Both were manually
  mutation-tested (delete the branch, confirm the new test fails with the
  expected diff, restore) — see this file's own commit for the exact
  before/after output.
- **`lib/data/feedback/supabase_feedback_service.dart` —
  `kSignedAttachmentUrlTtlSeconds`.** Round 7 flagged this as a live
  mutant with no test pinning it, worrying specifically that a widened
  value (it named 604800s/7 days) would hand out a week-long link to a
  minor's screenshot with no backstop. **Investigated for real:** the
  constant is, and per its own git history always has been, `300` (5
  minutes) — not 604800. There is no 604800 anywhere in this repo's
  history; round 7's number describes a risk the code was never actually
  running, not a regression that needs reverting. What round 7 got right
  is that the value had zero test coverage: `signedAttachmentUrl` was not
  exercised by any test at all before this round. **Fixed the actual gap**
  — a new `signedAttachmentUrl` test group in
  `test/data/feedback/supabase_feedback_service_test.dart` pins the
  request's `expiresIn` body field against the literal `300` (not against
  the constant itself, which would pass trivially no matter what the
  constant said) and covers the storage-error mapping path too. Manually
  mutation-tested: bumping the constant to `604800` fails the new test
  with `Expected: <300> Actual: <604800>`; reverted after confirming.
  300s remains the intentional value — short enough that a link copied out
  of the support-history screen is not still live hours later, long enough
  for the one synchronous render-and-display it's minted for.
- **`supabase/migrations/20260906130000_feedback_tickets.sql`'s
  `feedback_tickets_update` policy had no test coverage at all** — neither
  the positive path (can the ticket owner actually use the granted-column
  update U5's attachment flow depends on?) nor the negative one (can a
  *different* authenticated caller reach it?). **Investigated and fixed,
  with a documented limit:** two new pgTAP assertions in
  `supabase/tests/feedback_rls_test.sql` (8c positive, 8d negative). The
  positive one matters more than it first looks: PostgreSQL AND-combines
  the USING clauses of every policy applicable to UPDATE/DELETE, which
  means `feedback_tickets_select`'s own `user_id = auth.uid()` check is
  *also* enforced on every update — verified empirically while writing
  this test, by loosening the update policy's own USING clause to `true`
  and confirming a cross-account write was still blocked (0 rows), then
  loosening the select policy instead with the update policy back to
  normal and confirming the same block held. Only loosening *both at once*
  actually opened the door (confirmed: it also broke the existing AE1
  test and raised a WITH CHECK violation). One real consequence: a lone
  mutation of `feedback_tickets_update`'s own USING/WITH CHECK clause is
  not independently killable by a negative (cross-account) test alone,
  because `feedback_tickets_select` already backstops row visibility for
  UPDATE. The positive test closes the blind spot that check alone leaves
  open — a naively "safe-looking" loosening of the update policy (e.g.
  `using (false)`, confirmed to fail the positive test) would otherwise
  have broken the owner's *own* attachment upload with nothing to catch
  it. The `with check` clause is separately inert today given the current
  column grants (`user_id` is not in `grant update (...) to authenticated`
  at all, so no client write can ever produce a row that clause would
  reject) — kept as documented defense-in-depth against a future grant
  change, not something a test can currently exercise without also
  changing the grants.

## Diagnostics / breadcrumb bounds

- **`supabase/migrations/20260906130000_feedback_tickets.sql:73–96`
  (`is_allowed_device_info`) — the server-side allowlist checks top-level
  key *names* only; nothing bounds value type, nesting, or size.**
  `{"breadcrumbs": {"note": "…"}}` or a multi-megabyte value both satisfy
  the CHECK the column comment calls the R9 server guarantee. Raised every
  round (1's #9, round 2's validator explicitly ruled it "exactly what
  KTD3 specifies, not an implementation defect" and demoted it from P1 to
  P2), still open in the current migration. **Defer** — needs a follow-up
  migration (type/length bounds on the six scalar keys, an array-length
  and element-type check on `breadcrumbs`, `pg_column_size` cap) with new
  pgTAP cases; the reachable threat today is a modified client widening
  its own ticket, not a cross-account leak.
- **`lib/observability/scrub.dart:298–300` (`scrubBreadcrumb`'s
  non-navigation branch passes `data` through unfiltered by value).**
  `containsDenyListedKey` matches key names only, so health text in a
  `data` *value* under an innocuous key would reach the Sentry SDK
  unscrubbed. Round 3 (#19) confirmed this is latent, not live: nothing in
  `lib/` calls `Sentry.addBreadcrumb` or builds a `Breadcrumb` outside this
  file today. Still present in current code. **Defer** — re-open the
  moment any manual breadcrumb call site is added; not exploitable as
  shipped.
- **Breadcrumb names are empty in practice, and the ring is `[]` on any
  build without `SENTRY_DSN`.** `sentry_bootstrap.dart:85–89` only calls
  `log.record` from inside `configureSentryOptions`'s `beforeBreadcrumb`,
  which never runs unconfigured; and `scrubBreadcrumb` (`scrub.dart:302`)
  builds its returned message from `breadcrumb.message` alone, which the
  SDK's own `http`/`navigation` factories never populate. Confirmed
  unchanged since round 1 (#11/#20). **Defer** — the diagnostics preview
  is thinner than intended, not a leak; closing it needs a
  `NavigatorObserver` plus explicit `record()` call sites independent of
  Sentry init, which is new instrumentation, not a fix.

## `feedback-notify` hardening

- **`supabase/functions/feedback-notify/index.test.ts` — only
  `claimNotification` is driven through the real `buildDeps` +
  `fakeClientFactory`; `getTicket`, `releaseClaim`, and `resolveCallerId`
  are exercised only via the hand-rolled `fakeDeps`, never against a fake
  that enforces WHERE-clause filtering.** Confirmed by reading
  `index.test.ts`: deleting `.eq("id", ticketId)` from `releaseClaim` or
  `getTicket` inside `buildDeps` would leave every test green. This is the
  same shape of gap round 6 closed for `claimNotification` (the third
  round with a live mutant on that function), left open on its two
  siblings, and round 7 named it directly ("no test inspects the
  `FeedbackTicketSummary` passed to `sendEmail`", "`releaseClaim`/`getTicket`
  production predicates still untested"). **Defer** — needs two more
  fixture rows and assertions in the existing `fakeClientFactory`; test
  infrastructure work with its own review, not a one-line fix.
- **`feedback-notify/index.ts:189–192` — the outer `catch (_error)` around
  the whole ownership/claim/send sequence swallows a *thrown* error (a
  connection reset, a 5xx raised by `supabase-js`) with no log**, distinct
  from the destructured `{error}` shape `releaseClaim`/`claimNotification`
  already handle and log. If it fires after a successful claim, that
  ticket's alert is silently and permanently suppressed with no
  distinguishing signal — the same shape round 5 closed for the ordinary
  send-failure path, one level up. **Defer** — narrow (requires a thrown,
  not returned, error from the Supabase client) and needs restructuring
  the catch to still release the claim on this path.
- **`feedback-notify/index.ts:173–187` — releasing the claim on a
  `timeout` reason can produce a duplicate send** if Resend actually
  accepted the request before the client-side abort fired. Round 6 (#5)
  called this a deliberate design call (documented, three ways out
  offered) and it was not taken; the migration comment and AGENTS.md still
  assert "at most once." **Defer** — the trade (bounded duplicate vs.
  unbounded silent loss) was made deliberately in round 5/6 and not
  reversed; narrowing it needs a Resend idempotency key or a CAS release,
  which is new production logic.
- **`feedback-notify` has exactly one delivery attempt in the system's
  lifetime** — `_notifyBestEffort` is a single unawaited invoke with no
  retry and no DB-driven trigger, unlike `feedback-reply`'s webhook.
  Standing since round 2. **Defer** — architectural change (a Database
  Webhook on `feedback_tickets` insert), out of this PR's remaining scope.

## `feedback-reply` hardening

- **`feedback-reply/index.ts` has no test file at all and is structurally
  untestable** — `Deno.serve` is called at module top level with no
  `import.meta.main` guard and nothing is exported — and
  `supabase/functions/deno.json`'s `test.include` still excludes it, so
  CI's `edge-functions` job never even type-checks the one function here
  that is `verify_jwt = false` and reachable unauthenticated. Standing
  since round 3 (raised again every round through 6). **Defer** — needs
  the same `buildDeps`-style extraction `feedback-notify` got across
  rounds 4–7; a real refactor with its own review, not a quick fix.
- **`feedback-reply/index.ts:77–81` — `sendEmail`'s result is discarded**,
  so a bad `RESEND_API_KEY` or a Resend outage produces no log line at
  all; the sibling `feedback-notify` already logs this shape. Standing
  since round 3. **Defer** — blocked on the same untestability as the item
  above; a one-line `console.error` with no test to pin it is exactly how
  this feature's silent-failure bugs (#13/#15 etc.) kept shipping.
- **`feedback-reply/index.ts:29` — the webhook secret is compared with
  `!==`, not a constant-time comparison.** It is the only auth on this
  `verify_jwt = false` endpoint. Standing since round 5. **Defer** — low
  exploitability (network jitter defeats timing attacks in practice
  against a CSPRNG secret); same reasoning this repo already recorded in
  `feat-social-logins.md` for an analogous case.

## Migration / RLS hardening (same file, batchable into one follow-up migration)

- **`owns_feedback_ticket(p_ticket_id uuid, p_user_id uuid)`
  (`20260906130000_feedback_tickets.sql:163–181`) is `SECURITY DEFINER`,
  granted to `authenticated`, and takes a caller-supplied `p_user_id`** —
  an ownership oracle at `/rpc/owns_feedback_ticket` for a known (ticket,
  user) pair. Standing since round 2. **Defer** — both arguments are
  unguessable v4 UUIDs, so exploitation is narrow; needs a follow-up
  migration dropping the second argument in favor of `auth.uid()`.
- **`attachment_paths` (`feedback_tickets.attachment_paths`) is
  client-writable to any string** — only `array_length <= 3` is checked,
  with no shape/ownership constraint, so the owner-scoped update policy
  lets a caller point a path at another user's object. Standing since
  round 2. **Defer** — Storage RLS still blocks a client read of the
  mis-pointed path (impact is limited to a service-role fetch); needs a
  follow-up migration adding a check constraint on the path shape.
- **The 5/hour rate-limit trigger (`feedback_tickets_rate_limit`) is a
  bare `select count(*)` under READ COMMITTED with no advisory lock** —
  concurrent inserts from one caller can all observe the same pre-insert
  count and pass. Standing since round 1. **Defer** — the app's own submit
  path is `_busy`-guarded; exploiting this needs a scripted caller against
  the shipped publishable key, which is the acknowledged threat model.
  Needs a follow-up migration adding `pg_advisory_xact_lock`.
- **The `feedback_attachments_insert` storage policy
  (`20260906140000_feedback_attachments_bucket.sql`) checks only that path
  segment 1 is the caller's uid, not that segment 2 names a ticket they
  own**, and uploads carry no rate cap of their own (only ticket inserts
  are rate-limited). Raised in round 7's backend-hardening bullets.
  **Defer** — narrow; the bucket is already uid-scoped, and this needs its
  own follow-up migration.

## Support history failure paths (blocked as a group on the fake service)

- **`test/support/fake_feedback_service.dart` has no `failWithOnListReplies`
  or `failWithOnAddReply` hooks** (only `failWithOnListTickets` exists),
  so neither of the two catch blocks below is reachable from any widget
  test. This is the enabler round 4 named for both bugs below, and it has
  been open since round 1. **Defer as one batch with the two items below**
  — adding the hooks and the two UI fixes together (as the review's own
  "Preferred Resolution" grouped them in rounds 1–3) is the right shape
  for a single follow-up commit; adding just the fake hooks with no
  consuming assertion doesn't close anything on its own.
- **`lib/ui/feedback/support_history_screen.dart:113–118` — a transient
  `listReplies` failure caches `const []` into `_repliesByTicket`,
  indistinguishable from "no replies yet"; `_toggleExpanded`'s
  `containsKey` guard then skips every retry, and `_load()` never clears
  the map**, so a "Replied" ticket renders an empty thread for the rest of
  the session with no error and no retry affordance. Standing since round
  1 (#13/#10/#8/#5 in successive rounds). **Defer** — untestable until the
  fake above grows a failure hook.
- **`lib/ui/feedback/support_history_screen.dart:133–134` — a failed
  `addUserReply` is swallowed with only a `debugPrint`**: the button
  re-enables, the typed text stays, nothing tells the operator it wasn't
  sent. Standing since round 1 (#15/#11/#9/#6). Also in the same method
  family, `:85–98` — a failing local `feedbackLastSeenAt` write inside
  `_load()` throws past a *successful* ticket fetch that already ran
  `setState`, and the build method checks `_error != null` before
  `tickets`, so the successful list is discarded in favor of an error
  screen. **Defer** — same blocker as above.

## Attachment/form polish

- **`lib/ui/feedback/attachment_field.dart:93,101` — the two client-side
  rejection strings ("too large" / "not supported") are retyped verbatim
  from `FeedbackFailure.attachmentTooLarge()`/`.attachmentRejected()`'s own
  `userFacingMessage`**, so the two copies can drift silently. Standing
  since round 1 (#6/#8/#7). **Defer** — mechanical, but reading the
  `FeedbackFailure` message here means constructing the failure object
  just for its string, and a couple of widget tests likely assert the
  literal text, so it's not risk-free enough to make in this pass.
- **`lib/ui/feedback/attachment_field.dart` has three post-await
  `setState` calls (after the size/MIME checks and after a successful
  pick) with no `mounted` guard**, and the `context.read<GateController?>()`
  inside `_duringSystemUi` also runs after the consent dialog's async gap.
  It's the only file in `lib/ui/feedback/` without these guards — the
  other two screens guard every one. Raised in round 7 as a non-blocking
  companion to B2. **Defer** — narrow window (the picker sheet plus a
  dialog), no observed crash; same-shape fix as the file's existing
  `mounted` conventions elsewhere in the feature.
- **`lib/ui/feedback/feedback_screen.dart:107–124` — the
  `FeedbackAttachmentUploadFailedFailure` message still renders through
  `_error` (the red slot) rather than `_info`**, even though the message
  itself says "Your message was sent — no need to resend it." Round 2
  flagged this exact mixed signal, round 3 asked for `_info`, round 4
  recorded it unimplemented; still `_error` in current code. **Defer** —
  cosmetic/UX, not incorrect; low priority relative to the structural fix
  (clearing the message/attachment) that already shipped.
- **`lib/ui/feedback/feedback_screen.dart:155–156` — `_message.clear()`
  runs on the success path *before* the `mounted` check**, unlike the
  failure path three lines below it, which checks `mounted` first. If the
  screen is popped during the `submit()` await, `_message` is already
  disposed by `dispose()` and this call would throw. **Defer** — narrow
  race (requires popping mid-submit on a request that then succeeds); same
  class as the item above.
- **`lib/ui/feedback/feedback_controller.dart:28–31` — `loadDiagnostics()`
  is fired unawaited from `initState`; it calls `notifyListeners()`
  unconditionally after two platform-channel awaits**, with no `_disposed`
  guard. Popping the form before collection finishes trips
  `ChangeNotifier`'s disposed assert in debug/profile builds. Standing
  since round 1 (#21). **Defer** — debug/profile-only, narrow window, and
  a latent flakiness source rather than a user-facing bug.

## Contract and coverage-gate accuracy

- **`lib/domain/feedback/feedback_service.dart:300,383` —
  `FeedbackAttachmentUploadFailedFailure` inherits `FeedbackFailure`'s
  type-only `operator ==`/`hashCode` despite carrying a `ticket` and an
  `attachmentFailure` payload.** Standing since round 2 (#7/#6). **Defer**
  — no production code currently compares two instances for equality;
  contract gap, not a live bug.
- **`tool/quality/exclusions.dart:61–66` — the reason string for
  `lib/data/feedback/image_picker_attachment_source.dart` says it "holds
  no branching logic worth testing in isolation," but `_mimeTypeFromName`
  is a pure four-branch function that runs fine under `flutter test`**,
  same shape as the `key_store.dart`/`notification_scheduler.dart`
  precedents it cites, which do unit-test their pure parts. Confirmed
  still present in the current file; standing since round 1 (#18/#20/#18/#17,
  raised every round). **Defer** — the fix (lift the mapper to a top-level
  function, add a unit test, narrow the reason string) is genuinely
  mechanical but touches production code under a coverage exclusion plus a
  new test, which is outside this pass's no-test-suite-risk bar.

## Backend orphaning / privacy

- **`lib/data/feedback/supabase_feedback_service.dart:91–105`
  (`_attachAndUpdate`) — a successful `uploadBinary` followed by a failed
  `attachment_paths` UPDATE orphans the uploaded object**, referenced by
  nothing, while the user is told the attachment step failed. The bucket
  already grants an owner-scoped delete policy. Standing since round 1
  (#1's attachment half, then round 6 #9 named it directly). **Defer** — a
  compensating `remove([objectPath])` in the catch is small but is
  production Dart logic with no existing test seam for the failure
  ordering; out of this pass's fix bar.
- **`lib/data/feedback/image_picker_attachment_source.dart:19–20` —
  `pickImage()` passes no `imageQuality`/`maxWidth`/`requestFullMetadata`**,
  so a gallery photo's original EXIF (including GPS) survives into
  Storage untouched; the consent dialog warns about "cycle data for a
  family member" only, not location. Standing since round 6 (#9).
  **Defer** — needs a picker-parameter change plus arguably a consent-copy
  update; production logic under a coverage exclusion, out of this pass's
  fix bar.
- **Account deletion never purges `feedback-attachments` objects** —
  `delete-account/index.ts` has no reference to `storage` or
  `feedback-attachments`, so the ticket row cascades away (and with it
  `attachment_paths`, the only pointer to the object) while the file
  itself survives, unfindable. Round 6 (#4) called out that this was
  "closed with prose only, not code." **Defer** — this is already the
  most honestly documented gap in the PR: `PRIVACY.md:112` accurately
  describes exactly this behavior as a known, tracked limitation rather
  than promising an erasure the system doesn't perform. No code change is
  being requested here beyond what PRIVACY.md already discloses.

## Deploy pipeline

- **`.github/workflows/supabase-migrate.yml:110–113` (`Deploy Edge
  Functions`) has no secrets precondition** — unlike the explicit "Check
  Apple secrets" gate eight lines below for `delete-account` — and runs
  *before* the `delete-account` deploy, so a failure deploying the two
  brand-new feedback functions would now block an already-shipped
  release-gate function. Missing `RESEND_API_KEY`/`FEEDBACK_*` secrets
  deploy green and completely inert. Standing since round 4 (#8), round 5
  (#8), round 6 (deployment notes). **Defer** — CI/workflow change that
  needs its own verification against a real deploy; no
  `SUPABASE_ACCESS_TOKEN` is currently configured on this project's
  `production` environment, so nothing has actually deployed through this
  path yet (confirmed in round 5/6/AGENTS.md's Migration Flow §7).

## UI polish

- **`lib/ui/settings/settings_screen.dart:227–229` — the Support-history
  tile's `onTap` doesn't `await` the pushed route**, so `_checkUnread()`
  (which only runs from `initState`) never re-fires after the operator
  reads the thread that cleared it; the red unread dot survives the visit
  that should have cleared it. Standing since round 3 (#24/#9/#18).
  **Defer** — cosmetic; low priority relative to the correctness items
  above.

## Trivial fixes made while compiling this file

Three mechanical doc/comment corrections, no behavior change:

- `AGENTS.md`: added this PR's plan to the "Implementation plans of
  record" sentence (was omitted since round 1, #19); corrected the claim
  that CI's `edge-functions` job "runs `deno test` for all of
  `supabase/functions/`" to name the actual `deno.json` `test.include`
  scope (`feedback-reply`/`delete-account` are excluded — round 6 #3);
  removed the stale "there is no automated Deno coverage in CI yet" line
  in the Migration Flow section, which contradicted the CI job this same
  PR added.
- `supabase/functions/_shared/email.ts:7` — corrected a round
  misattribution ("PR #105 review round 5" → "round 4") for the
  claim-before-send ordering change, matching round 6's own finding #16
  about this exact drift.
- `lib/ui/feedback/feedback_screen.dart:6–8` — updated the stale doc
  comment claiming "every field kept intact on failure (R6)" to note the
  `FeedbackAttachmentUploadFailedFailure` exception, which deliberately
  clears the message and attachment.
