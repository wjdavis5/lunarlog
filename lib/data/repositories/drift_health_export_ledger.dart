/// Drift-backed [HealthExportLedger] (Issue #936) over the device-local
/// `health_export_ledger` table — the concrete half of the persisted
/// health-store export ledger. Deliberately never part of any server sync
/// path (`health_export_ledger` is not in the `SyncTable` remote set, so
/// `sync_push`/`remote_rows.dart`/`row_codec.dart` cannot see it), wired
/// through `app_dependencies.dart`.
library;

import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/health/health_export_ledger.dart';

class DriftHealthExportLedger implements HealthExportLedger {
  DriftHealthExportLedger(this.storage);

  final HealthDeviceStore storage;

  @override
  Future<List<HealthExportLedgerEntry>> readForProfile(String profileId) async {
    final rows = await storage.readHealthExportLedger(profileId);
    return [
      for (final row in rows)
        if (_kindFromDb(row.kind) case final kind?)
          HealthExportLedgerEntry(
            recordId: row.recordId,
            profileId: row.profileId,
            sourceRowId: row.sourceRowId,
            kind: kind,
            localDate: row.localDate,
            exportedAt: row.exportedAt.toUtc(),
          ),
    ];
  }

  @override
  Future<void> record(Iterable<HealthExportLedgerEntry> entries) =>
      storage.upsertHealthExportLedgerRows([
        for (final entry in entries)
          HealthExportLedgerRowData(
            recordId: entry.recordId,
            profileId: entry.profileId,
            sourceRowId: entry.sourceRowId,
            kind: entry.kind.name,
            localDate: entry.localDate,
            exportedAt: entry.exportedAt.toUtc(),
          ),
      ]);

  @override
  Future<void> removeRecordIds(Iterable<String> recordIds) =>
      storage.deleteHealthExportLedgerRecordIds(recordIds.toList());

  @override
  Future<void> clearProfile(String profileId) =>
      storage.deleteHealthExportLedgerForProfile(profileId);

  @override
  Future<void> clearAll() => storage.clearHealthExportLedger();

  /// Null for a `kind` this build does not know. A later build wrote the
  /// row, and this one leaves it and its record alone: it is not read,
  /// so nothing here writes, deletes or forgets it. It stays in the
  /// table for the build that knows it.
  ///
  /// It used to read as [HealthExportLedgerKind.entry]. That was safe
  /// only while nothing acted on an entry record whose source row is no
  /// live day. Since Issue #1589 the write pass deletes exactly those
  /// from the health store.
  static HealthExportLedgerKind? _kindFromDb(String value) =>
      HealthExportLedgerKind.values.asNameMap()[value];
}
