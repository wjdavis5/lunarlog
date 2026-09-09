/// Unit tests for the pure `Observation` value type (Issue #240) —
/// construction, `ObservationSource` (de)serialization, copyWith,
/// equality/hashCode, and toString. Mirrors `day_entry_test.dart`'s shape.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';

Observation _observation({
  String id = 'o1',
  String dayEntryId = 'e1',
  String profileId = 'p1',
  LocalDate? localDate,
  DateTime? observedAt,
  String tz = 'America/New_York',
  String category = 'pain',
  String? code = 'migraine',
  double? valueNum,
  String? valueText,
  String? unit,
  int? intensity,
  bool excluded = false,
  ObservationSource source = ObservationSource.manual,
  String? sourceId,
  String? raw,
  DateTime? updatedAt,
  DateTime? deletedAt,
  String? loggedByUserId,
  String? lastModifiedByUserId,
}) =>
    Observation(
      id: id,
      dayEntryId: dayEntryId,
      profileId: profileId,
      localDate: localDate ?? LocalDate(2026, 9, 1),
      observedAt: observedAt,
      tz: tz,
      category: category,
      code: code,
      valueNum: valueNum,
      valueText: valueText,
      unit: unit,
      intensity: intensity,
      excluded: excluded,
      source: source,
      sourceId: sourceId,
      raw: raw,
      updatedAt: updatedAt ?? DateTime.utc(2026, 9, 1),
      deletedAt: deletedAt,
      loggedByUserId: loggedByUserId,
      lastModifiedByUserId: lastModifiedByUserId,
    );

void main() {
  group('ObservationSource (de)serialization', () {
    test('toDb renders every value as the server''s enum string', () {
      expect(ObservationSource.manual.toDb(), 'manual');
      expect(ObservationSource.appleHealth.toDb(), 'apple_health');
      expect(ObservationSource.healthConnect.toDb(), 'health_connect');
      expect(ObservationSource.wearable.toDb(), 'wearable');
      expect(ObservationSource.clueImport.toDb(), 'clue_import');
    });

    test('fromDb parses every known value', () {
      expect(ObservationSource.fromDb('manual'), ObservationSource.manual);
      expect(ObservationSource.fromDb('apple_health'),
          ObservationSource.appleHealth);
      expect(ObservationSource.fromDb('health_connect'),
          ObservationSource.healthConnect);
      expect(ObservationSource.fromDb('wearable'), ObservationSource.wearable);
      expect(
          ObservationSource.fromDb('clue_import'), ObservationSource.clueImport);
    });

    test('fromDb degrades an unrecognised or null value to manual', () {
      expect(ObservationSource.fromDb('some_future_source'),
          ObservationSource.manual);
      expect(ObservationSource.fromDb(null), ObservationSource.manual);
    });

    test('toDb -> fromDb round-trips every value', () {
      for (final source in ObservationSource.values) {
        expect(ObservationSource.fromDb(source.toDb()), source);
      }
    });
  });

  group('Observation.copyWith', () {
    test('no arguments returns an equal copy', () {
      final observation = _observation(code: 'migraine', intensity: 3);
      expect(observation.copyWith(), observation);
    });

    test('explicit null clears code/intensity/observedAt (the _unset '
        'sentinel)', () {
      final observation = _observation(
        code: 'migraine',
        intensity: 3,
        observedAt: DateTime.utc(2026, 9, 1, 8),
      );
      final cleared = observation.copyWith(
          code: null, intensity: null, observedAt: null);
      expect(cleared.code, isNull);
      expect(cleared.intensity, isNull);
      expect(cleared.observedAt, isNull);
    });

    test('overrides only the given fields', () {
      final observation = _observation();
      final recategorized = observation.copyWith(category: 'mood');
      expect(recategorized.category, 'mood');
      expect(recategorized.id, observation.id);
      expect(recategorized.code, observation.code);
    });
  });

  group('Observation equality and hashCode', () {
    test('identical instance is equal to itself', () {
      final observation = _observation();
      // ignore: prefer_const_constructors
      expect(observation == observation, isTrue);
    });

    test('same field values are equal, with matching hashCode', () {
      final a = _observation(code: 'migraine', intensity: 3, valueNum: 98.4);
      final b = _observation(code: 'migraine', intensity: 3, valueNum: 98.4);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differing identity fields (id/dayEntryId/profileId/localDate) '
        'are unequal', () {
      final base = _observation();
      expect(base, isNot(_observation(id: 'other')));
      expect(base, isNot(_observation(dayEntryId: 'other')));
      expect(base, isNot(_observation(profileId: 'other')));
      expect(base, isNot(_observation(localDate: LocalDate(2026, 9, 2))));
    });

    test('differing content fields are unequal', () {
      final base = _observation();
      expect(base, isNot(_observation(category: 'mood')));
      expect(base, isNot(_observation(code: 'other_code')));
      expect(base, isNot(_observation(valueNum: 1.5)));
      expect(base, isNot(_observation(intensity: 5)));
      expect(base, isNot(_observation(excluded: true)));
      expect(base,
          isNot(_observation(source: ObservationSource.clueImport)));
      expect(base, isNot(_observation(updatedAt: DateTime.utc(2026, 9, 5))));
      expect(base, isNot(_observation(deletedAt: DateTime.utc(2026, 9, 5))));
      expect(base, isNot(base.copyWith(loggedByUserId: 'user_x')));
      expect(base, isNot(base.copyWith(lastModifiedByUserId: 'user_y')));
    });

    test('not equal to a different type', () {
      // ignore: unrelated_type_equality_checks
      expect(_observation() == 'not an Observation', isFalse);
    });
  });

  group('Observation.toString', () {
    test('bare observation: category and code, no tombstone marker', () {
      final observation = _observation(category: 'pain', code: 'migraine');
      final s = observation.toString();
      expect(s, contains('p1'));
      expect(s, contains('pain'));
      expect(s, contains('migraine'));
      expect(s, isNot(contains('tombstoned')));
    });

    test('a null code omits the slash-code suffix', () {
      final observation = _observation(category: 'bbt', code: null);
      final s = observation.toString();
      expect(s, contains('bbt'));
      expect(s, isNot(contains('/')));
    });

    test('tombstoned: includes the tombstoned marker', () {
      final observation =
          _observation(deletedAt: DateTime.utc(2026, 9, 2));
      expect(observation.toString(), contains('tombstoned'));
    });
  });
}
