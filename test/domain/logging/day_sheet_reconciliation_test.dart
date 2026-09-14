/// Unit tests for the day-sheet's pure flow/spotting/pain reconciliation
/// (issue #601), extracted out of `_DaySheetState`'s
/// `_resolveEffectiveFlow`/`_computeSpottingMutations`/
/// `_computePainMutations`. `test/ui/logging_test.dart`'s "spotting and the
/// new flow levels" and "pain intensity" groups exercise the same rules
/// end-to-end through the real widget and autosave; this file is the fast,
/// exhaustive unit-level complement.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/logging/day_sheet_reconciliation.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';

final _date = LocalDate(2026, 8, 30);
final _now = DateTime.utc(2026, 8, 30, 12);

Observation _spottingObs(String id) => Observation(
      id: id,
      dayEntryId: 'e1',
      profileId: 'p1',
      localDate: _date,
      tz: 'UTC',
      category: 'spotting',
      code: 'spotting',
      updatedAt: _now,
    );

Observation _painObs(String id, String code, {int? intensity}) => Observation(
      id: id,
      dayEntryId: 'e1',
      profileId: 'p1',
      localDate: _date,
      tz: 'UTC',
      category: 'pain',
      code: code,
      intensity: intensity,
      updatedAt: _now,
    );

