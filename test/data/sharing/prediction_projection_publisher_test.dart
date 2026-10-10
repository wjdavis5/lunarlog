/// Issue #151 coverage for the projection publisher: debounced
/// publish-on-change, the active-connection gate (only profiles shared OUT
/// are uploaded), signed-out gating, [publishNow], and the bounded retry
/// on failure. Mirrors reminder_window_publisher_test.dart's shape.
library;

import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/sharing/prediction_projection_publisher.dart';
import 'package:lunarlog/domain/birth_control.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
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
  usableCycleCount: 0,
);

class _FakeService implements PredictionConnectionService {
  _FakeService({required this.connectedProfileIds});

  Set<String> connectedProfileIds;
  final List<String> publishedFor = [];
  final List<PredictionProjection> published = [];
  Object? publishError;

  /// Issue LLA-061 coverage.
  final List<String> retractedFor = [];
  Object? retractError;

  /// Mirrors [remainingFailures] but for [retractProjection].
  int remainingRetractFailures = -1;

  /// Issue LLA-105 coverage: counts every [outgoingConnectedProfileIds]
  /// call so a test can assert concurrent flushes coalesced into one.
  int connectedLookups = 0;

  /// How many calls [publishError] should still fail before succeeding:
  /// -1 (default) means "fail every call for as long as [publishError] is
  /// set" (the original, still-used-by-most-tests shape); a non-negative
  /// value counts down so a test can exercise exactly N failed attempts
  /// followed by success — needed for issue #547's capped retry, where a
  /// zero-delay backoff resolves every retry within one `pumpEventQueue`
  /// call, well before a test could otherwise intervene to clear the error.
  int remainingFailures = -1;

  @override
  Future<Set<String>> outgoingConnectedProfileIds() async {
    connectedLookups++;
    // Issue #1777 coverage: lets a test hold this lookup "in flight" while
    // the profile is archived, then resolve it to prove the in-flight flush
    // still refuses to publish for a profile that left the active set.
    final hold = holdNextConnectedLookup;
    if (hold != null) {
      holdNextConnectedLookup = null;
      await hold.future;
    }
    return connectedProfileIds;
  }

  /// Issue #1777 coverage: see [outgoingConnectedProfileIds]'s comment.
  Completer<void>? holdNextConnectedLookup;

  @override
  Future<void> publishProjection({
    required String profileId,
    required PredictionProjection projection,
  }) async {
    // Issue LLA-062 coverage: lets a test hold this call "in flight" while
    // a newer emission runs on top of it, then resolve it (success or
    // failure) afterward.
    final hold = holdNextPublish;
    if (hold != null) {
      holdNextPublish = null;
      await hold.future;
    }
    if (publishError != null && remainingFailures != 0) {
      if (remainingFailures > 0) remainingFailures--;
      throw publishError!;
    }
    publishedFor.add(profileId);
    published.add(projection);
  }

  /// Issue LLA-062 coverage: see [publishProjection]'s own comment.
  Completer<void>? holdNextPublish;

  @override
  Future<void> retractProjection({required String profileId}) async {
    // Mirrors [holdNextPublish]'s own comment.
    final hold = holdNextRetract;
    if (hold != null) {
      holdNextRetract = null;
      await hold.future;
    }
    if (retractError != null && remainingRetractFailures != 0) {
      if (remainingRetractFailures > 0) remainingRetractFailures--;
      throw retractError!;
    }
    retractedFor.add(profileId);
  }

  /// See [holdNextPublish]'s own comment.
  Completer<void>? holdNextRetract;

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
    final profiles = StreamController<List<Profile>>(sync: true);
    final service = _FakeService(connectedProfileIds: {'p1'});
    final today = LocalDate(2026, 8, 30);

    final publisher = LocalPredictionProjectionPublisher(
      activeProfiles: profiles.stream,
      predictionFor: (id) => Stream<CyclePrediction>.value(_active(today)),
      service: service,
      isSignedIn: () => true,
      // Issue #1777: `_publishCurrent` refuses a profile outside the last
      // active set, so the profile must be active here (its production
      // state right after a connection is created); the long debounce
      // keeps the stream-driven flush out of this test's assertions.
      debounce: const Duration(minutes: 5),
    );
    publisher.start();
    addTearDown(() async {
      await publisher.dispose();
      await profiles.close();
    });

