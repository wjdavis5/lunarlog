/// Supabase Realtime sync coordinator (U6; KTD6). Subscribes to Realtime
/// channels for shared profiles and triggers debounced sync cycles when
/// co-caregivers push changes. Issue #77 (KTD2, KTD3) added the
/// backend publication that makes the channels actually emit, and the
/// sign-in channel rebuild below.
library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/auth/auth_service.dart';
import '../../domain/sync/sync_engine.dart';
import '../db/db.dart';
import '../db/storage.dart';

class RealtimeSyncCoordinator {
  RealtimeSyncCoordinator({
    required this.client,
    required this.syncEngine,
    required this.storage,
    this.auth,
    this.debounceDuration = const Duration(milliseconds: 500),
  });

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

  final Map<String, RealtimeChannel> _channels = {};
  StreamSubscription<List<Profile>>? _profilesSubscription;
  StreamSubscription<AuthSessionState>? _authSubscription;
  Timer? _debounceTimer;
  bool _disposed = false;

  /// The profile set from the most recent [storage] emission, kept so a
  /// sign-in/sign-out identity change can rebuild channels without waiting
  /// for another watch emission.
  List<Profile> _lastProfiles = const [];

  /// The signed-in user id channels are currently subscribed under, or null
  /// while signed out. Only a *change* of this value triggers a rebuild —
  /// a token refresh that leaves the identity the same must not churn
  /// channels.
  String? _boundUserId;

  /// Starts watching local profiles and subscribes to Realtime channels.
  void start() {
    if (_disposed) return;
    final auth = this.auth;
    if (auth != null) {
      _boundUserId = _identityOf(auth);
      _authSubscription = auth.states.listen((_) => _onAuthStateChanged());
    }
    _profilesSubscription = storage.watchProfiles().listen(_onProfilesUpdated);
  }

  String? _identityOf(AuthService auth) =>
      auth.state == AuthSessionState.signedIn ? auth.currentUserId : null;

  void _onAuthStateChanged() {
    if (_disposed) return;
    final auth = this.auth;
    if (auth == null) return;
    final identity = _identityOf(auth);
    if (identity == _boundUserId) return;
    _boundUserId = identity;
    _rebuildChannels();
  }

  /// Tears down every current channel and, while a user is signed in,
  /// re-subscribes from the last-known profile set under the new identity
  /// (KTD3). A transition to signed-out removes channels and stops there —
  /// there is no authorized identity to bind a fresh subscription to, so
  /// resubscribing would just open channels the server will reject.
  void _rebuildChannels() {
    for (final ch in _channels.values) {
      client.removeChannel(ch);
    }
    _channels.clear();
    if (_boundUserId == null) return;
    for (final profile in _lastProfiles) {
      _subscribeToProfile(profile.id);
    }
  }

  void _onProfilesUpdated(List<Profile> profiles) {
    if (_disposed) return;
    _lastProfiles = profiles;
    final currentIds = profiles.map((p) => p.id).toSet();

    // 1. Remove channels for profiles no longer present.
    final toRemove = _channels.keys.where((id) => !currentIds.contains(id)).toList();
    for (final id in toRemove) {
      final ch = _channels.remove(id);
      if (ch != null) {
        client.removeChannel(ch);
      }
    }

    // 2. Add channels for newly discovered profiles.
    for (final id in currentIds) {
      if (!_channels.containsKey(id)) {
        _subscribeToProfile(id);
      }
    }
  }

  void _subscribeToProfile(String profileId) {
    // `SupabaseClient.channel(name)` delegates to `RealtimeClient.channel`,
    // which itself builds the topic as `'realtime:$topic'` — passing
    // `'realtime:profile:$id'` here would double-prefix the wire topic to
    // `realtime:realtime:profile:<id>`.
    final channelName = 'profile:$profileId';
    final channel = client.channel(channelName);

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'day_entries',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'profile_id',
            value: profileId,
          ),
          callback: (_) => _onRemoteChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: profileId,
          ),
          callback: (_) => _onRemoteChange(),
        )
        .subscribe();

    _channels[profileId] = channel;
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
    _debounceTimer?.cancel();
    _debounceTimer = null;
    unawaited(_authSubscription?.cancel());
    _authSubscription = null;
    unawaited(_profilesSubscription?.cancel());
    _profilesSubscription = null;

    for (final ch in _channels.values) {
      await client.removeChannel(ch);
    }
    _channels.clear();
  }
}
