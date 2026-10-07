/// Coverage for Issue #936's device-local export ledger: the
/// [DriftHealthExportLedger] seam over `health_export_ledger`, plus the
/// structural guarantees that the table is device-local and never part of
/// any server sync path or the account export — it is not a member of the
/// remote [SyncTable] set, so `sync_push`/`remote_rows.dart`/`row_codec.dart`
/// cannot see it, and the export snapshot/repository never reads it.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/repositories/drift_account_export_snapshot_repository.dart';
import 'package:lunarlog/data/repositories/drift_cycle_overrides_repository.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_guardian_notes_repository.dart';
import 'package:lunarlog/data/repositories/drift_health_export_ledger.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profile_modes_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_tag_registry_repository.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/export/account_export.dart';
import 'package:lunarlog/domain/health/health_export_ledger.dart';

HealthExportLedgerEntry _entry(
  String recordId, {
  String profileId = 'p1',
  String sourceRowId = 'entry-1',
  HealthExportLedgerKind kind = HealthExportLedgerKind.entry,
  String localDate = '2026-09-01',
  String? payloadSummary,
}) =>
    HealthExportLedgerEntry(
      recordId: recordId,
      profileId: profileId,
      sourceRowId: sourceRowId,
      kind: kind,
      localDate: localDate,
      exportedAt: DateTime.utc(2026, 9, 1),
      payloadSummary: payloadSummary,
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late DriftHealthExportLedger ledger;

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    ledger = DriftHealthExportLedger(db.storage);
  });

  group('health_export_ledger', () {
    test('readForProfile returns nothing before any write', () async {
      expect(await ledger.readForProfile('p1'), isEmpty);
    });

    test('record round-trips every column, preserving kind and provenance',
        () async {
      await ledger.record([
        _entry('entry-1'),
        _entry(
          'bbt-obs-1',
          sourceRowId: 'obs-1',
          kind: HealthExportLedgerKind.bbt,
        ),
      ]);

      final rows = await ledger.readForProfile('p1');
      expect(rows, hasLength(2));
      final flow =
          rows.singleWhere((r) => r.recordId == 'entry-1');
      expect(flow.sourceRowId, 'entry-1');
      expect(flow.kind, HealthExportLedgerKind.entry);
      expect(flow.localDate, '2026-09-01');
      expect(flow.exportedAt, DateTime.utc(2026, 9, 1));
      final bbt = rows.singleWhere((r) => r.recordId == 'bbt-obs-1');
      expect(bbt.kind, HealthExportLedgerKind.bbt);
      expect(bbt.sourceRowId, 'obs-1');
    });

    test('record upserts by record id (no duplicate rows)', () async {
      await ledger.record([_entry('entry-1', localDate: '2026-09-01')]);
      await ledger.record([_entry('entry-1', localDate: '2026-09-02')]);

      final rows = await ledger.readForProfile('p1');
      expect(rows, hasLength(1));
      expect(rows.single.localDate, '2026-09-02');
    });

    test('readForProfile filters by profile', () async {
      await ledger.record([
        _entry('entry-1', profileId: 'p1'),
        _entry('entry-2', profileId: 'p2'),
      ]);

      expect((await ledger.readForProfile('p1')).single.recordId, 'entry-1');
      expect((await ledger.readForProfile('p2')).single.recordId, 'entry-2');
    });

    test('removeRecordIds drops exactly the named rows', () async {
      await ledger.record([
        _entry('entry-1'),
        _entry('symptom-entry-1-cramps'),
      ]);

      await ledger.removeRecordIds(['symptom-entry-1-cramps']);

      expect(
        (await ledger.readForProfile('p1')).map((r) => r.recordId),
        ['entry-1'],
      );
    });

    // Issue #1589. A later build may write a kind this one has no name
    // for. Read as a day's record, it would be deleted from the health
    // store as the record of a day that is gone.
    test('a row of a kind this build does not know is not read, and stays '
        'in the table', () async {
      await ledger.record([_entry('entry-1')]);
      await db.storage.upsertHealthExportLedgerRows([
        HealthExportLedgerRowData(
          recordId: 'later-1',
          profileId: 'p1',
          sourceRowId: 'something-a-later-build-knows',
          kind: 'a_later_kind',
          localDate: '2026-09-01',
          exportedAt: DateTime.utc(2026, 9, 1),
        ),
      ]);

      expect(
        (await ledger.readForProfile('p1')).map((row) => row.recordId),
        ['entry-1'],
      );
      expect(
        (await db.storage.readHealthExportLedger('p1'))
            .map((row) => row.recordId),
        unorderedEquals(['entry-1', 'later-1']),
      );

      // It still goes with its profile.
      await ledger.clearProfile('p1');
      expect(await db.storage.readHealthExportLedger('p1'), isEmpty);
    });

    test('every kind this build writes reads back as itself', () async {
      await ledger.record([
        for (final kind in HealthExportLedgerKind.values)
          _entry('record-${kind.name}', kind: kind),
      ]);

      expect(
        {for (final row in await ledger.readForProfile('p1')) row.kind},
        HealthExportLedgerKind.values.toSet(),
      );
    });

    test('clearProfile removes only that profile; clearAll removes everything',
        () async {
      await ledger.record([
        _entry('entry-1', profileId: 'p1'),
        _entry('entry-2', profileId: 'p2'),
      ]);

      await ledger.clearProfile('p1');
      expect(await ledger.readForProfile('p1'), isEmpty);
      expect(await ledger.readForProfile('p2'), hasLength(1));

      await ledger.clearAll();
      expect(await ledger.readForProfile('p2'), isEmpty);
    });

    test('the underlying table carries only ids and provenance — no sync '
        'flags, no health values', () async {
      await ledger.record([_entry('entry-1')]);
      final columns = (await db
              .customSelect("PRAGMA table_info('health_export_ledger')")
              .get())
          .map((row) => row.read<String>('name'))
          .toSet();
      expect(
        columns,
        {
          'record_id',
          'profile_id',
          'source_row_id',
          'kind',
          'local_date',
          'exported_at',
          // Issue #1591: what the written record said that other rows
          // decide. Nullable; null is the pre-#1591 "unknown" reading.
          'payload_summary',
        },
      );
    });

    // Issue #1591: a record is re-sent when what it said no longer
    // matches what its row now produces, so what it said must survive a
    // round trip.
    test('payloadSummary round-trips, null included', () async {
      await ledger.record([
        _entry('entry-1', payloadSummary: 'flow:light:1'),
        _entry('entry-2', payloadSummary: 'marker'),
      ]);
      await ledger.record([_entry('entry-3')]);

      final rows = {
        for (final row in await ledger.readForProfile('p1')) row.recordId: row,
      };
      expect(rows['entry-1']!.payloadSummary, 'flow:light:1');
      expect(rows['entry-2']!.payloadSummary, 'marker');
      expect(rows['entry-3']!.payloadSummary, isNull);
    });
  });

  group('AC: the ledger never syncs and never exports', () {
    test('it is not a member of the remote SyncTable set', () {
      expect(
        SyncTable.values.map((t) => t.name),
        isNot(contains('healthExportLedger')),
        reason: 'the export ledger must never appear in the remote row set '
            'that sync_push / the pull pages decode',
      );
    });

    test('an account export of a profile with a ledger row never carries it',
        () async {
      final storage = db.storage;
      final profile =
          await storage.upsertProfile(displayName: 'Riley', isMinor: false);
      const sentinel = 'ledger-sentinel-record-id';
      await ledger.record([
        _entry(sentinel, profileId: profile.id, sourceRowId: profile.id),
      ]);

      final snapshotRepo = DriftAccountExportSnapshotRepository(
        storage: storage,
        entriesRepository: DriftDayEntriesRepository(storage),
        observationsRepository: DriftObservationsRepository(storage),
        profileModesRepository: DriftProfileModesRepository(storage),
        cycleOverridesRepository: DriftCycleOverridesRepository(storage),
        tagRegistryRepository: DriftTagRegistryRepository(storage),
        guardianNotesRepository: DriftGuardianNotesRepository(storage),
      );
      final snapshot = await snapshotRepo.forProfile(profile.id);
      final domainProfile = (await DriftProfilesRepository(storage)
          .findById(profile.id))!;

      final doc = buildAccountExport(
        profiles: [domainProfile],
        entriesByProfile: {profile.id: snapshot.entries},
        observationsByProfile: {profile.id: snapshot.observations},
        profileModesByProfile: {profile.id: snapshot.profileMode},
        cycleOverridesByProfile: {profile.id: snapshot.cycleOverrides},
        mergeEventsByProfile: {profile.id: snapshot.mergeEvents},
        customTagsByProfile: {profile.id: snapshot.customTags},
        guardianNotesByProfile: {profile.id: snapshot.guardianNotes},
        exportedAt: DateTime.utc(2026, 9, 1),
        appVersion: '1.0.0+1',
      );

      expect(jsonEncode(doc).contains(sentinel), isFalse,
          reason: 'the export must never carry a health-store record id');
    });
  });
}
