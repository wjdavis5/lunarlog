/// Recording [ReminderScheduler] fake shared by the coordinator unit tests
/// and the composition-root widget tests: counts `initialize` calls, keeps
/// every `rescheduleAll` payload and the `cancelAll` count, and exposes the
/// launch callback the coordinator registered. [initialAvailability] drives
/// the permission-denial path; [initializeGate] parks `initialize` so a test
/// can act inside the window where an app resume races `start()`.
library;

import 'dart:async';

import 'package:lunarlog/data/notifications/notification_scheduler.dart';
import 'package:lunarlog/data/notifications/scheduling.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';

class FakeReminderScheduler implements ReminderScheduler {
  FakeReminderScheduler({
    this.initialAvailability = NotificationAvailability.available,
    this.initializeGate,
  });

  final NotificationAvailability initialAvailability;

  /// When set, [initialize] parks on this completer before reporting
  /// availability — the window in which an app resume can race `start()`.
  final Completer<void>? initializeGate;

  /// Answer for the next [checkAvailability] (the resume-time re-probe),
  /// when it should differ from [initialAvailability] — e.g. a permission
  /// revoked while the app was backgrounded.
  NotificationAvailability? currentAvailability;

  /// Parks successive [checkAvailability] calls so a test can interleave
  /// work with an in-flight permission probe.
  final List<Completer<NotificationAvailability>> availabilityGates = [];

  final List<List<PlannedReminder>> rescheduleCalls = [];
  int initializeCalls = 0;
  int cancelCalls = 0;
  int availabilityChecks = 0;
  void Function(String profileId)? launchSink;

  @override
  Future<NotificationAvailability> initialize({
    void Function(String profileId)? onLaunchFromNotification,
  }) async {
    initializeCalls++;
    launchSink = onLaunchFromNotification;
    await initializeGate?.future;
    return initialAvailability;
  }

  @override
  Future<NotificationAvailability> checkAvailability() async {
    availabilityChecks++;
    if (availabilityGates.isNotEmpty) {
      return availabilityGates.removeAt(0).future;
    }
    return currentAvailability ?? initialAvailability;
  }

  @override
  Future<void> rescheduleAll(List<PlannedReminder> reminders) async {
    rescheduleCalls.add(reminders);
  }

  @override
  Future<void> cancelAll() async {
    cancelCalls++;
  }
}
