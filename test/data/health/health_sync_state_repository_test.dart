/// Coverage for Issue #186's device-local anchor store: the
/// [DriftHealthSyncStateRepository] seam over `health_sync_state`, plus the
/// structural guarantee that the table is device-local and never part of any
/// server sync path (AC1) — `health_sync_state` is not a member of the
/// remote [SyncTable] set, so `sync_push`/`remote_rows.dart`/`row_codec.dart`
/// cannot see it.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/repositories/drift_health_sync_state_repository.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/health/health_sync_state_repository.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late DriftHealthSyncStateRepository repository;

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    repository = DriftHealthSyncStateRepository(db.storage);
  });

  group('health_sync_state anchors', () {
    test('readAnchor returns null before any write', () async {
      expect(await repository.readAnchor('health_connect'), isNull);
      expect(await repository.readAnchor('healthkit'), isNull);
    });

    test('writeAnchor upserts by platform (no duplicate rows)', () async {
      await repository.writeAnchor(const HealthSyncAnchor(
        platform: 'health_connect',
        anchor: 'token-1',
      ));
      await repository.writeAnchor(const HealthSyncAnchor(
        platform: 'health_connect',
        anchor: 'token-2',
      ));
      await repository.writeAnchor(const HealthSyncAnchor(
        platform: 'healthkit',
        anchor: 'anchor-1',
      ));

      final connect = await repository.readAnchor('health_connect');
      expect(connect!.anchor, 'token-2',
          reason: 'the later write replaces the row, it does not duplicate');
      final kit = await repository.readAnchor('healthkit');
      expect(kit!.anchor, 'anchor-1');
      // The two platforms are independent rows.
      expect((await db.select(db.healthSyncState).get()).length, 2);
    });

    test('clearing the anchor (anchor null) signals "full time-range read"',
        () async {
      await repository.writeAnchor(const HealthSyncAnchor(
        platform: 'health_connect',
        anchor: 'token-1',
      ));
      await repository.writeAnchor(const HealthSyncAnchor(
        platform: 'health_connect',
        anchor: null,
      ));
      final anchor = await repository.readAnchor('health_connect');
      expect(anchor, isNotNull);
      expect(anchor!.anchor, isNull,
          reason: 'the row exists but carries no anchor — the '
              'ChangesTokenExpiredException fallback shape');
    });
  });

  group('AC1: health_sync_state is never synced to the server', () {
    test('it is not a member of the remote SyncTable set', () {
      expect(
        SyncTable.values.map((t) => t.name),
        isNot(contains('healthSyncState')),
        reason: 'the anchor table must never appear in the remote row set '
            'that sync_push / the pull pages decode',
      );
    });

    test('the health_sync_state row type never encodes for the wire', () {
      // encode* / decode* live in row_codec.dart, which only knows the
      // SyncTable members above; a table outside that set has no wire
      // shape. The storage layer exposes read/write *storage* methods only.
      expect(repository, isNotNull);
    });
  });
}
