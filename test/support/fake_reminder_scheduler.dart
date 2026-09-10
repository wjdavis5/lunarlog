/// Recording [ReminderScheduler] fake shared by the coordinator unit tests
/// and the composition-root widget tests: counts `initialize` calls, keeps
/// every `rescheduleAll` payload and the `cancelAll` count, and exposes the
/// launch callback the coordinator registered. [initialAvailability] drives
/// the permission-denial path; [initializeGate] parks `initialize` so a test
/// can act inside the window where an app resume races `start()`.
library;

import 'dart:async';

import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/notifications/reminder_payload.dart';
import 'package:lunarlog/domain/notifications/reminder_scheduler.dart';
import 'package:lunarlog/domain/notifications/scheduling.dart';

class FakeReminderScheduler implements ReminderScheduler {
  FakeReminderScheduler({
    this.initialAvailability = NotificationAvailability.available,
    this.initializeGate,
    this.requestPermissionGate,
  });

  final NotificationAvailability initialAvailability;

  /// When set, [initialize] parks on this completer before reporting
  /// availability — the window in which an app resume can race `start()`.
  final Completer<void>? initializeGate;

  /// When set, [requestPermission] parks on this completer before
  /// reporting availability — the window in which the "Turn on reminders"
  /// tap's own system-UI wrapping (issue #168) can be observed before the
  /// (fake) OS dialog resolves.
  final Completer<void>? requestPermissionGate;

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
  int requestPermissionCalls = 0;
  void Function(ReminderLaunch launch)? launchSink;

  /// Emits [launch] through the callback the coordinator registered —
  /// the tap path. Tests call this after `start()` with a decoded
  /// [ReminderLaunch] (or a legacy plain-profileId one via
  /// [fireLegacyPayload]).
  void fireLaunch(ReminderLaunch launch) => launchSink?.call(launch);

  /// Same, from a raw payload string (a pre-#136 notification's plain
  /// profile id payload still pending on a device when the app updates).
  void fireLegacyPayload(String payload) {
    final launch = decodeReminderLaunch(payload);
    if (launch != null) launchSink?.call(launch);
  }

  /// Answer for the next [requestPermission] (issue #168's "Turn on
  /// reminders" tap), when it should differ from [currentAvailability].
  NotificationAvailability? requestPermissionResult;

  @override
  Future<NotificationAvailability> initialize({
    void Function(ReminderLaunch launch)? onLaunchFromNotification,
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
  Future<NotificationAvailability> requestPermission() async {
    requestPermissionCalls++;
    await requestPermissionGate?.future;
    return requestPermissionResult ?? currentAvailability ?? initialAvailability;
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
