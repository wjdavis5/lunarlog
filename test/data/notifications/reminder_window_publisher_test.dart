/// U6 coverage (KTD4, R13): debounced publish-on-change, episode_open
/// derivation, signed-out gating, and disposal discipline. Mirrors
/// test/data/reminder_coordinator_test.dart's stream-fan-in test shape.
library;

import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/notifications/reminder_window_publisher.dart';
import 'package:lunarlog/domain/birth_control.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/notifications/reminder_window_remote.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

Profile _profile(String id) => Profile(
      id: id,
      displayName: 'Profile $id',
      isMinor: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

ActivePrediction _active(
  LocalDate today, {
  bool duringEpisode = false,
  LocalDate? estimatedNextStart,
  LocalDate? originalEstimatedNextStart,
}) =>
    ActivePrediction(
      today: today,
      lastEpisodeStart: today.addDays(-34),
      estimatedNextStart: estimatedNextStart ?? today.addDays(-6),
      originalEstimatedNextStart:
          originalEstimatedNextStart ?? estimatedNextStart ?? today.addDays(-6),
      averagedCycleLengths: const [28],
      meanCycleLengthDays: 28,
      cycleDay: 35,
      duringEpisode: duringEpisode,
      completedCycleCount: 4,
      validCycleCount: 4,
    );

const _notEnoughHistory = NotEnoughHistory(
  episodeCount: 1,
  completedCycleCount: 0,
  validCycleCount: 0,
  usableCycleCount: 0,
);

class _UpsertCall {
  _UpsertCall(this.profileId, this.estimatedNextStartIso, this.episodeOpen);
  final String profileId;
  final String estimatedNextStartIso;
  final bool episodeOpen;
}

/// Adapts an inline closure to the named [ReminderWindowRemote] contract
/// (U9) so these tests can keep recording calls inline.
class _RecordingRemote implements ReminderWindowRemote {
  _RecordingRemote(this._onUpsert, [this._onRetract]);

  final Future<void> Function(
      String profileId, String estimatedNextStartIso, bool episodeOpen)
      _onUpsert;
  final Future<void> Function(String profileId)? _onRetract;
  final List<String> retracted = [];

  @override
  Future<void> upsert({
    required String profileId,
    required String estimatedNextStartIso,
    required bool episodeOpen,
  }) =>
      _onUpsert(profileId, estimatedNextStartIso, episodeOpen);

  @override
  Future<void> retract({required String profileId}) async {
    retracted.add(profileId);
    final onRetract = _onRetract;
    if (onRetract != null) await onRetract(profileId);
  }
}

_RecordingRemote _remote(
  Future<void> Function(
          String profileId, String estimatedNextStartIso, bool episodeOpen)
      onUpsert, [
  Future<void> Function(String profileId)? onRetract,
]) =>
    _RecordingRemote(onUpsert, onRetract);

void main() {
  test('a prediction change publishes exactly one upsert after the debounce, '
      'not one per intermediate emission', () async {
    final profiles = StreamController<List<Profile>>(sync: true);
    final predictions = <String, StreamController<CyclePrediction>>{};
    final calls = <_UpsertCall>[];
    final today = LocalDate(2026, 8, 30);

    final publisher = ReminderWindowPublisher(
      activeProfiles: profiles.stream,
      predictionFor: (id) => predictions
          .putIfAbsent(id, () => StreamController<CyclePrediction>(sync: true))
          .stream,
      upsert: _remote((profileId, iso, episodeOpen) async {
        calls.add(_UpsertCall(profileId, iso, episodeOpen));
      }),
      isSignedIn: () => true,
      debounce: Duration.zero,
    );
    publisher.start();
    addTearDown(() async {
      await publisher.dispose();
      await profiles.close();
      for (final c in predictions.values) {
        await c.close();
      }
    });

    profiles.add([_profile('p1')]);
    predictions['p1']!.add(_active(today, estimatedNextStart: today.addDays(1)));
    predictions['p1']!.add(_active(today, estimatedNextStart: today.addDays(2)));
    predictions['p1']!.add(_active(today, estimatedNextStart: today.addDays(3)));
    await pumpEventQueue();

    expect(calls, hasLength(1));
    expect(calls.single.estimatedNextStartIso, today.addDays(3).iso);
  });

  test('an ActivePrediction with an open episode publishes episodeOpen: true; '
      'a NotEnoughHistory prediction publishes nothing', () async {
    final profiles = StreamController<List<Profile>>(sync: true);
    final predictions = <String, StreamController<CyclePrediction>>{};
    final calls = <_UpsertCall>[];
    final today = LocalDate(2026, 8, 30);

    final publisher = ReminderWindowPublisher(
      activeProfiles: profiles.stream,
      predictionFor: (id) => predictions
          .putIfAbsent(id, () => StreamController<CyclePrediction>(sync: true))
          .stream,
      upsert: _remote((profileId, iso, episodeOpen) async {
        calls.add(_UpsertCall(profileId, iso, episodeOpen));
      }),
      isSignedIn: () => true,
      debounce: Duration.zero,
    );
    publisher.start();
    addTearDown(() async {
      await publisher.dispose();
      await profiles.close();
      for (final c in predictions.values) {
        await c.close();
      }
    });

    profiles.add([_profile('p1'), _profile('p2')]);
    predictions['p1']!.add(_active(today, duringEpisode: true));
    predictions['p2']!.add(_notEnoughHistory);
    await pumpEventQueue();

    expect(calls, hasLength(1));
    expect(calls.single.profileId, 'p1');
    expect(calls.single.episodeOpen, isTrue);
  });

  test('a signed-out state publishes nothing', () async {
    final profiles = StreamController<List<Profile>>(sync: true);
    final predictions = <String, StreamController<CyclePrediction>>{};
    final calls = <_UpsertCall>[];
    final today = LocalDate(2026, 8, 30);

    final publisher = ReminderWindowPublisher(
      activeProfiles: profiles.stream,
      predictionFor: (id) => predictions
          .putIfAbsent(id, () => StreamController<CyclePrediction>(sync: true))
          .stream,
      upsert: _remote((profileId, iso, episodeOpen) async {
        calls.add(_UpsertCall(profileId, iso, episodeOpen));
      }),
      isSignedIn: () => false,
      debounce: Duration.zero,
    );
    publisher.start();
    addTearDown(() async {
      await publisher.dispose();
      await profiles.close();
      for (final c in predictions.values) {
        await c.close();
      }
    });

    profiles.add([_profile('p1')]);
    predictions['p1']!.add(_active(today));
    await pumpEventQueue();

    expect(calls, isEmpty);
  });

  test('a failure from the RPC is swallowed and does not cancel the subscription', () async {
    final profiles = StreamController<List<Profile>>(sync: true);
    final predictions = <String, StreamController<CyclePrediction>>{};
    var attemptCount = 0;
    final today = LocalDate(2026, 8, 30);

    final publisher = ReminderWindowPublisher(
      activeProfiles: profiles.stream,
      predictionFor: (id) => predictions
          .putIfAbsent(id, () => StreamController<CyclePrediction>(sync: true))
          .stream,
      upsert: _remote((profileId, iso, episodeOpen) async {
        attemptCount++;
        throw Exception('network down');
      }),
      isSignedIn: () => true,
      debounce: Duration.zero,
    );
    publisher.start();
    addTearDown(() async {
      await publisher.dispose();
      await profiles.close();
      for (final c in predictions.values) {
        await c.close();
      }
    });

    profiles.add([_profile('p1')]);
    predictions['p1']!.add(_active(today, estimatedNextStart: today.addDays(1)));
    await pumpEventQueue();
    expect(attemptCount, 1);

    // A second emission after the first failure must still be attempted --
    // the subscription must not have been torn down by the thrown error.
    predictions['p1']!.add(_active(today, estimatedNextStart: today.addDays(2)));
    await pumpEventQueue();
    expect(attemptCount, 2);
  });

  test(
      '#12/#547: a transient (SocketException) failed publish retries the '
      'same prediction after retryDelay, without waiting for a new '
      'prediction change', () async {
    final profiles = StreamController<List<Profile>>(sync: true);
    final predictions = <String, StreamController<CyclePrediction>>{};
    final calls = <_UpsertCall>[];
    var attemptCount = 0;
    final today = LocalDate(2026, 8, 30);

    final publisher = ReminderWindowPublisher(
      activeProfiles: profiles.stream,
      predictionFor: (id) => predictions
          .putIfAbsent(id, () => StreamController<CyclePrediction>(sync: true))
          .stream,
      upsert: _remote((profileId, iso, episodeOpen) async {
        attemptCount++;
        if (attemptCount == 1) throw const SocketException('network down');
        calls.add(_UpsertCall(profileId, iso, episodeOpen));
      }),
      isSignedIn: () => true,
      debounce: Duration.zero,
      retryDelay: Duration.zero,
    );
    publisher.start();
    addTearDown(() async {
      await publisher.dispose();
      await profiles.close();
      for (final c in predictions.values) {
        await c.close();
      }
    });

    profiles.add([_profile('p1')]);
    predictions['p1']!.add(_active(today, estimatedNextStart: today.addDays(1)));

    // No second prediction change and no app restart -- only the bounded
    // retry itself must republish the same (unchanged) prediction.
    await pumpEventQueue();

    expect(attemptCount, 2,
        reason: 'the first attempt failed; the retry made a second attempt '
            'on its own, without a new prediction change');
    expect(calls, hasLength(1));
    expect(calls.single.profileId, 'p1');
    expect(calls.single.estimatedNextStartIso, today.addDays(1).iso);
  });

  test(
      'issue #547: a non-retryable failure never retries — no update reaches '
      'the server until a genuine prediction change re-arms it', () async {
    final profiles = StreamController<List<Profile>>(sync: true);
    final predictions = <String, StreamController<CyclePrediction>>{};
    final calls = <_UpsertCall>[];
    var attemptCount = 0;
    final today = LocalDate(2026, 8, 30);

    final publisher = ReminderWindowPublisher(
      activeProfiles: profiles.stream,
      predictionFor: (id) => predictions
          .putIfAbsent(id, () => StreamController<CyclePrediction>(sync: true))
          .stream,
      // A permanent rejection — never a
      // SocketException/TimeoutException/PostgREST 5xx.
      upsert: _remote((profileId, iso, episodeOpen) async {
        attemptCount++;
        throw StateError('permanently rejected');
      }),
      isSignedIn: () => true,
      debounce: Duration.zero,
      retryDelay: Duration.zero,
    );
    publisher.start();
    addTearDown(() async {
      await publisher.dispose();
      await profiles.close();
      for (final c in predictions.values) {
        await c.close();
      }
    });

    profiles.add([_profile('p1')]);
    predictions['p1']!.add(_active(today, estimatedNextStart: today.addDays(1)));
    await pumpEventQueue();

    expect(attemptCount, 1);
    expect(calls, isEmpty,
        reason: 'a non-retryable failure must not re-arm a retry timer');
  });

  test('#12 (review fix): a genuinely new prediction after a failure supersedes the pending retry rather than racing it', () async {
    final profiles = StreamController<List<Profile>>(sync: true);
    final predictions = <String, StreamController<CyclePrediction>>{};
    final calls = <_UpsertCall>[];
    var attemptCount = 0;
    final today = LocalDate(2026, 8, 30);

    final publisher = ReminderWindowPublisher(
      activeProfiles: profiles.stream,
      predictionFor: (id) => predictions
          .putIfAbsent(id, () => StreamController<CyclePrediction>(sync: true))
          .stream,
      upsert: _remote((profileId, iso, episodeOpen) async {
        attemptCount++;
        if (attemptCount == 1) throw Exception('network down');
        calls.add(_UpsertCall(profileId, iso, episodeOpen));
      }),
      isSignedIn: () => true,
      debounce: Duration.zero,
      retryDelay: const Duration(minutes: 5),
    );
    publisher.start();
    addTearDown(() async {
      await publisher.dispose();
      await profiles.close();
      for (final c in predictions.values) {
        await c.close();
      }
    });

    profiles.add([_profile('p1')]);
    predictions['p1']!.add(_active(today, estimatedNextStart: today.addDays(1)));
    await pumpEventQueue();
    expect(attemptCount, 1, reason: 'the first attempt failed');
    expect(calls, isEmpty);

    // A real prediction change arrives well before the 5-minute retry would
    // have fired; it must supersede the stale retry with the fresh value,
    // not merely add a second, separate publish of the old one.
    predictions['p1']!.add(_active(today, estimatedNextStart: today.addDays(2)));
    await pumpEventQueue();

    expect(attemptCount, 2);
    expect(calls, hasLength(1));
    expect(calls.single.estimatedNextStartIso, today.addDays(2).iso);
  });

  test('dispose cancels every subscription and a late emission after disposal is a no-op', () async {
    final profiles = StreamController<List<Profile>>(sync: true);
    final predictions = <String, StreamController<CyclePrediction>>{};
    final calls = <_UpsertCall>[];
    final today = LocalDate(2026, 8, 30);

    final publisher = ReminderWindowPublisher(
      activeProfiles: profiles.stream,
      predictionFor: (id) => predictions
          .putIfAbsent(id, () => StreamController<CyclePrediction>(sync: true))
          .stream,
      upsert: _remote((profileId, iso, episodeOpen) async {
        calls.add(_UpsertCall(profileId, iso, episodeOpen));
      }),
      isSignedIn: () => true,
      debounce: Duration.zero,
    );
    publisher.start();
    profiles.add([_profile('p1')]);
    await pumpEventQueue();

    await publisher.dispose();

    // A late emission after disposal must be a no-op, not a crash.
    predictions['p1']!.add(_active(today));
    await pumpEventQueue();

    expect(calls, isEmpty);
    await profiles.close();
    for (final c in predictions.values) {
      await c.close();
    }
  });

  test(
      '#221 follow-up (review fix): a late, rolled prediction publishes the '
      'ORIGINAL (un-rolled) estimatedNextStart, not the rolled one -- the '
      'server missed-entry scan gates on estimated_next_start <= current_date '
      'and a future, rolled date would silence it', () async {
    final profiles = StreamController<List<Profile>>(sync: true);
    final predictions = <String, StreamController<CyclePrediction>>{};
    final calls = <_UpsertCall>[];
    final today = LocalDate(2026, 8, 30);

    final publisher = ReminderWindowPublisher(
      activeProfiles: profiles.stream,
      predictionFor: (id) => predictions
          .putIfAbsent(id, () => StreamController<CyclePrediction>(sync: true))
          .stream,
      upsert: _remote((profileId, iso, episodeOpen) async {
        calls.add(_UpsertCall(profileId, iso, episodeOpen));
      }),
      isSignedIn: () => true,
      debounce: Duration.zero,
    );
    publisher.start();
    addTearDown(() async {
      await publisher.dispose();
      await profiles.close();
      for (final c in predictions.values) {
        await c.close();
      }
    });

    profiles.add([_profile('p1')]);
    // A rolled-forward prediction: the original estimate was well in the
    // past (late), but the rolled estimatedNextStart has been stepped
    // forward into the future for display.
    predictions['p1']!.add(_active(
      today,
      estimatedNextStart: today.addDays(5),
      originalEstimatedNextStart: today.addDays(-23),
    ));
    await pumpEventQueue();

    expect(calls, hasLength(1));
    expect(calls.single.estimatedNextStartIso, today.addDays(-23).iso,
        reason: 'must publish the original, un-rolled date so the server '
            'gate (estimated_next_start <= current_date) stays open, not '
            'the rolled, future-dated one');
  });

  group('issue LLA-061: suppression retracts a previously published window',
      () {
    test('Pregnancy/Postpartum/Perimenopause retracts', () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final calls = <_UpsertCall>[];
      final today = LocalDate(2026, 8, 30);
      final remote = _remote((profileId, iso, episodeOpen) async {
        calls.add(_UpsertCall(profileId, iso, episodeOpen));
      });

      final publisher = ReminderWindowPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
            .stream,
        upsert: remote,
        isSignedIn: () => true,
        debounce: Duration.zero,
      );
      publisher.start();
      addTearDown(() async {
        await publisher.dispose();
        await profiles.close();
        for (final c in predictions.values) {
          await c.close();
        }
      });

      profiles.add([_profile('p1')]);
      predictions['p1']!.add(_active(today));
      await pumpEventQueue();
      expect(calls, hasLength(1));

      predictions['p1']!.add(
          const PredictionsSuppressed(lifecycleMode: LifecycleMode.pregnancy));
      await pumpEventQueue();

      expect(remote.retracted, ['p1']);
    });

    test('a continuous birth-control method retracts', () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final today = LocalDate(2026, 8, 30);
      final remote = _remote((profileId, iso, episodeOpen) async {});

      final publisher = ReminderWindowPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
            .stream,
        upsert: remote,
        isSignedIn: () => true,
        debounce: Duration.zero,
      );
      publisher.start();
      addTearDown(() async {
        await publisher.dispose();
        await profiles.close();
        for (final c in predictions.values) {
          await c.close();
        }
      });

      profiles.add([_profile('p1')]);
      predictions['p1']!.add(_active(today));
      await pumpEventQueue();

      predictions['p1']!
          .add(const PredictionsSuppressed(method: BirthControlMethod.hormonalIud));
      await pumpEventQueue();

      expect(remote.retracted, ['p1']);
    });

    test('predictions turned off (PredictionsDisabled) retracts', () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final today = LocalDate(2026, 8, 30);
      final remote = _remote((profileId, iso, episodeOpen) async {});

      final publisher = ReminderWindowPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
            .stream,
        upsert: remote,
        isSignedIn: () => true,
        debounce: Duration.zero,
      );
      publisher.start();
      addTearDown(() async {
        await publisher.dispose();
        await profiles.close();
        for (final c in predictions.values) {
          await c.close();
        }
      });

      profiles.add([_profile('p1')]);
      predictions['p1']!.add(_active(today));
      await pumpEventQueue();

      predictions['p1']!.add(const PredictionsDisabled());
      await pumpEventQueue();

      expect(remote.retracted, ['p1']);
    });

    test('NotEnoughHistory does NOT retract — only a deliberate suppression '
        'does', () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final today = LocalDate(2026, 8, 30);
      final remote = _remote((profileId, iso, episodeOpen) async {});

      final publisher = ReminderWindowPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
            .stream,
        upsert: remote,
        isSignedIn: () => true,
        debounce: Duration.zero,
      );
      publisher.start();
      addTearDown(() async {
        await publisher.dispose();
        await profiles.close();
        for (final c in predictions.values) {
          await c.close();
        }
      });

      profiles.add([_profile('p1')]);
      predictions['p1']!.add(_active(today));
      await pumpEventQueue();

      predictions['p1']!.add(_notEnoughHistory);
      await pumpEventQueue();

      expect(remote.retracted, isEmpty);
    });
  });

  group('issue LLA-062: a stale, in-flight completion never reinstates '
      'state a newer emission already superseded', () {
    test('a late failed upsert does not reinstate pending state after a '
        'newer suppression already retracted it', () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final calls = <_UpsertCall>[];
      final today = LocalDate(2026, 8, 30);
      final hold = Completer<void>();
      var holdArmed = true;

      final remote = _remote((profileId, iso, episodeOpen) async {
        if (holdArmed) {
          holdArmed = false;
          await hold.future;
        }
        calls.add(_UpsertCall(profileId, iso, episodeOpen));
      });

      final publisher = ReminderWindowPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
            .stream,
        upsert: remote,
        isSignedIn: () => true,
        debounce: Duration.zero,
        retryDelay: const Duration(minutes: 5),
      );
      publisher.start();
      addTearDown(() async {
        await publisher.dispose();
        await profiles.close();
        for (final c in predictions.values) {
          await c.close();
        }
      });

      profiles.add([_profile('p1')]);
      predictions['p1']!.add(_active(today)); // A: upsert held in flight.
      await pumpEventQueue();

      predictions['p1']!.add(
          const PredictionsSuppressed(lifecycleMode: LifecycleMode.pregnancy));
      await pumpEventQueue();
      expect(remote.retracted, ['p1']);

      hold.completeError(const SocketException('network down'));
      await pumpEventQueue();

      expect(calls, isEmpty,
          reason: 'A never actually succeeded and must not be reinstated');
      expect(remote.retracted, ['p1'],
          reason: 'the stale failure must not trigger a second retraction');
    });
  });

  group('issue LLA-105: unchanged windows skip the upsert RPC', () {
    test('an unrelated recompute that lands on an unchanged window skips '
        'the upsert entirely', () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final calls = <_UpsertCall>[];
      final today = LocalDate(2026, 8, 30);
      final remote = _remote((profileId, iso, episodeOpen) async {
        calls.add(_UpsertCall(profileId, iso, episodeOpen));
      });

      final publisher = ReminderWindowPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
            .stream,
        upsert: remote,
        isSignedIn: () => true,
        debounce: Duration.zero,
      );
      publisher.start();
      addTearDown(() async {
        await publisher.dispose();
        await profiles.close();
        for (final c in predictions.values) {
          await c.close();
        }
      });

      profiles.add([_profile('p1')]);
      predictions['p1']!.add(_active(today));
      await pumpEventQueue();
      expect(calls, hasLength(1));

      // A second, distinct prediction instance carrying the exact same
      // estimatedNextStart/episodeOpen — the shape a re-emission from an
      // unrelated settings edit takes.
      predictions['p1']!.add(_active(today));
      await pumpEventQueue();

      expect(calls, hasLength(1),
          reason: 'no redundant upsert for the unchanged window');
    });
  });

  group('_flushRetraction coverage: retry, give-up, staleness, dispose, '
      'and signed-out', () {
    test(
        '#547: a transient (SocketException) failed retract retries and '
        'then succeeds, without waiting for another prediction change',
        () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final today = LocalDate(2026, 8, 30);
      var attemptCount = 0;
      final remote = _remote((profileId, iso, episodeOpen) async {},
          (profileId) async {
        attemptCount++;
        if (attemptCount == 1) throw const SocketException('network down');
      });

      final publisher = ReminderWindowPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
            .stream,
        upsert: remote,
        isSignedIn: () => true,
        debounce: Duration.zero,
        retryDelay: Duration.zero,
      );
      publisher.start();
      addTearDown(() async {
        await publisher.dispose();
        await profiles.close();
        for (final c in predictions.values) {
          await c.close();
        }
      });

      profiles.add([_profile('p1')]);
      predictions['p1']!.add(_active(today));
      await pumpEventQueue();

      predictions['p1']!.add(const PredictionsDisabled());
      await pumpEventQueue();

      expect(attemptCount, 2,
          reason: 'the first attempt failed; the bounded retry made a '
              'second attempt on its own, without a new prediction change');
    });

    test(
        '#547: a non-retryable failure never retries — retraction is '
        'abandoned until a genuine prediction change re-arms it', () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final today = LocalDate(2026, 8, 30);
      var attemptCount = 0;
      // A permanent rejection -- never a
      // SocketException/TimeoutException/PostgREST 5xx.
      final remote = _remote((profileId, iso, episodeOpen) async {},
          (profileId) async {
        attemptCount++;
        throw StateError('permanently rejected');
      });

      final publisher = ReminderWindowPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
            .stream,
        upsert: remote,
        isSignedIn: () => true,
        debounce: Duration.zero,
        retryDelay: Duration.zero,
      );
      publisher.start();
      addTearDown(() async {
        await publisher.dispose();
        await profiles.close();
        for (final c in predictions.values) {
          await c.close();
        }
      });

      profiles.add([_profile('p1')]);
      predictions['p1']!.add(_active(today));
      await pumpEventQueue();

      predictions['p1']!.add(const PredictionsDisabled());
      await pumpEventQueue();

      expect(attemptCount, 1,
          reason: 'a non-retryable failure must not re-arm a retry timer');
    });

    test(
        'a late failed retract does not reinstate a retry once a newer '
        'prediction already superseded the suppression (stale generation)',
        () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final calls = <_UpsertCall>[];
      final today = LocalDate(2026, 8, 30);
      final hold = Completer<void>();
      var holdArmed = true;
      final remote = _remote(
        (profileId, iso, episodeOpen) async {
          calls.add(_UpsertCall(profileId, iso, episodeOpen));
        },
        (profileId) async {
          if (holdArmed) {
            holdArmed = false;
            await hold.future;
          }
        },
      );

      final publisher = ReminderWindowPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
            .stream,
        upsert: remote,
        isSignedIn: () => true,
        debounce: Duration.zero,
        retryDelay: const Duration(minutes: 5),
      );
      publisher.start();
      addTearDown(() async {
        await publisher.dispose();
        await profiles.close();
        for (final c in predictions.values) {
          await c.close();
        }
      });

      profiles.add([_profile('p1')]);
      predictions['p1']!.add(_active(today));
      await pumpEventQueue();

      // Triggers the retraction; the remote call is held in flight.
      predictions['p1']!.add(const PredictionsDisabled());
      await pumpEventQueue();
      expect(remote.retracted, ['p1']);

      // A newer, genuinely active prediction supersedes the suppression
      // before the held retract resolves. (The first `_active` emission
      // above already published once, before the suppression.)
      predictions['p1']!.add(_active(today.addDays(1)));
      await pumpEventQueue();
      expect(calls, hasLength(2),
          reason: 'the newer active prediction published normally');

      // The stale held retract now fails.
      hold.completeError(const SocketException('network down'));
      await pumpEventQueue();

      expect(calls, hasLength(2),
          reason: 'no corruption from the stale retract failure');
      expect(remote.retracted, ['p1'],
          reason: 'the stale failure must not trigger a retry attempt');
    });

    test('dispose during a failed retract is a no-op — no retry timer, no '
        'crash', () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final today = LocalDate(2026, 8, 30);
      final hold = Completer<void>();
      final remote = _remote(
        (profileId, iso, episodeOpen) async {},
        (profileId) => hold.future,
      );

      final publisher = ReminderWindowPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
            .stream,
        upsert: remote,
        isSignedIn: () => true,
        debounce: Duration.zero,
        retryDelay: const Duration(minutes: 5),
      );
      publisher.start();

      profiles.add([_profile('p1')]);
      predictions['p1']!.add(_active(today));
      await pumpEventQueue();
      predictions['p1']!.add(const PredictionsDisabled());
      await pumpEventQueue();
      expect(remote.retracted, ['p1']);

      await publisher.dispose();
      hold.completeError(const SocketException('network down'));
      await pumpEventQueue();

      // Reaching here without the held future's error escaping is itself
      // part of the assertion; also confirm no further attempt was made.
      expect(remote.retracted, ['p1']);
      await profiles.close();
      for (final c in predictions.values) {
        await c.close();
      }
    });

    test('a signed-out state never calls retract', () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      var signedIn = true;
      final today = LocalDate(2026, 8, 30);
      final remote = _remote((profileId, iso, episodeOpen) async {});

      final publisher = ReminderWindowPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
            .stream,
        upsert: remote,
        isSignedIn: () => signedIn,
        debounce: Duration.zero,
      );
      publisher.start();
      addTearDown(() async {
        await publisher.dispose();
        await profiles.close();
        for (final c in predictions.values) {
          await c.close();
        }
      });

      profiles.add([_profile('p1')]);
      predictions['p1']!.add(_active(today));
      await pumpEventQueue();

      signedIn = false;
      predictions['p1']!.add(const PredictionsDisabled());
      await pumpEventQueue();

      expect(remote.retracted, isEmpty);
    });
  });
}
