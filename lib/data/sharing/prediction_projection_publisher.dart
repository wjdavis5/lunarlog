/// Keeps the server's prediction-projection snapshot (issue #151) in step
/// with each profile the signed-in account shares predictions FOR,
/// debounced and best-effort. Mirrors
/// `lib/data/notifications/reminder_window_publisher.dart`'s debounced
/// stream-fan-in, bounded retry, and disposal discipline.
///
/// Privacy posture: derived-phase data is only uploaded for profiles with
/// an ACTIVE outgoing connection ([PredictionConnectionService
/// .outgoingConnectedProfileIds] is re-queried per flush — prediction
/// changes are rare and the query is a single narrow select). The server
/// enforces the same gate and additionally no-ops (deleting any stored
/// snapshot) when no active connection exists, so a publish racing a
/// revocation can never leave derived data behind.
library;

// Named required parameters cannot be initializing formals; the private
// finals below are assigned through the constructor's initializer list.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/sharing/prediction_connection_service.dart';
import 'package:lunarlog/domain/sharing/prediction_projection.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

typedef ActiveProfilesStream = Stream<List<Profile>>;
typedef PredictionStream = Stream<CyclePrediction> Function(String profileId);

class PredictionProjectionPublisher {
  PredictionProjectionPublisher({
    required ActiveProfilesStream activeProfiles,
    required PredictionStream predictionFor,
    required PredictionConnectionService service,
    required bool Function() isSignedIn,
    this.debounce = const Duration(milliseconds: 500),
    this.retryDelay = const Duration(minutes: 5),
  })  : _activeProfiles = activeProfiles,
        _predictionFor = predictionFor,
        _service = service,
        _isSignedIn = isSignedIn;

  final ActiveProfilesStream _activeProfiles;
  final PredictionStream _predictionFor;
  final PredictionConnectionService _service;
  final bool Function() _isSignedIn;
  final Duration debounce;

  /// How long to wait before retrying a failed publish of an
  /// otherwise-unchanged prediction (the reminder-window publisher's #12
  /// review fix): the recipient's calendar stays stale until something
  /// re-arms, and "the next prediction change or app restart" is not
  /// bounded.
  final Duration retryDelay;

  StreamSubscription<List<Profile>>? _profilesSub;
  final Map<String, StreamSubscription<CyclePrediction>> _predictionSubs = {};
  final Map<String, Timer> _debounceTimers = {};
  final Map<String, ActivePrediction> _pending = {};
  bool _disposed = false;

  void start() {
    if (_disposed) return;
    _profilesSub = _activeProfiles.listen(_onProfilesChanged);
  }

  void _onProfilesChanged(List<Profile> profiles) {
    if (_disposed) return;
    final activeIds = profiles.map((p) => p.id).toSet();
    _predictionSubs.removeWhere((id, sub) {
      if (activeIds.contains(id)) return false;
      unawaited(sub.cancel());
      _debounceTimers.remove(id)?.cancel();
      _pending.remove(id);
      return true;
    });
    for (final id in activeIds) {
      _predictionSubs.putIfAbsent(
        id,
        () => _predictionFor(id)
            .listen((prediction) => _onPrediction(id, prediction)),
      );
    }
  }

  void _onPrediction(String profileId, CyclePrediction prediction) {
    if (_disposed) return;
    if (prediction is! ActivePrediction) {
      // NotEnoughHistory: nothing derived to share right now.
      _debounceTimers.remove(profileId)?.cancel();
      _pending.remove(profileId);
      return;
    }
    _pending[profileId] = prediction;
    _debounceTimers[profileId]?.cancel();
    _debounceTimers[profileId] =
        Timer(debounce, () => unawaited(_flush(profileId)));
  }

  Future<void> _flush(String profileId) async {
    if (_disposed) return;
    _debounceTimers.remove(profileId);
    final prediction = _pending.remove(profileId);
    if (prediction == null) return;
    if (!_isSignedIn()) return;
    try {
      // Only upload while this account actually shares this profile OUT;
      // re-queried per flush so a create/revoke elsewhere in the app is
      // honored without a separate invalidation channel.
      final connected = await _service.outgoingConnectedProfileIds();
      if (!connected.contains(profileId)) return;
      await _service.publishProjection(
        profileId: profileId,
        projection: buildPredictionProjection(prediction),
      );
    } catch (_) {
      // Best-effort background upkeep (the reminder-window publisher's
      // posture): a failed publish must never surface to the UI or cancel
      // the subscription — but it also must not go unaddressed until the
      // next genuine change (see [retryDelay]).
      if (_disposed) return;
      _pending[profileId] = prediction;
      _debounceTimers[profileId]?.cancel();
      _debounceTimers[profileId] =
          Timer(retryDelay, () => unawaited(_flush(profileId)));
    }
  }

  /// Publishes [profileId]'s current prediction right away — used right
  /// after a connection is created so the recipient's first fetch has
  /// data without waiting for the sharer's next prediction change.
  /// Best-effort: a failure here leaves the publish to the regular
  /// stream-driven path.
  Future<void> publishNow(String profileId) async {
    if (_disposed || !_isSignedIn()) return;
    try {
      final prediction = await _predictionFor(profileId).first;
      if (_disposed) return;
      if (prediction is! ActivePrediction) return;
      final connected = await _service.outgoingConnectedProfileIds();
      if (!connected.contains(profileId)) return;
      await _service.publishProjection(
        profileId: profileId,
        projection: buildPredictionProjection(prediction),
      );
    } catch (_) {
      // Best-effort (see above).
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _profilesSub?.cancel();
    _profilesSub = null;
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    for (final sub in _predictionSubs.values) {
      await sub.cancel();
    }
    _predictionSubs.clear();
    _pending.clear();
  }
}