    profiles.add([_profile('p1')]);
    await pumpEventQueue();

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
      final profiles = StreamController<List<Profile>>(sync: true);
      final service = _FakeService(connectedProfileIds: {'p1', 'p2', 'p3'});
      final today = LocalDate(2026, 8, 30);

      final publisher = LocalPredictionProjectionPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => Stream<CyclePrediction>.value(
            id == 'p2' ? _notEnoughHistory : _active(today)),
        service: service,
        isSignedIn: () => true,
        // Issue #1777: every connected profile must be in the active set to
        // reach the publish path; the long debounce keeps the
        // stream-driven flush out of this test's assertions.
        debounce: const Duration(minutes: 5),
      );
      publisher.start();
      addTearDown(() async {
        await publisher.dispose();
        await profiles.close();
      });

      profiles.add([_profile('p1'), _profile('p2'), _profile('p3')]);
      await pumpEventQueue();

      await publisher.republishConnected();
      expect(service.publishedFor, unorderedEquals(['p1', 'p3']));
      for (final projection in service.published) {
        expect(projection.generatedAt, today);
      }
    });

    test('is a no-op while signed out, after dispose, and on a failing '
        'service', () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final service = _FakeService(connectedProfileIds: {'p1'});
      var signedIn = false;
      final publisher = LocalPredictionProjectionPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) =>
            Stream<CyclePrediction>.value(_active(LocalDate(2026, 8, 30))),
        service: service,
        isSignedIn: () => signedIn,
        // Issue #1777: p1 must be active for the failing-service phase to
        // actually reach the publish call it means to swallow.
        debounce: const Duration(minutes: 5),
      );
      publisher.start();
      addTearDown(() async {
        await publisher.dispose();
        await profiles.close();
      });

      profiles.add([_profile('p1')]);
      await pumpEventQueue();

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

  group('issue LLA-061: suppression retracts a previously published '
      'snapshot', () {
    test('Pregnancy/Postpartum/Perimenopause retracts', () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final service = _FakeService(connectedProfileIds: {'p1'});
      final today = LocalDate(2026, 8, 30);

      final publisher = LocalPredictionProjectionPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
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

      predictions['p1']!
          .add(const PredictionsSuppressed(lifecycleMode: LifecycleMode.pregnancy));
      await pumpEventQueue();

      expect(service.retractedFor, ['p1']);
    });

    test('a continuous birth-control method retracts', () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final service = _FakeService(connectedProfileIds: {'p1'});
      final today = LocalDate(2026, 8, 30);

      final publisher = LocalPredictionProjectionPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
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

      predictions['p1']!
          .add(const PredictionsSuppressed(method: BirthControlMethod.hormonalIud));
      await pumpEventQueue();

      expect(service.retractedFor, ['p1']);
    });

    test('predictions turned off (PredictionsDisabled) retracts', () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final service = _FakeService(connectedProfileIds: {'p1'});
      final today = LocalDate(2026, 8, 30);

      final publisher = LocalPredictionProjectionPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
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

      predictions['p1']!.add(const PredictionsDisabled());
      await pumpEventQueue();

      expect(service.retractedFor, ['p1']);
    });

    test('NotEnoughHistory does NOT retract — only a deliberate suppression '
        'does', () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final service = _FakeService(connectedProfileIds: {'p1'});
      final today = LocalDate(2026, 8, 30);

      final publisher = LocalPredictionProjectionPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
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

      predictions['p1']!.add(_notEnoughHistory);
      await pumpEventQueue();

      expect(service.retractedFor, isEmpty,
          reason: 'dipping below the history threshold is not the '
              'deliberate-suppression case this issue addresses');
    });

    test('a retraction retry succeeds after a transient failure, without '
        'waiting for another prediction change', () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final service = _FakeService(connectedProfileIds: {'p1'});
      final today = LocalDate(2026, 8, 30);

      final publisher = LocalPredictionProjectionPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
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

      profiles.add([_profile('p1')]);
      predictions['p1']!.add(_active(today));
      await pumpEventQueue();

      // Fails exactly once, then succeeds — mirroring the publish-retry
      // test's own shape (with a zero-delay backoff every retry resolves
      // within one pumpEventQueue call).
      service.retractError = const SocketException('network down');
      service.remainingRetractFailures = 1;
      predictions['p1']!.add(const PredictionsDisabled());
      await pumpEventQueue();

      expect(service.retractedFor, ['p1'], reason: 'the bounded retry fired');
    });
  });

  group('issue LLA-062: a stale, in-flight completion never reinstates '
      'state a newer emission already superseded', () {
    test('a late failed publish does not reinstate pending state after a '
        'newer suppression already retracted it', () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final service = _FakeService(connectedProfileIds: {'p1'});
      final today = LocalDate(2026, 8, 30);

      final publisher = LocalPredictionProjectionPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
            .stream,
        service: service,
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

      final hold = Completer<void>();
      service.holdNextPublish = hold;

      profiles.add([_profile('p1')]);
      predictions['p1']!.add(_active(today)); // A: publish held in flight.
      await pumpEventQueue();

      // B: a suppression supersedes A before A's held publish resolves.
      predictions['p1']!.add(
          const PredictionsSuppressed(lifecycleMode: LifecycleMode.pregnancy));
      await pumpEventQueue();
      expect(service.retractedFor, ['p1'], reason: 'the suppression retracted already');

      // A's held publish now fails.
      hold.completeError(const SocketException('network down'));
      await pumpEventQueue();

      expect(service.publishedFor, isEmpty,
          reason: 'A never actually succeeded and must not be reinstated '
              'as a pending retry now that B has already superseded it');
      expect(service.retractedFor, ['p1'],
          reason: 'the stale failure must not trigger a second retraction '
              'either');
    });

    test('a late failed publish does not reinstate pending state after a '
        'newer prediction already published in its place', () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final service = _FakeService(connectedProfileIds: {'p1'});
      final today = LocalDate(2026, 8, 30);

      final publisher = LocalPredictionProjectionPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
            .stream,
        service: service,
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

      final hold = Completer<void>();
      service.holdNextPublish = hold;

      profiles.add([_profile('p1')]);
      predictions['p1']!.add(_active(today)); // A: publish held in flight.
      await pumpEventQueue();

      // B: a genuinely newer prediction supersedes A before A's held
      // publish resolves — B is not held, so it publishes normally.
      predictions['p1']!.add(_active(today.addDays(1)));
      await pumpEventQueue();
      expect(service.publishedFor, ['p1'], reason: 'B published');
      expect(service.published.single.generatedAt, today.addDays(1));

      // A's held publish now fails.
      hold.completeError(const SocketException('network down'));
      await pumpEventQueue();

      expect(service.publishedFor, ['p1'],
          reason: 'still only B — A must not be reinstated as a pending '
              'retry and republish its now-stale payload over B\'s');
      expect(service.published.single.generatedAt, today.addDays(1));
    });
  });

  group('issue LLA-105: unchanged payloads and shared connection lookups',
      () {
    test('an unrelated recompute that lands on a bit-identical projection '
        'skips both the connection lookup and the publish RPC', () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final service = _FakeService(connectedProfileIds: {'p1'});
      final today = LocalDate(2026, 8, 30);

      final publisher = LocalPredictionProjectionPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
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
      expect(service.connectedLookups, 1);

      // A second, distinct ActivePrediction INSTANCE that derives a
      // bit-identical projection (same today, same forecast shape) — the
      // shape a re-emission from an unrelated settings edit takes.
      predictions['p1']!.add(_active(today));
      await pumpEventQueue();

      expect(service.publishedFor, ['p1'],
          reason: 'no redundant publish for the unchanged payload');
      expect(service.connectedLookups, 1,
          reason: 'no redundant connection lookup either');
    });

    test('two profiles publishing concurrently coalesce into one '
        'outgoingConnectedProfileIds lookup', () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final service = _FakeService(connectedProfileIds: {'p1', 'p2'});
      final today = LocalDate(2026, 8, 30);

      final publisher = LocalPredictionProjectionPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => Stream<CyclePrediction>.value(_active(today)),
        service: service,
        isSignedIn: () => true,
        // Issue #1777: both profiles must be in the active set to reach the
        // publish path.
        debounce: const Duration(minutes: 5),
      );
      publisher.start();
      addTearDown(() async {
        await publisher.dispose();
        await profiles.close();
      });

      profiles.add([_profile('p1'), _profile('p2')]);
      await pumpEventQueue();

      // Neither call is awaited before the next is issued, so both reach
      // the connection lookup before either's underlying call resolves.
      final f1 = publisher.publishNow('p1');
      final f2 = publisher.publishNow('p2');
      await Future.wait([f1, f2]);

      expect(service.connectedLookups, 1,
          reason: 'both concurrent calls shared one in-flight lookup');
      expect(service.publishedFor, unorderedEquals(['p1', 'p2']));
    });
  });

  group('_flushRetraction coverage: give-up, staleness, dispose, and '
      'signed-out', () {
    test(
        '#547: a non-retryable failure never retries — retraction is '
        'abandoned until a genuine prediction change re-arms it', () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final service = _FakeService(connectedProfileIds: {'p1'});
      final today = LocalDate(2026, 8, 30);
      service.retractError = StateError('permanently rejected');

      final publisher = LocalPredictionProjectionPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
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

      profiles.add([_profile('p1')]);
      predictions['p1']!.add(_active(today));
      await pumpEventQueue();

      predictions['p1']!.add(const PredictionsDisabled());
      await pumpEventQueue();

      expect(service.retractedFor, isEmpty,
          reason: 'the non-retryable failure never actually succeeds');
    });

    test(
        'a late failed retraction does not reinstate a retry once a newer '
        'prediction already superseded the suppression (stale generation)',
        () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final service = _FakeService(connectedProfileIds: {'p1'});
      final today = LocalDate(2026, 8, 30);

      final publisher = LocalPredictionProjectionPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
            .stream,
        service: service,
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

      final hold = Completer<void>();
      service.holdNextRetract = hold;

      profiles.add([_profile('p1')]);
      predictions['p1']!.add(_active(today));
      await pumpEventQueue();
      expect(service.publishedFor, ['p1']);

      // Triggers the retraction; the remote call is held in flight.
      predictions['p1']!.add(const PredictionsDisabled());
      await pumpEventQueue();

      // A newer, genuinely active prediction supersedes the suppression
      // before the held retract resolves.
      predictions['p1']!.add(_active(today.addDays(1)));
      await pumpEventQueue();
      expect(service.publishedFor, ['p1', 'p1'],
          reason: 'the newer active prediction published normally');

      // The stale held retract now fails.
      hold.completeError(const SocketException('network down'));
      await pumpEventQueue();

      expect(service.publishedFor, ['p1', 'p1'],
          reason: 'no corruption from the stale retract failure');
      expect(service.retractedFor, isEmpty,
          reason: 'the stale failure must not trigger a retry attempt');
    });

    test('dispose during a failed retraction is a no-op — no retry timer, '
        'no crash', () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final service = _FakeService(connectedProfileIds: {'p1'});
      final today = LocalDate(2026, 8, 30);

      final publisher = LocalPredictionProjectionPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
            .stream,
        service: service,
        isSignedIn: () => true,
        debounce: Duration.zero,
        retryDelay: const Duration(minutes: 5),
      );
      publisher.start();

      final hold = Completer<void>();
      service.holdNextRetract = hold;

      profiles.add([_profile('p1')]);
      predictions['p1']!.add(_active(today));
      await pumpEventQueue();
      predictions['p1']!.add(const PredictionsDisabled());
      await pumpEventQueue();

      await publisher.dispose();
      hold.completeError(const SocketException('network down'));
      await pumpEventQueue();

      // Reaching here without the held future's error escaping is itself
      // part of the assertion; also confirm no retraction ever succeeded.
      expect(service.retractedFor, isEmpty);
      await profiles.close();
      for (final c in predictions.values) {
        await c.close();
      }
    });

    test('a signed-out state never calls retractProjection', () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final predictions = <String, StreamController<CyclePrediction>>{};
      final service = _FakeService(connectedProfileIds: {'p1'});
      var signedIn = true;
      final today = LocalDate(2026, 8, 30);

      final publisher = LocalPredictionProjectionPublisher(
        activeProfiles: profiles.stream,
        predictionFor: (id) => predictions
            .putIfAbsent(
                id, () => StreamController<CyclePrediction>(sync: true))
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
      predictions['p1']!.add(_active(today));
      await pumpEventQueue();

      signedIn = false;
      predictions['p1']!.add(const PredictionsDisabled());
      await pumpEventQueue();

      expect(service.retractedFor, isEmpty);
    });
  });

  test('issue #1727: a profile leaving the active set retracts its published '
      'projection and stops publishing', () async {
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
    expect(service.publishedFor, ['p1'], reason: 'the live profile published');

    // The filtered watch drops an archived profile (activeProfilesOnly) --
    // that removal is what must retract the server-side projection.
    profiles.add(const <Profile>[]);
    await pumpEventQueue();
    expect(service.retractedFor, ['p1']);

    // The cancelled subscription publishes nothing further.
    predictions['p1']!.add(_active(today));
    await pumpEventQueue();
    expect(service.publishedFor, ['p1']);
  });

  group('issue #1777: a profile that left the active set is never '
      're-published', () {
    test('republishConnected skips a profile archived since its retraction',
        () async {
      final profiles = StreamController<List<Profile>>(sync: true);
      final service = _FakeService(connectedProfileIds: {'p1'});
      final today = LocalDate(2026, 8, 30);

      final publisher = LocalPredictionProjectionPublisher(
        activeProfiles: profiles.stream,
        // A fresh listenable stream per call, the shape of the production
        // `predictionFor`: pre-fix, the resume republish reads this again
        // and re-uploads; post-fix the active-set guard stops it before
        // the read.
        predictionFor: (id) => Stream<CyclePrediction>.value(_active(today)),
        service: service,
        isSignedIn: () => true,
        debounce: Duration.zero,
      );
      publisher.start();
      addTearDown(() async {
        await publisher.dispose();
        await profiles.close();
      });

      profiles.add([_profile('p1')]);
      await pumpEventQueue();
      expect(service.publishedFor, ['p1'],
          reason: 'the active profile published');

      // The profile leaves the active set (archived) -- its snapshot is
      // retracted, and the connection stays active server-side.
      profiles.add(const <Profile>[]);
      await pumpEventQueue();
      expect(service.retractedFor, ['p1']);

      // The next resume republish must not undo the retraction: the
      // connection list has no archive state, so only the publisher's own
      // active set can tell that this profile is out of everyday use.
      await publisher.republishConnected();
      expect(service.publishedFor, ['p1'],
          reason: 'the archived profile must not be re-uploaded on resume');

      // publishNow (a connection created/refreshed from the manage screen)
      // holds the same guard.
      await publisher.publishNow('p1');
      expect(service.publishedFor, ['p1'],
          reason: 'publishNow must not re-upload the archived profile either');
    });

    test('an in-flight debounced flush does not publish a profile archived '
        'while its connection lookup was in flight', () async {
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

      final lookupHold = Completer<void>();
      service.holdNextConnectedLookup = lookupHold;

      profiles.add([_profile('p1')]);
      predictions['p1']!.add(_active(today));
      await pumpEventQueue(); // The flush starts and holds on the lookup.

      // Archived while the lookup is still in flight; the retraction runs.
      profiles.add(const <Profile>[]);
      await pumpEventQueue();
      expect(service.retractedFor, ['p1']);

      lookupHold.complete();
      await pumpEventQueue();
      expect(service.publishedFor, isEmpty,
          reason: 'the in-flight flush must not re-publish after the '
              'retraction');
    });
  });

  test('issue #1873: a failed publishNow clears the dedupe cache so the '
      'next identical emission republishes', () async {
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

    // The explicit refresh fails - the shape of a just-created connection
    // whose best-effort first publish hit a rejection.
    service.publishError = StateError('rejected');
    service.remainingFailures = 1;
    await publisher.publishNow('p1');
    service.publishError = null;

    // The same unchanged projection re-emits (an unrelated settings edit);
    // without the cache clear it would be deduped against a server
    // snapshot the refresh may no longer correspond to.
    predictions['p1']!.add(_active(today));
    await pumpEventQueue();
    expect(service.publishedFor, ['p1', 'p1'],
        reason: 'the failed refresh must not leave a stale dedupe hit');
  });
}
