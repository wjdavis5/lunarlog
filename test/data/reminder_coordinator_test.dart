/// U8 coordinator tests (KTD7): replanning on stream changes, permission
/// denial skips scheduling, archiving drops a profile's reminders, the
/// notification-tap payload reaches the gate seam.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/notifications/reminder_coordinator.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/ui/overview/notification_permission_state.dart';

import '../support/fake_reminder_scheduler.dart';

class _RecordingSink implements NotificationAvailabilitySink {
  final List<NotificationAvailability> updates = [];

  @override
  void update(NotificationAvailability next) {
    updates.add(next);
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
    final scheduler = FakeReminderScheduler();
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
        FakeReminderScheduler(initialAvailability: NotificationAvailability.denied);
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

  test('a minimal sink (no UI notifier) still receives denial and skips '
      'scheduling', () async {
    final scheduler =
        FakeReminderScheduler(initialAvailability: NotificationAvailability.denied);
    final sink = _RecordingSink();
    final profiles = StreamController<List<Profile>>(sync: true);

    final coordinator = ReminderCoordinator(
      scheduler: scheduler,
      permissionState: sink,
      activeProfiles: profiles.stream,
      predictionFor: (_) => const Stream.empty(),
      replanDebounce: Duration.zero,
    );
    await coordinator.start();
    addTearDown(() async {
      await coordinator.dispose();
      await profiles.close();
    });

    expect(sink.updates, [NotificationAvailability.denied]);
    profiles.add([_profile('p1')]);
    await pumpEventQueue();
    expect(scheduler.rescheduleCalls, isEmpty);
    expect(scheduler.cancelCalls, greaterThan(0));
  });

  test('archiving a profile drops its reminders from the plan', () async {
    final scheduler = FakeReminderScheduler();
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

  test('a resume during initialize plans as available without throwing, and '
      'a replan still lands once initialize resolves', () async {
    // app.dart fires `unawaited(_startReminders())` from initState, so a
    // lifecycle resume can land while `_scheduler.initialize(...)` is still
    // pending (unbounded on iOS/macOS first launch, where it waits on the
    // system permission dialog). The coordinator must plan as "available"
    // in that gap rather than throw — a `late` _availability field throws
    // LateInitializationError here.
    //
    // The pre-resolve call is deliberately NOT the thing that keeps
    // reminders working: the real scheduler's rescheduleAll starts with
    // `if (!_initialized) return;`, so it drops that call. What production
    // actually honours is the replan driven by the profiles stream after
    // initialize resolves, so this test asserts that too — otherwise a
    // regression that broke the post-init replan would leave it green.
    final today = LocalDate(2026, 8, 30);
    final gate = Completer<void>();
    final scheduler = FakeReminderScheduler(initializeGate: gate);
    final permissionState = _RecordingSink();
    final profiles = StreamController<List<Profile>>(sync: true);
    final predictions = StreamController<CyclePrediction>(sync: true);
    final coordinator = ReminderCoordinator(
      scheduler: scheduler,
      permissionState: permissionState,
      activeProfiles: profiles.stream,
      predictionFor: (_) => predictions.stream,
      today: () => today,
      replanDebounce: Duration.zero,
    );
    final started = coordinator.start();
    addTearDown(() async {
      await coordinator.dispose();
      await profiles.close();
      await predictions.close();
    });

    coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();

    expect(scheduler.rescheduleCalls, hasLength(1),
        reason: 'the resume replan runs instead of throwing');
    expect(scheduler.cancelCalls, 0);

    gate.complete();
    await started;

    final beforePostInit = scheduler.rescheduleCalls.length;
    profiles.add([_profile('p1')]);
    predictions.add(_late(today));
    await pumpEventQueue();

    expect(scheduler.rescheduleCalls.length, greaterThan(beforePostInit),
        reason: 'a replan lands after initialize resolved — the call the '
            'real scheduler actually honours');
    expect(scheduler.rescheduleCalls.last.any((r) => r.profileId == 'p1'),
        isTrue);
  });

  test('notification tap payload reaches the launch seam', () async {
    final scheduler = FakeReminderScheduler();
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
