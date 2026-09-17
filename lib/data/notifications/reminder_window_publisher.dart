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

import 'package:lunarlog/data/publish_retry.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/notifications/reminder_window_remote.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

class ReminderWindowPublisher {
  ReminderWindowPublisher({
    required ActiveProfilesStream activeProfiles,
    required PredictionStream predictionFor,
    required ReminderWindowRemote upsert,
    required bool Function() isSignedIn,
    this.debounce = const Duration(milliseconds: 500),
    this.retryDelay = const Duration(minutes: 5),
  })  : _activeProfiles = activeProfiles,
        _predictionFor = predictionFor,
        _upsert = upsert,
        _isSignedIn = isSignedIn;

  final ActiveProfilesStream _activeProfiles;
  final PredictionStream _predictionFor;
  final ReminderWindowRemote _upsert;
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
  // regardless of branch — see prediction_projection_publisher.dart's
  // mirrored field for the full reasoning. A [_flush]/[_flushRetraction]
  // attempt whose captured generation no longer matches on completion has
  // been superseded by a newer emission and must not reinstate itself.
  final Map<String, int> _generation = {};
  // Issue LLA-105: the last successfully published (estimatedNextStartIso,
  // episodeOpen) pair per profile, so an unrelated recompute that lands on
  // an unchanged window skips the upsert RPC entirely. Cleared on a
  // suppression's retraction so a later resumed Active prediction is
  // never deduped against a snapshot the server no longer holds.
  final Map<String, (String, bool)> _lastPublished = {};
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
    // which branch below runs.
    _generation[profileId] = (_generation[profileId] ?? 0) + 1;
    _debounceTimers.remove(profileId)?.cancel();
    switch (prediction) {
      case NotEnoughHistory():
        // Not (yet) enough data — leave any previously published window
        // alone; this is not the deliberate-suppression case LLA-061
        // addresses.
        _pending.remove(profileId);
        _pendingRetraction.remove(profileId);
        _retryAttempts.remove(profileId);
        return;
      case PredictionsSuppressed():
      case PredictionsDisabled():
        // Issue LLA-061: a deliberate suppression must retract any
        // previously published window right away — its stale
        // estimated_next_start/episode_open would otherwise keep feeding
        // scan_missed_entry_reminders()'s inner join indefinitely, since
        // nothing server-side clears it on its own.
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
    // #221 follow-up (review fix): publish the UN-ROLLED
    // originalEstimatedNextStart, not the (possibly rolled-forward)
    // estimatedNextStart. scan_missed_entry_reminders() (see
    // supabase/migrations/20260906230000_reminder_windows_and_cron.sql)
    // only enqueues when `estimated_next_start <= current_date` and dedupes
    // on `last_enqueued_for`; a late cycle's estimatedNextStart is rolled
    // forward in whole mean-cycle-length steps (prediction.dart's
    // _rollLateEstimate) to stay near-term for display, which means it is
    // typically *in the future* server-side even while the guardian has
    // gone unheard-from for a while. Publishing that rolled date would
    // silence the missed-entry scan for as long as ~ (mean cycle length -
    // grace) out of every mean-cycle-length days -- roughly 25 of every 28
    // for a typical cycle. originalEstimatedNextStart never rolls, so once
    // it is in the past the gate stays open every day after.
    final iso = prediction.originalEstimatedNextStart.iso;
    final episodeOpen = prediction.duringEpisode;
    // Issue LLA-105: skip the upsert RPC entirely when this profile's
    // window has not actually changed since the last successful publish —
    // an unrelated recompute must not cause redundant cloud fanout.
    if (_dedupeHit(profileId, iso, episodeOpen)) return;
    final generation = _currentGeneration(profileId);
    try {
      await _upsert.upsert(
        profileId: profileId,
        estimatedNextStartIso: iso,
        episodeOpen: episodeOpen,
      );
      _retryAttempts.remove(profileId);
      _lastPublished[profileId] = (iso, episodeOpen);
    } catch (error, stackTrace) {
      // Best-effort background upkeep (R13): a failed publish must never
      // surface to the UI or cancel the subscription. Issue LLA-062: a
      // newer emission already superseded this attempt — reinstating
      // this stale payload would fight whatever the newer emission
      // already set up.
      if (_disposed || _isStale(profileId, generation)) return;
      // Issue #547 (supersedes the #12 review fix's fixed 5-minute
      // retry): retry only a transient failure, with exponential backoff
      // and an attempt cap — a permanent rejection used to re-arm this
      // same fixed retry forever, a select + upsert every 5 minutes
      // indefinitely on cellular for a rejection that will never succeed.
      // schedulePublishRetry's decidePublishRetry captures a
      // non-retryable/exhausted failure to Sentry exactly once (never a
      // bare swallow). If a fresh prediction arrives first,
      // _onPrediction overwrites _pending, resets the attempt count, and
      // resets the timer to the normal (short) debounce anyway, so this
      // retry never fights a real update.
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

  /// The retraction half of [_flush] (issue LLA-061) — same bounded-retry
  /// shape via [schedulePublishRetry], and the same staleness check
  /// ([_isStale], issue LLA-062) so a stale attempt never reinstates
  /// itself over a newer emission.
  Future<void> _flushRetraction(String profileId) async {
    if (_disposed || !_pendingRetraction.contains(profileId)) return;
    if (!_isSignedIn()) return;
    final generation = _currentGeneration(profileId);
    try {
      await _upsert.retract(profileId: profileId);
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
  /// attempt that captured [generation] (issue LLA-062).
  bool _isStale(String profileId, int generation) =>
      _generation[profileId] != generation;

  /// Issue LLA-105: true when `(iso, episodeOpen)` is identical to the
  /// last window successfully published for [profileId] — [_flush] skips
  /// the upsert RPC entirely in that case. Clears [_retryAttempts] too:
  /// an unchanged window is not itself a failure to keep retrying.
  bool _dedupeHit(String profileId, String iso, bool episodeOpen) {
    if (_lastPublished[profileId] != (iso, episodeOpen)) return false;
    _retryAttempts.remove(profileId);
    return true;
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
    _pendingRetraction.clear();
    _retryAttempts.clear();
    _generation.clear();
    _lastPublished.clear();
  }
}
