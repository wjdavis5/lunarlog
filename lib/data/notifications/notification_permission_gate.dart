/// Serializes the OS notification-permission requests issue #287 found
/// racing: [FirebasePushTokenSource] (`FirebaseMessaging.instance
/// .requestPermission()`) and [FlutterLocalNotificationsScheduler]
/// (`AndroidFlutterLocalNotificationsPlugin.requestNotificationsPermission()`
/// / Darwin's `requestAlertPermission`) both fire, unawaited, at database
/// open on a `hasPush` build — `LunarLogRootState._startPushRegistration`
/// (`lib/app_root.dart`) and `_LunarLogAppState._scheduleReminderStart`
/// (`lib/app.dart`) are two independent widgets with no ordering
/// relationship between them.
///
/// **Decision (issue #287):** neither side is designated the sole owner —
/// which of the two actually runs first is genuine start-up timing, not
/// something either widget can cheaply guarantee without a larger
/// composition-root restructure. Instead both funnel every OS
/// permission-request call through this one shared gate
/// ([defaultNotificationPermissionGate]), which serializes them: whichever
/// caller arrives first runs its request to completion; the other queues
/// behind it rather than firing concurrently. Android drops a second
/// `requestPermissions()` call while one is already pending — resolving it
/// spuriously `false` (poisoning the denial counter
/// `notification_scheduler.dart`'s `_androidDeniedAttempts` persists) or
/// throwing `PERMISSION_REQUEST_IN_PROGRESS` — so serializing, not just
/// tolerating a bad outcome afterwards, is what actually closes the race
/// (`notification_scheduler.dart` already treated a `null` result as
/// "unknown, not a refusal" as a partial mitigation before this issue; that
/// stays, as defense in depth, now that the race itself is closed too).
library;

import 'dart:async';

/// Chains every [guard]ed request onto the same `Future`, mirroring
/// `ReminderCoordinator._schedulerQueue`'s own "chain onto the previous
/// Future" idiom for the identical class of problem (overlapping
/// platform-plugin calls) rather than a `Lock`/`Mutex` package dependency.
class NotificationPermissionGate {
  Future<void> _queue = Future<void>.value();

  /// Runs [request] only once every previously [guard]ed request on this
  /// gate has finished — so two callers racing at process start always run
  /// one at a time, never concurrently. Every caller still gets its own
  /// result (or error): the queue chain itself advances via a `Future` that
  /// always completes (never a bare `await` on [request] that would leave
  /// the chain stuck behind a rejected Future once something throws), so
  /// one caller's failure never blocks a later, unrelated caller.
  Future<T> guard<T>(Future<T> Function() request) {
    final previous = _queue;
    final completer = Completer<T>();
    _queue = previous.then((_) async {
      try {
        completer.complete(await request());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

/// The process-wide gate [FirebasePushTokenSource] and
/// [FlutterLocalNotificationsScheduler] share by default (both take an
/// optional gate constructor parameter for tests) — a top-level singleton,
/// not a per-class private instance, is exactly the point: it is only
/// useful as long as every real caller serializes through the *same*
/// instance.
final NotificationPermissionGate defaultNotificationPermissionGate =
    NotificationPermissionGate();
