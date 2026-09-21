/// Supabase Realtime sync coordinator (U6; KTD6). Subscribes to Realtime
/// channels for shared profiles and triggers debounced sync cycles when
/// co-caregivers push changes. Issue #77 (KTD2, KTD3) added the
/// backend publication that makes the channels actually emit, and the
/// sign-in channel rebuild below.
///
/// Listens on `public.sync_signals`, a dedicated wake-signal table — not
/// `day_entries`/`profiles` directly (PR #92 review revision of KTD2):
/// Realtime's WALRUS decodes with wal2json, which only honors a publication
/// as a table-level membership list, so a narrow *publication* column list
/// on the source tables would not have kept `note`/`tags`/`flow` off this
/// channel (see `supabase/migrations/20260905100000_realtime_publication.sql`).
/// `sync_signals` carries no health content by construction, so there is
/// nothing to discard here except a bare "something changed" notification.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/auth/auth_service.dart';
import '../../domain/sync/sync_engine.dart';
import '../db/db.dart';
import '../db/storage.dart';

/// Builds a one-shot timer for a Realtime re-subscribe attempt; the default
/// is `Timer(delay, callback)`. Injected so tests can drive retries without
/// real time (the `SyncTimerFactory` pattern in `supabase_sync_engine.dart`).
typedef RealtimeRetryTimerFactory = Timer Function(
    Duration delay, void Function() callback);

Timer _defaultRealtimeRetryTimer(
        Duration delay, void Function() callback) =>
    Timer(delay, callback);

/// Base delay for a failed-subscribe retry; doubled per consecutive failure.
const Duration kRealtimeRetryBase = Duration(seconds: 2);

/// Cap for the retry delay: retries stay spaced, never a tight loop.
const Duration kRealtimeRetryCap = Duration(minutes: 2);

class RealtimeSyncCoordinator with WidgetsBindingObserver {
  RealtimeSyncCoordinator({
    required this.client,
    required this.syncEngine,
    required this.storage,
    this.auth,
    this.debounceDuration = const Duration(milliseconds: 500),
    RealtimeRetryTimerFactory? retryTimerFactory,
  }) : _retryTimerFactory = retryTimerFactory ?? _defaultRealtimeRetryTimer;

  final SupabaseClient client;
  final SyncEngine syncEngine;
  final LunarLogStorage storage;

  /// The account seam (issue #77; KTD3). Optional: a coordinator constructed
  /// without one behaves exactly as before — channels are subscribed once
  /// from the current profile set and never rebuilt on an identity change.
  /// When present, `SupabaseClient` already forwards session changes to
  /// Realtime (`realtime.setAuth`), but whether an *existing*
  /// `postgres_changes` subscription re-evaluates its RLS binding on that
  /// token push is version-dependent, so the coordinator rebuilds its own
  /// channels instead of trusting that.
  final AuthService? auth;

  final Duration debounceDuration;
  final RealtimeRetryTimerFactory _retryTimerFactory;

  final Map<String, RealtimeChannel> _channels = {};

  /// Last subscription status per profile (issue #98, AC1). Set from the
  /// `subscribe()` status callback; a profile with no entry has not reported
  /// yet. Read via [channelStatuses]/[isLive] — a coarse live/polling bit so
  /// a silent degradation to the periodic sync is observable.
  final Map<String, RealtimeSubscribeStatus> _statuses = {};

  /// Pending re-subscribe timers per profile (AC3) and the consecutive
  /// failure count each timer's delay was computed from.
  final Map<String, Timer> _retryTimers = {};
  final Map<String, int> _retryAttempts = {};
  StreamSubscription<List<Profile>>? _profilesSubscription;
  StreamSubscription<AuthSessionState>? _authSubscription;
  Timer? _debounceTimer;
  bool _disposed = false;

  /// Issue #842: whether channels are currently paused because the app is
  /// backgrounded. While true, no channel is (re)subscribed — the profile
  /// watch still tracks ids and removes channels for vanished profiles, but
  /// the "add newly discovered profile" step is deferred until resume.
  bool _lifecyclePaused = false;

  /// The profile ids from the most recent [storage] emission, kept so a
  /// sign-in/sign-out identity change can rebuild channels without waiting
  /// for another watch emission.
  Set<String> _lastProfileIds = const {};

  /// The signed-in user id channels are currently subscribed under, or null
  /// while signed out. Only a *change* of this value triggers a rebuild —
  /// a token refresh that leaves the identity the same must not churn
  /// channels.
  String? _boundUserId;

