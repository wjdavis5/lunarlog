/// Notification availability contracts (KTD1): whether the OS lets the app
/// show reminders at all, and the write-only seam `lib/data` uses to report
/// it upward. Pure Dart on purpose — `lib/domain` carries no Flutter
/// dependency, so the observable notifier that renders the U6 overview hint
/// lives in `lib/ui/overview/notification_permission_state.dart` and
/// implements [NotificationAvailabilitySink] from there.
library;

enum NotificationAvailability { available, denied }

/// Maps a platform notification-permission probe's answer onto
/// [NotificationAvailability] (issue #215).
///
/// Extracted verbatim out of
/// `lib/data/notifications/notification_scheduler.dart`'s
/// `checkAvailability()` (the flutter_local_notifications adapter, excluded
/// from the coverage/CRAP gates) so the mapping is a directly unit-tested
/// pure function in the domain layer, on the `buildFirebaseOptions()`
/// precedent.
///
/// Only an explicit `false` reads as [NotificationAvailability.denied]:
/// `true` means enabled, and `null` — no platform implementation resolved
/// (the probe is Android/iOS/macOS-only), the probe coming back
/// inconclusive, or no probe run at all — reads as
/// [NotificationAvailability.available], because the OS remains the
/// enforcement boundary and an unavailable probe must never brick reminder
/// coordination.
NotificationAvailability notificationAvailabilityFromPlatformProbe(
  bool? enabled,
) =>
    enabled == false
        ? NotificationAvailability.denied
        : NotificationAvailability.available;

/// Receives availability as the scheduler resolves it. The reminder
/// coordinator only ever writes through this seam, which is what keeps the
/// contract free of Flutter.
abstract interface class NotificationAvailabilitySink {
  void update(NotificationAvailability next);
}
