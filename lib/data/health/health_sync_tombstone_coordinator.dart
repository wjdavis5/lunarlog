/// The tombstone-propagation trigger for Issue #186 (AC6), mirroring
/// `health_flow_write_coordinator.dart`'s stream fan-in: watch the health
/// store binding and the bound profile's day entries and observations, and
/// whenever either is soft-deleted (tombstoned), hand the record ids of
/// every health-store sample it produced to
/// [HealthSyncDeletionService.deleteSamples], so the corresponding sample is
/// deleted rather than orphaned.
///
/// A deletion is only meaningful for records this device actually wrote to
/// the store; a tombstoned row that was never exported simply matches
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
/// **Issue #924:** the coordinator no longer relays only a day entry's own
/// id. Because #238/#228 write symptom, cervical-mucus, and ovulation-test
/// samples whose record ids embed the day entry id (and BBT samples keyed by
/// the observation id), it remembers **every record id each live row
/// produced** — via `health_record_ids.dart`'s builders, the same ones the
/// write path uses — and relays the whole set on a tombstone. Without this,
/// a widened native delete would still never be asked for the right ids.
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

import 'health_fertility_mapping.dart'
    show
        kBbtObservationCategory,
        resolveCervicalMucus,
        resolveOvulationTests;
import 'health_flow_mapping.dart' show kSpottingObservationCategory;
import 'health_record_ids.dart';
import 'health_symptom_mapping.dart' show resolveHealthKitSymptoms;

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

  /// Every health-store record id each live day entry produced this process
  /// (Issue #924) — the entry's own flow id plus its symptom,
  /// cervical-mucus, and ovulation-test ids. A day-entry tombstone clears
  /// the entry's tags (`softDeleteDayEntry`), so the derived ids can only be
  /// reconstructed from a live emission the coordinator already saw — the
  /// same accepted gap [_knownObservationRecordIds] documents for a row
  /// tombstoned before this session began.
  final Map<String, Set<String>> _knownEntryRecordIds = {};

  /// The record id each live observation maps to (Issue #924): a spotting
  /// observation's own id, or `bbt-<id>` for a BBT row. Mirrors
  /// [_knownEntryRecordIds]'s "remember it live" requirement — a tombstone
  /// (direct or a day-entry cascade) nulls `category`, so the post-tombstone
  /// row alone carries no trace of what it used to be.
  final Map<String, String> _knownObservationRecordIds = {};

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
    _knownEntryRecordIds.clear();
    _knownObservationRecordIds.clear();
  }

  void _subscribe(String profileId) {
    _entriesSub = _source.watchDayEntries(profileId).listen((entries) {
      for (final entry in entries) {
        if (entry.deletedAt == null) {
          _knownEntryRecordIds[entry.id] = _recordIdsForEntry(entry);
        }
      }
      _latestEntries = entries;
      _scheduleDeletion();
    });
    _observationsSub =
        _source.watchObservations(profileId).listen((observations) {
      for (final observation in observations) {
        if (observation.deletedAt != null) continue;
        final recordId = _recordIdForObservation(observation);
        if (recordId != null) {
          _knownObservationRecordIds[observation.id] = recordId;
        }
      }
      _latestObservations = observations;
      _scheduleDeletion();
    });
  }

  /// Every health-store record id a live [entry] can have produced (Issue
  /// #924): its flow/marker id itself, plus the symptom, cervical-mucus, and
  /// ovulation ids the write path derives from the entry's tags. Uses the
  /// same builders (`health_record_ids.dart`) and resolvers as
  /// `health_flow_write_service.dart`, so deletion cannot address an id the
  /// write path never wrote. Severity is irrelevant to the id, so the graded
  /// pain map is deliberately empty.
  Set<String> _recordIdsForEntry(DayEntry entry) {
    final ids = <String>{healthFlowRecordId(entry.id)};
    for (final symptom in resolveHealthKitSymptoms(
      tags: entry.tags,
      gradedPainIntensities: const <String, int>{},
    )) {
      ids.add(healthSymptomRecordId(entry.id, symptom.typeIdentifier));
    }
    if (resolveCervicalMucus(entry.tags) != null) {
      ids.add(healthCervicalMucusRecordId(entry.id));
    }
    for (final ovulation in resolveOvulationTests(entry.tags)) {
      ids.add(healthOvulationRecordId(entry.id, ovulation.healthKitResult));
    }
    return ids;
  }

  /// The record id a live [observation] maps to, or null for a category the
  /// app never exports — a record this device never wrote is never
  /// requested.
  String? _recordIdForObservation(HealthTombstoneObservation observation) =>
      switch (observation.category) {
        kSpottingObservationCategory => healthSpottingRecordId(observation.id),
        kBbtObservationCategory => healthBbtRecordId(observation.id),
        _ => null,
      };

  void _scheduleDeletion() {
    if (_disposed) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      _debounceTimer = null;
      unawaited(_runDeletion());
    });
  }

  /// Every not-yet-deleted record id belonging to a tombstoned row: a day
  /// entry's remembered derived ids (falling back to its own id when it was
  /// never seen live), and each observation's remembered record id.
  List<String> _collectTombstoned() {
    final ids = <String>{};
    for (final entry in _latestEntries) {
      if (entry.deletedAt == null) continue;
      ids.addAll(
        _knownEntryRecordIds[entry.id] ?? {healthFlowRecordId(entry.id)},
      );
    }
    for (final observation in _latestObservations) {
      if (observation.deletedAt == null) continue;
      final recordId = _knownObservationRecordIds[observation.id];
      if (recordId != null) ids.add(recordId);
    }
    return [
      for (final id in ids)
        if (!_alreadyDeleted.contains(id)) id,
    ];
  }

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