  /// Last reported subscription status per profile (AC1). A profile with no
  /// entry has not reported yet.
  Map<String, RealtimeSubscribeStatus> get channelStatuses =>
      Map.unmodifiable(_statuses);

  /// True when no channel is known-degraded: every profile that has reported
  /// is `subscribed` (vacuously true with no channels). A coarse
  /// live/polling bit for the sync status tile so a silent degradation to
  /// the 15-minute periodic sync is observable.
  bool get isLive => _statuses.values
      .every((status) => status == RealtimeSubscribeStatus.subscribed);

  /// Starts watching local profiles and subscribes to Realtime channels.
  void start() {
    if (_disposed) return;
    WidgetsBinding.instance.addObserver(this);
    final auth = this.auth;
    if (auth != null) {
      _boundUserId = auth.confirmedUserId;
      _authSubscription = auth.states.listen((_) => _onAuthStateChanged());
    }
    _profilesSubscription = storage.watchProfiles().listen(_onProfilesUpdated);
  }

  /// Issue #842: pause the Realtime channels (and the signup websocket's
  /// heartbeat) while backgrounded, and re-subscribe on resume. One
  /// lifecycle mechanism, the same `resumed`/`paused`/`hidden` states the
  /// sync engine and prediction ticker key off.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.resumed) {
      _onResumed();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _onPaused();
    }
  }

  /// Issue #842: whether Realtime currently has a live subscription that can
  /// deliver changes — at least one channel, and every channel reporting
  /// `subscribed`. Deliberately stricter than [isLive], which is vacuously
  /// true with no channels: the engine's resume-skip must not treat a set of
  /// channels torn down for backgrounding as "connected", or a remote change
  /// made while backgrounded could be missed until the next trigger.
  bool get isSubscribed =>
      _channels.isNotEmpty &&
      _statuses.length == _channels.length &&
      isLive;

  void _onPaused() {
    if (_lifecyclePaused) return;
    _lifecyclePaused = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    for (final removal in _clearChannels()) {
      unawaited(removal);
    }
  }

  void _onResumed() {
    if (!_lifecyclePaused) return;
    _lifecyclePaused = false;
    _resubscribeAll();
  }

  /// Re-opens a channel for every known profile under the current identity,
  /// through the shared gates in [_subscribeMissingProfiles] — safe for the
  /// no-auth coordinator too (which has no `_boundUserId` and subscribes
  /// unconditionally), so resume restores exactly the channels pause removed.
  void _resubscribeAll() {
    if (_disposed) return;
    _subscribeMissingProfiles(_lastProfileIds);
  }

  void _onAuthStateChanged() {
    if (_disposed) return;
    final auth = this.auth;
    if (auth == null) return;
    final identity = auth.confirmedUserId;
    if (identity == _boundUserId) return;
    _boundUserId = identity;
    _rebuildChannels();
  }

  /// Tears down every current channel and, while a user is signed in,
  /// re-subscribes from the last-known profile set under the new identity
  /// (KTD3). A transition to signed-out removes channels and stops there —
  /// there is no authorized identity to bind a fresh subscription to, so
  /// resubscribing would just open channels the server will reject. Since
  /// issue #778 the same posture covers the initial subscribe too (see
  /// [_subscribeMissingProfiles]): a signed-out coordinator never opens a
  /// channel in the first place, so there is nothing to tear down on
  /// sign-out unless the sign-out happens mid-subscription.
  void _rebuildChannels() {
    for (final removal in _clearChannels()) {
      unawaited(removal);
    }
    if (_boundUserId == null) return;
    // Issue #842: while backgrounded, defer re-subscription to [_onResumed]
    // rather than opening channels the pause just removed.
    _subscribeMissingProfiles(_lastProfileIds);
  }

  void _onProfilesUpdated(List<Profile> profiles) {
    if (_disposed) return;
    final currentIds = profiles.map((p) => p.id).toSet();
    _lastProfileIds = currentIds;

    // 1. Remove channels for profiles no longer present.
    final toRemove = _channels.keys.where((id) => !currentIds.contains(id)).toList();
    for (final id in toRemove) {
      _cancelRetry(id);
      _retryAttempts.remove(id);
      _statuses.remove(id);
      final ch = _channels.remove(id);
      if (ch != null) {
        unawaited(client.removeChannel(ch));
      }
    }

    // 2. Add channels for newly discovered profiles, under the global
    // gates in [_subscribeMissingProfiles].
    _subscribeMissingProfiles(currentIds);
  }

  /// Opens a channel for every profile in [ids] that does not already
  /// have one, under the two global gates: no channel while backgrounded
  /// (issue #842 — [_onResumed] re-runs this from [_lastProfileIds]) and,
  /// with an auth source, no channel while signed out (issue #778 — there
  /// is no authorized identity to bind a fresh subscription to, so the
  /// server rejects it under RLS and every retry would be doomed, the
  /// #771 storm just backoff-tapered; sign-in's [_rebuildChannels]
  /// re-runs this from the recorded profile set instead of waiting for
  /// another profile emission). A coordinator built without an auth
  /// source has no identity concept and subscribes unconditionally.
  void _subscribeMissingProfiles(Iterable<String> ids) {
    if (_lifecyclePaused) return;
    if (auth != null && _boundUserId == null) return;
    for (final id in ids) {
      if (!_channels.containsKey(id)) {
        _subscribeToProfile(id);
      }
    }
  }

  /// Removes every current channel and clears [_channels], returning the
  /// pending removal futures so each caller decides whether to await them:
  /// [dispose] awaits them all concurrently, while [_rebuildChannels] fires
  /// them and moves straight to re-subscribing (the old channels' removal
  /// completing is not a precondition for the new ones). Pending retry
  /// timers, attempts, and statuses are cleared too — a rebuild starts each
  /// profile's backoff over under the new identity.
  List<Future<void>> _clearChannels() {
    _cancelAllRetries();
    _retryAttempts.clear();
    _statuses.clear();
    final removals = _channels.values.map(client.removeChannel).toList();
    _channels.clear();
    return removals;
  }

  void _subscribeToProfile(String profileId) {
    if (_disposed) return;
    _cancelRetry(profileId);
    // `SupabaseClient.channel(name)` delegates to `RealtimeClient.channel`,
    // which itself builds the topic as `'realtime:$topic'` — passing
    // `'realtime:profile:$id'` here would double-prefix the wire topic to
    // `realtime:realtime:profile:<id>`.
    final channelName = 'profile:$profileId';
    final channel = client.channel(channelName);
    // Recorded before subscribing: the status callback can fire
    // synchronously (and [_onSubscribeStatus] ignores callbacks from a
    // channel that is not the current one for the profile).
    _channels[profileId] = channel;

    // Listens on `sync_signals`, not `day_entries`/`profiles` directly
    // (Issue #77 PR #92 review, KTD2 revised): Supabase Realtime's WALRUS
    // decodes with wal2json, which only honors a publication as a
    // table-level membership list — a narrow *publication* column list on
    // the source tables would not have stopped full rows (note/tags/flow)
    // from reaching this callback, because `has_column_privilege` still
    // passes for every column under this app's table-wide `select` grant.
    // `sync_signals` carries no health content by construction, so there is
    // nothing here to discard except a bare change notification — which is
    // exactly what this callback already treated the payload as.
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'sync_signals',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'profile_id',
            value: profileId,
          ),
          callback: (_) => _onRemoteChange(),
        )
        .subscribe((status, _) => _onSubscribeStatus(profileId, channel, status));
  }

  /// Whether a reported [RealtimeSubscribeStatus.subscribed] may clear the
  /// retry backoff (issue #771).
  ///
  /// `RealtimeChannel.subscribe` reports `subscribed` from the Phoenix join's
  /// *optimistic* ack, before the server has finished setting up the
  /// `postgres_changes` replication. If that setup then fails — which is
  /// guaranteed while there is no authorized identity, because RLS rejects
  /// every subscription — the realtime client forwards the failure as
  /// `channelError` on the same channel (its `onSystemEvents` handler). A
  /// `subscribed` that is followed by such a rejection proves nothing about
  /// recovery: if it cleared the counter, every retry's fresh channel would
  /// reset the backoff and the delay would stay pinned at
  /// [kRealtimeRetryBase] forever.
  ///
  /// So with an auth source, only a bound (signed-in) identity can produce a
  /// channel that actually delivers and only then is `subscribed` treated as
  /// recovery. A coordinator built without an auth source has no identity
  /// concept and keeps its previous trust-the-status behavior.
  bool get _canTrustSubscribed => auth == null || _boundUserId != null;

  /// Records a subscription status (AC1) and, on a terminal failure,
  /// logs the kind and schedules a bounded retry (AC2/AC3).
  ///
  /// The [channel] identity guard drops late callbacks from a channel that
  /// has since been replaced (a retry tear-down followed by a fresh
  /// subscribe under the same profile id) so a stale failure cannot
  /// overwrite the replacement's status.
  void _onSubscribeStatus(
    String profileId,
    RealtimeChannel channel,
    RealtimeSubscribeStatus status,
  ) {
    if (_disposed) return;
    if (!identical(_channels[profileId], channel)) return;
    _statuses[profileId] = status;
    if (status == RealtimeSubscribeStatus.subscribed) {
      _cancelRetry(profileId);
      if (_canTrustSubscribed) {
        _retryAttempts.remove(profileId);
      }
      return;
    }
    // Log only the first failure of a degradation episode: each later retry
    // in the same episode is the same problem, so a line per attempt is the
    // unbounded log spam issue #771 reports. A trusted `subscribed` clears
    // the counter above and so starts a fresh episode.
    if ((_retryAttempts[profileId] ?? 0) == 0) {
      _logSubscribeStatus(status);
    }
    _scheduleRetry(profileId);
  }

  /// R18-safe failure log (AC2): the status kind only — an enum name, never
  /// payload, table content, or user id. Same `debugPrint` seam the sync
  /// engine uses for its own kind-only lines.
  void _logSubscribeStatus(RealtimeSubscribeStatus status) {
    debugPrint('lunarlog realtime: subscribe ${status.name}');
  }

  /// Schedules a re-subscribe with capped exponential backoff (AC3). The
  /// timer is per profile so one degraded channel never churns the rest,
  /// and is cancelled by [_cancelRetry]/[_cancelAllRetries] on profile
  /// removal, rebuild, and [dispose].
  void _scheduleRetry(String profileId) {
    if (_disposed) return;
    if (!_lastProfileIds.contains(profileId)) return;
    _cancelRetry(profileId);
    final attempt = (_retryAttempts[profileId] ?? 0) + 1;
    _retryAttempts[profileId] = attempt;
    final delay = _retryDelay(attempt);
    _retryTimers[profileId] = _retryTimerFactory(delay, () => _onRetry(profileId));
  }

  /// `base * 2^(attempt-1)`, capped: 2s, 4s, 8s, … up to 2 minutes.
  Duration _retryDelay(int attempt) {
    final shift = (attempt - 1).clamp(0, 16);
    final scaled = kRealtimeRetryBase.inMilliseconds * (1 << shift);
    return Duration(
        milliseconds:
            scaled.clamp(0, kRealtimeRetryCap.inMilliseconds));
  }

  /// Fires a scheduled retry: tears down the degraded channel and
  /// re-subscribes. Guards mirror [_scheduleRetry] so a profile removed or
  /// a coordinator disposed while the timer was pending does not
  /// re-create a channel.
  void _onRetry(String profileId) {
    _retryTimers.remove(profileId);
    if (_disposed) return;
    if (!_lastProfileIds.contains(profileId)) {
      _retryAttempts.remove(profileId);
      _statuses.remove(profileId);
      return;
    }
    final old = _channels.remove(profileId);
    if (old != null) {
      unawaited(client.removeChannel(old));
    }
    _statuses.remove(profileId);
    _subscribeToProfile(profileId);
  }

  void _cancelRetry(String profileId) {
    final timer = _retryTimers.remove(profileId);
    timer?.cancel();
  }

  void _cancelAllRetries() {
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
  }

  void _onRemoteChange() {
    if (_disposed) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, () {
      if (!_disposed) {
        syncEngine.requestSync();
      }
    });
  }

  /// Closes all Realtime channels and cancels subscriptions.
  ///
  /// The two subscription cancellations are deliberately fire-and-forget
  /// (not awaited): both are backed by real asynchronous work (the auth
  /// stream and a drift query watcher that can hop to a database worker
  /// isolate), so awaiting them here would make every caller's teardown
  /// depend on that being pumped. Safety does not depend on the
  /// cancellation completing before this method returns — [_disposed] is
  /// set first and every callback (`_onProfilesUpdated`, `_onRemoteChange`,
  /// `_onAuthStateChanged`) checks it before doing anything, so a
  /// leftover in-flight event on either stream is a no-op.
  Future<void> dispose() async {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _debounceTimer?.cancel();
    _debounceTimer = null;
    unawaited(_authSubscription?.cancel());
    _authSubscription = null;
    unawaited(_profilesSubscription?.cancel());
    _profilesSubscription = null;

    await Future.wait(_clearChannels());
  }
}
