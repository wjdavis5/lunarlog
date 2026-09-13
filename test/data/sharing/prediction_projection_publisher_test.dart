/// Issue #151 coverage for the projection publisher: debounced
/// publish-on-change, the active-connection gate (only profiles shared OUT
/// are uploaded), signed-out gating, [publishNow], and the bounded retry
/// on failure. Mirrors reminder_window_publisher_test.dart's shape.
library;

import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/sharing/prediction_projection_publisher.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/sharing/prediction_connection_service.dart';
import 'package:lunarlog/domain/sharing/prediction_projection.dart';

Profile _profile(String id) => Profile(
      id: id,
      displayName: 'Profile $id',
      isMinor: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

ActivePrediction _active(LocalDate today) {
  final nextStart = today.addDays(10);
  return ActivePrediction(
    today: today,
    lastEpisodeStart: today.addDays(-34),
    estimatedNextStart: nextStart,
    originalEstimatedNextStart: nextStart,
    averagedCycleLengths: const [28],
    meanCycleLengthDays: 28,
    cycleDay: 35,
    duringEpisode: false,
    completedCycleCount: 4,
    validCycleCount: 4,
    meanPeriodLengthDays: 4,
    spreadDays: 2,
    tier: CycleConfidence.high,
    forecast: [
      PredictedCycle(
        cycleIndex: 1,
        start: nextStart,
        estimatedPeriodLengthDays: 4,
        tier: CycleConfidence.high,
        spreadDays: 2,
      ),
    ],
  );
}

const _notEnoughHistory = NotEnoughHistory(
  episodeCount: 1,
  completedCycleCount: 0,
  validCycleCount: 0,
);

class _FakeService implements PredictionConnectionService {
  _FakeService({required this.connectedProfileIds});

  Set<String> connectedProfileIds;
  final List<String> publishedFor = [];
  final List<PredictionProjection> published = [];
  Object? publishError;

  /// How many calls [publishError] should still fail before succeeding:
  /// -1 (default) means "fail every call for as long as [publishError] is
  /// set" (the original, still-used-by-most-tests shape); a non-negative
  /// value counts down so a test can exercise exactly N failed attempts
  /// followed by success — needed for issue #547's capped retry, where a
  /// zero-delay backoff resolves every retry within one `pumpEventQueue`
  /// call, well before a test could otherwise intervene to clear the error.
  int remainingFailures = -1;

  @override
  Future<Set<String>> outgoingConnectedProfileIds() async =>
      connectedProfileIds;

  @override
  Future<void> publishProjection({
    required String profileId,
    required PredictionProjection projection,
  }) async {
    if (publishError != null && remainingFailures != 0) {
      if (remainingFailures > 0) remainingFailures--;
      throw publishError!;
    }
    publishedFor.add(profileId);
    published.add(projection);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  test('a prediction change publishes the projection after the debounce for '
      'a connected profile', () async {
    final profiles = StreamController<List<Profile>>(sync: true);
    final predictions = <String, StreamController<CyclePrediction>>{};
    final service = _FakeService(connectedProfileIds: {'p1'});
    final today = LocalDate(2026, 8, 30);

    final publisher = LocalPredictionProjectionPublisher(
      activeProfiles: profiles.stream,
      predictionFor: (id) => predictions
          .putIfAbsent(id, () => StreamController<CyclePrediction>(sync: true))
          .stream,
      service: service,
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

    expect(service.publishedFor, ['p1']);
    expect(service.published.single.generatedAt, today);
    expect(service.published.single.periodDays, isNotEmpty);
  });

  test('a profile without an active outgoing connection is never published',
      () async {
    final profiles = StreamController<List<Profile>>(sync: true);
    final predictions = <String, StreamController<CyclePrediction>>{};
    final service = _FakeService(connectedProfileIds: {});

    final publisher = LocalPredictionProjectionPublisher(
      activeProfiles: profiles.stream,
      predictionFor: (id) => predictions
          .putIfAbsent(id, () => StreamController<CyclePrediction>(sync: true))
          .stream,
      service: service,
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
    predictions['p1']!.add(_active(LocalDate(2026, 8, 30)));
    await pumpEventQueue();

    expect(service.publishedFor, isEmpty);
  });

  test('signed-out and NotEnoughHistory states publish nothing', () async {
    final profiles = StreamController<List<Profile>>(sync: true);
    final predictions = <String, StreamController<CyclePrediction>>{};
    var signedIn = false;
    final service = _FakeService(connectedProfileIds: {'p1'});

    final publisher = LocalPredictionProjectionPublisher(
      activeProfiles: profiles.stream,
      predictionFor: (id) => predictions
          .putIfAbsent(id, () => StreamController<CyclePrediction>(sync: true))
          .stream,
      service: service,
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
    predictions['p1']!.add(_active(LocalDate(2026, 8, 30)));
    await pumpEventQueue();
    expect(service.publishedFor, isEmpty, reason: 'signed out');

    signedIn = true;
    predictions['p1']!.add(_notEnoughHistory);
    await pumpEventQueue();
    expect(service.publishedFor, isEmpty, reason: 'nothing derived to share');
  });

  test('publishNow publishes immediately for a connected profile', () async {
    final service = _FakeService(connectedProfileIds: {'p1'});
    final today = LocalDate(2026, 8, 30);

    final publisher = LocalPredictionProjectionPublisher(
      activeProfiles: const Stream.empty(),
      predictionFor: (id) => Stream<CyclePrediction>.value(_active(today)),
      service: service,
      isSignedIn: () => true,
    );
    addTearDown(() => publisher.dispose());

    await publisher.publishNow('p1');
    expect(service.publishedFor, ['p1']);
    expect(service.published.single.generatedAt, today);
    expect(service.published.single.periodDays, isNotEmpty);
  });

  test(
      'a transient (SocketException) failed publish retries on the retry '
      'delay, not only on the next change (issue #547)', () async {
    final profiles = StreamController<List<Profile>>(sync: true);
    final predictions = <String, StreamController<CyclePrediction>>{};
    final service = _FakeService(connectedProfileIds: {'p1'});
    final today = LocalDate(2026, 8, 30);

    final publisher = LocalPredictionProjectionPublisher(
      activeProfiles: profiles.stream,
      predictionFor: (id) => predictions
          .putIfAbsent(id, () => StreamController<CyclePrediction>(sync: true))
          .stream,
      service: service,
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

    // Fails exactly once, then succeeds — with a zero-delay backoff every
    // retry resolves within one pumpEventQueue call, so this is the
    // observable outcome rather than an intermediate "still empty" state.
    service.publishError = const SocketException('network down');
    service.remainingFailures = 1;
    profiles.add([_profile('p1')]);
    predictions['p1']!.add(_active(today));
    await pumpEventQueue();

    expect(service.publishedFor, ['p1'], reason: 'the bounded retry fired');
  });

  test(
      'a non-retryable failure (issue #547) never retries — the recipient '
      'never gets an update until a genuine prediction change re-arms it',
      () async {
    final profiles = StreamController<List<Profile>>(sync: true);
    final predictions = <String, StreamController<CyclePrediction>>{};
    final service = _FakeService(connectedProfileIds: {'p1'});
    final today = LocalDate(2026, 8, 30);

    final publisher = LocalPredictionProjectionPublisher(
      activeProfiles: profiles.stream,
      predictionFor: (id) => predictions
          .putIfAbsent(id, () => StreamController<CyclePrediction>(sync: true))
          .stream,
      service: service,
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

    // A permanent rejection (e.g. revoked access surfacing as a 4xx, or a
    // client bug) — never a SocketException/TimeoutException/PostgREST 5xx.
    service.publishError = StateError('permanently rejected');
    profiles.add([_profile('p1')]);
    predictions['p1']!.add(_active(today));
    await pumpEventQueue();
    expect(service.publishedFor, isEmpty);

    service.publishError = null;
    await pumpEventQueue();
    expect(service.publishedFor, isEmpty,
        reason: 'a non-retryable failure must not re-arm a retry timer');
  });

  group('republishConnected (issue #373, the resume hook)', () {
    test('publishes the current prediction for every connected profile '
        'and skips one with nothing derived', () async {
      final service = _FakeService(connectedProfileIds: {'p1', 'p2', 'p3'});
      final today = LocalDate(2026, 8, 30);

      final publisher = LocalPredictionProjectionPublisher(
        activeProfiles: const Stream.empty(),
        predictionFor: (id) => Stream<CyclePrediction>.value(
            id == 'p2' ? _notEnoughHistory : _active(today)),
        service: service,
        isSignedIn: () => true,
      );
      addTearDown(() => publisher.dispose());

      await publisher.republishConnected();
      expect(service.publishedFor, unorderedEquals(['p1', 'p3']));
      for (final projection in service.published) {
        expect(projection.generatedAt, today);
      }
    });

    test('is a no-op while signed out, after dispose, and on a failing '
        'service', () async {
      final service = _FakeService(connectedProfileIds: {'p1'});
      var signedIn = false;
      final publisher = LocalPredictionProjectionPublisher(
        activeProfiles: const Stream.empty(),
        predictionFor: (id) =>
            Stream<CyclePrediction>.value(_active(LocalDate(2026, 8, 30))),
        service: service,
        isSignedIn: () => signedIn,
      );

      await publisher.republishConnected();
      expect(service.publishedFor, isEmpty, reason: 'signed out');

      signedIn = true;
      service.publishError = Exception('network down');
      await publisher.republishConnected();
      expect(service.publishedFor, isEmpty, reason: 'best-effort, swallowed');

      service.publishError = null;
      await publisher.dispose();
      await publisher.republishConnected();
      expect(service.publishedFor, isEmpty, reason: 'disposed');
    });
  });
}
