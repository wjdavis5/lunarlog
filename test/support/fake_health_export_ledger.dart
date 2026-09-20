/// In-memory [HealthExportLedger] for tests (Issue #936) — the same
/// read/record/remove semantics as `DriftHealthExportLedger`, without a
/// database, so the deletion paths' cross-session behaviour can be exercised
/// under `flutter test`.
library;

import 'package:lunarlog/domain/health/health_export_ledger.dart';

class FakeHealthExportLedger implements HealthExportLedger {
  final Map<String, HealthExportLedgerEntry> _rows = {};

  /// When set, [readForProfile] throws it once (mirrors a storage read
  /// failing while a coordinator seeds itself).
  Object? throwOnRead;

  @override
  Future<List<HealthExportLedgerEntry>> readForProfile(String profileId) async {
    final toThrow = throwOnRead;
    if (toThrow != null) {
      throwOnRead = null;
      throw toThrow;
    }
    return [
      for (final row in _rows.values)
        if (row.profileId == profileId) row,
    ];
  }

  @override
  Future<void> record(Iterable<HealthExportLedgerEntry> entries) async {
    for (final entry in entries) {
      _rows[entry.recordId] = entry;
    }
  }

  @override
  Future<void> removeRecordIds(Iterable<String> recordIds) async {
    for (final id in recordIds) {
      _rows.remove(id);
    }
  }

  @override
  Future<void> clearProfile(String profileId) async {
    _rows.removeWhere((_, row) => row.profileId == profileId);
  }

  @override
  Future<void> clearAll() async => _rows.clear();

  /// Every row currently persisted (test introspection only).
  List<HealthExportLedgerEntry> get rows => _rows.values.toList();
}
