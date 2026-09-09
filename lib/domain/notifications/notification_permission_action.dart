/// Pure decision logic for issue #168's "Turn on reminders" affordance.
/// Deliberately split out of `lib/data/notifications/notification_scheduler.dart`
/// (a platform seam excluded from the coverage/CRAP gate — see
/// `tool/quality/exclusions.dart`) so this branch stays directly
/// unit-tested rather than riding along, untested, inside the wrapper.
library;

/// What re-requesting notification permission should actually do next.
enum NotificationPermissionAction {
  /// Ask the OS again — the system dialog is still eligible to appear.
  request,

  /// Open the platform's own notification-settings screen instead of
  /// asking again — the OS has stopped showing the dialog at all.
  openSettings,
}

/// Android draws its own line at two refusals: after the second denial,
/// `shouldShowRequestPermissionRationale` goes false and every later call
/// to the permission API silently no-ops without ever showing UI again —
/// from then on the only path back to "on" runs through the app's
/// notification-settings screen. [deniedAttempts] counts every OS ask this
/// app has made so far (the automatic one `initialize()` makes, plus every
/// "Turn on reminders" tap) that came back refused; a granted result
/// resets it to zero.
NotificationPermissionAction nextNotificationPermissionAction(
  int deniedAttempts,
) => deniedAttempts >= 2
    ? NotificationPermissionAction.openSettings
    : NotificationPermissionAction.request;
