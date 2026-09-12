/// The tombstone-propagation trigger for Issue #186 (AC6), mirroring
/// `health_flow_write_coordinator.dart`'s stream fan-in: watch the health
/// store binding and the bound profile's day entries; whenever entries are
/// soft-deleted (tombstoned), hand their ULIDs to
/// [HealthSyncDeletionService.deleteSamples] so the corresponding health
/// store samples are deleted rather than orphaned.
///
/// A deletion is only meaningful for entries this device actually wrote to
/// the store; a tombstoned entry that was never exported simply matches
/// nothing on the native side (a harmless no-op delete). Forward-only /
/// grant semantics are the write flow's concern (#193) — this coordinator
/// only reacts to tombstones, which are safe to delete regardless of the
/// write cursor.
///
/// Best-effort, like every background upkeep here: a throwing pass is
/// swallowed — the next genuine change re-arms it.
///
/// Pure Dart (R14/R16). Wiring in `app.dart` like the write coordinator.
library;

import 'dart:async';

import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_sync_deletion_service.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';

// The same named-required-parameter pattern the write coordinator uses.
// ignore_for_file: prefer_initializing_formals

class HealthSyncTombstoneCoordinator {
  HealthSyncTombstoneCoordinator({
    required HealthSyncBinding binding,
    required DayEntriesRepository dayEntries,
    required HealthSyncDeletionService deletionService,
    this.debounce = const Duration(milliseconds: 300),
  })  : _binding = binding,
        _dayEntries = dayEntries,
        _deletionService = deletionService;

  final HealthSyncBinding _binding;
  final DayEntriesRepository _dayEntries;
  final HealthSyncDeletionService _deletionService;
  final Duration debounce;

  StreamSubscription<String?>? _boundSub;
  StreamSubscription<List<DayEntry>>? _entriesSub;
  Timer? _debounceTimer;
  String? _lastBoundId;
  bool _disposed = false;

  /// The last-seen set of "already-deleted" entry ids, so a repeated
  /// emission of the same tombstone is not re-deleted every time.
  Set<String> _alreadyDeleted = const {};

  void start() {
    if (_disposed) return;
    _boundSub = _binding.watchBoundProfileId().listen(_onBoundProfileChanged);
  }

  void _onBoundProfileChanged(String? profileId) {
    if (_disposed) return;
    final previous = _lastBoundId;
    _lastBoundId = profileId;
    final previousEntriesSub = _entriesSub;
    _entriesSub = null;
    if (previousEntriesSub != null) unawaited(previousEntriesSub.cancel());
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _alreadyDeleted = const {};
    if (profileId == null) return;
    if (previous == null) {
      // First emission this process: watch from here; tombstones before the
      // coordinator started are the importer's concern, not this reactive
      // trigger's.
      _subscribeEntries(profileId);
      return;
    }
    // A replace (bind while bound): the old profile's tombstones are
    // retired; watch the new one.
    _subscribeEntries(profileId);
  }

  void _subscribeEntries(String profileId) {
    _entriesSub = _dayEntries.watchForProfile(profileId).listen((entries) {
      _scheduleDeletion(entries);
    });
  }

  void _scheduleDeletion(List<DayEntry> entries) {
    if (_disposed) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      _debounceTimer = null;
      unawaited(_runDeletion(entries));
    });
  }

  Future<void> _runDeletion(List<DayEntry> entries) async {
    try {
      final tombstoned = [
        for (final entry in entries)
          if (entry.deletedAt != null && !_alreadyDeleted.contains(entry.id))
            entry.id,
      ];
      if (tombstoned.isEmpty) return;
      _alreadyDeleted = {..._alreadyDeleted, ...tombstoned};
      await _deletionService.deleteSamples(tombstoned);
    } catch (_) {
      // Best-effort background upkeep — the next change re-arms it.
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _boundSub?.cancel();
    _boundSub = null;
    await _entriesSub?.cancel();
    _entriesSub = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }
}
