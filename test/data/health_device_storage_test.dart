/// Unit tests for the extracted [HealthDeviceStorage] (issue #551 problem
/// 1, part 1 step 3): the device-local `health_sync_state` anchor and
/// `health_export_ledger` rows, exercised directly against a real drift
/// database (SQL behaviour, not a fake), plus the delegation shim proving
/// `LunarLogStorage` forwards to it unchanged.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late HealthDeviceStorage store;
  late LunarLogStorage storage;

  final t0 = DateTime.utc(2026, 1, 15, 8);

  HealthExportLedgerRowData ledgerRow(
    String recordId, {
    String profileId = 'profile-a',
    String sourceRowId = 'source-1',
    String kind = 'entry',
    String localDate = '2026-01-15',
    DateTime? exportedAt,
  }) =>
      HealthExportLedgerRowData(
        recordId: recordId,
        profileId: profileId,
        sourceRowId: sourceRowId,
        kind: kind,
        localDate: localDate,
        exportedAt: exportedAt ?? t0,
      );

  setUp(() {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    storage = LunarLogStorage(db, clock: () => t0);
    store = HealthDeviceStorage(db);
  });

  group('health_sync_state anchor', () {
    test('readHealthSyncAnchor returns null before anything is written',
        () async {
      expect(await store.readHealthSyncAnchor('health_connect'), isNull);
    });

    test('writeHealthSyncAnchor round-trips the anchor row', () async {
      final anchor = HealthSyncStateRow(
        platform: 'health_connect',
        anchor: 'token-7',
        lastSyncedAt: t0,
      );
      await store.writeHealthSyncAnchor(anchor);

      final read = await store.readHealthSyncAnchor('health_connect');
      expect(read?.platform, 'health_connect');
      expect(read?.anchor, 'token-7');
      expect(read?.lastSyncedAt, t0);
    });

    test('writeHealthSyncAnchor upserts by platform', () async {
      await store.writeHealthSyncAnchor(
        const HealthSyncStateRow(platform: 'health_connect', anchor: 'old'),
      );
      await store.writeHealthSyncAnchor(
        const HealthSyncStateRow(platform: 'health_connect', anchor: 'new'),
      );
      await store.writeHealthSyncAnchor(
        const HealthSyncStateRow(platform: 'healthkit', anchor: 'kit-1'),
      );

      expect((await store.readHealthSyncAnchor('health_connect'))?.anchor,
          'new');
      expect(
          (await store.readHealthSyncAnchor('healthkit'))?.anchor, 'kit-1');
    });

    test('a null anchor clears the row (the full-read fallback signal)',
        () async {
      await store.writeHealthSyncAnchor(
        const HealthSyncStateRow(platform: 'health_connect', anchor: 'token'),
      );
      await store.writeHealthSyncAnchor(
        const HealthSyncStateRow(platform: 'health_connect'),
      );

      final read = await store.readHealthSyncAnchor('health_connect');
      expect(read, isNotNull);
      expect(read?.anchor, isNull);
    });

    test(
        'LunarLogStorage delegates the anchor members to the extracted store',
        () async {
      await storage.writeHealthSyncAnchor(
        const HealthSyncStateRow(platform: 'healthkit', anchor: 'via-shim'),
      );
      expect((await storage.readHealthSyncAnchor('healthkit'))?.anchor,
          'via-shim');
      expect((await store.readHealthSyncAnchor('healthkit'))?.anchor,
          'via-shim');
    });
  });

  group('health_export_ledger', () {
    test('readHealthExportLedger is empty for an unknown profile', () async {
      expect(await store.readHealthExportLedger('profile-a'), isEmpty);
    });

    test('upsertHealthExportLedgerRows inserts and reads back', () async {
      await store.upsertHealthExportLedgerRows([
        ledgerRow('record-1'),
        ledgerRow('record-2', kind: 'bbt'),
      ]);

      final rows = await store.readHealthExportLedger('profile-a');
      expect(rows.map((r) => r.recordId), unorderedEquals(['record-1',
          'record-2']));
    });

    test('upsertHealthExportLedgerRows replaces by record id', () async {
      await store.upsertHealthExportLedgerRows([ledgerRow('record-1')]);
      await store.upsertHealthExportLedgerRows([
        ledgerRow('record-1', sourceRowId: 'source-rewritten'),
      ]);

      final rows = await store.readHealthExportLedger('profile-a');
      expect(rows, hasLength(1));
      expect(rows.single.sourceRowId, 'source-rewritten');
    });

    test('upsertHealthExportLedgerRows with an empty list is a no-op',
        () async {
      await store.upsertHealthExportLedgerRows(const []);
      expect(await store.readHealthExportLedger('profile-a'), isEmpty);
    });

    test('deleteHealthExportLedgerRecordIds removes only the named records',
        () async {
      await store.upsertHealthExportLedgerRows([
        ledgerRow('record-1'),
        ledgerRow('record-2'),
        ledgerRow('record-3'),
      ]);

      await store.deleteHealthExportLedgerRecordIds(['record-1', 'record-3']);

      final rows = await store.readHealthExportLedger('profile-a');
      expect(rows.map((r) => r.recordId), ['record-2']);
    });

    test('deleteHealthExportLedgerRecordIds with an empty list is a no-op',
        () async {
      await store.upsertHealthExportLedgerRows([ledgerRow('record-1')]);

      await store.deleteHealthExportLedgerRecordIds(const []);

      expect(await store.readHealthExportLedger('profile-a'), hasLength(1));
    });

    test('deleteHealthExportLedgerForProfile keeps other profiles', () async {
      await store.upsertHealthExportLedgerRows([
        ledgerRow('record-1', profileId: 'profile-a'),
        ledgerRow('record-2', profileId: 'profile-b'),
      ]);

      await store.deleteHealthExportLedgerForProfile('profile-a');

      expect(await store.readHealthExportLedger('profile-a'), isEmpty);
      expect(await store.readHealthExportLedger('profile-b'), hasLength(1));
    });

    test('clearHealthExportLedger removes every row on the device', () async {
      await store.upsertHealthExportLedgerRows([
        ledgerRow('record-1', profileId: 'profile-a'),
        ledgerRow('record-2', profileId: 'profile-b'),
      ]);

      await store.clearHealthExportLedger();

      expect(await store.readHealthExportLedger('profile-a'), isEmpty);
      expect(await store.readHealthExportLedger('profile-b'), isEmpty);
    });

    test(
        'LunarLogStorage delegates the ledger members to the extracted store',
        () async {
      await storage.upsertHealthExportLedgerRows([ledgerRow('record-1')]);

      expect(await storage.readHealthExportLedger('profile-a'), hasLength(1));
      await storage.deleteHealthExportLedgerRecordIds(['record-1']);
      expect(await store.readHealthExportLedger('profile-a'), isEmpty);

      await storage.upsertHealthExportLedgerRows(
          [ledgerRow('record-2'), ledgerRow('record-3')]);
      await storage.deleteHealthExportLedgerForProfile('profile-a');
      expect(await store.readHealthExportLedger('profile-a'), isEmpty);

      await storage.upsertHealthExportLedgerRows([ledgerRow('record-4')]);
      await storage.clearHealthExportLedger();
      expect(await store.readHealthExportLedger('profile-a'), isEmpty);
    });
  });

  group('schema', () {
    test('the health tables hold what the writes put there', () async {
      await store.writeHealthSyncAnchor(
        const HealthSyncStateRow(platform: 'health_connect', anchor: 'tok'),
      );
      await store.upsertHealthExportLedgerRows([ledgerRow('record-1')]);

      expect(await db.select(db.healthSyncState).get(), hasLength(1));
      expect(await db.select(db.healthExportLedger).get(), hasLength(1));
    });
  });
}
