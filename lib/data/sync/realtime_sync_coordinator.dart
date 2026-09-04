/// Supabase Realtime sync coordinator (U6; KTD6).
///
/// Subscribes to Supabase Realtime channels for shared profiles and triggers
/// debounced sync cycles when co-caregivers push changes.
library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/sync/sync_engine.dart';
import '../db/storage.dart';

class RealtimeSyncCoordinator {
  RealtimeSyncCoordinator({
    required this.client,
    required this.syncEngine,
    required this.storage,
    this.debounceDuration = const Duration(milliseconds: 500),
  });

  final SupabaseClient client;
  final SyncEngine syncEngine;
  final LunarLogStorage storage;
  final Duration debounceDuration;

  final Map<String, RealtimeChannel> _channels = {};
  StreamSubscription? _profilesSubscription;
  Timer? _debounceTimer;
  bool _disposed = false;

  /// Starts watching local profiles and subscribes to Realtime channels.
  void start() {
    if (_disposed) return;
    _profilesSubscription = storage.watchProfiles().listen(_onProfilesUpdated);
  }

  void _onProfilesUpdated(List<dynamic> profiles) {
    if (_disposed) return;

    final currentIds = profiles.map((p) => p.id as String).toSet();

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
    final channelName = 'realtime:profile:$profileId';
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
  Future<void> dispose() async {
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _profilesSubscription?.cancel();
    _profilesSubscription = null;

    for (final ch in _channels.values) {
      await client.removeChannel(ch);
    }
    _channels.clear();
  }
}
