/// U6 coverage (KTD4, R13): debounced publish-on-change, episode_open
/// derivation, signed-out gating, and disposal discipline. Mirrors
/// test/data/reminder_coordinator_test.dart's stream-fan-in test shape.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/notifications/reminder_window_publisher.dart';
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
  _RecordingRemote(this._onUpsert);

  final Future<void> Function(
      String profileId, String estimatedNextStartIso, bool episodeOpen)
      _onUpsert;

  @override
  Future<void> upsert({
    required String profileId,
    required String estimatedNextStartIso,
    required bool episodeOpen,
  }) =>
      _onUpsert(profileId, estimatedNextStartIso, episodeOpen);
}

ReminderWindowRemote _remote(
  Future<void> Function(
          String profileId, String estimatedNextStartIso, bool episodeOpen)
      onUpsert,
) =>
    _RecordingRemote(onUpsert);

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

  test('#12 (review fix): a failed publish retries the same prediction after retryDelay, without waiting for a new prediction change', () async {
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
}