void main() {
  group('resolveEffectiveFlow (issue #247)', () {
    test('spotting alone (no other flow chosen) raises to notBleeding', () {
      expect(
        resolveEffectiveFlow(
          spotting: true,
          flow: FlowLevel.none,
          hadSpottingOnLoad: false,
          flowExplicitlySet: false,
        ),
        FlowLevel.notBleeding,
      );
    });

    test('spotting alongside a real bleed level keeps that level', () {
      expect(
        resolveEffectiveFlow(
          spotting: true,
          flow: FlowLevel.heavy,
          hadSpottingOnLoad: false,
          flowExplicitlySet: false,
        ),
        FlowLevel.heavy,
      );
    });

    test(
        'unchecking spotting on a day whose only signal was spotting '
        'reverts to none (review fix, carried over verbatim)', () {
      expect(
        resolveEffectiveFlow(
          spotting: false,
          flow: FlowLevel.notBleeding,
          hadSpottingOnLoad: true,
          flowExplicitlySet: false,
        ),
        FlowLevel.none,
      );
    });

    test(
        'unchecking spotting after explicitly choosing "Not bleeding" this '
        'session keeps notBleeding -- an explicit choice survives', () {
      expect(
        resolveEffectiveFlow(
          spotting: false,
          flow: FlowLevel.notBleeding,
          hadSpottingOnLoad: true,
          flowExplicitlySet: true,
        ),
        FlowLevel.notBleeding,
      );
    });

    test('spotting never had on load: unchecking (a no-op toggle) does not '
        'revert an explicit notBleeding', () {
      expect(
        resolveEffectiveFlow(
          spotting: false,
          flow: FlowLevel.notBleeding,
          hadSpottingOnLoad: false,
          flowExplicitlySet: false,
        ),
        FlowLevel.notBleeding,
      );
    });

    test('no spotting involved at all: flow passes through unchanged', () {
      for (final flow in FlowLevel.values) {
        expect(
          resolveEffectiveFlow(
            spotting: false,
            flow: flow,
            hadSpottingOnLoad: false,
            flowExplicitlySet: false,
          ),
          flow,
        );
      }
    });
  });

  group('computeSpottingMutations (issue #247)', () {
    test('spotting on, none persisted yet: upserts a new row', () {
      final mutations = computeSpottingMutations(
        existingObservations: const [],
        spotting: true,
        targetDayEntryId: 'e1',
        profileId: 'p1',
        date: _date,
        tz: 'UTC',
        updatedAt: _now,
      );
      expect(mutations.toUpsert, hasLength(1));
      expect(mutations.toUpsert.single.category, 'spotting');
      expect(mutations.toUpsert.single.dayEntryId, 'e1');
      expect(mutations.toDelete, isEmpty);
    });

    test('spotting on, already persisted: no-op (never updates a row with '
        'nothing to change)', () {
      final mutations = computeSpottingMutations(
        existingObservations: [_spottingObs('o1')],
        spotting: true,
        targetDayEntryId: 'e1',
        profileId: 'p1',
        date: _date,
        tz: 'UTC',
        updatedAt: _now,
      );
      expect(mutations.toUpsert, isEmpty);
      expect(mutations.toDelete, isEmpty);
    });

    test('spotting off, one persisted: deletes it', () {
      final mutations = computeSpottingMutations(
        existingObservations: [_spottingObs('o1')],
        spotting: false,
        targetDayEntryId: 'e1',
        profileId: 'p1',
        date: _date,
        tz: 'UTC',
        updatedAt: _now,
      );
      expect(mutations.toDelete, ['o1']);
      expect(mutations.toUpsert, isEmpty);
    });

    test('spotting off, several persisted rows (imported data): deletes '
        'every one', () {
      final mutations = computeSpottingMutations(
        existingObservations: [_spottingObs('o1'), _spottingObs('o2')],
        spotting: false,
        targetDayEntryId: 'e1',
        profileId: 'p1',
        date: _date,
        tz: 'UTC',
        updatedAt: _now,
      );
      expect(mutations.toDelete, unorderedEquals(['o1', 'o2']));
    });

    test('spotting off, none persisted: no-op', () {
      final mutations = computeSpottingMutations(
        existingObservations: const [],
        spotting: false,
        targetDayEntryId: 'e1',
        profileId: 'p1',
        date: _date,
        tz: 'UTC',
        updatedAt: _now,
      );
      expect(mutations.toUpsert, isEmpty);
      expect(mutations.toDelete, isEmpty);
    });

    test('a pain row in existingObservations is ignored entirely', () {
      final mutations = computeSpottingMutations(
        existingObservations: [_painObs('o1', 'cramps', intensity: 3)],
        spotting: true,
        targetDayEntryId: 'e1',
        profileId: 'p1',
        date: _date,
        tz: 'UTC',
        updatedAt: _now,
      );
      expect(mutations.toUpsert, hasLength(1));
      expect(mutations.toDelete, isEmpty);
    });
  });

  group('computePainMutations (issue #256)', () {
    test('empty painIntensity: no-op regardless of existing rows', () {
      final mutations = computePainMutations(
        existingObservations: [_painObs('o1', 'cramps', intensity: 2)],
        painIntensity: const {},
        targetDayEntryId: 'e1',
        profileId: 'p1',
        date: _date,
        tz: 'UTC',
        updatedAt: _now,
      );
      expect(mutations.toUpsert, isEmpty);
      expect(mutations.toDelete, isEmpty);
    });

    test('a graded code with no existing row: upserts a new one', () {
      final mutations = computePainMutations(
        existingObservations: const [],
        painIntensity: const {'cramps': 4},
        targetDayEntryId: 'e1',
        profileId: 'p1',
        date: _date,
        tz: 'UTC',
        updatedAt: _now,
      );
      expect(mutations.toUpsert, hasLength(1));
      final row = mutations.toUpsert.single;
      expect(row.category, 'pain');
      expect(row.code, 'cramps');
      expect(row.intensity, 4);
      expect(mutations.toDelete, isEmpty);
    });

    test('a graded code whose existing row already carries that grade: '
        'no-op (never rewrites an unchanged row)', () {
      final mutations = computePainMutations(
        existingObservations: [_painObs('o1', 'cramps', intensity: 3)],
        painIntensity: const {'cramps': 3},
        targetDayEntryId: 'e1',
        profileId: 'p1',
        date: _date,
        tz: 'UTC',
        updatedAt: _now,
      );
      expect(mutations.toUpsert, isEmpty);
      expect(mutations.toDelete, isEmpty);
    });

    test('a graded code whose existing row carries a different grade: '
        'upserts the updated row, preserving its id', () {
      final mutations = computePainMutations(
        existingObservations: [_painObs('o1', 'cramps', intensity: 2)],
        painIntensity: const {'cramps': 5},
        targetDayEntryId: 'e1',
        profileId: 'p1',
        date: _date,
        tz: 'UTC',
        updatedAt: _now,
      );
      expect(mutations.toUpsert, hasLength(1));
      expect(mutations.toUpsert.single.id, 'o1');
      expect(mutations.toUpsert.single.intensity, 5);
      expect(mutations.toDelete, isEmpty);
    });

    test('an explicitly cleared (null) code with a graded existing row: '
        'deletes it -- ungraded means no severity recorded, never low', () {
      final mutations = computePainMutations(
        existingObservations: [_painObs('o1', 'cramps', intensity: 4)],
        painIntensity: const {'cramps': null},
        targetDayEntryId: 'e1',
        profileId: 'p1',
        date: _date,
        tz: 'UTC',
        updatedAt: _now,
      );
      expect(mutations.toDelete, ['o1']);
      expect(mutations.toUpsert, isEmpty);
    });

    test('an explicitly cleared code with no existing graded row: no-op '
        '(nothing to delete)', () {
      final mutations = computePainMutations(
        existingObservations: const [],
        painIntensity: const {'cramps': null},
        targetDayEntryId: 'e1',
        profileId: 'p1',
        date: _date,
        tz: 'UTC',
        updatedAt: _now,
      );
      expect(mutations.toDelete, isEmpty);
      expect(mutations.toUpsert, isEmpty);
    });

    test(
        'several already-persisted rows share the same code (imported '
        'data): only the first is considered for an update', () {
      final mutations = computePainMutations(
        existingObservations: [
          _painObs('o1', 'cramps', intensity: 2),
          _painObs('o2', 'cramps', intensity: 2),
        ],
        painIntensity: const {'cramps': 5},
        targetDayEntryId: 'e1',
        profileId: 'p1',
        date: _date,
        tz: 'UTC',
        updatedAt: _now,
      );
      expect(mutations.toUpsert, hasLength(1));
      expect(mutations.toUpsert.single.id, 'o1');
    });

    test('several distinct codes: each gets its own mutation', () {
      final mutations = computePainMutations(
        existingObservations: [_painObs('o1', 'cramps', intensity: 2)],
        painIntensity: const {'cramps': 2, 'backache': 3},
        targetDayEntryId: 'e1',
        profileId: 'p1',
        date: _date,
        tz: 'UTC',
        updatedAt: _now,
      );
      // cramps unchanged -> no mutation; backache is new -> one upsert.
      expect(mutations.toUpsert, hasLength(1));
      expect(mutations.toUpsert.single.code, 'backache');
    });
  });

  group('computeObservationMutations (combines both categories)', () {
    test('spotting and pain mutations both surface in one result', () {
      final mutations = computeObservationMutations(
        existingObservations: const [],
        spotting: true,
        painIntensity: const {'cramps': 4},
        targetDayEntryId: 'e1',
        profileId: 'p1',
        date: _date,
        tz: 'UTC',
        updatedAt: _now,
      );
      expect(mutations.toUpsert, hasLength(2));
      expect(
        mutations.toUpsert.map((o) => o.category),
        containsAll(['spotting', 'pain']),
      );
    });

    test('neither category has anything to do: an empty result', () {
      final mutations = computeObservationMutations(
        existingObservations: const [],
        spotting: false,
        painIntensity: const {},
        targetDayEntryId: 'e1',
        profileId: 'p1',
        date: _date,
        tz: 'UTC',
        updatedAt: _now,
      );
      expect(mutations.toUpsert, isEmpty);
      expect(mutations.toDelete, isEmpty);
    });
  });
}
