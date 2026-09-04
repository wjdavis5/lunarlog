/// Notification availability contracts (KTD1): whether the OS lets the app
/// show reminders at all, and the write-only seam `lib/data` uses to report
/// it upward. Pure Dart on purpose — `lib/domain` carries no Flutter
/// dependency, so the observable notifier that renders the U6 overview hint
/// lives in `lib/ui/overview/notification_permission_state.dart` and
/// implements [NotificationAvailabilitySink] from there.
library;

enum NotificationAvailability { available, denied }

/// Receives availability as the scheduler resolves it. The reminder
/// coordinator only ever writes through this seam, which is what keeps the
/// contract free of Flutter.
abstract interface class NotificationAvailabilitySink {
  void update(NotificationAvailability next);
}
