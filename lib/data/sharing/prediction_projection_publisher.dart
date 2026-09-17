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

import 'package:lunarlog/data/publish_retry.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/sharing/prediction_connection_service.dart';
import 'package:lunarlog/domain/sharing/prediction_projection.dart';
import 'package:lunarlog/domain/sharing/prediction_projection_publisher.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

class LocalPredictionProjectionPublisher
    implements PredictionProjectionPublisher {
  LocalPredictionProjectionPublisher({
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

  @override
  final Duration debounce;

  /// How long to wait before retrying a failed publish of an
  /// otherwise-unchanged prediction (the reminder-window publisher's #12
  /// review fix): the recipient's calendar stays stale until something
  /// re-arms, and "the next prediction change or app restart" is not
  /// bounded.
  @override
  final Duration retryDelay;

  StreamSubscription<List<Profile>>? _profilesSub;
  final Map<String, StreamSubscription<CyclePrediction>> _predictionSubs = {};
  final Map<String, Timer> _debounceTimers = {};
  final Map<String, ActivePrediction> _pending = {};
  // Issue LLA-061: profiles a suppression transition (Pregnancy/
  // Postpartum/Perimenopause, a continuous method, or predictions turned
  // off) has queued for retraction. A profile is in at most one of
  // [_pending]/[_pendingRetraction] at a time — [_onPrediction]'s switch
  // clears the other on every emission.
  final Set<String> _pendingRetraction = {};
  // Issue #547: consecutive-failure count per profile, feeding
  // decidePublishRetry's exponential backoff — reset on any genuine
  // prediction change ([_onPrediction]) so a fresh update never inherits a
  // stale profile's long backoff.
  final Map<String, int> _retryAttempts = {};
  // Issue LLA-062: bumped on every [_onPrediction] call for a profile,
  // regardless of branch. A [_flush]/[_flushRetraction] attempt captures
  // this value before its (possibly slow) network call; if it no longer
  // matches when that call resolves, a newer emission has already
  // superseded this attempt (a fresher prediction re-armed [_pending], or
  // a suppression already queued/ran its own retraction), so a failure
  // must not reinstate this stale attempt's retry.
  final Map<String, int> _generation = {};
  // Issue LLA-105: the last successfully published payload per profile,
  // so an unrelated recompute that lands on a bit-identical projection
  // (e.g. an unconnected setting edit re-emitting the same prediction)
  // skips both the connection lookup and the publish RPC entirely.
  // Cleared on a suppression's retraction so a later resumed Active
  // prediction — even one coincidentally identical to the pre-suppression
  // payload — always republishes rather than being deduped against a
  // snapshot the server no longer holds.
  final Map<String, PredictionProjection> _lastPublished = {};
  // Issue LLA-105: coalesces concurrent outgoingConnectedProfileIds()
  // lookups (e.g. several profiles' debounced flushes landing in the same
  // tick, which the LLA-070 date-rollover ticker makes more likely) into
  // one in-flight request rather than one per profile.
  Future<Set<String>>? _pendingConnectedLookup;
  bool _disposed = false;

  @override
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
      _pendingRetraction.remove(id);
      _retryAttempts.remove(id);
      _generation.remove(id);
      _lastPublished.remove(id);
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
    // Issue LLA-062: every emission bumps the generation, regardless of
    // which branch below runs — a stale [_flush]/[_flushRetraction]
    // attempt in flight from a previous emission checks this before
    // reinstating itself.
    _generation[profileId] = (_generation[profileId] ?? 0) + 1;
    _debounceTimers.remove(profileId)?.cancel();
    switch (prediction) {
      case NotEnoughHistory():
        // Not (yet) enough data — leave any previously published
        // snapshot alone; this is not the deliberate-suppression case
        // LLA-061 addresses, and a profile can drift in and out of this
        // state as omissions/history change.
        _pending.remove(profileId);
        _pendingRetraction.remove(profileId);
        _retryAttempts.remove(profileId);
        return;
      case PredictionsSuppressed():
      case PredictionsDisabled():
        // Issue LLA-061: a deliberate suppression (Pregnancy/Postpartum/
        // Perimenopause, a continuous method, or predictions turned off)
        // must retract any previously published snapshot right away —
        // unlike revocation or the minor gate, nothing server-side
        // clears it on its own, and the connection itself is still
        // active, so a stale phase would otherwise stay readable
        // indefinitely.
        _pending.remove(profileId);
        _retryAttempts.remove(profileId);
        _lastPublished.remove(profileId);
        _pendingRetraction.add(profileId);
        unawaited(_flushRetraction(profileId));
        return;
      case ActivePrediction():
        _pendingRetraction.remove(profileId);
        _pending[profileId] = prediction;
        _retryAttempts.remove(profileId);
        _debounceTimers[profileId] =
            Timer(debounce, () => unawaited(_flush(profileId)));
    }
  }

  Future<void> _flush(String profileId) async {
    if (_disposed) return;
    _debounceTimers.remove(profileId);
    final prediction = _pending.remove(profileId);
    if (prediction == null) return;
    if (!_isSignedIn()) return;
    final projection = buildPredictionProjection(prediction);
    // Issue LLA-105: skip the connection lookup and the publish RPC
    // entirely when this profile's projection has not actually changed
    // since the last successful publish — an unrelated recompute (a
    // settings edit, a date-rollover tick with today unchanged in
    // content) must not cause redundant cloud fanout.
    if (_dedupeHit(profileId, projection)) return;
    final generation = _currentGeneration(profileId);
    try {
      // Only upload while this account actually shares this profile OUT;
      // re-queried per flush so a create/revoke elsewhere in the app is
      // honored without a separate invalidation channel.
      final connected = await _connectedProfileIds();
      if (!connected.contains(profileId)) return;
      await _service.publishProjection(
        profileId: profileId,
        projection: projection,
      );
      _retryAttempts.remove(profileId);
      _lastPublished[profileId] = projection;
    } catch (error, stackTrace) {
      // Issue LLA-062: a newer emission already superseded this attempt
      // (a fresher prediction re-armed [_pending], or the profile has
      // since moved to a suppression and queued its own retraction) —
      // reinstating this stale, now-superseded payload as a pending
      // retry would fight whatever the newer emission already set up.
      if (_disposed || _isStale(profileId, generation)) return;
      // Issue #547: retry only a transient failure, with exponential
      // backoff and an attempt cap — a permanent rejection (revoked
      // access surfacing as a 4xx, a malformed payload) used to re-arm
      // this same fixed 5-minute retry forever, a select + upsert every 5
      // minutes indefinitely on cellular for a rejection that will never
      // succeed. decidePublishRetry (inside schedulePublishRetry)
      // captures a non-retryable/exhausted failure to Sentry exactly
      // once (never a bare swallow).
      schedulePublishRetry(
        profileId: profileId,
        error: error,
        stackTrace: stackTrace,
        retryAttempts: _retryAttempts,
        timers: _debounceTimers,
        retryDelay: retryDelay,
        onRetry: () => _pending[profileId] = prediction,
        retry: () => _flush(profileId),
        onGiveUp: () {},
      );
    }
  }

  /// The retraction half of [_flush] (issue LLA-061), same bounded-retry
  /// shape via [schedulePublishRetry]: a transient failure retries with
  /// backoff, a permanent one gives up until the next emission re-arms
  /// it, and a superseding emission ([_isStale], issue LLA-062) drops a
  /// stale attempt rather than fighting whatever ran after it.
  Future<void> _flushRetraction(String profileId) async {
    if (_disposed || !_pendingRetraction.contains(profileId)) return;
    if (!_isSignedIn()) return;
    final generation = _currentGeneration(profileId);
    try {
      await _service.retractProjection(profileId: profileId);
      _pendingRetraction.remove(profileId);
      _retryAttempts.remove(profileId);
    } catch (error, stackTrace) {
      if (_disposed || _isStale(profileId, generation)) return;
      schedulePublishRetry(
        profileId: profileId,
        error: error,
        stackTrace: stackTrace,
        retryAttempts: _retryAttempts,
        timers: _debounceTimers,
        retryDelay: retryDelay,
        onRetry: () {},
        retry: () => _flushRetraction(profileId),
        onGiveUp: () => _pendingRetraction.remove(profileId),
      );
    }
  }

  /// The profile's current generation token (issue LLA-062), captured
  /// before a `_flush`/`_flushRetraction` attempt's network call so its
  /// catch block can later tell whether a newer emission superseded it.
  int _currentGeneration(String profileId) => _generation[profileId] ?? 0;

  /// Whether a newer [_onPrediction] emission has already superseded the
  /// attempt that captured [generation] (issue LLA-062) — a stale
  /// completion must drop itself rather than reinstate state a fresher
  /// emission already set up.
  bool _isStale(String profileId, int generation) =>
      _generation[profileId] != generation;

  /// Issue LLA-105: true when [projection] is bit-identical to the last
  /// payload successfully published for [profileId] — [_flush] skips the
  /// connection lookup and the publish RPC entirely in that case. Clears
  /// [_retryAttempts] too: an unchanged payload is not itself a failure
  /// to keep retrying.
  bool _dedupeHit(String profileId, PredictionProjection projection) {
    if (_lastPublished[profileId] != projection) return false;
    _retryAttempts.remove(profileId);
    return true;
  }

  /// Issue LLA-105: coalesces concurrent [PredictionConnectionService
  /// .outgoingConnectedProfileIds] calls into one in-flight request — several
  /// profiles' debounced flushes landing in the same event-loop tick (more
  /// likely now that the prediction stream also ticks on a civil-date
  /// rollover, LLA-070) previously each queried the same set independently.
  Future<Set<String>> _connectedProfileIds() {
    final pending = _pendingConnectedLookup;
    if (pending != null) return pending;
    final Future<Set<String>> future = _service.outgoingConnectedProfileIds();
    _pendingConnectedLookup = future;
    // A second (independent) listener on the same future, purely to clear
    // the cache once it settles -- the caller above still gets (and
    // handles) the original future's own success/error separately, so
    // this never turns a failure into an unhandled one.
    unawaited(future.then(
      (_) => _clearConnectedLookup(future),
      onError: (_) => _clearConnectedLookup(future),
    ));
    return future;
  }

  void _clearConnectedLookup(Future<Set<String>> future) {
    if (identical(_pendingConnectedLookup, future)) {
      _pendingConnectedLookup = null;
    }
  }

  /// Publishes [profileId]'s current prediction right away — used right
  /// after a connection is created so the recipient's first fetch has
  /// data without waiting for the sharer's next prediction change.
  /// Best-effort: a failure here leaves the publish to the regular
  /// stream-driven path.
  @override
  Future<void> publishNow(String profileId) async {
    if (_disposed || !_isSignedIn()) return;
    try {
      final connected = await _connectedProfileIds();
      if (!connected.contains(profileId)) return;
      await _publishCurrent(profileId);
    } catch (_) {
      // Best-effort (see above).
    }
  }

  /// Issue #373: publishes the current prediction for EVERY profile this
  /// account shares OUT, right away. The app shell calls it on resume:
  /// the stream-driven path only fires on a prediction change, so a
  /// recipient who redeemed a code while the sharer's app was in the
  /// background would otherwise see no snapshot until the sharer's next
  /// cycle event. One narrow select, then one idempotent upsert per
  /// connected profile; best-effort like [publishNow].
  @override
  Future<void> republishConnected() async {
    if (_disposed || !_isSignedIn()) return;
    try {
      final connected = await _connectedProfileIds();
      for (final profileId in connected) {
        if (_disposed) return;
        await _publishCurrent(profileId);
      }
    } catch (_) {
      // Best-effort (see above).
    }
  }

  /// The shared tail of [publishNow] and [republishConnected]: reads the
  /// profile's current prediction once and uploads it when derived. The
  /// caller has already confirmed the profile is connected.
  Future<void> _publishCurrent(String profileId) async {
    final prediction = await _predictionFor(profileId).first;
    if (_disposed) return;
    if (prediction is! ActivePrediction) return;
    final projection = buildPredictionProjection(prediction);
    await _service.publishProjection(
      profileId: profileId,
      projection: projection,
    );
    // Issue LLA-105: keeps the dedup cache honest about the true last-
    // published payload regardless of which path (this explicit refresh,
    // or the regular debounced [_flush]) published it most recently.
    _lastPublished[profileId] = projection;
  }

  @override
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
    _pendingRetraction.clear();
    _retryAttempts.clear();
    _generation.clear();
    _lastPublished.clear();
    _pendingConnectedLookup = null;
  }
}
