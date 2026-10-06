/// What this phone remembers having written to the health store (Issue
/// #1581): the persisted [HealthExportLedger], read once and kept in
/// memory beside it, with the two questions the write pass asks of it.
///
/// * [holds]: is this record in the store at this version of its row? A
///   record the pass wrote is remembered with its row's `updatedAt`, so a
///   row that has changed since, or was never written, is not held and is
///   due.
/// * [recordIdsOf]: which records did this row put in the store? Whatever
///   the row no longer produces is taken out again.
///
/// Only a write the store accepted is remembered, and only a delete it
/// accepted is forgotten. So a record that could not be written (its type
/// is switched off, the write failed) stays due, and one that could not be
/// removed stays remembered, however many passes go by.
///
/// The tombstone coordinator reads and trims the same persisted ledger on
/// its own. This copy can therefore remember a record the coordinator has
/// already deleted; the only effect is one more delete of a record that is
/// not there, which the store ignores.
///
/// Pure Dart (R14/R16).
library;

import 'package:lunarlog/domain/health/health_export_ledger.dart';

class HealthExportMemory {
  HealthExportMemory(this._ledger);

  final HealthExportLedger _ledger;

  /// The profile the maps below hold rows for; null until [load].
  String? _profileId;

  final Map<String, HealthExportLedgerEntry> _byRecord = {};
  final Map<String, Set<String>> _bySourceRow = {};

  /// Reads the ledger for [profileId], once. A relaunch starts with nothing
  /// in memory (on iOS a fresh process is the common case, Issue #936), so
  /// every pass calls this first.
  Future<void> load(String profileId) async {
    if (_profileId == profileId) return;
    _clear();
    for (final entry in await _ledger.readForProfile(profileId)) {
      _index(entry);
    }
    _profileId = profileId;
  }

  /// Whether [recordId] was written for its row as it stood at [version],
  /// or later.
  bool holds(String recordId, DateTime version) {
    final written = _byRecord[recordId];
    return written != null && !written.exportedAt.isBefore(version);
  }

  /// What is remembered about [recordId], or null.
  HealthExportLedgerEntry? entryOf(String recordId) => _byRecord[recordId];

  /// Whether any record written from the row [sourceRowId] is remembered.
  bool knowsRow(String sourceRowId) =>
      _bySourceRow[sourceRowId]?.isNotEmpty ?? false;

  /// The records written from the row [sourceRowId].
  Set<String> recordIdsOf(String sourceRowId) =>
      {...?_bySourceRow[sourceRowId]};

  /// Every remembered record of [kind].
  List<HealthExportLedgerEntry> ofKind(HealthExportLedgerKind kind) => [
        for (final entry in _byRecord.values)
          if (entry.kind == kind) entry,
      ];

  /// Remembers [entries] as written, here and in the persisted ledger. A
  /// record written again replaces what was remembered for it.
  Future<void> remember(Iterable<HealthExportLedgerEntry> entries) async {
    final written = entries.toList();
    if (written.isEmpty) return;
    await _ledger.record(written);
    for (final entry in written) {
      _unindex(entry.recordId);
      _index(entry);
    }
  }

  /// Forgets [recordIds], here and in the persisted ledger: the store has
  /// let them go.
  Future<void> forget(Iterable<String> recordIds) async {
    final gone = recordIds.toList();
    if (gone.isEmpty) return;
    await _ledger.removeRecordIds(gone);
    gone.forEach(_unindex);
  }

  /// Forgets everything on the device (unbind): the remembered records
  /// belong to one binding.
  Future<void> reset() async {
    _clear();
    await _ledger.clearAll();
  }

  void _clear() {
    _byRecord.clear();
    _bySourceRow.clear();
    _profileId = null;
  }

  void _index(HealthExportLedgerEntry entry) {
    _byRecord[entry.recordId] = entry;
    _bySourceRow.putIfAbsent(entry.sourceRowId, () => {}).add(entry.recordId);
  }

  void _unindex(String recordId) {
    final entry = _byRecord.remove(recordId);
    if (entry == null) return;
    final ofRow = _bySourceRow[entry.sourceRowId];
    if (ofRow == null) return;
    ofRow.remove(recordId);
    if (ofRow.isEmpty) _bySourceRow.remove(entry.sourceRowId);
  }
}
