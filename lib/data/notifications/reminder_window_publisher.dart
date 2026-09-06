/// Keeps the server's reminder-window snapshot (Issue #5, U6; KTD4, R13) in
/// step with each active profile's local prediction, debounced and
/// best-effort. Mirrors `lib/data/notifications/reminder_coordinator.dart`'s
/// debounced stream-fan-in and disposal discipline.
///
/// #12 (review fix): a failed publish retries the same prediction on a
/// bounded [retryDelay] rather than only on the next genuine prediction
/// change - `scan_missed_entry_reminders()` inner-joins
/// `profile_reminder_windows`, so a profile with no published row (or a
/// stale one) is silently excluded from the missed-entry scan entirely
/// until a publish for it eventually succeeds.
library;

// Named required parameters cannot be initializing formals; the private
// finals below are assigned through the constructor's initializer list.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

typedef ActiveProfilesStream = Stream<List<Profile>>;
typedef PredictionStream = Stream<CyclePrediction> Function(String profileId);

/// Publishes one profile's window. [estimatedNextStartIso] is the civil
/// `yyyy-MM-dd` date the server's `date` column expects.
typedef ReminderWindowUpsert = Future<void> Function(
  String profileId,
  String estimatedNextStartIso,
  bool episodeOpen,
);

class ReminderWindowPublisher {
  ReminderWindowPublisher({
    required ActiveProfilesStream activeProfiles,
    required PredictionStream predictionFor,
    required ReminderWindowUpsert upsert,
    required bool Function() isSignedIn,
    this.debounce = const Duration(milliseconds: 500),
    this.retryDelay = const Duration(minutes: 5),
  })  : _activeProfiles = activeProfiles,
        _predictionFor = predictionFor,
        _upsert = upsert,
        _isSignedIn = isSignedIn;

  final ActiveProfilesStream _activeProfiles;
  final PredictionStream _predictionFor;
  final ReminderWindowUpsert _upsert;
  final bool Function() _isSignedIn;
  final Duration debounce;

  /// #12 (review fix): how long to wait before retrying a *failed* publish
  /// of an otherwise-unchanged prediction. Without this, a swallowed
  /// failure left profile_reminder_windows with no row (or a stale one) for
  /// the profile, and scan_missed_entry_reminders()'s inner join on that
  /// table then excluded the profile from the missed-entry scan entirely --
  /// "the next prediction change or app restart retries" is not bounded and
  /// silently disables the feature for as long as the prediction happens
  /// not to change and the app happens to stay running.
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
      // NotEnoughHistory / PausedAwaitingNextPeriod: nothing to publish for
      // this profile right now.
      _debounceTimers.remove(profileId)?.cancel();
      _pending.remove(profileId);
      return;
    }
    _pending[profileId] = prediction;
    _debounceTimers[profileId]?.cancel();
    _debounceTimers[profileId] = Timer(debounce, () => unawaited(_flush(profileId)));
  }

  Future<void> _flush(String profileId) async {
    if (_disposed) return;
    _debounceTimers.remove(profileId);
    final prediction = _pending.remove(profileId);
    if (prediction == null) return;
    if (!_isSignedIn()) return;
    try {
      await _upsert(
        profileId,
        prediction.estimatedNextStart.iso,
        prediction.duringEpisode,
      );
    } catch (_) {
      // Best-effort background upkeep (R13): a failed publish must never
      // surface to the UI or cancel the subscription.
      //
      // #12 (review fix): but it also must not go unaddressed until
      // something else happens to change - re-arm this same prediction on
      // a bounded retryDelay rather than only waiting for a genuinely new
      // prediction (_onPrediction) or an app restart. If a fresh prediction
      // arrives first, _onPrediction overwrites _pending and resets the
      // timer to the normal (short) debounce anyway, so this retry never
      // fights a real update.
      if (_disposed) return;
      _pending[profileId] = prediction;
      _debounceTimers[profileId]?.cancel();
      _debounceTimers[profileId] =
          Timer(retryDelay, () => unawaited(_flush(profileId)));
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
