---
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
product_contract_source: ce-plan-bootstrap
execution: code
---

# Fix Sync Clock Offset Persistence (Issue #70) and Bounded Reconcile Loop (Issue #71)

## Goal Capsule

- **Objective:** Resolve Issues #70 and #71 in `lunarlog`:
  1. Fix dropped server-clock offset persistence when push fails mid-batch (Issue #70).
  2. Stop unbounded daily reconcile re-execution when an un-appliable row causes perpetual reconcile retries (Issue #71).
- **Means:** Update `lib/data/sync/supabase_sync_engine.dart` to persist `serverClockOffsetMs` immediately per batch in `_pushBatch` and track consecutive reconcile retries with a bound (`kMaxConsecutiveReconcileRetries = 3`), advancing `lastFullPullAt` once the limit is exceeded. Update test R8 and add/update tests for bounded reconcile loop in `test/data/sync_engine_test.dart`.
- **Authority Hierarchy:**
  1. Issues #70 and #71 descriptions.
  2. Existing codebase invariants: zero secrets leaked, >=90% test coverage, 0 CRAP score violations.
- **Stop Conditions:** Code changes implemented, unit tests pass (`flutter test test/data/sync_engine_test.dart`), full test suite passes (`flutter test`), and quality gate passes (`dart run tool/quality_gate.dart`).

## Product Contract

### Requirements
- **R1 (Issue #70):** Whenever a push batch succeeds and determines a `serverClockOffset`, the offset must be persisted to `sync_state.server_clock_offset_ms` immediately as part of `_pushBatch` rather than waiting for the entire multi-batch loop in `_push` to complete. If a subsequent batch fails or throws, the persisted offset must reflect the last successful batch's offset.
- **R2 (Issue #70 Test):** Test R8 in `test/data/sync_engine_test.dart` must be updated to assert that `(await rig.state()).serverClockOffsetMs` equals `offsetBefore + 5 minutes` (matching `rig.storage.clockOffset`).
- **R3 (Issue #71):** A single un-appliable reconcile row (e.g. an orphan day entry whose parent profile was deleted) must not cause a full reconcile to execute on every single sync cycle indefinitely. The sync engine must track consecutive cycles that end in `reconcileRetry == true`. If consecutive retries reach or exceed a limit (`kMaxConsecutiveReconcileRetries = 3`), the engine must advance `lastFullPullAt` to `_clock().toUtc()` and reset the consecutive retries counter, avoiding an infinite retry loop while still re-reconciling on the normal 24-hour interval. When a reconcile cycle completes without any retry, the counter must reset to 0.
- **R4 (Issue #71 Test):** Add regression test(s) verifying that after 3 consecutive cycles with an un-appliable reconcile row, `lastFullPullAt` advances to `now`, and the 4th cycle does not trigger a full reconcile. Ensure existing single-cycle fallback test R9 continues to pass (with 1 cycle deferring `lastFullPullAt`).

## Planning Contract

### Technical Design

#### 1. Immediate Per-Batch Clock Offset Persistence (Issue #70)
- In `lib/data/sync/supabase_sync_engine.dart`:
  - In `_pushBatch`:
    ```dart
    final offset = result.serverNow.toUtc().difference(_clock().toUtc());
    _storage.setClockOffset(offset);
    await _updateState((s) => s.copyWith(serverClockOffsetMs: Value(offset.inMilliseconds)));
    return (resolvedSeen: result.resolved.isNotEmpty, offset: offset);
    ```
  - In `_push`:
    - Remove `Duration? lastOffset;` and the post-loop persistence block.

#### 2. Bounded Reconcile Retry Loop (Issue #71)
- In `lib/data/sync/supabase_sync_engine.dart`:
  - Introduce constant:
    ```dart
    /// Maximum consecutive sync cycles that may retry reconciliation due to
    /// un-appliable remote rows before advancing lastFullPullAt to avoid an
    /// unbounded reconcile loop.
    const int kMaxConsecutiveReconcileRetries = 3;
    ```
  - Add engine state field:
    ```dart
    int _consecutiveReconcileRetries = 0;
    ```
  - In `_reconcileIfDue`:
    ```dart
    Future<bool> _reconcileIfDue({
      required String uid,
      required bool reconcileDueBeforePush,
      required bool resolvedSeen,
    }) async {
      if (!reconcileDueBeforePush && !resolvedSeen) return false;
      final reconcileRetry = await _reconcile(uid);
      if (!reconcileRetry) {
        _consecutiveReconcileRetries = 0;
        await _updateState(
            (s) => s.copyWith(lastFullPullAt: Value(_clock().toUtc())));
      } else {
        _consecutiveReconcileRetries++;
        if (_consecutiveReconcileRetries >= kMaxConsecutiveReconcileRetries) {
          _consecutiveReconcileRetries = 0;
          await _updateState(
              (s) => s.copyWith(lastFullPullAt: Value(_clock().toUtc())));
        }
      }
      return reconcileRetry;
    }
    ```

#### 3. Test Updates
- In `test/data/sync_engine_test.dart`:
  - **Test R8:**
    Change:
    ```dart
    expect((await rig.state()).serverClockOffsetMs, offsetBefore,
        reason: 'the persist happens after the batch loop, which the '
            'exception skipped');
    ```
    To:
    ```dart
    expect(
      (await rig.state()).serverClockOffsetMs,
      const Duration(minutes: 5).inMilliseconds,
      reason: 'the persist happens immediately per committed batch',
    );
    ```
  - **Bounded Reconcile Test:**
    Add test in pull group:
    Verify that an un-appliable row defers `lastFullPullAt` for cycles 1 and 2, but on cycle 3 (reaching `kMaxConsecutiveReconcileRetries`), `lastFullPullAt` advances to `now`, and cycle 4 does not perform full pull.

### Work Breakdown Units

- **[U1] Immediate per-batch clock offset persistence in `_pushBatch` & cleanup `_push`**
  - Files: `lib/data/sync/supabase_sync_engine.dart`
  - Update `_pushBatch` to await `_updateState` for `serverClockOffsetMs`.
  - Drop post-loop `_updateState` in `_push`.
  - Update test R8 in `test/data/sync_engine_test.dart`.

- **[U2] Bounded consecutive reconcile retries in `_reconcileIfDue`**
  - Files: `lib/data/sync/supabase_sync_engine.dart`
  - Define `kMaxConsecutiveReconcileRetries = 3`.
  - Track `_consecutiveReconcileRetries`.
  - Advance `lastFullPullAt` when limit is reached.
  - Add bounded reconcile tests in `test/data/sync_engine_test.dart`.

- **[U3] Quality Gate & Verification**
  - Run `flutter test test/data/sync_engine_test.dart`.
  - Run `flutter analyze`.
  - Run `dart run tool/quality_gate.dart`.
