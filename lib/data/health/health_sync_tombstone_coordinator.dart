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
/// **Issue #936:** that memory is seeded from the persisted device-local
/// [HealthExportLedger] on bind, so a row tombstoned *before this session
/// began* — the common case on iOS, where a fresh process is normal — is
/// still deleted. Previously the remembered set started empty every launch
/// and this was a documented accepted gap. Successfully deleted ids are
/// removed from the ledger so the table does not grow forever.
///
/// Best-effort, like every background upkeep here: a throwing pass is
/// swallowed — the next genuine change re-arms it.
///
/// Pure Dart (R14/R16). Wiring in `app.dart` like the write coordinator.
library;

import 'dart:async';

import 'package:lunarlog/domain/health/health_export_ledger.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_sync_deletion_service.dart';
import 'package:lunarlog/domain/health/health_sync_tombstone_source.dart';
import 'package:lunarlog/domain/models/day_entry.dart';

import 'health_fertility_mapping.dart' show kBbtObservationCategory;
import 'health_flow_mapping.dart' show kSpottingObservationCategory;
import 'health_record_ids.dart';

// The same named-required-parameter pattern the write coordinator uses.
// ignore_for_file: prefer_initializing_formals

class HealthSyncTombstoneCoordinator {
  HealthSyncTombstoneCoordinator({
    required HealthSyncBinding binding,
    required HealthSyncTombstoneSource source,
    required HealthSyncDeletionService deletionService,
    required HealthExportLedger ledger,
    this.debounce = const Duration(milliseconds: 300),
  })  : _binding = binding,
        _source = source,
        _deletionService = deletionService,
        _ledger = ledger;

  final HealthSyncBinding _binding;
  final HealthSyncTombstoneSource _source;
  final HealthSyncDeletionService _deletionService;

  /// The persisted device-local export ledger (Issue #936) — the
  /// cross-session source of the record ids the write path actually
  /// exported. Seeded into [_knownEntryRecordIds]/[_knownObservationRecordIds]
  /// on bind, so a row tombstoned before this session began still has its
  /// record ids to delete.
  final HealthExportLedger _ledger;
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

  /// Every health-store record id each live day entry produced (Issue #924)
  /// — the entry's own flow id plus its symptom, cervical-mucus, and
  /// ovulation-test ids. A day-entry tombstone clears the entry's tags
  /// (`softDeleteDayEntry`), so the derived ids can only be reconstructed
  /// from a live emission the coordinator saw or from the persisted
  /// [HealthExportLedger] (Issue #936, [_seedLedger]) — the cross-session
  /// half that used to be an accepted gap.
  final Map<String, Set<String>> _knownEntryRecordIds = {};

  /// The record id each live observation maps to (Issue #924): a spotting
  /// observation's own id, or `bbt-<id>` for a BBT row. Mirrors
  /// [_knownEntryRecordIds]'s requirement — a tombstone (direct or a
  /// day-entry cascade) nulls `category`, so the post-tombstone row alone
  /// carries no trace of what it used to be. Seeded from the ledger too
  /// (Issue #936).
  final Map<String, String> _knownObservationRecordIds = {};

  /// The profile the coordinator is currently subscribed to (or loading
  /// for) — lets the async ledger seed abandon itself if the binding moved
  /// on before it resolved.
  String? _activeProfileId;

  void start() {
    if (_disposed) return;
    _boundSub = _binding.watchBoundProfileId().listen(_onBoundProfileChanged);
  }

  void _onBoundProfileChanged(String? profileId) {
    if (_disposed) return;
    _resetSubscriptions();
    if (profileId == null) return;
    _activeProfileId = profileId;
    // Issue #936: seed from the persisted ledger BEFORE subscribing, so the
    // source's immediate initial emission cannot race ahead of the seed and
    // schedule a deletion pass with an empty memory.
    unawaited(_subscribeFor(profileId));
  }

  /// Loads [profileId]'s ledger rows and, if the binding has not moved on,
  /// seeds them then subscribes. The write path is the ledger's only
  /// writer, so these are exactly the record ids this device exported.
  Future<void> _subscribeFor(String profileId) async {
    // Best-effort, like every background upkeep here: a storage read that
    // fails (a database closing during shutdown, an unexpected drift error)
    // must not surface as an unhandled async error. Proceeding with an
    // empty seed is the pre-#936 behaviour — only records seen live this
    // session are deletable.
    List<HealthExportLedgerEntry> rows;
    try {
      rows = await _ledger.readForProfile(profileId);
    } catch (_) {
      rows = const [];
    }
    if (_disposed || _activeProfileId != profileId) return;
    _seedLedger(rows);
    _subscribe(profileId);
  }

  /// Seeds the in-memory record-id maps from the persisted ledger (Issue
  /// #936). Entry-kind rows group by their source day-entry id;
  /// spotting/BBT rows map their source observation id to the one record id
  /// they export.
  void _seedLedger(List<HealthExportLedgerEntry> rows) {
    for (final row in rows) {
      switch (row.kind) {
        case HealthExportLedgerKind.entry:
          _knownEntryRecordIds
              .putIfAbsent(row.sourceRowId, () => <String>{})
              .add(row.recordId);
        case HealthExportLedgerKind.spotting:
        case HealthExportLedgerKind.bbt:
          _knownObservationRecordIds[row.sourceRowId] = row.recordId;
      }
    }
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
    _activeProfileId = null;
  }

  void _subscribe(String profileId) {
    _entriesSub = _source.watchDayEntries(profileId).listen((entries) {
      for (final entry in entries) {
        if (entry.deletedAt == null) {
          _knownEntryRecordIds[entry.id] = healthRecordIdsForEntry(entry);
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
        // Issue #936: the persisted ledger rows go with the successfully
        // deleted store samples, so the table does not grow forever. This
        // runs BEFORE the ids join _alreadyDeleted: a ledger-write failure
        // must leave the ids retryable (a second delete of an already-gone
        // sample is a documented no-op) rather than stranding the rows.
        await _ledger.removeRecordIds(tombstoned);
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
