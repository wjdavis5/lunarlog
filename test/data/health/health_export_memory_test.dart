// Issue #1581: what the phone remembers having written to the health
// store, read from the persisted ledger and kept in step with it.

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_export_memory.dart';
import 'package:lunarlog/domain/health/health_export_ledger.dart';

import '../../support/fake_health_export_ledger.dart';

const _profileId = 'p1';
final _v1 = DateTime.utc(2026, 6, 2, 9, 0, 0, 0, 455);
final _v2 = _v1.add(const Duration(microseconds: 1));

HealthExportLedgerEntry _row(
  String recordId, {
  String sourceRowId = 'entry-1',
  HealthExportLedgerKind kind = HealthExportLedgerKind.entry,
  DateTime? version,
  String profileId = _profileId,
}) =>
    HealthExportLedgerEntry(
      recordId: recordId,
      profileId: profileId,
      sourceRowId: sourceRowId,
      kind: kind,
      localDate: '2026-06-02',
      exportedAt: version ?? _v1,
    );

void main() {
  late FakeHealthExportLedger ledger;
  late HealthExportMemory memory;

  setUp(() {
    ledger = FakeHealthExportLedger();
    memory = HealthExportMemory(ledger);
  });

  group('holds', () {
    test('a record is held at the version it was written with, and at any '
        'earlier one, to the microsecond', () async {
      await memory.remember([_row('entry-1', version: _v2)]);

      expect(memory.holds('entry-1', _v2), isTrue);
      expect(memory.holds('entry-1', _v1), isTrue);
      expect(
        memory.holds('entry-1', _v2.add(const Duration(microseconds: 1))),
        isFalse,
        reason: 'the row has changed since',
      );
    });

    test('a record that was never written is not held', () {
      expect(memory.holds('entry-1', _v1), isFalse);
    });

    test('a record written again is held at the newer version', () async {
      await memory.remember([_row('entry-1')]);
      await memory.remember([_row('entry-1', version: _v2)]);

      expect(memory.holds('entry-1', _v2), isTrue);
      expect(ledger.rows.single.exportedAt, _v2);
      expect(memory.recordIdsOf('entry-1'), {'entry-1'});
    });
  });

  group('what a row put in the store', () {
    test('every record written from it, and none from another row', () async {
      await memory.remember([
        _row('entry-1'),
        _row('symptom-entry-1-headache'),
        _row('entry-2', sourceRowId: 'entry-2'),
      ]);

      expect(
        memory.recordIdsOf('entry-1'),
        {'entry-1', 'symptom-entry-1-headache'},
      );
      expect(memory.knowsRow('entry-1'), isTrue);
      expect(memory.knowsRow('entry-3'), isFalse);
      expect(memory.recordIdsOf('entry-3'), isEmpty);
    });

    test('the set handed back is a copy', () async {
      await memory.remember([_row('entry-1')]);

      memory.recordIdsOf('entry-1').clear();

      expect(memory.recordIdsOf('entry-1'), {'entry-1'});
    });

    test('a record written again under another row moves to it', () async {
      await memory.remember([_row('period-1', sourceRowId: 'a/b')]);
      await memory.remember([_row('period-1', sourceRowId: 'a/c')]);

      expect(memory.knowsRow('a/b'), isFalse);
      expect(memory.recordIdsOf('a/c'), {'period-1'});
    });

    test('by kind', () async {
      await memory.remember([
        _row('entry-1'),
        _row('bbt-o1', sourceRowId: 'o1', kind: HealthExportLedgerKind.bbt),
        _row('bbt-o2', sourceRowId: 'o2', kind: HealthExportLedgerKind.bbt),
      ]);

      expect(
        memory.ofKind(HealthExportLedgerKind.bbt).map((row) => row.recordId),
        unorderedEquals(['bbt-o1', 'bbt-o2']),
      );
      expect(memory.ofKind(HealthExportLedgerKind.period), isEmpty);
      expect(memory.entryOf('bbt-o1')!.sourceRowId, 'o1');
      expect(memory.entryOf('bbt-o9'), isNull);
    });
  });

  group('forgetting', () {
    test('a forgotten record is gone from the ledger too, and its row is '
        'unknown once its last record goes', () async {
      await memory.remember([_row('entry-1'), _row('symptom-entry-1-acne')]);

      await memory.forget(['symptom-entry-1-acne']);
      expect(memory.knowsRow('entry-1'), isTrue);
      expect(memory.holds('symptom-entry-1-acne', _v1), isFalse);
      expect(ledger.rows.map((row) => row.recordId), ['entry-1']);

      await memory.forget(['entry-1', 'never-written']);
      expect(memory.knowsRow('entry-1'), isFalse);
      expect(ledger.rows, isEmpty);
    });

    test('reset empties the memory and the whole ledger', () async {
      await memory.load(_profileId);
      await memory.remember([_row('entry-1')]);
      await ledger.record([_row('entry-9', profileId: 'someone-else')]);

      await memory.reset();

      expect(memory.knowsRow('entry-1'), isFalse);
      expect(ledger.rows, isEmpty);
    });
  });

  group('the persisted ledger', () {
    test('is read once for a profile, so a later session starts from what '
        'an earlier one wrote', () async {
      await ledger.record([
        _row('entry-1', version: _v2),
        _row('entry-9', profileId: 'someone-else'),
      ]);

      await memory.load(_profileId);

      expect(memory.holds('entry-1', _v2), isTrue);
      expect(memory.holds('entry-9', _v1), isFalse);

      // Not read again for the same profile: what a pass has remembered
      // since is not thrown away for a ledger read that fails.
      ledger.throwOnRead = StateError('must not be read');
      await memory.load(_profileId);
      expect(memory.holds('entry-1', _v2), isTrue);
    });

    test('is read again for another profile, and the first one\'s rows are '
        'dropped', () async {
      await ledger.record([
        _row('entry-1'),
        _row('entry-9', sourceRowId: 'entry-9', profileId: 'p2'),
      ]);
      await memory.load(_profileId);

      await memory.load('p2');

      expect(memory.knowsRow('entry-1'), isFalse);
      expect(memory.knowsRow('entry-9'), isTrue);
    });

    test('nothing is written for an empty list', () async {
      ledger.throwOnRead = null;
      await memory.remember(const []);
      await memory.forget(const []);
      expect(ledger.rows, isEmpty);
    });
  });
}
