/// U8 coordinator tests (KTD7): replanning on stream changes, permission
/// denial skips scheduling, archiving drops a profile's reminders, the
/// notification-tap payload reaches the gate seam.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/notifications/reminder_coordinator.dart';
import 'package:lunarlog/domain/birth_control.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/notifications/reminder_config.dart';
import 'package:lunarlog/domain/notifications/reminder_config_store.dart';
import 'package:lunarlog/domain/notifications/reminder_payload.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/ui/overview/notification_permission_state.dart';

import '../support/fake_reminder_scheduler.dart';
import '../support/fake_settings_store.dart';

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
      originalEstimatedNextStart: today.addDays(-6),
      averagedCycleLengths: const [28],
      meanCycleLengthDays: 28,
      cycleDay: 35,
      duringEpisode: false,
      completedCycleCount: 4,
      validCycleCount: 4,
    );

ActivePrediction _upcoming(LocalDate today, LocalDate estimate) =>
    ActivePrediction(
      today: today,
      lastEpisodeStart: estimate.addDays(-28),
      estimatedNextStart: estimate,
      originalEstimatedNextStart: estimate,
      averagedCycleLengths: const [28],
      meanCycleLengthDays: 28,
      cycleDay: today.difference(estimate.addDays(-28)) + 1,
      duringEpisode: false,
      completedCycleCount: 4,
      validCycleCount: 4,
    );

