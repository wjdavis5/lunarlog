/// Reminder scheduling seam (KTD7, R12): the coordinator plans
/// ([scheduling.dart]); an implementation owns the platform plugin.
/// Web deliberately has no reminders in v1 — a no-op scheduler (the plan's
/// posture: web is an insecure iteration surface).
///
/// The contract lives in `lib/domain` (U2); the platform implementation
/// (`FlutterLocalNotificationsScheduler`) and the no-op
/// (`NoopReminderScheduler`) live in
/// `lib/data/notifications/notification_scheduler.dart`.
library;

import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/notifications/reminder_payload.dart';
import 'package:lunarlog/domain/notifications/scheduling.dart';

abstract interface class ReminderScheduler {
  /// Initializes the plugin and reports whether notifications are actually
  /// enabled. It must never ask for the permission or present any other
  /// system UI: it runs at app start, before the operator has seen what a
  /// reminder is, and both platforms ration the dialog (issue #863 for
  /// Darwin, issue #1425 for Android). Asking is [requestPermission]'s job.
  ///
  /// [onLaunchFromNotification] fires for a notification tap (warm) and
  /// for a cold start launched by a tap, decoded into a [ReminderLaunch] —
  /// whose [ReminderLaunch.actionId] distinguishes an action-button tap
  /// (Issue #136) from a plain tap.
  Future<NotificationAvailability> initialize({
    void Function(ReminderLaunch launch)? onLaunchFromNotification,
  });

  /// Reads the current OS permission without reinitializing the plugin.
  Future<NotificationAvailability> checkAvailability();

  /// Issue #168: requests the OS permission from an explicit user action
  /// (the overview hint's "Turn on reminders" tap) — the only place this
  /// seam ever requests it, and not gated on push/FCM being configured.
  /// Once the OS has stopped showing the request dialog at all — Android:
  /// two refusals (see [nextNotificationPermissionAction]); Darwin: one,
  /// since its own dialog is one-shot-per-install — this opens the
  /// platform's notification-settings screen instead of re-prompting
  /// silently. Always ends by reporting the resulting availability, the
  /// same as [initialize] and [checkAvailability].
  Future<NotificationAvailability> requestPermission();

  Future<void> rescheduleAll(List<PlannedReminder> reminders);

  Future<void> cancelAll();
}
