---
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
product_contract_source: ce-plan-bootstrap
execution: code
---

# Fix Backlog Bugs (Issues #10-#15) in LunarLog

## Goal Capsule

- **Objective:** Resolve all 6 open bug issues in `lunarlog` (Issues #10, #11, #12, #13, #14, #15) discovered during the Supabase sync code review, ensuring robust offline behavior, reliable sync recovery, deadlock resilience, push serialization, and privacy-preserving sign-out data resets.
- **Means:** Target code fixes in Flutter data, UI, and sync layers along with a Supabase migration for `sync_push` concurrency controls, backed by comprehensive regression tests.
- **Authority Hierarchy:**
  1. User Directive: Work exclusively on the backlog of bugs (only bugs) in lunarlog; use git worktrees exclusively (`.worktrees/`).
  2. AGENTS.md: Local-first privacy architecture, strict RLS enforcement, safe local reset, and zero raw credential leaks.
  3. Review findings and GitHub Issues #10, #11, #12, #13, #14, #15.
- **Stop Conditions:** All 6 issues resolved with targeted fixes and automated tests; `flutter analyze` clean; `flutter test` green (388+ tests); database migration and tests verified.

## Product Contract

### Context & Problem Statement
During review of the Supabase auth and cloud sync implementation (`feat/supabase-auth-cloud-sync`, PR #16), 6 bugs were identified and filed as issues:
1. **Issue #10:** `review: cold start from an auth link blocks the first frame on the network`
2. **Issue #11:** `review: server-rejected sync rows stay pinned for the whole app session`
3. **Issue #12:** `review: expired token while offline maps to an auth error and stops backoff`
4. **Issue #13:** `review: sync_push per-row catch can mistake a transient deadlock for a permanent rejection`
5. **Issue #14:** `review: concurrent pushes create server_version gaps the incremental pull skips`
6. **Issue #15:** `review: a failed 'Sign out everywhere' drops the session but keeps device data`

### Requirements
- **R1 (Issue #10):** `SupabaseAuthService.start()` must not await `handleLink(initial)` so the app's first frame and local startup are never blocked on network exchanges.
- **R2 (Issue #11):** `SupabaseSyncEngine` must not pin rejected rows permanently in memory:
  - Clear `_rejected` when `reconcileDue` is true (or periodic sync cycle) to retry previously rejected rows.
  - When a profile is accepted in a push batch, remove any rejected day entries associated with that profile from `_rejected` so they can be pushed on subsequent cycles.
- **R3 (Issue #12):** `mapSyncTransportError` must classify `AuthRetryableFetchException` as `SyncTransportError.network()` before the generic `AuthException` check.
- **R4 (Issue #13):** `sync_push` in Postgres must check SQLSTATE and re-raise transient concurrency errors (`40P01` deadlock_detected, `40001` serialization_failure, `55P03` lock_not_available) rather than converting them to permanent `{"rejected": true}` row rejections.
- **R5 (Issue #14):** `sync_push` must serialize pushes for the same user via `perform pg_advisory_xact_lock(hashtext(v_uid::text));` immediately after authentication check to prevent out-of-order `server_version` commits.
- **R6 (Issue #15):** `AccountSection._signOutEverywhere` must execute the local database reset `_reset(context)` even if `auth.signOut(scope: AuthSignOutScope.global)` throws `AuthFailure`, because Gotrue already removed the local session and device data must not be orphaned.
- **R7 (Regression Testing):** Automated tests must accompany every fix:
  - Unit test in `supabase_auth_service_test.dart` for unblocked cold start.
  - Unit test in `supabase_sync_transport_test.dart` for `AuthRetryableFetchException` mapping.
  - Unit test in `account_test.dart` for global sign-out error executing reset.
  - Unit test in `sync_engine_test.dart` for rejected rows retry and profile-linked day entry retry.
  - pgTAP test in `supabase/tests/` or migration for `sync_push` advisory lock and re-raise.

## Planning Contract

### Technical Design

#### 1. Cold Start Auth Link (R1 / Issue #10)
- In `lib/data/auth/supabase_auth_service.dart:142`:
  Replace:
  ```dart
  if (initial != null) await handleLink(initial);
  ```
  With:
  ```dart
  if (initial != null) unawaited(handleLink(initial));
  ```
  `handleLink` already catches errors and surfaces link failures via streams. Unawaiting allows `SupabaseAuthService.start()` to return synchronously to `bootstrapSupabase()` and `main()`, rendering the first frame immediately.

#### 2. Expired Token Offline Mapping (R3 / Issue #12)
- In `lib/data/sync/supabase_sync_transport.dart:123`:
  Insert before `if (error is AuthException)`:
  ```dart
  if (error is AuthRetryableFetchException) {
    return const SyncTransportError.network();
  }
  ```
  This mirrors the logic in `supabase_auth_service.dart:68`.

#### 3. Sign Out Everywhere Data Reset (R6 / Issue #15)
- In `lib/ui/account/account_section.dart:189-199`:
  In `_signOutEverywhere`, inside `on AuthFailure catch (failure)`:
  ```dart
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(
        '${authFailureCopy(failure)} Other devices were not signed out.'),
  ));
  await _reset(context);
  return;
  ```
  Ensures that local device data is cleanly wiped as promised to the user, even if remote invalidation timed out or failed.

#### 4. Engine Rejection Memory & Cascade Retry (R2 / Issue #11)
- In `lib/data/sync/supabase_sync_engine.dart`:
  1. In `_cycle()`: calculate `reconcileDue` or pass a flag to `_push()` to clear `_rejected` when `reconcileDue` is true or during periodic cycles.
  2. In `_push()`: when profiles are accepted (`_rejected.remove(item.id)`), find all rejected entries in `_rejected` that belong to those accepted profiles and remove them from `_rejected`.
  3. Ensure `_rejected.clear()` is called on reconcile cycles so that transient rejections are given another attempt.

#### 5. Postgres `sync_push` Concurrency & Deadlock Handling (R4, R5 / Issues #13, #14)
- Add migration `supabase/migrations/20260903053000_sync_push_concurrency.sql`:
  1. Add advisory xact lock right after authentication check:
     ```sql
     perform pg_advisory_xact_lock(hashtext(v_uid::text));
     ```
  2. In both exception blocks (profiles loop and day_entries loop), re-raise transient codes:
     ```sql
     exception
       when sqlstate '40P01' or sqlstate '40001' or sqlstate '55P03' then
         raise;
       when others then
         v_rejected := v_rejected || jsonb_build_object('id', v_row -> 'id', 'rejected', true);
     end;
     ```
  This guarantees per-user FIFO commit ordering for `server_version` and converts lock contention into transient retries handled by the client's backoff logic.

## Implementation Units

### U1: Cold Start Auth Link Async Latch (Issue #10)
- **Target File:** `lib/data/auth/supabase_auth_service.dart`
- **Action:** Replace `await handleLink(initial)` with `unawaited(handleLink(initial))`.
- **Test:** In `test/data/supabase_auth_service_test.dart`, add a test verifying that `start()` completes immediately even if `getSessionFromUrl` is hanging/unresolved.

### U2: Expired Token Offline Classification (Issue #12)
- **Target File:** `lib/data/sync/supabase_sync_transport.dart`
- **Action:** Map `AuthRetryableFetchException` to `SyncTransportError.network()` before `AuthException`.
- **Test:** In `test/data/supabase_sync_transport_test.dart`, add an assertion in `mapSyncTransportError` tests verifying `AuthRetryableFetchException` produces `SyncTransportNetworkError`.

### U3: Sign Out Everywhere Local Reset on AuthFailure (Issue #15)
- **Target File:** `lib/ui/account/account_section.dart`
- **Action:** In `_signOutEverywhere`, call `await _reset(context);` inside the `AuthFailure` catch block after showing the SnackBar.
- **Test:** In `test/ui/account_test.dart`, add a widget test where `auth.signOut(scope: AuthSignOutScope.global)` throws `AuthFailure`, asserting that `_reset` runs and the SnackBar is displayed.

### U4: Engine Retry of Rejected Rows and Cascade Un-rejection (Issue #11)
- **Target File:** `lib/data/sync/supabase_sync_engine.dart`
- **Action:**
  - Clear `_rejected` on reconcile/periodic cycles.
  - When profile upsert succeeds, clear `_rejected` entries for any day entries referencing that profile.
- **Test:** In `test/data/sync_engine_test.dart`, add a test that rejects a profile and its day entries on push 1, accepts the profile on push 2, and verifies the day entries are automatically re-sent on push 3.

### U5: Supabase `sync_push` Concurrency & Transient Re-raise (Issues #13 & #14)
- **Target Files:** `supabase/migrations/20260903053000_sync_push_concurrency.sql`, `supabase/tests/sync_push_test.sql`
- **Action:**
  - Create migration updating `sync_push` with `pg_advisory_xact_lock(hashtext(v_uid::text))` and SQLSTATE checks (`40P01`, `40001`, `55P03` re-raise).
  - Update pgTAP test suite to verify advisory lock and error behavior.

## Verification Contract

Run the following commands in `.worktrees/fix-backlog-bugs`:
- `C:\src\flutter\bin\flutter.bat analyze` -> must complete with 0 issues.
- `C:\src\flutter\bin\flutter.bat test` -> all tests pass (388 existing + new regression tests).
- Validate SQL migration syntax and pgTAP tests.

## Definition of Done

- All 6 issues (#10, #11, #12, #13, #14, #15) fixed according to specifications.
- Regression tests added and passing for each issue.
- Git worktree kept isolated under `.worktrees/fix-backlog-bugs`.
- Code review and simplification steps pass with no blocking findings.