/// An upcoming prediction whose displayed cycle-length average is
/// [meanCycleDays] — the statistic the `cycleStatisticChange` reminder
/// watches (Issue #178).
ActivePrediction _withMeanCycle(LocalDate today, LocalDate estimate,
        double meanCycleDays) =>
    ActivePrediction(
      today: today,
      lastEpisodeStart: estimate.addDays(-28),
      estimatedNextStart: estimate,
      originalEstimatedNextStart: estimate,
      averagedCycleLengths: const [28],
      meanCycleLengthDays: meanCycleDays,
      cycleDay: today.difference(estimate.addDays(-28)) + 1,
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

  test('care-mode presets: switching mode replans at the next coordinator '
      'pass, prospectively (Issue #131, KTD10)', () async {
    final scheduler = FakeReminderScheduler();
    final permissionState =
        NotificationPermissionState(NotificationAvailability.available);
    final profiles = StreamController<List<Profile>>(sync: true);
    final p1 = StreamController<CyclePrediction>(sync: true);
    final today = LocalDate(2026, 8, 30);

    final coordinator = ReminderCoordinator(
      scheduler: scheduler,
      permissionState: permissionState,
      activeProfiles: profiles.stream,
      predictionFor: (id) => id == 'p1' ? p1.stream : const Stream.empty(),
      today: () => today,
      replanDebounce: Duration.zero,
    );
    await coordinator.start();
    addTearDown(() async {
      await coordinator.dispose();
      await profiles.close();
      await p1.close();
    });

    // A caregiver-mode profile with a late prediction: its preset arms
    // nothing, so the plan is empty.
    profiles.add([_profile('p1').copyWith(mode: ProfileMode.caregiver)]);
    p1.add(_late(today));
    await pumpEventQueue();
    expect(scheduler.rescheduleCalls, isNotEmpty);
    expect(scheduler.rescheduleCalls.last, isEmpty,
        reason: 'caregiver preset plans no reminders');

    // Switching the profile's mode rides the same profiles stream; the
    // next coordinator pass replans with the standard preset. The late
    // prediction (still live, untouched by the switch) now pre-arms.
    profiles.add([_profile('p1').copyWith(mode: ProfileMode.standard)]);
    await pumpEventQueue();
    final lastPlan = scheduler.rescheduleCalls.last;
    expect(lastPlan, isNotEmpty);
    expect(lastPlan.every((r) => r.kind == ReminderKind.late), isTrue,
        reason: 'the mode switch never touched the prediction or entries');
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
    ReminderLaunch? launched;
    final coordinator = ReminderCoordinator(
      scheduler: scheduler,
      permissionState: permissionState,
      activeProfiles: const Stream.empty(),
      predictionFor: (_) => const Stream.empty(),
      replanDebounce: Duration.zero,
    );
    await coordinator.start(onLaunchFromNotification: (launch) {
      launched = launch;
    });
    addTearDown(coordinator.dispose);

    scheduler.launchSink!(const ReminderLaunch(profileId: 'p9'));
    expect(launched, isNotNull);
    expect(launched!.profileId, 'p9');
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

  test('requestPermission (issue #168, "Turn on reminders") re-requests '
      'and republishes the result without waiting for a resume', () async {
    final scheduler = FakeReminderScheduler(
        initialAvailability: NotificationAvailability.denied)
      ..requestPermissionResult = NotificationAvailability.available;
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

    expect(permissionState.value, NotificationAvailability.denied);
    await coordinator.requestPermission();

    expect(scheduler.requestPermissionCalls, 1);
    expect(permissionState.value, NotificationAvailability.available);
  });

  test('requestPermission cancels reminders when the re-request is still '
      'denied', () async {
    final scheduler = FakeReminderScheduler(
        initialAvailability: NotificationAvailability.denied)
      ..requestPermissionResult = NotificationAvailability.denied;
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

    final cancelsBefore = scheduler.cancelCalls;
    await coordinator.requestPermission();
    await pumpEventQueue();

    expect(permissionState.value, NotificationAvailability.denied);
    expect(scheduler.cancelCalls, greaterThan(cancelsBefore));
  });

  test('requestPermission before start() completes is a no-op (mirrors the '
      '_started guard on a resume)', () async {
    final gate = Completer<void>();
    final scheduler = FakeReminderScheduler(initializeGate: gate)
      ..requestPermissionResult = NotificationAvailability.available;
    final permissionState =
        NotificationPermissionState(NotificationAvailability.available);
    final coordinator = ReminderCoordinator(
      scheduler: scheduler,
      permissionState: permissionState,
      activeProfiles: const Stream.empty(),
      predictionFor: (_) => const Stream.empty(),
      replanDebounce: Duration.zero,
    );
    final started = coordinator.start();
    addTearDown(coordinator.dispose);

    await coordinator.requestPermission();
    expect(scheduler.requestPermissionCalls, 0,
        reason: 'start() has not finished initializing yet');

    gate.complete();
    await started;
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

  group('per-profile local reminder configuration (Issue #136)', () {
    test('a stored config flows into the plan; a profile without one '
        'keeps its preset defaults', () async {
      final scheduler = FakeReminderScheduler();
      final permissionState =
          NotificationPermissionState(NotificationAvailability.available);
      final profiles = StreamController<List<Profile>>(sync: true);
      final p1 = StreamController<CyclePrediction>(sync: true);
      final store = FakeSettingsStore();
      final configService = ReminderConfigService(store);
      addTearDown(store.close);
      final today = LocalDate(2026, 8, 30);

      // p1 turns the log nudge on; p2 stays unconfigured.
      await configService.save(
        'p1',
        ReminderConfig.standard.copyWith(
          log: ReminderTypeConfig(
              enabled: true, timeOfDayMinutes: 20 * 60),
        ),
      );

      final coordinator = ReminderCoordinator(
        scheduler: scheduler,
        permissionState: permissionState,
        activeProfiles: profiles.stream,
        predictionFor: (id) => id == 'p1' ? p1.stream : const Stream.empty(),
        localSettings: configService,
        today: () => today,
        replanDebounce: Duration.zero,
      );
      await coordinator.start();
      addTearDown(() async {
        await coordinator.dispose();
        await profiles.close();
        await p1.close();
      });

      profiles.add([_profile('p1'), _profile('p2')]);
      p1.add(_upcoming(today, today.addDays(10)));
      await pumpEventQueue();

      final plan = scheduler.rescheduleCalls.last;
      final p1Kinds =
          plan.where((r) => r.profileId == 'p1').map((r) => r.kind).toSet();
      expect(p1Kinds, {ReminderKind.upcoming, ReminderKind.log},
          reason: 'the stored config adds the nudge to the preset default');
      expect(
        plan.where((r) => r.profileId == 'p2').map((r) => r.kind),
        isEmpty,
        reason: 'p2 has no prediction, so only its (absent) nudge could '
            'plan — nothing else',
      );
    });

    test('a settings edit replans at the next pass (the changes stream)',
        () async {
      final scheduler = FakeReminderScheduler();
      final permissionState =
          NotificationPermissionState(NotificationAvailability.available);
      final profiles = StreamController<List<Profile>>(sync: true);
      final p1 = StreamController<CyclePrediction>(sync: true);
      final store = FakeSettingsStore();
      final configService = ReminderConfigService(store);
      addTearDown(store.close);
      final today = LocalDate(2026, 8, 30);

      final coordinator = ReminderCoordinator(
        scheduler: scheduler,
        permissionState: permissionState,
        activeProfiles: profiles.stream,
        predictionFor: (id) => id == 'p1' ? p1.stream : const Stream.empty(),
        localSettings: configService,
        today: () => today,
        replanDebounce: Duration.zero,
      );
      await coordinator.start();
      addTearDown(() async {
        await coordinator.dispose();
        await profiles.close();
        await p1.close();
      });

      profiles.add([_profile('p1')]);
      p1.add(_upcoming(today, today.addDays(10)));
      await pumpEventQueue();
      expect(
        scheduler.rescheduleCalls.last
            .any((r) => r.kind == ReminderKind.log),
        isFalse,
      );

      // The settings screen saves; no prediction or profile change
      // happens — the changes stream alone drives the replan.
      final plansBefore = scheduler.rescheduleCalls.length;
      await configService.save(
        'p1',
        ReminderConfig.standard.copyWith(
          log: ReminderTypeConfig(
              enabled: true, timeOfDayMinutes: 20 * 60),
        ),
      );
      await pumpEventQueue();
      expect(scheduler.rescheduleCalls.length, greaterThan(plansBefore));
      expect(
        scheduler.rescheduleCalls.last
            .any((r) => r.kind == ReminderKind.log),
        isTrue,
      );
    });

    test('two profiles hold different schedules and both plan correctly',
        () async {
      final scheduler = FakeReminderScheduler();
      final permissionState =
          NotificationPermissionState(NotificationAvailability.available);
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final store = FakeSettingsStore();
      final configService = ReminderConfigService(store);
      addTearDown(store.close);
      final today = LocalDate(2026, 8, 30);

      // Alice: due reminder at 07:30. Bea: late nudge disabled, log nudge
      // at 21:00.
      await configService.save(
        'alice',
        ReminderConfig.standard.copyWith(
          upcoming: ReminderTypeConfig(
              enabled: true, leadDays: 2, timeOfDayMinutes: 7 * 60 + 30),
        ),
      );
      await configService.save(
        'bea',
        ReminderConfig.standard.copyWith(
          upcoming: ReminderTypeConfig(
              enabled: false, leadDays: 2, timeOfDayMinutes: 9 * 60),
          log: ReminderTypeConfig(
              enabled: true, timeOfDayMinutes: 21 * 60),
        ),
      );

      final coordinator = ReminderCoordinator(
        scheduler: scheduler,
        permissionState: permissionState,
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
            .stream,
        localSettings: configService,
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

      profiles.add([_profile('alice'), _profile('bea')]);
      predictions['alice']!
          .add(_upcoming(today, today.addDays(10)));
      predictions['bea']!.add(_upcoming(today, today.addDays(10)));
      await pumpEventQueue();

      final plan = scheduler.rescheduleCalls.last;
      final aliceUpcoming = plan
          .where((r) => r.profileId == 'alice' && r.kind == ReminderKind.upcoming)
          .single;
      expect(aliceUpcoming.fireOn, today.addDays(8));
      expect(aliceUpcoming.timeOfDayMinutes, 7 * 60 + 30);
      final beaPlan = plan.where((r) => r.profileId == 'bea').toList();
      expect(beaPlan, isNotEmpty);
      expect(beaPlan.map((r) => r.kind), everyElement(ReminderKind.log),
          reason: 'Bea\'s due reminder is off; only her nudge plans');
      expect(beaPlan.every((r) => r.timeOfDayMinutes == 21 * 60), isTrue);
      expect(beaPlan.map((r) => r.fireOn), contains(today),
          reason: 'the nudge window starts today');
    });

    test('a "Not yet" snooze suppresses the late window at the next '
        'replan, and an estimate shift re-derives the fire date', () async {
      final scheduler = FakeReminderScheduler();
      final permissionState =
          NotificationPermissionState(NotificationAvailability.available);
      final profiles = StreamController<List<Profile>>(sync: true);
      final p1 = StreamController<CyclePrediction>(sync: true);
      final store = FakeSettingsStore();
      final configService = ReminderConfigService(store);
      addTearDown(store.close);
      final today = LocalDate(2026, 8, 30);

      final coordinator = ReminderCoordinator(
        scheduler: scheduler,
        permissionState: permissionState,
        activeProfiles: profiles.stream,
        predictionFor: (id) => id == 'p1' ? p1.stream : const Stream.empty(),
        localSettings: configService,
        today: () => today,
        replanDebounce: Duration.zero,
      );
      await coordinator.start();
      addTearDown(() async {
        await coordinator.dispose();
        await profiles.close();
        await p1.close();
      });

      profiles.add([_profile('p1')]);
      p1.add(_late(today));
      await pumpEventQueue();
      expect(
        scheduler.rescheduleCalls.last
            .map((r) => r.kind)
            .toSet(),
        {ReminderKind.late},
      );

      // The "Not yet" action snoozes through the executor; the write lands
      // in the same service the coordinator re-reads.
      await configService.snoozeLate('p1', days: 3, today: today);
      await pumpEventQueue();
      expect(
        scheduler.rescheduleCalls.last
            .where((r) => r.kind == ReminderKind.late),
        isEmpty,
        reason: 'the snoozed late window stops planning',
      );

      // The estimate shifts: the next replan re-derives the upcoming fire
      // date from the live estimate.
      p1.add(_upcoming(today, today.addDays(12)));
      await pumpEventQueue();
      final upcoming = scheduler.rescheduleCalls.last
          .where((r) => r.kind == ReminderKind.upcoming)
          .single;
      expect(upcoming.fireOn, today.addDays(10),
          reason: 'estimate 12 days out minus the default 2-day lead');
    });
  });

  group('cycle-statistic-change detection (Issue #178)', () {
    ReminderConfig statEnabled() => ReminderConfig.standard.copyWith(
          cycleStatisticChange:
              ReminderTypeConfig(enabled: true, timeOfDayMinutes: 9 * 60),
        );

    test('AC3: a threshold move against the stored baseline plans a '
        'same-day notification once; a re-emission does not duplicate',
        () async {
      final scheduler = FakeReminderScheduler();
      final permissionState =
          NotificationPermissionState(NotificationAvailability.available);
      final profiles = StreamController<List<Profile>>(sync: true);
      final p1 = StreamController<CyclePrediction>(sync: true);
      final store = FakeSettingsStore();
      final configService = ReminderConfigService(store);
      addTearDown(store.close);
      final today = LocalDate(2026, 8, 30);
      await configService.save('p1', statEnabled());

      final coordinator = ReminderCoordinator(
        scheduler: scheduler,
        permissionState: permissionState,
        activeProfiles: profiles.stream,
        predictionFor: (id) => id == 'p1' ? p1.stream : const Stream.empty(),
        localSettings: configService,
        today: () => today,
        replanDebounce: Duration.zero,
      );
      await coordinator.start();
      addTearDown(() async {
        await coordinator.dispose();
        await profiles.close();
        await p1.close();
      });

      // First emission: no baseline yet, so nothing fires — this pass
      // re-baselines.
      profiles.add([_profile('p1')]);
      p1.add(_withMeanCycle(today, today.addDays(10), 28));
      await pumpEventQueue();
      expect(
        scheduler.rescheduleCalls.last
            .where((r) => r.kind == ReminderKind.cycleStatisticChange),
        isEmpty,
      );

      // +3 displayed days: a meaningful change. The same-day reminder
      // arms.
      p1.add(_withMeanCycle(today, today.addDays(10), 31));
      await pumpEventQueue();
      final stat = scheduler.rescheduleCalls.last
          .where((r) => r.kind == ReminderKind.cycleStatisticChange)
          .single;
      expect(stat.profileId, 'p1');
      expect(stat.fireOn, today);
      expect(stat.timeOfDayMinutes, 9 * 60);

      // The signal persists in the store for the same-day restart case.
      expect(await configService.loadStatisticChangeSignals(), {'p1': today});
      // And the baseline moved with the observation.
      expect((await configService.loadStatisticBaselines())['p1']!
          .meanCycleLengthDays, 31);

      // A further no-change replan keeps exactly the same plan (same
      // stable id, no duplicate).
      p1.add(_withMeanCycle(today, today.addDays(10), 31));
      await pumpEventQueue();
      final statAgain = scheduler.rescheduleCalls.last
          .where((r) => r.kind == ReminderKind.cycleStatisticChange)
          .toList();
      expect(statAgain, hasLength(1));
      expect(statAgain.single.id, stat.id);
    });

    test('a sub-threshold move plans nothing and updates the baseline',
        () async {
      final scheduler = FakeReminderScheduler();
      final permissionState =
          NotificationPermissionState(NotificationAvailability.available);
      final profiles = StreamController<List<Profile>>(sync: true);
      final p1 = StreamController<CyclePrediction>(sync: true);
      final store = FakeSettingsStore();
      final configService = ReminderConfigService(store);
      addTearDown(store.close);
      final today = LocalDate(2026, 8, 30);
      await configService.save('p1', statEnabled());

      final coordinator = ReminderCoordinator(
        scheduler: scheduler,
        permissionState: permissionState,
        activeProfiles: profiles.stream,
        predictionFor: (id) => id == 'p1' ? p1.stream : const Stream.empty(),
        localSettings: configService,
        today: () => today,
        replanDebounce: Duration.zero,
      );
      await coordinator.start();
      addTearDown(() async {
        await coordinator.dispose();
        await profiles.close();
        await p1.close();
      });

      profiles.add([_profile('p1')]);
      p1.add(_withMeanCycle(today, today.addDays(10), 28));
      await pumpEventQueue();
      p1.add(_withMeanCycle(today, today.addDays(10), 29));
      await pumpEventQueue();

      expect(
        scheduler.rescheduleCalls.last
            .where((r) => r.kind == ReminderKind.cycleStatisticChange),
        isEmpty,
        reason: '28 → 29 displayed days is below the documented threshold',
      );
      expect(
        scheduler.rescheduleCalls.last
            .where((r) => r.kind == ReminderKind.upcoming),
        isNotEmpty,
        reason: 'the ordinary kinds replanned as always',
      );
      expect((await configService.loadStatisticBaselines())['p1']!
          .meanCycleLengthDays, 29,
          reason: 'the baseline tracks every observation, fired or not');
      expect(await configService.loadStatisticChangeSignals(), isEmpty);
    });

    test('detection runs while the kind is off; enabling it mid-day fires '
        'the observed change at the next pass', () async {
      final scheduler = FakeReminderScheduler();
      final permissionState =
          NotificationPermissionState(NotificationAvailability.available);
      final profiles = StreamController<List<Profile>>(sync: true);
      final p1 = StreamController<CyclePrediction>(sync: true);
      final store = FakeSettingsStore();
      final configService = ReminderConfigService(store);
      addTearDown(store.close);
      final today = LocalDate(2026, 8, 30);

      final coordinator = ReminderCoordinator(
        scheduler: scheduler,
        permissionState: permissionState,
        activeProfiles: profiles.stream,
        predictionFor: (id) => id == 'p1' ? p1.stream : const Stream.empty(),
        localSettings: configService,
        today: () => today,
        replanDebounce: Duration.zero,
      );
      await coordinator.start();
      addTearDown(() async {
        await coordinator.dispose();
        await profiles.close();
        await p1.close();
      });

      profiles.add([_profile('p1')]);
      p1.add(_withMeanCycle(today, today.addDays(10), 28));
      await pumpEventQueue();
      // The kind is still off in the default config.
      p1.add(_withMeanCycle(today, today.addDays(10), 31));
      await pumpEventQueue();
      expect(
        scheduler.rescheduleCalls.last
            .where((r) => r.kind == ReminderKind.cycleStatisticChange),
        isEmpty,
        reason: 'the toggle gates the notification, not the detection',
      );

      // The operator flips the toggle; the changes stream replans and the
      // same-day signal (already recorded) becomes a notification.
      await configService.save('p1', statEnabled());
      await pumpEventQueue();
      final stat = scheduler.rescheduleCalls.last
          .where((r) => r.kind == ReminderKind.cycleStatisticChange)
          .single;
      expect(stat.fireOn, today);
    });

    test('two profiles detect independently (consistent with the #136 ACs)',
        () async {
      final scheduler = FakeReminderScheduler();
      final permissionState =
          NotificationPermissionState(NotificationAvailability.available);
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final store = FakeSettingsStore();
      final configService = ReminderConfigService(store);
      addTearDown(store.close);
      final today = LocalDate(2026, 8, 30);
      await configService.save('alice', statEnabled());
      await configService.save('bea', statEnabled());

      final coordinator = ReminderCoordinator(
        scheduler: scheduler,
        permissionState: permissionState,
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
            .stream,
        localSettings: configService,
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

      profiles.add([_profile('alice'), _profile('bea')]);
      predictions['alice']!
          .add(_withMeanCycle(today, today.addDays(10), 28));
      predictions['bea']!.add(_withMeanCycle(today, today.addDays(10), 28));
      await pumpEventQueue();

      // Only Alice's statistics move past the threshold.
      predictions['alice']!
          .add(_withMeanCycle(today, today.addDays(10), 31));
      await pumpEventQueue();

      final plan = scheduler.rescheduleCalls.last;
      expect(
        plan
            .where((r) => r.kind == ReminderKind.cycleStatisticChange)
            .map((r) => r.profileId),
        ['alice'],
        reason: 'Bea\'s unchanged statistics plan no statistic reminder',
      );
      // Bea still plans her ordinary reminder.
      expect(
        plan.any((r) => r.profileId == 'bea'),
        isTrue,
      );
    });
  });

  group('birth-control state watcher (Issue #183)', () {
    test('a recorded method flows into the plan; enabling the kind arms '
        'its cadence without any prediction', () async {
      final scheduler = FakeReminderScheduler();
      final permissionState =
          NotificationPermissionState(NotificationAvailability.available);
      final profiles = StreamController<List<Profile>>(sync: true);
      final p1Mode = StreamController<BirthControlState?>(sync: true);
      final store = FakeSettingsStore();
      final configService = ReminderConfigService(store);
      addTearDown(store.close);
      final today = LocalDate(2026, 8, 30);
      await configService.save(
        'p1',
        ReminderConfig.standard.copyWith(
          birthControlPill:
              ReminderTypeConfig(enabled: true, timeOfDayMinutes: 9 * 60),
        ),
      );

      final coordinator = ReminderCoordinator(
        scheduler: scheduler,
        permissionState: permissionState,
        activeProfiles: profiles.stream,
        predictionFor: (_) => const Stream.empty(),
        localSettings: configService,
        birthControlStateFor: (id) =>
            id == 'p1' ? p1Mode.stream : const Stream.empty(),
        today: () => today,
        replanDebounce: Duration.zero,
      );
      await coordinator.start();
      addTearDown(() async {
        await coordinator.dispose();
        await profiles.close();
        await p1Mode.close();
      });

      profiles.add([_profile('p1')]);
      await pumpEventQueue();
      // No row yet: the enabled kind has nothing to anchor on.
      expect(
        scheduler.rescheduleCalls.last
            .where((r) => r.kind == ReminderKind.birthControlPill),
        isEmpty,
      );

      p1Mode.add((method: 'pill', startedOn: null, stoppedOn: null));
      await pumpEventQueue();
      final kinds = scheduler.rescheduleCalls.last
          .where((r) => r.profileId == 'p1')
          .map((r) => r.kind)
          .toSet();
      expect(kinds, {ReminderKind.birthControlPill},
          reason: 'prediction-independent: the pill window plans from the '
              'method alone');
    });

    test('changing the recorded method re-routes the reminder; nothing '
        'stale keeps firing for the old method', () async {
      final scheduler = FakeReminderScheduler();
      final permissionState =
          NotificationPermissionState(NotificationAvailability.available);
      final profiles = StreamController<List<Profile>>(sync: true);
      final p1Mode = StreamController<BirthControlState?>(sync: true);
      final store = FakeSettingsStore();
      final configService = ReminderConfigService(store);
      addTearDown(store.close);
      final today = LocalDate(2026, 8, 30);
      // Both kinds enabled: only the current method's may ever plan.
      await configService.save(
        'p1',
        ReminderConfig.standard.copyWith(
          birthControlPill:
              ReminderTypeConfig(enabled: true, timeOfDayMinutes: 9 * 60),
          birthControlPatch:
              ReminderTypeConfig(enabled: true, timeOfDayMinutes: 9 * 60),
        ),
      );

      final coordinator = ReminderCoordinator(
        scheduler: scheduler,
        permissionState: permissionState,
        activeProfiles: profiles.stream,
        predictionFor: (_) => const Stream.empty(),
        localSettings: configService,
        birthControlStateFor: (_) => p1Mode.stream,
        today: () => today,
        replanDebounce: Duration.zero,
      );
      await coordinator.start();
      addTearDown(() async {
        await coordinator.dispose();
        await profiles.close();
        await p1Mode.close();
      });

      profiles.add([_profile('p1')]);
      p1Mode.add((
        method: 'pill',
        startedOn: today.addDays(-30).iso,
        stoppedOn: null,
      ));
      await pumpEventQueue();
      var kinds = scheduler.rescheduleCalls.last
          .where((r) => r.profileId == 'p1')
          .map((r) => r.kind)
          .toSet();
      expect(kinds, {ReminderKind.birthControlPill});

      // Switch to the patch: the row emission replans and the pill
      // reminders are gone from the fresh plan (rescheduleAll cancels all
      // pending first, so the armed pill notifications die with it).
      p1Mode.add((method: 'patch', startedOn: today.iso, stoppedOn: null));
      await pumpEventQueue();
      kinds = scheduler.rescheduleCalls.last
          .where((r) => r.profileId == 'p1')
          .map((r) => r.kind)
          .toSet();
      expect(kinds, {ReminderKind.birthControlPatch},
          reason: 'the pill kind vanished with the method');

      // Stopping the method (a stop date as of today) clears the
      // adherence reminder entirely.
      p1Mode.add((
        method: 'patch',
        startedOn: today.addDays(-7).iso,
        stoppedOn: today.iso,
      ));
      await pumpEventQueue();
      kinds = scheduler.rescheduleCalls.last
          .where((r) => r.profileId == 'p1')
          .map((r) => r.kind)
          .toSet();
      expect(kinds, isEmpty,
          reason: 'a stopped method is not in effect, so no adherence '
              'reminder plans');
    });

    test('no watcher wired keeps the pre-#183 shape (no adherence '
        'reminders)', () async {
      final scheduler = FakeReminderScheduler();
      final permissionState =
          NotificationPermissionState(NotificationAvailability.available);
      final profiles = StreamController<List<Profile>>(sync: true);
      final p1 = StreamController<CyclePrediction>(sync: true);
      final store = FakeSettingsStore();
      final configService = ReminderConfigService(store);
      addTearDown(store.close);
      final today = LocalDate(2026, 8, 30);
      await configService.save(
        'p1',
        ReminderConfig.standard.copyWith(
          birthControlPill:
              ReminderTypeConfig(enabled: true, timeOfDayMinutes: 9 * 60),
        ),
      );

      final coordinator = ReminderCoordinator(
        scheduler: scheduler,
        permissionState: permissionState,
        activeProfiles: profiles.stream,
        predictionFor: (id) => id == 'p1' ? p1.stream : const Stream.empty(),
        localSettings: configService,
        today: () => today,
        replanDebounce: Duration.zero,
      );
      await coordinator.start();
      addTearDown(() async {
        await coordinator.dispose();
        await profiles.close();
        await p1.close();
      });

      profiles.add([_profile('p1')]);
      p1.add(_upcoming(today, today.addDays(10)));
      await pumpEventQueue();

      final kinds = scheduler.rescheduleCalls.last
          .where((r) => r.profileId == 'p1')
          .map((r) => r.kind)
          .toSet();
      expect(kinds, {ReminderKind.upcoming},
          reason: 'without a birth-control stream the plan is exactly what '
              'pre-#183 code produced');
    });
  });
}
