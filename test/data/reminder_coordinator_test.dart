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
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/notifications/reminder_config.dart';
import 'package:lunarlog/domain/notifications/reminder_config_store.dart';
import 'package:lunarlog/domain/notifications/reminder_payload.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/sharing/guardian_lens.dart';
import 'package:lunarlog/ui/overview/notification_permission_state.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

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

/// A guardian row fixture for the #850 lens source (mirrors the production
/// shape: the viewer's accepted membership, subject-stamped per #802).
ProfileGuardian _row({
  required String profileId,
  required String userId,
  bool isSubject = false,
  GuardianRole role = GuardianRole.caregiver,
}) =>
    ProfileGuardian(
      id: '$profileId-$userId',
      profileId: profileId,
      userId: userId,
      role: role,
      isSubject: isSubject,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

/// The production lens source shape (`app_dependencies.dart`'s
/// `_subjectProfileSource`): resolve the viewer's lens from the profile's
/// guardian rows over [guardianLensFor].
SubjectProfileSource _lensSource({
  required String? viewerId,
  required Map<String, List<ProfileGuardian>> rows,
}) =>
    (profileId) async =>
        guardianLensFor(rows[profileId] ?? const [], viewerId) ==
        GuardianLens.subject;

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
  tzdata.initializeTimeZones();

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

    // A teen-mode profile with a late prediction: its preset keeps
    // upcoming but drops the late window, so the plan is empty.
    // (Issue #850 retired caregiver's "arms nothing" preset — a guardian's
    // device is gated on the per-viewer lens in U4, not on the mode — so
    // teen now carries this case.)
    profiles.add([_profile('p1').copyWith(mode: ProfileMode.teen)]);
    p1.add(_late(today));
    await pumpEventQueue();
    expect(scheduler.rescheduleCalls, isNotEmpty);
    expect(scheduler.rescheduleCalls.last, isEmpty,
        reason: 'teen preset plans no late reminder');

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

  test('guardian lens: a guarded profile arms nothing while the viewer\'s '
      'own subject profile still arms its mode preset (Issue #850, D-6)',
      () async {
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
      predictionFor: (id) => predictions
          .putIfAbsent(id, () => StreamController<CyclePrediction>(sync: true))
          .stream,
      today: () => today,
      // The viewer is the subject of their own profile and a primary
      // guardian (not the subject) of the guarded one — #802's
      // is_subject marker, exactly what the app wires from the guardian
      // rows + signed-in user id.
      isSubjectFor: _lensSource(
        viewerId: 'u-mom',
        rows: {
          'subject': [
            _row(profileId: 'subject', userId: 'u-mom', isSubject: true),
          ],
          'guarded': [
            _row(
              profileId: 'guarded',
              userId: 'u-mom',
              role: GuardianRole.primaryGuardian,
            ),
          ],
        },
      ),
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

    profiles.add([
      _profile('subject').copyWith(mode: ProfileMode.standard),
      _profile('guarded').copyWith(mode: ProfileMode.standard),
    ]);
    predictions['subject']!.add(_late(today));
    predictions['guarded']!.add(_late(today));
    await pumpEventQueue();

    final plan = scheduler.rescheduleCalls.last;
    expect(plan.any((r) => r.profileId == 'subject'), isTrue,
        reason: 'the viewer is the subject — the standard mode preset arms');
    expect(plan.any((r) => r.profileId == 'guarded'), isFalse,
        reason: 'the viewer only guards this profile — no local reminder '
            'for someone else\'s record');
  });

  test('a null lens source keeps the pre-#850 all-subject default '
      '(Issue #850, D-6)', () async {
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
      predictionFor: (id) => predictions
          .putIfAbsent(id, () => StreamController<CyclePrediction>(sync: true))
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

    profiles.add([_profile('p1'), _profile('p2')]);
    predictions['p1']!.add(_late(today));
    predictions['p2']!.add(_late(today));
    await pumpEventQueue();

    final plan = scheduler.rescheduleCalls.last;
    expect(plan.any((r) => r.profileId == 'p1'), isTrue);
    expect(plan.any((r) => r.profileId == 'p2'), isTrue,
        reason: 'with no source every active profile is treated as the '
            'viewer\'s own, exactly as before #850');
  });

  test('the legacy caregiver mode now plans like standard on a subject '
      'profile (Issue #850, U2/D-6)', () async {
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
      // The viewer is the subject (or, failing open, treated as one): the
      // retired caregiver wire value no longer suppresses anything.
      isSubjectFor: (_) async => true,
      replanDebounce: Duration.zero,
    );
    await coordinator.start();
    addTearDown(() async {
      await coordinator.dispose();
      await profiles.close();
      await p1.close();
    });

    profiles.add([_profile('p1').copyWith(mode: ProfileMode.caregiver)]);
    p1.add(_late(today));
    await pumpEventQueue();

    final plan = scheduler.rescheduleCalls.last;
    expect(plan, isNotEmpty,
        reason: 'caregiver is a retired wire value mapped to standard — it '
            'arms the late window, unlike the pre-#850 behavior');
    expect(plan.every((r) => r.profileId == 'p1'), isTrue);
    expect(plan.every((r) => r.kind == ReminderKind.late), isTrue);
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

  test(
      'resume re-resolves changed device timezone, updates tz.local, and replans (issue #169)',
      () async {
    final scheduler = FakeReminderScheduler();
    final permissionState =
        NotificationPermissionState(NotificationAvailability.available);
    final ny = tz.getLocation('America/New_York');
    tz.setLocalLocation(ny);
    expect(tz.local.name, 'America/New_York');

    var currentTz = 'Europe/Paris';
    final coordinator = ReminderCoordinator(
      scheduler: scheduler,
      permissionState: permissionState,
      activeProfiles: const Stream.empty(),
      predictionFor: (_) => const Stream.empty(),
      localTimeZoneProvider: () async => currentTz,
      replanDebounce: Duration.zero,
    );
    await coordinator.start();
    addTearDown(coordinator.dispose);

    final initialReschedules = scheduler.rescheduleCalls.length;

    // Simulate traveling to Tokyo and resuming
    currentTz = 'Asia/Tokyo';
    coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();

    expect(tz.local.name, 'Asia/Tokyo');
    expect(scheduler.rescheduleCalls.length, greaterThan(initialReschedules));
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
      // No real zone change here — the case where a resolved zone change
      // must itself trigger a correcting replan is covered separately
      // below ("a timezone change discovered after the debounce still
      // triggers a correcting replan"). Reading `tz.local.name` at call
      // time (rather than the real platform-channel default, whose
      // resolution the coordinator no longer waits on per #655) keeps
      // this test's single `cancelAll` count from depending on whatever
      // `tz.local` a prior test in this file happened to leave behind.
      localTimeZoneProvider: () async => tz.local.name,
      replanDebounce: Duration.zero,
    );
    await coordinator.start();
    addTearDown(coordinator.dispose);

    coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();

    expect(permissionState.value, NotificationAvailability.denied);
    expect(scheduler.cancelCalls, 1,
        reason: 'denied means only cancelAll is ever called here, exactly '
            'once — a resolved-but-unchanged zone must never trigger a '
            'second (redundant) cancelAll');
  });

  test('a timezone change discovered after the debounce still triggers a '
      'correcting replan (issue #169)', () async {
    // The real-world shape this guards: a cold resume where the resume's
    // own (debounced) replan fires using the stale zone before the
    // platform-channel timezone lookup — genuinely slower here than
    // `replanDebounce` — resolves with a *different* one. Fixing #655
    // (never gating the replan on that lookup) must not regress #169
    // (a real zone change going uncorrected).
    final scheduler = FakeReminderScheduler();
    final permissionState =
        NotificationPermissionState(NotificationAvailability.available);
    final ny = tz.getLocation('America/New_York');
    tz.setLocalLocation(ny);
    final tzGate = Completer<String>();

    final coordinator = ReminderCoordinator(
      scheduler: scheduler,
      permissionState: permissionState,
      activeProfiles: const Stream.empty(),
      predictionFor: (_) => const Stream.empty(),
      // Never resolves until the test completes it — guaranteed to
      // outlast the (zero) debounce below, deterministically, with no
      // reliance on real elapsed time.
      localTimeZoneProvider: () => tzGate.future,
      replanDebounce: Duration.zero,
    );
    await coordinator.start();
    addTearDown(coordinator.dispose);

    coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();

    // The resume's own replan has already fired against the stale zone;
    // the timezone lookup is still parked on the gate.
    final callsBeforeTzResolves = scheduler.rescheduleCalls.length;
    expect(callsBeforeTzResolves, greaterThan(0),
        reason: 'the #655 fix: the permission-driven replan never waits '
            'on the timezone lookup');
    expect(tz.local.name, 'America/New_York',
        reason: 'the zone has not changed yet');

    // The platform channel now answers with a different zone.
    tzGate.complete('Asia/Tokyo');
    await pumpEventQueue();

    expect(tz.local.name, 'Asia/Tokyo');
    expect(scheduler.rescheduleCalls.length, greaterThan(callsBeforeTzResolves),
        reason: 'a zone that turns out to have actually changed must '
            'still trigger its own correcting replan, even though the '
            'first pass already fired under the old zone');
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

    test('stored custom notification text reaches the scheduler payload '
        '(Issue #184: the scheduling path reads the per-type text)', () async {
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
          upcoming: ReminderTypeConfig.upcoming.copyWith(
            customTitle: 'Tea time',
            customBody: 'Bring the blue bottle.',
          ),
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

      final plan = scheduler.rescheduleCalls.last;
      final reminder = plan.singleWhere((r) => r.kind == ReminderKind.upcoming);
      expect(reminder.title, 'Tea time');
      expect(reminder.body, 'Bring the blue bottle.');

      // Editing the stored text re-arms the plan with the new copy through
      // the same changes-stream replan the schedule edits ride.
      await configService.save(
        'p1',
        ReminderConfig.standard.copyWith(
          upcoming: ReminderTypeConfig.upcoming.copyWith(
            customTitle: 'New title',
            customBody: 'New body',
          ),
        ),
      );
      await pumpEventQueue();
      final replanned = scheduler.rescheduleCalls.last
          .singleWhere((r) => r.kind == ReminderKind.upcoming);
      expect(replanned.title, 'New title');
      expect(replanned.body, 'New body');
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

  group('lifecycle serialization and disposal draining (Issue #634, '
      'LLA-097)', () {
    test('a superseded replan() pass is invalidated once a fresher one '
        'starts — only the latest plan reaches the scheduler', () async {
      final scheduler = FakeReminderScheduler();
      final permissionState =
          NotificationPermissionState(NotificationAvailability.available);
      final profiles = StreamController<List<Profile>>(sync: true);
      final p1 = StreamController<CyclePrediction>(sync: true);
      final store = FakeSettingsStore();
      final configService = ReminderConfigService(store);
      addTearDown(store.close);
      var today = LocalDate(2026, 8, 30);

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
      final before = scheduler.rescheduleCalls.length;

      // Advance today so the replan computes a fresh plan that differs from
      // the cached _lastAppliedPlan (Issue #840).
      today = today.addDays(1);

      // Two replan passes fired back-to-back with nothing awaited in
      // between — the same shape a fast profile edit racing a debounced
      // resume produces: the first is still reading stored config when
      // the second starts and (synchronously) claims the generation.
      final stale = coordinator.replan();
      final fresh = coordinator.replan();
      await Future.wait([stale, fresh]);

      expect(scheduler.rescheduleCalls.length, before + 1,
          reason: 'the superseded (first) pass never reaches the '
              'scheduler once a fresher one has started — no '
              'interleaved or duplicate rescheduleAll call');
    });

    test('dispose does not wait for an in-flight replan, and that replan '
        'still never re-arms the scheduler once it does settle', () async {
      // Issue #634, LLA-097, revised after PR #668's review round 2:
      // dispose() used to `await` the in-flight replan (and the scheduler
      // call it queued) so it could be observed as fully "drained" by the
      // time dispose() returned. That `await` had no bound, and hung a
      // real scenario: `LunarLogApp hands its coordinator teardown to
      // onTeardown` (test/ui/app_auth_provider_test.dart) — a widget
      // test's `State.dispose()` runs inside flutter_test's fake-async
      // zone, where an in-principle-already-resolved Future can still sit
      // unresolved until the zone is pumped again, which that test never
      // did before handing the returned teardown Future off. So dispose()
      // must return promptly regardless (asserted below via a bounded
      // timeout) — invalidation, not draining, is what actually keeps
      // LLA-097's guarantee.
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
        await profiles.close();
        await p1.close();
      });

      profiles.add([_profile('p1')]);
      p1.add(_late(today));
      await pumpEventQueue();
      final beforeDispose = scheduler.rescheduleCalls.length;

      // A replan is mid-flight (still reading stored config) when
      // dispose() is called.
      final inFlight = coordinator.replan();
      await coordinator.dispose().timeout(const Duration(seconds: 2));

      // Let the in-flight pass actually finish unwinding, then confirm it
      // never reached the scheduler — whether or not anyone waited for
      // it.
      await inFlight;
      expect(scheduler.rescheduleCalls.length, beforeDispose,
          reason: 'a replan already in flight when dispose() starts must '
              'never re-arm the scheduler once torn down — closed-store '
              'failures and stale re-armed reminders (LLA-097) both come '
              'from letting a pre-teardown pass keep writing');
    });

    test('a scheduler call that never completes cannot block dispose() — '
        'a hung platform call must never block app teardown', () async {
      final scheduler = FakeReminderScheduler()
        ..rescheduleGate = Completer<void>(); // never completed
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

      profiles.add([_profile('p1')]);
      p1.add(_late(today));
      await pumpEventQueue();
      // The replan is now genuinely stuck inside `rescheduleAll`, parked
      // on a gate that this test never completes.
      expect(scheduler.rescheduleCalls, isEmpty);

      // dispose() must return promptly regardless of that hang.
      await coordinator.dispose().timeout(const Duration(seconds: 2));

      await profiles.close();
      await p1.close();
    });
  });

  group('archived/removed profiles cannot plan through stored config or '
      'birth-control state (Issue #634, LLA-098)', () {
    test('a removed profile\'s stored config cannot plan a reminder once '
        'it leaves the active set', () async {
      final scheduler = FakeReminderScheduler();
      final permissionState =
          NotificationPermissionState(NotificationAvailability.available);
      final profiles = StreamController<List<Profile>>(sync: true);
      final store = FakeSettingsStore();
      final configService = ReminderConfigService(store);
      addTearDown(store.close);
      final today = LocalDate(2026, 8, 30);

      // p1's log nudge is enabled and persisted device-locally — nothing
      // deletes this row just because p1 leaves the active-profiles
      // stream (an archive or a remove).
      await configService.save(
        'p1',
        ReminderConfig.standard.copyWith(
          log: ReminderTypeConfig(enabled: true, timeOfDayMinutes: 20 * 60),
        ),
      );

      final coordinator = ReminderCoordinator(
        scheduler: scheduler,
        permissionState: permissionState,
        activeProfiles: profiles.stream,
        predictionFor: (_) => const Stream.empty(),
        localSettings: configService,
        today: () => today,
        replanDebounce: Duration.zero,
      );
      await coordinator.start();
      addTearDown(() async {
        await coordinator.dispose();
        await profiles.close();
      });

      profiles.add([_profile('p1')]);
      await pumpEventQueue();
      expect(
        scheduler.rescheduleCalls.last.any((r) => r.profileId == 'p1'),
        isTrue,
        reason: 'baseline: the log nudge plans while p1 is active',
      );

      // p1 is archived/removed: the active-profiles stream stops naming
      // it, but its stored config row is untouched in the settings
      // store.
      profiles.add([]);
      await pumpEventQueue();
      expect(
        scheduler.rescheduleCalls.last.any((r) => r.profileId == 'p1'),
        isFalse,
        reason: 'a stored config for a profile no longer in the active '
            'set must never plan a reminder',
      );
    });
  });

  group('skip rescheduleAll when plan is unchanged (Issue #840)', () {
    test('skip rescheduleAll when the computed reminder plan is unchanged',
        () async {
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

      profiles.add([_profile('p1')]);
      p1.add(_late(today));
      await pumpEventQueue();

      expect(scheduler.rescheduleCalls.length, 1);
      final initialPlan = scheduler.rescheduleCalls.single;

      // Trigger a direct replan without any input changes: plan is identical.
      await coordinator.replan();
      expect(
        scheduler.rescheduleCalls.length,
        1,
        reason:
            'rescheduleAll should be skipped when the computed plan is identical',
      );

      // A prediction update that changes the estimated date (and hence the plan)
      // must trigger rescheduleAll.
      p1.add(_upcoming(today, today.addDays(3)));
      await pumpEventQueue();

      expect(
        scheduler.rescheduleCalls.length,
        2,
        reason: 'rescheduleAll should be called when the plan actually changes',
      );
      expect(scheduler.rescheduleCalls.last, isNot(equals(initialPlan)));
    });

    test('identical prediction re-emission skips scheduling a replan',
        () async {
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

      profiles.add([_profile('p1')]);
      final pred = _late(today);
      p1.add(pred);
      await pumpEventQueue();

      expect(scheduler.rescheduleCalls.length, 1);

      // Re-emit the identical memo-cached prediction instance.
      p1.add(pred);
      await pumpEventQueue();

      expect(
        scheduler.rescheduleCalls.length,
        1,
        reason:
            'identical prediction emission should short-circuit before _scheduleReplan',
      );
    });

    test('identical birth-control state re-emission skips scheduling a replan',
        () async {
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
      final initialCount = scheduler.rescheduleCalls.length;

      const state = (method: 'pill', startedOn: null, stoppedOn: null);
      p1Mode.add(state);
      await pumpEventQueue();

      expect(scheduler.rescheduleCalls.length, initialCount + 1);

      // Re-emit identical state.
      p1Mode.add(state);
      await pumpEventQueue();

      expect(
        scheduler.rescheduleCalls.length,
        initialCount + 1,
        reason:
            'identical birth-control state emission should not schedule a replan',
      );
    });

    test('plan changes from config edits trigger rescheduleAll', () async {
      final scheduler = FakeReminderScheduler();
      final permissionState =
          NotificationPermissionState(NotificationAvailability.available);
      final profiles = StreamController<List<Profile>>(sync: true);
      final store = FakeSettingsStore();
      final configService = ReminderConfigService(store);
      addTearDown(store.close);
      final today = LocalDate(2026, 8, 30);

      final coordinator = ReminderCoordinator(
        scheduler: scheduler,
        permissionState: permissionState,
        activeProfiles: profiles.stream,
        predictionFor: (_) => const Stream.empty(),
        localSettings: configService,
        today: () => today,
        replanDebounce: Duration.zero,
      );
      await coordinator.start();
      addTearDown(() async {
        await coordinator.dispose();
        await profiles.close();
      });

      profiles.add([_profile('p1')]);
      await pumpEventQueue();

      final initialReschedules = scheduler.rescheduleCalls.length;

      // Enable log reminder in config.
      await configService.save(
        'p1',
        ReminderConfig.standard.copyWith(
          log: ReminderTypeConfig(enabled: true, timeOfDayMinutes: 21 * 60),
        ),
      );
      await pumpEventQueue();

      expect(
        scheduler.rescheduleCalls.length,
        initialReschedules + 1,
        reason:
            'config change updating the reminder plan should call rescheduleAll',
      );
    });

    test('timezone change resets cached plan and forces rescheduleAll',
        () async {
      final scheduler = FakeReminderScheduler();
      final permissionState =
          NotificationPermissionState(NotificationAvailability.available);
      final profiles = StreamController<List<Profile>>(sync: true);
      final p1 = StreamController<CyclePrediction>(sync: true);
      final today = LocalDate(2026, 8, 30);

      final ny = tz.getLocation('America/New_York');
      tz.setLocalLocation(ny);

      var currentTz = 'America/New_York';
      final coordinator = ReminderCoordinator(
        scheduler: scheduler,
        permissionState: permissionState,
        activeProfiles: profiles.stream,
        predictionFor: (id) => id == 'p1' ? p1.stream : const Stream.empty(),
        localTimeZoneProvider: () async => currentTz,
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

      expect(scheduler.rescheduleCalls.length, 1);

      // Direct replan without timezone change: rescheduleAll is skipped.
      await coordinator.replan();
      expect(scheduler.rescheduleCalls.length, 1);

      // Change timezone and resume: _lastAppliedPlan is cleared and rescheduleAll runs.
      currentTz = 'Europe/London';
      coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();

      expect(tz.local.name, 'Europe/London');
      expect(
        scheduler.rescheduleCalls.length,
        2,
        reason:
            'timezone change must re-anchor reminders via rescheduleAll even if calendar dates match',
      );
    });

    test('permission denial resets cached plan so re-granting reschedules',
        () async {
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

      profiles.add([_profile('p1')]);
      p1.add(_late(today));
      await pumpEventQueue();

      expect(scheduler.rescheduleCalls.length, 1);

      // Simulate permission denial on resume.
      scheduler.currentAvailability = NotificationAvailability.denied;
      coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();

      expect(scheduler.cancelCalls, 1);

      // Permission granted again on resume.
      scheduler.currentAvailability = NotificationAvailability.available;
      coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();

      expect(
        scheduler.rescheduleCalls.length,
        2,
        reason:
            'permission grant after denial must reschedule even if the computed plan is identical',
      );
    });
  });
}
