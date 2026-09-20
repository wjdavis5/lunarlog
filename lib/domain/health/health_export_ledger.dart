/// The device-local health-store export ledger (Issue #936): the persisted
/// record of which health-store samples **this device** wrote, so a
/// tombstone or an edit made in a later app session can still reconcile the
/// sample away.
///
/// Both deletion paths used to remember their exports only in process
/// memory (`LocalHealthFlowWriteService._exportedEntryRecordIds` /
/// `_exportedBbtRecordIds` and `HealthSyncTombstoneCoordinator.
/// _knownEntryRecordIds` / `_knownObservationRecordIds`). On iOS a fresh
/// process is the common case, not an edge case: after a relaunch the
/// "previously exported" side of the diff is empty, so a deleted or edited
/// entry left its symptom / mood / fertility / BBT samples in Apple Health
/// or Health Connect permanently. The forward-only **write** cursor
/// (`SettingsKeys.healthSyncWrittenThroughMs`) is already persisted, so
/// only the deletion side forgot.
///
/// **Never synced.** What this device exported to *its own* health store is
/// per-device state, exactly like the write cursor. This table is not a
/// member of the remote `SyncTable` set, so it can never appear in a
/// `sync_push` payload, reach another device, or be read back by the
/// account export. It is cleared when its records are deleted from the
/// store, when the device unbinds the profile, and when the profile is
/// deleted or the account reset.
///
/// **Ids and provenance only — no health values.** A record id embeds an
/// entry id and a type name, the same shape already crossing the platform
/// channel; no flow level, tag, note, or measurement is ever stored here.
///
/// Pure Dart (R14/R16): the drift-backed implementation lives in
/// `lib/data/repositories/`, wired through `app_dependencies.dart`.
library;

/// The kind of source row a ledger record was derived from — i.e. how a
/// consumer groups the rows it reads back.
enum HealthExportLedgerKind {
  /// A record derived from a day entry: its own flow/marker id plus any
  /// symptom, cervical-mucus, or ovulation ids its tags produce. Rows of
  /// this kind share one [HealthExportLedgerEntry.sourceRowId] (the day
  /// entry's id).
  entry,

  /// A spotting observation's own record id; [HealthExportLedgerEntry.sourceRowId]
  /// is the observation id.
  spotting,

  /// A basal-body-temperature observation's `bbt-<id>` record id;
  /// [HealthExportLedgerEntry.sourceRowId] is the observation id.
  bbt,
}

/// One persisted health-store export.
class HealthExportLedgerEntry {
  const HealthExportLedgerEntry({
    required this.recordId,
    required this.profileId,
    required this.sourceRowId,
    required this.kind,
    required this.localDate,
    required this.exportedAt,
  });

  /// The platform external id this device wrote (Health Connect
  /// `clientRecordId` / HealthKit `HKMetadataKeyExternalUUID`). Primary key
  /// of the ledger.
  final String recordId;

  /// The bound profile the export belonged to. Rows are cleared per profile
  /// on unbind and on profile/account deletion.
  final String profileId;

  /// The source day-entry or observation id the record was derived from —
  /// the grouping key for [kind].
  final String sourceRowId;

  final HealthExportLedgerKind kind;

  /// ISO calendar date `yyyy-MM-dd` the export was for (provenance only).
  final String localDate;

  /// The UTC instant the record was exported.
  final DateTime exportedAt;
}

/// The read/write port for the device-local health-store export ledger.
/// Deliberately never part of any server sync path.
abstract interface class HealthExportLedger {
  /// Every ledger row for [profileId], across all kinds.
  Future<List<HealthExportLedgerEntry>> readForProfile(String profileId);

  /// Upserts [entries] keyed by [HealthExportLedgerEntry.recordId].
  Future<void> record(Iterable<HealthExportLedgerEntry> entries);

  /// Removes the rows for [recordIds] (called once the corresponding
  /// samples have been deleted from the store).
  Future<void> removeRecordIds(Iterable<String> recordIds);

  /// Removes every row for [profileId] (profile/account deletion).
  Future<void> clearProfile(String profileId);

  /// Removes every row on the device (unbind).
  Future<void> clearAll();
}
