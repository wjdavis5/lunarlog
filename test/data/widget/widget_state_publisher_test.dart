/// Unit tests for the widget payload publisher (issue #141): it derives
/// the discreet render state from the app's own streams (prediction
/// changes, guardian-role changes, profile selection) and writes exactly
/// the documented boundary payload — no timer anywhere, nothing but the
/// documented keys (or fewer) crossing.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/widget/widget_state_publisher.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/widget/widget_cycle_state.dart';
import 'package:lunarlog/domain/widget/widget_data_store.dart';

import '../../support/fake_settings_store.dart';

class _InMemoryProfiles implements ProfilesRepository {
  final List<Profile> _live;

  _InMemoryProfiles(this._live);

  @override
  Stream<List<Profile>> watch() => Stream.value(_live);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InMemoryGuardians implements ProfileGuardiansRepository {
  final Map<String, List<ProfileGuardian>> _byProfile;

  _InMemoryGuardians(this._byProfile);

  @override
  Stream<List<ProfileGuardian>> watchForProfile(String profileId) =>
      Stream.value(_byProfile[profileId] ?? const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Capturing store: records every payload written and refresh requested.
class _CapturingStore implements WidgetDataStore {
  final List<Map<String, String>> payloads = [];
  int refreshes = 0;

  @override
  Future<void> savePayload(Map<String, String> payload) async {
    payloads.add(Map.of(payload));
  }

  @override
  Future<void> refresh() async {
    refreshes++;
  }

  @override
  Future<Uri?> initialLaunch() async => null;

  @override
  Stream<Uri> get launches => const Stream<Uri>.empty();
}

Profile _profile(String id) => Profile(
      id: id,
      displayName: 'Profile $id',
      isMinor: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

ProfileGuardian _guardian(String userId, GuardianRole role) => ProfileGuardian(
      id: 'g-$userId',
      profileId: 'p1',
      userId: userId,
      role: role,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

final LocalDate _today = LocalDate(2026, 9, 20);

ActivePrediction _active({int cycleDay = 14, int untilNext = 7}) {
  final lastStart = _today.addDays(-(cycleDay - 1));
  return ActivePrediction(
    today: _today,
    lastEpisodeStart: lastStart,
    estimatedNextStart: _today.addDays(untilNext),
    originalEstimatedNextStart: _today.addDays(untilNext),
    averagedCycleLengths: const [28, 28, 28],
    meanCycleLengthDays: 28,
    cycleDay: cycleDay,
    duringEpisode: false,
    completedCycleCount: 3,
    validCycleCount: 3,
  );
}

/// One publisher under test with its fakes, and the plumbing to let the
/// stream pipelines drain deterministically.
class _Harness {
  final store = _CapturingStore();
  final settings = FakeSettingsStore();
  final controllers = <String, StreamController<CyclePrediction>>{};
  Map<String, List<ProfileGuardian>> guardiansByProfile = {};
  List<Profile> profiles = [];
  WidgetStatePublisher? _publisher;

  /// Per-profile prediction streams: the publisher re-subscribes when the
  /// selection changes, exactly as it does against the real
  /// CyclePredictionService.
  Stream<CyclePrediction> predictionFor(String profileId) =>
      controllers
          .putIfAbsent(profileId, () => StreamController<CyclePrediction>())
          .stream;

  void emit(String profileId, CyclePrediction prediction) {
    controllers.putIfAbsent(
        profileId, () => StreamController<CyclePrediction>());
    controllers[profileId]!.add(prediction);
  }

  Future<void> start() async {
    _publisher = WidgetStatePublisher(
      profiles: _InMemoryProfiles(profiles),
      settings: settings,
      predictionFor: predictionFor,
      guardians: _InMemoryGuardians(guardiansByProfile),
      store: store,
      currentUserId: () => 'me',
      today: () => _today,
    )..start();
    await settle();
  }

  /// Lets the watch → resolve → subscribe → publish chain drain.
  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> dispose() async {
    await _publisher?.dispose();
    for (final controller in controllers.values) {
      await controller.close();
    }
    await settings.close();
  }
}

void main() {
  late _Harness h;

  setUp(() {
    h = _Harness();
  });

  tearDown(() => h.dispose());

  test('a prediction emission publishes the live-cycle payload', () async {
    h.profiles = [_profile('p1')];
    h.settings.setSilently('last_active_profile', 'p1');
    await h.start();
    h.emit('p1', _active(cycleDay: 14, untilNext: 7));
    await h.settle();

    expect(h.store.payloads, isNotEmpty);
    final payload = h.store.payloads.last;
    expect(payload[WidgetCycleStatePayload.keyState], 'day');
    expect(payload[WidgetCycleStatePayload.keyCycleDay], '14');
    expect(payload[WidgetCycleStatePayload.keyDaysUntilNext], '7');
    expect(payload[WidgetCycleStatePayload.keyCanQuickLog], '1');
    expect(h.store.refreshes, greaterThanOrEqualTo(1),
        reason: 'every payload write re-renders the widget');
  });

  test('a known viewer gets no quick-log flag in the payload', () async {
    h.profiles = [_profile('p1')];
    h.settings.setSilently('last_active_profile', 'p1');
    h.guardiansByProfile = {
      'p1': [_guardian('me', GuardianRole.viewer)],
    };
    await h.start();
    h.emit('p1', _active());
    await h.settle();

    expect(h.store.payloads.last[WidgetCycleStatePayload.keyCanQuickLog],
        '0');
  });

  test('an unknown role keeps the quick-log flag (fails open)', () async {
    h.profiles = [_profile('p1')];
    h.settings.setSilently('last_active_profile', 'p1');
    await h.start();
    h.emit('p1', _active());
    await h.settle();

    expect(h.store.payloads.last[WidgetCycleStatePayload.keyCanQuickLog],
        '1');
  });

  test('suppressed predictions publish the dash state (no counts)',
      () async {
    h.profiles = [_profile('p1')];
    h.settings.setSilently('last_active_profile', 'p1');
    await h.start();
    h.emit(
        'p1',
        const PredictionsSuppressed(
          lifecycleMode: LifecycleMode.pregnancy,
        ));
    await h.settle();

    final payload = h.store.payloads.last;
    expect(payload[WidgetCycleStatePayload.keyState], 'suppressed');
    expect(payload.containsKey(WidgetCycleStatePayload.keyCycleDay), isFalse);
    expect(payload.containsKey(WidgetCycleStatePayload.keyDaysUntilNext),
        isFalse);
  });

  test('pinning another profile re-points the payload at that profile',
      () async {
    h.profiles = [_profile('p1'), _profile('p2')];
    h.settings.setSilently('last_active_profile', 'p1');
    h.guardiansByProfile = {
      'p1': [],
      'p2': [_guardian('me', GuardianRole.caregiver)],
    };
    await h.start();
    h.emit('p1', _active(cycleDay: 14, untilNext: 7));
    await h.settle();

    await h.settings.set('widget_profile_id', 'p2');
    await h.settle();
    h.emit('p2', _active(cycleDay: 3, untilNext: 25));
    await h.settle();

    final payload = h.store.payloads.last;
    expect(payload[WidgetCycleStatePayload.keyProfileId], 'p2');
    expect(payload[WidgetCycleStatePayload.keyCycleDay], '3');
    expect(payload[WidgetCycleStatePayload.keyDaysUntilNext], '25');
  });

  test('no profiles at all: neutral dash, quick-log intent cleared',
      () async {
    await h.start();

    final payload = h.store.payloads.last;
    expect(payload, isNotEmpty,
        reason: 'the degraded payload is written so a stale widget clears');
    expect(payload[WidgetCycleStatePayload.keyState], 'no_data');
    expect(payload[WidgetCycleStatePayload.keyProfileId], isEmpty);
    expect(payload[WidgetCycleStatePayload.keyCanQuickLog], '0');
  });
}
