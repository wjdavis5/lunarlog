part of 'storage.dart';

// The device-local health tables, extracted out of `LunarLogStorage` into
// their own class (issue #551 problem 1, part 1 step 3), following
// `SyncCursorStorage`'s template extraction (step 2).
//
// `HealthDeviceStorage` implements `HealthDeviceStore` — the
// `health_sync_state` anchor (issue #186) and the `health_export_ledger`
// rows (issue #936). Both tables are deliberately never synced to the
// server, so the role carries no clock, no dirty flags, and no
// remote-apply half: every member is a plain read or write over the same
// drift database `LunarLogStorage` uses. `LunarLogStorage` keeps
// implementing the role by delegating every member to its own
// `HealthDeviceStorage` (the `LunarLogStorageHealthDevice` mixin below), so
// every existing consumer and test compiles and behaves exactly as before.

/// The device-local `health_sync_state` anchor and `health_export_ledger`
/// rows (issues #186/#936), extracted verbatim from `LunarLogStorage`
/// (issue #551 part 1 step 3). Constructed with the same drift database the
/// storage uses; every member is a pure move.
class HealthDeviceStorage implements HealthDeviceStore {
  HealthDeviceStorage(this.db);

  final LunarLogDatabase db;

  /// The device-local `health_sync_state` anchor for [platform], or null
  /// when never written (Issue #186 — never synced to the server).
  @override
  Future<HealthSyncStateRow?> readHealthSyncAnchor(String platform) async {
    final row = await (db.select(db.healthSyncState)
          ..where((t) => t.platform.equals(platform)))
        .getSingleOrNull();
    return row;
  }

  /// Every device-local `health_export_ledger` row for [profileId] (Issue
  /// #936 — never synced to the server).
  @override
  Future<List<HealthExportLedgerRowData>> readHealthExportLedger(
    String profileId,
  ) =>
      (db.select(db.healthExportLedger)
            ..where((t) => t.profileId.equals(profileId)))
          .get();

  /// Upserts the device-local `health_sync_state` anchor for its platform
  /// (Issue #186 — never synced to the server; keyed by `platform`).
  @override
  Future<void> writeHealthSyncAnchor(HealthSyncStateRow anchor) async {
    await db
        .into(db.healthSyncState)
        .insertOnConflictUpdate(anchor.toCompanion(false));
  }

  /// Upserts device-local `health_export_ledger` rows keyed by `record_id`
  /// (Issue #936 — never synced to the server).
  @override
  Future<void> upsertHealthExportLedgerRows(
    List<HealthExportLedgerRowData> rows,
  ) async {
    if (rows.isEmpty) return;
    await db.batch((batch) {
      batch.insertAll(
        db.healthExportLedger,
        rows,
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  /// Removes `health_export_ledger` rows by record id (Issue #936) — called
  /// once the corresponding store samples have actually been deleted.
  @override
  Future<void> deleteHealthExportLedgerRecordIds(
    List<String> recordIds,
  ) async {
    if (recordIds.isEmpty) return;
    await (db.delete(db.healthExportLedger)
          ..where((t) => t.recordId.isIn(recordIds)))
        .go();
  }

  /// Removes every `health_export_ledger` row for [profileId] (Issue #936)
  /// — profile and account deletion.
  @override
  Future<void> deleteHealthExportLedgerForProfile(String profileId) async {
    await (db.delete(db.healthExportLedger)
          ..where((t) => t.profileId.equals(profileId)))
        .go();
  }

  /// Removes every `health_export_ledger` row on the device (Issue #936) —
  /// unbind.
  @override
  Future<void> clearHealthExportLedger() async {
    await db.delete(db.healthExportLedger).go();
  }
}

/// Delegation shim (issue #551 part 1 step 3): `LunarLogStorage` keeps
/// implementing [HealthDeviceStore] by forwarding each member to the
/// extracted [HealthDeviceStorage] it owns. Every existing consumer and
/// test therefore keeps compiling against the same `LunarLogStorage`
/// surface.
mixin LunarLogStorageHealthDevice implements HealthDeviceStore {
  HealthDeviceStore get healthDevice;

  @override
  Future<HealthSyncStateRow?> readHealthSyncAnchor(String platform) =>
      healthDevice.readHealthSyncAnchor(platform);

  @override
  Future<List<HealthExportLedgerRowData>> readHealthExportLedger(
          String profileId) =>
      healthDevice.readHealthExportLedger(profileId);

  @override
  Future<void> writeHealthSyncAnchor(HealthSyncStateRow anchor) =>
      healthDevice.writeHealthSyncAnchor(anchor);

  @override
  Future<void> upsertHealthExportLedgerRows(
          List<HealthExportLedgerRowData> rows) =>
      healthDevice.upsertHealthExportLedgerRows(rows);

  @override
  Future<void> deleteHealthExportLedgerRecordIds(List<String> recordIds) =>
      healthDevice.deleteHealthExportLedgerRecordIds(recordIds);

  @override
  Future<void> deleteHealthExportLedgerForProfile(String profileId) =>
      healthDevice.deleteHealthExportLedgerForProfile(profileId);

  @override
  Future<void> clearHealthExportLedger() =>
      healthDevice.clearHealthExportLedger();
}
