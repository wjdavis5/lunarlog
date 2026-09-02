/// U8 coordinator tests (KTD7): replanning on stream changes, permission
/// denial skips scheduling, archiving drops a profile's reminders, the
/// notification-tap payload reaches the gate seam.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/notifications/notification_scheduler.dart';
import 'package:lunarlog/data/notifications/reminder_coordinator.dart';
import 'package:lunarlog/data/notifications/scheduling.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/ui/overview/notification_availability.dart';

class _FakeScheduler implements ReminderScheduler {
  _FakeScheduler({this.initialAvailability = NotificationAvailability.available});

  final NotificationAvailability initialAvailability;
  final List<List<PlannedReminder>> rescheduleCalls = [];
  int cancelCalls = 0;
  void Function(String profileId)? launchSink;

  @override
  Future<NotificationAvailability> initialize({
    void Function(String profileId)? onLaunchFromNotification,
  }) async {
    launchSink = onLaunchFromNotification;
    return initialAvailability;
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

Profile _profile(String id) => Profile(
      id: id,
      displayName: 'Profile $id',
      isMinor: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

ActivePrediction _late(LocalDate today) => ActivePrediction(
      today: today,
      lastEpisodeStart: today.addDays(-34),
      estimatedNextStart: today.addDays(-6),
      averagedCycleLengths: const [28],
      meanCycleLengthDays: 28,
      cycleDay: 35,
      duringEpisode: false,
      completedCycleCount: 4,
      validCycleCount: 4,
    );

void main() {
  // The coordinator registers with WidgetsBinding (lifecycle observer);
  // plain tests need the test binding initialized for that.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('profiles + predictions flow through to a reschedule call', () async {
    final scheduler = _FakeScheduler();
    final permissionState =
        NotificationPermissionState(NotificationAvailability.available);
    final profiles = StreamController<List<Profile>>(sync: true);
    final predictions = <String, StreamController<CyclePrediction>>{};
    final today = LocalDate(2026, 8, 30);

    final coordinator = ReminderCoordinator(
      scheduler: scheduler,
      permissionState: permissionState,
      activeProfiles: profiles.stream,
      predictionFor: (id) =>
          predictions.putIfAbsent(id, () => StreamController<CyclePrediction>(sync: true))
              .stream,
      today: () => today,
      replanDebounce: Duration.zero,
    );
    await coordinator.start();
    addTearDown(() async {
      await coordinator.dispose();
      await profiles.close();
      for (final c in predictions.values) {
        await c.close();
      }
    });

    profiles.add([_profile('p1')]);
    predictions['p1']!.add(_late(today));
    await pumpEventQueue();

    expect(scheduler.rescheduleCalls, isNotEmpty);
    final last = scheduler.rescheduleCalls.last;
    expect(last, isNotEmpty);
    expect(last.every((r) => r.profileId == 'p1'), isTrue);
  });

  test('denied permission: no scheduling, reminders cancelled, hint state set',
      () async {
    final scheduler =
        _FakeScheduler(initialAvailability: NotificationAvailability.denied);
    final permissionState =
        NotificationPermissionState(NotificationAvailability.available);
    final profiles = StreamController<List<Profile>>(sync: true);

    final coordinator = ReminderCoordinator(
      scheduler: scheduler,
      permissionState: permissionState,
      activeProfiles: profiles.stream,
      predictionFor: (_) => const Stream.empty(),
      replanDebounce: Duration.zero,
    );
    await coordinator.start();
    addTearDown(() async {
      await coordinator.dispose();
      await profiles.close();
    });

    expect(permissionState.value, NotificationAvailability.denied);
    profiles.add([_profile('p1')]);
    await pumpEventQueue();
    expect(scheduler.rescheduleCalls, isEmpty);
    expect(scheduler.cancelCalls, greaterThan(0));
  });

  test('archiving a profile drops its reminders from the plan', () async {
    final scheduler = _FakeScheduler();
    final permissionState =
        NotificationPermissionState(NotificationAvailability.available);
    final profiles = StreamController<List<Profile>>(sync: true);
    final p1Predictions = StreamController<CyclePrediction>(sync: true);
    final today = LocalDate(2026, 8, 30);

    final coordinator = ReminderCoordinator(
      scheduler: scheduler,
      permissionState: permissionState,
      activeProfiles: profiles.stream,
      predictionFor: (id) => id == 'p1' ? p1Predictions.stream : const Stream.empty(),
      today: () => today,
      replanDebounce: Duration.zero,
    );
    await coordinator.start();
    addTearDown(() async {
      await coordinator.dispose();
      await profiles.close();
      await p1Predictions.close();
    });

    profiles.add([_profile('p1')]);
    p1Predictions.add(_late(today));
    await pumpEventQueue();
    expect(
      scheduler.rescheduleCalls.last.any((r) => r.profileId == 'p1'),
      isTrue,
    );

    // p1 archived away.
    profiles.add([]);
    await pumpEventQueue();
    expect(
      scheduler.rescheduleCalls.last.any((r) => r.profileId == 'p1'),
      isFalse,
    );
  });

  test('notification tap payload reaches the launch seam', () async {
    final scheduler = _FakeScheduler();
    final permissionState =
        NotificationPermissionState(NotificationAvailability.available);
    String? launched;
    final coordinator = ReminderCoordinator(
      scheduler: scheduler,
      permissionState: permissionState,
      activeProfiles: const Stream.empty(),
      predictionFor: (_) => const Stream.empty(),
      replanDebounce: Duration.zero,
    );
    await coordinator.start(onLaunchFromNotification: (id) => launched = id);
    addTearDown(coordinator.dispose);

    scheduler.launchSink!('p9');
    expect(launched, 'p9');
  });
}
