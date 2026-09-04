---
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
product_contract_source: ce-plan
execution: code
---

# Fix Issues #24 and #43 in LunarLog

## Goal Capsule

- **Objective:** Resolve two high-priority defect issues:
  1. **Issue #24:** Stale network link failure (`_pendingLinkFailure`) survives a successful retry and is misreported to the user as an error SnackBar upon sign-in.
  2. **Issue #43:** iOS notification permission denial is not reported because only Android permissions were checked in `FlutterLocalNotificationsScheduler`, preventing the overview reminder hint from appearing on iOS when notifications are denied.
- **Means:**
  - In `lib/data/auth/supabase_auth_service.dart`, reset `_pendingLinkFailure = null;` upon successful link exchange in `_exchangeAuthLink()`.
  - In `lib/data/notifications/notification_scheduler.dart`, probe iOS/Darwin notification permissions via `IOSFlutterLocalNotificationsPlugin.checkPermissions()` and allow injecting `IOSFlutterLocalNotificationsPlugin` (or a custom permission checker seam) for testability.
  - Add regression tests in `test/data/supabase_auth_service_test.dart` and `test/data/notification_scheduler_test.dart`.
- **Authority Hierarchy:**
  1. User Directive: Resolve issues 24 and 43 end-to-end via `/compound-engineering:lfg`.
  2. AGENTS.md: Worktree isolation (`.worktrees/`), credential safety, 90% test coverage floor, CRAP <= 10.
  3. GitHub Issues #24 and #43 problem specifications and evidence.
- **Stop Conditions:** Code implemented, regression tests written and passing, plan verified, `ce-simplify-code` / `ce-code-review` passed, PR pushed and opened.

## Product Contract

### Problem Statement

1. **Issue #24 (`SupabaseAuthService._exchangeAuthLink`)**:
   - When a magic-link exchange fails transiently due to a network error (`AuthNetworkFailure`), `_handleAuthLinkExchangeError` sets `_pendingLinkFailure = failure;` and un-latches `_lastHandledLink`.
   - When the user or app retries the link successfully, `getSessionFromUrl(uri)` completes and establishes a session, but `_pendingLinkFailure` is not cleared.
   - Downstream listeners (e.g. `ProfileHomeGate._maybeShowLinkFailure`) consume `pendingLinkFailure` and display a failure SnackBar even though the user successfully signed in.

2. **Issue #43 (`FlutterLocalNotificationsScheduler.initialize`)**:
   - In `lib/data/notifications/notification_scheduler.dart:80-84`, the scheduler only queries:
     ```dart
     final androidEnabled = await _plugin
         .resolvePlatformSpecificImplementation<
             AndroidFlutterLocalNotificationsPlugin>()
         ?.areNotificationsEnabled();
     final enabled = androidEnabled ?? true;
     ```
   - On iOS (and macOS), `androidEnabled` evaluates to `null`, which defaults to `true`. Even when the user denies notification permissions in iOS settings or at the prompt, `NotificationAvailability.available` is returned.
   - Consequently, the `ReminderCoordinator` thinks notifications are available, does not cancel pending reminders, and the UI never displays the hint prompting the user to enable notifications in iOS device settings.

### Requirements

- **R1 (Issue #24 Fix):** Clear `_pendingLinkFailure = null;` upon successful execution of `_gateway.getSessionFromUrl(uri)` in `_exchangeAuthLink()`.
- **R2 (Issue #24 Test):** Verify in `test/data/supabase_auth_service_test.dart` that after a transient network failure followed by a successful retry of the same link, `pendingLinkFailure` is `null`.
- **R3 (Issue #43 Fix):** In `FlutterLocalNotificationsScheduler.initialize()`, probe Darwin/iOS permissions:
  - Check `AndroidFlutterLocalNotificationsPlugin` if available.
  - Check `IOSFlutterLocalNotificationsPlugin.checkPermissions()` if available. If `checkPermissions()` returns `options`, check `options?.isEnabled ?? false`.
  - Also support `MacOSFlutterLocalNotificationsPlugin.checkPermissions()` if present.
  - If neither plugin implementation resolves (or both return null, e.g. in headless unit tests or unsupported platforms), fallback to default `true`.
- **R4 (Issue #43 Seam & Test):** Provide unit testing for `FlutterLocalNotificationsScheduler` (or an injectable plugin seam / subclass) in `test/data/notification_scheduler_test.dart` asserting that when Darwin permissions are disabled (`isEnabled: false`), `NotificationAvailability.denied` is returned; when enabled, `NotificationAvailability.available`.

## Planning Contract

### Technical Design

#### 1. Issue #24 Fix (`lib/data/auth/supabase_auth_service.dart`)
In `_exchangeAuthLink`:
```dart
Future<void> _exchangeAuthLink(
  Uri uri, {
  required bool recovery,
  required String key,
}) async {
  try {
    final response = await _gateway.getSessionFromUrl(uri);
    _pendingLinkFailure = null;
    if (recovery || _isRecoveryType(response.redirectType)) {
      _latchRecovery();
    }
  } catch (error) {
    _handleAuthLinkExchangeError(error, key);
  }
}
```

#### 2. Issue #43 Fix (`lib/data/notifications/notification_scheduler.dart`)
In `FlutterLocalNotificationsScheduler`:
```dart
final android = _plugin.resolvePlatformSpecificImplementation<
    AndroidFlutterLocalNotificationsPlugin>();
final ios = _plugin.resolvePlatformSpecificImplementation<
    IOSFlutterLocalNotificationsPlugin>();
final macos = _plugin.resolvePlatformSpecificImplementation<
    MacOSFlutterLocalNotificationsPlugin>();

bool enabled = true;
if (android != null) {
  enabled = await android.areNotificationsEnabled() ?? true;
} else if (ios != null) {
  final options = await ios.checkPermissions();
  if (options != null) {
    enabled = options.isEnabled;
  }
} else if (macos != null) {
  final options = await macos.checkPermissions();
  if (options != null) {
    enabled = options.isEnabled;
  }
}

return enabled
    ? NotificationAvailability.available
    : NotificationAvailability.denied;
```
Allow injecting `FlutterLocalNotificationsPlugin? plugin` in the `FlutterLocalNotificationsScheduler` constructor for testing.

## Implementation Tasks

- [ ] Task 1: Update `_exchangeAuthLink` in `lib/data/auth/supabase_auth_service.dart` to reset `_pendingLinkFailure = null;` on success.
- [ ] Task 2: Add test in `test/data/supabase_auth_service_test.dart` asserting `pendingLinkFailure` is reset after successful retry.
- [ ] Task 3: Update `FlutterLocalNotificationsScheduler` in `lib/data/notifications/notification_scheduler.dart` to check iOS (`IOSFlutterLocalNotificationsPlugin`) and macOS permissions.
- [ ] Task 4: Add unit tests in `test/data/notification_scheduler_test.dart` verifying permission probing on Android, iOS, and fallback.
- [ ] Task 5: Verify all tests pass, analyze clean, run quality gates.
