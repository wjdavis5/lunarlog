/// The tombstone-propagation trigger for Issue #186 (AC6), mirroring
/// `health_flow_write_coordinator.dart`'s stream fan-in: watch the health
/// store binding and the bound profile's day entries and spotting
/// observations, and whenever either is soft-deleted (tombstoned), hand its
/// ULID to [HealthSyncDeletionService.deleteSamples] so the corresponding
/// health store sample is deleted rather than orphaned.
///
/// A deletion is only meaningful for entries this device actually wrote to
/// the store; a tombstoned entry that was never exported simply matches
/// nothing on the native side (a harmless no-op delete). Forward-only /
/// grant semantics are the write flow's concern (#193) — this coordinator
/// only reacts to tombstones, which are safe to delete regardless of the
/// write cursor.
///
/// **Issue #619, LLA-018:** this coordinator watches
/// [HealthSyncTombstoneSource] — a full-fidelity, tombstones-included
/// stream — never `DayEntriesRepository.watchForProfile`, which filters
/// tombstoned rows for UI reads and so could never carry the deletions this
/// coordinator exists to relay. **LLA-019:** an id is recorded into
/// [_alreadyDeleted] only once [HealthSyncDeletionService.deleteSamples]
/// reports no refusal, so a refused or throwing attempt is retried by the
/// next entries/observations change rather than being silently treated as
/// done. **LLA-020:** a spotting observation's own id — not its parent day
/// entry's — is what the write path used as the platform's `recordId`, so
/// this coordinator separately tracks and deletes tombstoned spotting
/// observations (whether tombstoned directly, or cascaded from their
/// parent day entry's own deletion, Issue #470).
///
/// Best-effort, like every background upkeep here: a throwing pass is
/// swallowed — the next genuine change re-arms it.
///
/// Pure Dart (R14/R16). Wiring in `app.dart` like the write coordinator.
library;

import 'dart:async';

import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_sync_deletion_service.dart';
import 'package:lunarlog/domain/health/health_sync_tombstone_source.dart';
import 'package:lunarlog/domain/models/day_entry.dart';

import 'health_flow_mapping.dart' show kSpottingObservationCategory;

// The same named-required-parameter pattern the write coordinator uses.
// ignore_for_file: prefer_initializing_formals

class HealthSyncTombstoneCoordinator {
  HealthSyncTombstoneCoordinator({
    required HealthSyncBinding binding,
    required HealthSyncTombstoneSource source,
    required HealthSyncDeletionService deletionService,
    this.debounce = const Duration(milliseconds: 300),
  })  : _binding = binding,
        _source = source,
        _deletionService = deletionService;

  final HealthSyncBinding _binding;
  final HealthSyncTombstoneSource _source;
  final HealthSyncDeletionService _deletionService;
  final Duration debounce;

  StreamSubscription<String?>? _boundSub;
  StreamSubscription<List<DayEntry>>? _entriesSub;
  StreamSubscription<List<HealthTombstoneObservation>>? _observationsSub;
  Timer? _debounceTimer;
  bool _disposed = false;

  /// The last-seen set of "already-deleted" ids (day entries and
  /// observations share one namespace of ULIDs), so a repeated emission of
  /// the same tombstone is not re-deleted every time, and so a refused
  /// deletion (LLA-019) is never marked done.
  Set<String> _alreadyDeleted = const {};

  /// The latest emission from each watch, combined on every deletion pass.
  List<DayEntry> _latestEntries = const [];
  List<HealthTombstoneObservation> _latestObservations = const [];

  /// Ids ever seen live with `category == 'spotting'` this process
  /// (LLA-020) — a cascade tombstone (Issue #470) clears `category`, so
  /// recognising the deletion of a spotting observation requires having
  /// already seen it live. Mirrors the existing, accepted gap for day
  /// entries tombstoned before this coordinator started this session.
  final Set<String> _knownSpottingIds = {};

  void start() {
    if (_disposed) return;
    _boundSub = _binding.watchBoundProfileId().listen(_onBoundProfileChanged);
  }

  void _onBoundProfileChanged(String? profileId) {
    if (_disposed) return;
    _resetSubscriptions();
    if (profileId == null) return;
    _subscribe(profileId);
  }

  void _resetSubscriptions() {
    final previousEntriesSub = _entriesSub;
    final previousObservationsSub = _observationsSub;
    _entriesSub = null;
    _observationsSub = null;
    if (previousEntriesSub != null) unawaited(previousEntriesSub.cancel());
    if (previousObservationsSub != null) {
      unawaited(previousObservationsSub.cancel());
    }
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _alreadyDeleted = const {};
    _latestEntries = const [];
    _latestObservations = const [];
    _knownSpottingIds.clear();
  }

  void _subscribe(String profileId) {
    _entriesSub = _source.watchDayEntries(profileId).listen((entries) {
      _latestEntries = entries;
      _scheduleDeletion();
    });
    _observationsSub =
        _source.watchObservations(profileId).listen((observations) {
      for (final observation in observations) {
        if (observation.deletedAt == null &&
            observation.category == kSpottingObservationCategory) {
          _knownSpottingIds.add(observation.id);
        }
      }
      _latestObservations = observations;
      _scheduleDeletion();
    });
  }

  void _scheduleDeletion() {
    if (_disposed) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      _debounceTimer = null;
      unawaited(_runDeletion());
    });
  }

  /// Every not-yet-deleted tombstoned id across both watches: day entries
  /// outright, and observations whose id was seen live as spotting
  /// ([_knownSpottingIds]) before it was tombstoned — directly or via its
  /// parent day entry's cascade (Issue #470).
  List<String> _collectTombstoned() => [
        for (final entry in _latestEntries)
          if (entry.deletedAt != null && !_alreadyDeleted.contains(entry.id))
            entry.id,
        for (final observation in _latestObservations)
          if (observation.deletedAt != null &&
              _knownSpottingIds.contains(observation.id) &&
              !_alreadyDeleted.contains(observation.id))
            observation.id,
      ];

  Future<void> _runDeletion() async {
    final tombstoned = _collectTombstoned();
    if (tombstoned.isEmpty) return;
    try {
      final report = await _deletionService.deleteSamples(tombstoned);
      // LLA-019: only ids the service did not report as blocked are
      // recorded done — a refusal (transient permission/provider failure)
      // must be retried by the next change, not silently swallowed.
      if (report.blocked == null) {
        _alreadyDeleted = {..._alreadyDeleted, ...tombstoned};
      }
    } catch (_) {
      // Best-effort background upkeep — the next change re-arms it, and
      // since _alreadyDeleted was never updated, these same ids retry too.
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _boundSub?.cancel();
    _boundSub = null;
    await _entriesSub?.cancel();
    _entriesSub = null;
    await _observationsSub?.cancel();
    _observationsSub = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }
}
