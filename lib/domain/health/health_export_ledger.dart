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
/// (Since #1591 [HealthExportLedgerEntry.payloadSummary] adds a type name
/// and a boolean about what the written record said — the shape of the
/// export, never its content.)
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

  /// One period episode's interval record (Issue #1478) — Health Connect's
  /// `MenstruationPeriodRecord`, the one exported record that is derived
  /// from *several* day entries rather than one source row. Nothing a
  /// single tombstone carries can address it, so the write path reconciles
  /// it itself from this row: [HealthExportLedgerEntry.sourceRowId] is the
  /// exported interval, `<first day>/<last day>` as ISO dates, which is what
  /// a later pass compares against the episode the profile's days derive
  /// now. A build that does not know a kind does not read its rows at all
  /// (`DriftHealthExportLedger.readForProfile`), so it leaves the record
  /// in the store and the row in the table.
  period,
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
    this.payloadSummary,
    this.writtenVersion,
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

  /// The version of the source row the record was written from: the
  /// row's `updatedAt` at that moment (Issue #1581). A row whose
  /// `updatedAt` is later than this has changed since, and its record is
  /// due to be written again. Two exceptions. A [HealthExportLedgerKind
  /// .period] row holds the version number the record was written with
  /// (Issue #1478). And a row written by a build before #1581 holds the
  /// time of the export, which is at or after the row's version, so it
  /// reads as written.
  final DateTime exportedAt;

  /// A short summary of what the written record says that *other* rows
  /// decide (Issue #1591) — for a flow or spotting record the type written
  /// and, for a flow sample, the cycle-start flag (`flow:light:1`,
  /// `marker`; see `flowPayloadSummary` in `health_flow_mapping.dart`).
  /// Null for a kind with no such payload, and for a row written before
  /// #1591: read as "what it says is unknown", which sends the record once
  /// more so the store is corrected.
  final String? payloadSummary;

  /// The version given to the health store when writing the sample
  /// (Issue #1643). Null for rows written before #1643, for which the
  /// written version was [exportedAt].
  final DateTime? writtenVersion;

  /// The version the health store holds this record at: [writtenVersion]
  /// when known, otherwise [exportedAt].
  DateTime get storeVersion => writtenVersion ?? exportedAt;

  HealthExportLedgerEntry copyWith({
    String? recordId,
    String? profileId,
    String? sourceRowId,
    HealthExportLedgerKind? kind,
    String? localDate,
    DateTime? exportedAt,
    String? payloadSummary,
    DateTime? writtenVersion,
  }) =>
      HealthExportLedgerEntry(
        recordId: recordId ?? this.recordId,
        profileId: profileId ?? this.profileId,
        sourceRowId: sourceRowId ?? this.sourceRowId,
        kind: kind ?? this.kind,
        localDate: localDate ?? this.localDate,
        exportedAt: exportedAt ?? this.exportedAt,
        payloadSummary: payloadSummary ?? this.payloadSummary,
        writtenVersion: writtenVersion ?? this.writtenVersion,
      );
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
