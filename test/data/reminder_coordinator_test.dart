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

  test('a resume during initialize is ignored, and a replan lands once start() completes', () async {
    // app.dart fires `unawaited(_startReminders())` from initState, so a
    // lifecycle resume can land while `_scheduler.initialize(...)` is still
    // pending (unbounded on iOS/macOS first launch, where it waits on the
    // system permission dialog).
    //
    // `didChangeAppLifecycleState` guards on `_started`, which is set only
    // at the end of `start()`, so that resume is dropped rather than
    // driving a replan against half-initialised state. Dropping it costs
    // nothing: the real scheduler's `rescheduleAll` opens with
    // `if (!_initialized) return;`, so it would have discarded the call
    // anyway. What production actually honours is the replan the profiles
    // stream drives after `start()` completes — asserted below, so a
    // regression that broke it cannot leave this test green.
    //
    // `_availability`'s eager initializer is defence in depth for the same
    // window: `replan()` reads it, and a `late` field would throw
    // LateInitializationError if anything ever reached it before start().

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

    expect(scheduler.rescheduleCalls, isEmpty,
        reason: 'the _started guard drops a resume that lands mid-start');
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

  test('resume refreshes permission before replanning', () async {
    final scheduler = FakeReminderScheduler(
        initialAvailability: NotificationAvailability.denied)
      ..currentAvailability = NotificationAvailability.available;
    final permissionState =
        NotificationPermissionState(NotificationAvailability.denied);
    final coordinator = ReminderCoordinator(
      scheduler: scheduler,
      permissionState: permissionState,
      activeProfiles: const Stream.empty(),
      predictionFor: (_) => const Stream.empty(),
      replanDebounce: Duration.zero,
    );
    await coordinator.start();
    addTearDown(coordinator.dispose);

    coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();

    expect(scheduler.availabilityChecks, 1);
    expect(permissionState.value, NotificationAvailability.available);
    expect(scheduler.rescheduleCalls, isNotEmpty);
  });

  test('resume notices revoked permission and cancels reminders', () async {
    final scheduler = FakeReminderScheduler()
      ..currentAvailability = NotificationAvailability.denied;
    final permissionState =
        NotificationPermissionState(NotificationAvailability.available);
    final coordinator = ReminderCoordinator(
      scheduler: scheduler,
      permissionState: permissionState,
      activeProfiles: const Stream.empty(),
      predictionFor: (_) => const Stream.empty(),
      replanDebounce: Duration.zero,
    );
    await coordinator.start();
    addTearDown(coordinator.dispose);

    coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();

    expect(permissionState.value, NotificationAvailability.denied);
    expect(scheduler.cancelCalls, 1);
  });

  test('a stale permission probe cannot overwrite a newer resume', () async {
    final first = Completer<NotificationAvailability>();
    final second = Completer<NotificationAvailability>();
    final scheduler = FakeReminderScheduler()
      ..availabilityGates.addAll([first, second]);
    final permissionState =
        NotificationPermissionState(NotificationAvailability.available);
    final coordinator = ReminderCoordinator(
      scheduler: scheduler,
      permissionState: permissionState,
      activeProfiles: const Stream.empty(),
      predictionFor: (_) => const Stream.empty(),
      replanDebounce: Duration.zero,
    );
    await coordinator.start();
    addTearDown(coordinator.dispose);

    coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
    coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
    second.complete(NotificationAvailability.available);
    await pumpEventQueue();
    first.complete(NotificationAvailability.denied);
    await pumpEventQueue();

    expect(permissionState.value, NotificationAvailability.available);
    expect(scheduler.cancelCalls, 0);
  });
}
