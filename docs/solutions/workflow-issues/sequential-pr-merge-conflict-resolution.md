---
title: Resolve a sibling-PR merge conflict by merging main into the feature branch
date: '2026-09-10'
category: workflow-issues
module: coordinator dispatch workflow
problem_type: workflow_issue
component: development_workflow
severity: low
applies_when:
  - two concurrently dispatched branches modify the same files
  - a merged sibling PR leaves your PR unmergeable
tags:
  - merge-conflicts
  - coordinator-workflow
  - git-merge
  - no-rebase
  - flutter
related_components:
  - lib/ui/account/account_section.dart
  - test/data/supabase_auth_service_test.dart
---

# Resolve a sibling-PR merge conflict by merging main into the feature branch

## Context

Two coordinator-dispatched tidy-up PRs in the lunarlog Flutter repo landed on the same files at the same time. PR #392 (issue #23, sync-review tidy-ups) and PR #393 (issue #32, social-login tidy-ups) both modified `lib/ui/account/account_section.dart` and `test/data/supabase_auth_service_test.dart`. PR #392 merged first, which left PR #393 unmergeable: `gh pr merge` on #393 failed with "Pull Request has merge conflicts".

The overlap was semantic, not just textual. Both PRs touched the account section's signed-in predicate and the auth-service test surface, but with different intents:

- PR #392's intent: introduce a shared `hasUsableSession` auth-state helper and relocate the `DeviceResetCallback` wiring.
- PR #393's intent: strict-`signedIn` `canLink` tile gating plus two new `AuthFailure` kinds, `AuthRateLimitedFailure` and `AuthMisconfiguredFailure`.

Pre-merge tree grounding (verified on this checkout): `lib/ui/account/account_section.dart:276` still defines the private helper `bool _isSignedIn(AuthSessionState state) => state == AuthSessionState.signedIn || state == AuthSessionState.passwordRecovery;`, the same predicate is duplicated as a free function in `lib/ui/account/sync_status_tile.dart:77`, and `lib/domain/auth/auth_service.dart:262` still ends its sealed `AuthFailure` factory list at `lastSignInMethod` with no rate-limited or misconfigured kinds. That duplication is exactly what made the conflict non-trivial: both branches edited the same predicate and adjacent test blocks.

## Guidance

Merge `origin/main` INTO the feature branch. Never rebase — this repo forbids force-push, so rewrite-based conflict resolution is off the table.

