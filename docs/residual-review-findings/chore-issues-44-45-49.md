# Residual Review Findings — `chore/issues-44-45-49`

Run context: code review of the branch closing issues #44, #45, and #49
(plan: `docs/plans/2026-09-03-005-refactor-layering-cleanups-sync-coverage-plan.md`).
Reviewers: correctness, adversarial, testing, maintainability, performance,
reliability, project-standards. Cross-model peer pass did not run — no peer is
configured on this machine, so the in-process adversarial reviewer covered that
lens instead.

Everything actionable and in scope was applied on the branch (commit
`824652c`). What follows is what was deliberately **not** fixed here.

## Filed to the tracker

- **[P2] Persisted server-clock offset is dropped when a push fails mid-batch**
  — `lib/data/sync/supabase_sync_engine.dart` (`_push` / `_pushBatch`).
  A mid-push failure leaves the in-memory offset advanced and the persisted
  copy stale; after a restart, writes are stamped against a clock the engine
  already measured as wrong, which under last-writer-wins can silently lose a
  local edit. **Pre-existing** (predates base `abc234f`); the new R8 test pins
  the behaviour rather than introducing it, and its assertion must change when
  this is fixed. → https://github.com/wjdavis5/lunarlog/issues/70

- **[P2] One un-appliable reconcile row re-runs a full reconcile every cycle**
  — `lib/data/sync/supabase_sync_engine.dart` (`_reconcileIfDue`).
  A row that can never apply locally keeps `lastFullPullAt` frozen, so every
  periodic tick pages both tables from version 0 forever — unbounded network,
  battery, and write amplification, signalled only by a `debugPrint`.
  **Pre-existing** (predates base `abc234f`). → https://github.com/wjdavis5/lunarlog/issues/71

Both are genuine defects in the sync engine, but issue #45 was scoped to adding
regression coverage, and `lib/data/sync/supabase_sync_engine.dart` is unchanged
on this branch. Fixing them here would have been an unrequested behaviour change
to the sync engine on a test-only ticket.

## Recorded here only (no ticket)

- **The availability mirror is armed to diverge.** `ReminderCoordinator` now
  reads a private `_availability` field instead of the shared notifier's live
  value, and `NotificationAvailabilitySink` is write-only by design. Today the
  coordinator is the only writer, so nothing can diverge — but the class doc
  promises U8 will wire "the real permission query", and a settings-screen or
  resume-time re-check that updates the notifier would leave the coordinator
  planning against the value it captured at launch. The visible symptom would be
  the overview hint saying notifications are off while the coordinator keeps
  scheduling. Worth revisiting when U8 lands.
- **The layering guard covers one direction.** It enforces `lib/data -/-> lib/ui`
  and `lib/domain -/-> package:flutter`. It does not check `lib/ui -> lib/data`
  (which `lib/ui/startup/fail_closed_screen.dart` already does, and which the
  plan deferred) or `lib/domain -> lib/data`.
- **`getProfile` re-implements the query shape of the private `_profileOrNull`.**
  Not identical — `getProfile` adds the tombstone filter — but the two could
  share a builder.
- **`test/data/sync_engine_test.dart` is ~1330 lines** and grew again here. It
  was already over 1000 before this branch; worth splitting by concern.
- **`test/ui/app_auth_provider_test.dart` imports `seedEpisodes` from
  `overview_test.dart`** rather than from `test/support/`, which is inconsistent
  with the fake consolidation done in the same branch (the file has an existing
  precedent for cross-test imports, so this was left alone).
- **The composition-root reminder test derives its fixture from the real
  `LocalDate.today()`** where the rest of the suite injects a fixed `today`. The
  expectation is robust across the dates involved, but it is wall-clock
  dependent.

## Testing gaps noted, not closed

- No test asserts the reconcile batch apply is *transactional* — a regression
  removing the transaction around `applyRemoteRows` would leave R9 green,
  because the per-row fallback produces the same end state.
- No test covers a reconcile deferring a row across two consecutive cycles,
  which is where the amplification in issue #71 becomes visible.
- No test covers an *intra*-batch `markPushed` failure (row k of a large
  production batch); R8 covers the cross-batch case at `batchSize: 1`.
- No test pumps `LunarLogApp` with a different `db` into the same element
  position. A `didUpdateWidget` assert was added on this branch to make that
  invariant explicit instead.
