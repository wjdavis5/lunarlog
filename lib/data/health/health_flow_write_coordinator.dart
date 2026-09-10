/// The debounced trigger for the #193 health-flow write path, mirroring
/// `lib/data/sharing/prediction_projection_publisher.dart`'s stream
/// fan-in and disposal discipline (and, like it, the reminder-window
/// publisher before that): watch the device's health-store binding, and
/// while one exists, run [HealthFlowWriteService.syncNow] — debounced —
/// whenever anything that could change the bound profile's data does.
///
/// What it subscribes to:
///
/// * `HealthSyncBinding.watchBoundProfileId` — the opt-in switch. A
///   transition away from a previously-seen binding (unbind, or a replace)
///   calls the service's unbind path first, so the forward-only cursor and
///   the native-side binding mirror never survive a binding change; a
///   fresh binding then syncs from its own new grant moment. The initial
///   emission of an already-bound profile (app startup) deliberately does
///   **not** clear anything — the cursor is durable across restarts.
/// * `DayEntriesRepository.watchForProfile(bound)` — emits the current
///   list immediately on subscribe (the pass that catches up whatever was
///   logged since the last cursor) and again on every write or tombstone,
///   each debounced into at most one pass per [debounce] window.
///
/// Best-effort, like every background upkeep here: a throwing pass is
/// swallowed (the service surfaces its own expected failures as a
/// [HealthFlowSyncReport]), never propagated into the subscription — the
/// next genuine change re-arms it.
///
/// Pure Dart (R14/R16). Wiring (iOS-only until #202) lives in `app.dart`,
/// exactly where the other publishers are constructed and disposed.
library;

import 'dart:async';

import 'package:lunarlog/domain/health/health_flow_write_coordinator.dart'
    as domain;
import 'package:lunarlog/domain/health/health_flow_write_service.dart' as domain;
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';

// Named required parameters cannot be initializing formals; the private
// finals below are assigned through the constructor's initializer list
// (the prediction-projection publisher's declared pattern).
// ignore_for_file: prefer_initializing_formals

class HealthFlowWriteCoordinator implements domain.HealthFlowWriteCoordinator {
  HealthFlowWriteCoordinator({
    required HealthSyncBinding binding,
    required DayEntriesRepository dayEntries,
    required domain.HealthFlowWriteService service,
    this.debounce = const Duration(milliseconds: 500),
  })  : _binding = binding,
        _dayEntries = dayEntries,
        _service = service;

  final HealthSyncBinding _binding;
  final DayEntriesRepository _dayEntries;
  final domain.HealthFlowWriteService _service;
  final Duration debounce;

  StreamSubscription<String?>? _boundSub;
  StreamSubscription<List<DayEntry>>? _entriesSub;
  Timer? _debounceTimer;
  String? _lastBoundId;
  bool _disposed = false;

  @override
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
    if (previous == null) {
      // First emission this process: an already-bound profile starts
      // syncing under its existing cursor; unbound stays idle.
      if (profileId != null) _subscribeEntries(profileId);
      return;
    }
    if (profileId == null) {
      // Explicit unbind: retire the cursor and the native mirror.
      unawaited(_service.onUnbound());
      return;
    }
    // A replace (bind while bound): the old binding's consent is retired
    // before the new one syncs, so the new profile's history is not
    // backfilled under the old cursor.
    unawaited(_service.onUnbound().then((_) {
      if (_disposed || _lastBoundId != profileId) return;
      _subscribeEntries(profileId);
      _scheduleSync();
    }));
  }

  void _subscribeEntries(String profileId) {
    _entriesSub = _dayEntries.watchForProfile(profileId).listen((_) {
      _scheduleSync();
    });
  }

  void _scheduleSync() {
    if (_disposed) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      _debounceTimer = null;
      unawaited(_runSync());
    });
  }

  Future<void> _runSync() async {
    try {
      await _service.syncNow();
    } catch (_) {
      // Best-effort background upkeep — see the library doc. The next
      // entry change (or app restart) re-arms the pass.
    }
  }

  @override
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