Exact command shape (from the feature branch checkout, e.g. the branch behind PR #393):

```powershell
git fetch origin
git checkout <feature-branch>
git merge origin/main
# resolve conflicts, keeping both intents
flutter analyze
flutter test
git add <resolved files>
git commit
git push origin <feature-branch>
```

Conflict-resolution rules applied here, in priority order:

1. Keep both intents. The merged `account_section.dart` must contain #392's shared `hasUsableSession` helper AND #393's strict-`signedIn` `canLink` gating AND the new failure kinds. Dropping either side to make the merge "easy" is a scope violation against the other issue.
2. Deduplicate toward the shared helper. #393 had introduced its own private `_isSignedIn`; after merging in #392's `hasUsableSession`, the duplicate is deleted and all call sites use the shared one. One predicate, one definition.
3. Re-verify the full gate after resolving: `flutter analyze` clean, `flutter test` green, quality gate PASS, and confirm the PR reads MERGEABLE with CI re-running. Per this session's conclusion, the final merge of PR #393 was still pending CI as of this writing — open in #393, unmerged as of this writing — so "resolved locally" never substitutes for the CI verdict.

Before/after of the predicate hunk (the "after" shape is per the reviewed #392/#393 diffs, since the #393 merge was still pending as of this writing):

Before — two private duplicates, one per file:

```dart
// lib/ui/account/account_section.dart (method, pre-merge)
bool _isSignedIn(AuthSessionState state) =>
    state == AuthSessionState.signedIn ||
    state == AuthSessionState.passwordRecovery;

// lib/ui/account/sync_status_tile.dart (free function, pre-merge)
bool _isSignedIn(AuthSessionState? authState) =>
    authState == AuthSessionState.signedIn ||
    authState == AuthSessionState.passwordRecovery;
```

After — #393's duplicate deleted, both call sites use #392's shared extension getter; #393's gating stays strict where it must:

```dart
// shared helper (from PR #392, per the reviewed diff)
extension UsableAuthSession on AuthSessionState? {
  bool get hasUsableSession =>
      this == AuthSessionState.signedIn ||
      this == AuthSessionState.passwordRecovery;
}

// lib/ui/account/account_section.dart (merged)
final signedIn = auth.state.hasUsableSession;
// ...but the link tiles keep PR #393's strict gate:
final canLink = auth.state == AuthSessionState.signedIn;
```

The distinction is deliberate: general section rendering treats `passwordRecovery` as signed in, while linking a second provider requires a fully `signedIn` session. The merge preserves both rules instead of collapsing them into one.

## Why This Matters

Parallel coordinator dispatches make same-file conflicts routine rather than exceptional: two small, individually correct tidy-ups can still collide when they share a predicate or a test file. The cost of resolving wrong is silent scope loss — one issue's behavior disappears inside the other's merge commit, and neither `flutter analyze` nor the test suite will flag "you kept the code compiling but dropped the intent".

The merge-not-rebase rule also matters beyond convention. A rebase rewrite would require force-push, which this repo forbids; beyond policy, rewriting the feature branch after review started would orphan existing review comments and CI runs on the open PR. Merging `origin/main` in preserves both histories and keeps the PR's review/CI context intact.

De-duplicating toward the shared helper (rather than keeping both `_isSignedIn` and `hasUsableSession` alive to "minimize the diff") matters because the pre-merge tree already carried this predicate in at least two places (`account_section.dart:276`, `sync_status_tile.dart:77`), a duplication the repo's own residual-findings note calls out. A conflict that touches a known duplicate is the cheapest moment to collapse it: the merge forces every call site into view anyway.

## When to Apply

- Two open PRs modify the same UI predicate, failure hierarchy, or test file and the second merge fails with "Pull Request has merge conflicts".
- A feature branch has fallen behind `main` after a sibling PR merged first, and the repo forbids force-push (so rebase is unavailable).
- A merge surfaces a duplicated private helper (e.g. `_isSignedIn`) alongside a newly merged shared one (`hasUsableSession`): delete the private copy, repoint call sites, and keep any stricter per-call-site gate (e.g. `canLink`) explicit rather than folding it into the shared predicate.
- After any conflict resolution touching auth-state gating or failure mapping: re-run `flutter analyze`, the full `flutter test`, and the quality gate before pushing, and treat the PR as unmerged until CI itself passes.

## Examples

1. The #392/#393 collision itself. Files: `lib/ui/account/account_section.dart`, `test/data/supabase_auth_service_test.dart`. Sequence: #392 merged → #393 conflicted → `git merge origin/main` into #393's branch → kept #392's `hasUsableSession` + `DeviceResetCallback` relocation and #393's `canLink` gating + `AuthRateLimitedFailure`/`AuthMisconfiguredFailure` → deleted #393's duplicate `_isSignedIn` → analyze clean, local `flutter test` and quality gate reported PASS in-session (exact count unconfirmed — CI pending at time of writing) → PR #393 MERGEABLE, CI re-running, open in #393 and unmerged as of this writing.
2. The predicate-versus-gate split as a reusable pattern. Shared rendering predicate (`hasUsableSession`, covers `signedIn` + `passwordRecovery`) answers "show the signed-in section?"; strict gate (`auth.state == AuthSessionState.signedIn`) answers "allow linking another provider now?". When a future change needs a third answer (e.g. "allow destructive delete during recovery?"), add a named gate rather than stretching either existing one.
3. The failure-kind addition as a merge checklist item. Adding `AuthFailure` variants (rate-limited, misconfigured) requires updating every exhaustive switch over the sealed hierarchy. During a conflicted merge, grep for `AuthFailure` switches after resolving and confirm exhaustiveness still compiles; the compiler is the backstop, but only if every switch is exhaustive rather than default-armed.

## Related

- Issue #23 (closed — sync-review tidy-ups, PR #392, merged)
- Issue #32 (open — social-login tidy-ups, PR #393, open and unmerged as of this writing)
- No prior `docs/solutions/` doc covers this area; this file seeds the corpus.
