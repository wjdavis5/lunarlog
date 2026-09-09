/// Unit tests for the pure `DayEntry` value type — construction, copyWith,
/// equality/hashCode, toString, and `DayEntrySource` (de)serialization.
/// Previously untested (no `test/domain/models/` coverage existed), which is
/// why `==` and `toString` showed up as CRAP-gate offenders (0% and low
/// coverage); the `DayEntrySource` table-driven cases below mirror
/// `observation_test.dart`'s `ObservationSource` coverage (Issue #159
/// review finding: `toDb`/`fromDb`'s remaining arms were untested).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';

DayEntry _entry({
  String id = 'e1',
  String profileId = 'p1',
  LocalDate? localDate,
  String tz = 'America/New_York',
  FlowLevel flow = FlowLevel.medium,
  List<String> tags = const [],
  String? note,
  DateTime? updatedAt,
  DateTime? deletedAt,
}) =>
    DayEntry(
      id: id,
      profileId: profileId,
      localDate: localDate ?? LocalDate(2026, 9, 1),
      tz: tz,
      flow: flow,
      tags: tags,
      note: note,
      updatedAt: updatedAt ?? DateTime.utc(2026, 9, 1),
      deletedAt: deletedAt,
    );

void main() {
  group('DayEntry.copyWith', () {
    test('no arguments returns an equal copy', () {
      final entry = _entry(tags: const ['cramps'], note: 'ok');
      expect(entry.copyWith(), entry);
    });

    test('explicit null clears note and deletedAt (the _unset sentinel)', () {
      final entry = _entry(note: 'ok', deletedAt: DateTime.utc(2026, 9, 2));
      final cleared = entry.copyWith(note: null, deletedAt: null);
      expect(cleared.note, isNull);
      expect(cleared.deletedAt, isNull);
    });

    test('overrides only the given fields', () {
      final entry = _entry();
      final renamed = entry.copyWith(profileId: 'p2');
      expect(renamed.profileId, 'p2');
      expect(renamed.id, entry.id);
      expect(renamed.localDate, entry.localDate);
    });
  });

  group('DayEntry equality and hashCode', () {
    test('identical instance is equal to itself', () {
      final entry = _entry();
      // ignore: prefer_const_constructors
      expect(entry == entry, isTrue);
    });

    test('same field values are equal, with matching hashCode', () {
      final a = _entry(tags: const ['cramps', 'headache'], note: 'ok');
      final b = _entry(tags: const ['cramps', 'headache'], note: 'ok');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differing identity fields (id/profileId/localDate/tz) are unequal', () {
      final base = _entry();
      expect(base, isNot(_entry(id: 'other')));
      expect(base, isNot(_entry(profileId: 'other')));
      expect(base, isNot(_entry(localDate: LocalDate(2026, 9, 2))));
      expect(base, isNot(_entry(tz: 'UTC')));
    });

    test('differing content fields (flow/tags/note/updatedAt/deletedAt/attribution) are unequal', () {
      final base = _entry();
      expect(base, isNot(_entry(flow: FlowLevel.heavy)));
      expect(base, isNot(_entry(tags: const ['spotting'])));
      expect(base, isNot(_entry(note: 'different')));
      expect(base, isNot(_entry(updatedAt: DateTime.utc(2026, 9, 5))));
      expect(base, isNot(_entry(deletedAt: DateTime.utc(2026, 9, 5))));
      expect(base, isNot(base.copyWith(loggedByUserId: 'user_x')));
      expect(base, isNot(base.copyWith(lastModifiedByUserId: 'user_y')));
    });

    test('loggedByUserId and lastModifiedByUserId are retained across copyWith', () {
      final entry = _entry().copyWith(
        loggedByUserId: 'user_1',
        lastModifiedByUserId: 'user_2',
      );
      expect(entry.loggedByUserId, 'user_1');
      expect(entry.lastModifiedByUserId, 'user_2');

      final copied = entry.copyWith(note: 'new note');
      expect(copied.loggedByUserId, 'user_1');
      expect(copied.lastModifiedByUserId, 'user_2');
      expect(copied.note, 'new note');

      final cleared = entry.copyWith(loggedByUserId: null, lastModifiedByUserId: null);
      expect(cleared.loggedByUserId, isNull);
      expect(cleared.lastModifiedByUserId, isNull);
    });

    test('not equal to a different type', () {
      // ignore: unrelated_type_equality_checks
      expect(_entry() == 'not a DayEntry', isFalse);
    });
  });

  group('DayEntry.toString', () {
    test('bare entry: no note, no tombstone marker', () {
      final entry = _entry(flow: FlowLevel.light);
      final s = entry.toString();
      expect(s, contains('p1'));
      expect(s, contains('light'));
      expect(s, isNot(contains('note')));
      expect(s, isNot(contains('tombstoned')));
    });

    test('with a note: includes the note marker (never the note text itself)', () {
      final entry = _entry(note: 'private detail');
      final s = entry.toString();
      expect(s, contains('note'));
      expect(s, isNot(contains('private detail')));
    });

    test('tombstoned: includes the tombstoned marker', () {
      final entry = _entry(deletedAt: DateTime.utc(2026, 9, 2));
      expect(entry.toString(), contains('tombstoned'));
    });
  });

  group('DayEntrySource (de)serialization', () {
    test('toDb renders every value as the server''s enum string', () {
      expect(DayEntrySource.manual.toDb(), 'manual');
      expect(DayEntrySource.clueImport.toDb(), 'clue_import');
      expect(DayEntrySource.healthkit.toDb(), 'healthkit');
      expect(DayEntrySource.healthConnect.toDb(), 'health_connect');
      expect(DayEntrySource.fileImport.toDb(), 'file_import');
    });

    test('fromDb parses every known value', () {
      expect(DayEntrySource.fromDb('manual'), DayEntrySource.manual);
      expect(DayEntrySource.fromDb('clue_import'), DayEntrySource.clueImport);
      expect(DayEntrySource.fromDb('healthkit'), DayEntrySource.healthkit);
      expect(DayEntrySource.fromDb('health_connect'),
          DayEntrySource.healthConnect);
      expect(
          DayEntrySource.fromDb('file_import'), DayEntrySource.fileImport);
    });

    test('fromDb degrades an unrecognised or null value to manual', () {
      expect(DayEntrySource.fromDb('some_future_source'),
          DayEntrySource.manual);
      expect(DayEntrySource.fromDb(null), DayEntrySource.manual);
    });

    test('toDb -> fromDb round-trips every value', () {
      for (final source in DayEntrySource.values) {
        expect(DayEntrySource.fromDb(source.toDb()), source);
      }
    });
  });
}
