// Issue #1581: what the health write pass keeps between passes beside the
// floor and the export ledger.

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/health/health_write_pass_state.dart';

void main() {
  final t0 = DateTime.utc(2026, 6, 1, 12, 0, 0, 0, 455);
  DateTime after(int microseconds) =>
      t0.add(Duration(microseconds: microseconds));

  group('a floor for each write type', () {
    test('a type that has never been found off admits anything', () {
      const state = HealthWritePassState();
      expect(state.admitsNew('cervicalMucus', DateTime.utc(2000)), isTrue);
    });

    test('a type found off admits only what was saved after that, to the '
        'microsecond', () {
      final state = const HealthWritePassState()
          .withObservedTypesOff(['cervicalMucus'], t0);

      expect(state.admitsNew('cervicalMucus', after(-1)), isFalse);
      expect(state.admitsNew('cervicalMucus', t0), isFalse);
      expect(state.admitsNew('cervicalMucus', after(1)), isTrue);
      expect(state.admitsNew('menstrualFlow', after(-1)), isTrue,
          reason: 'another type has its own floor');
    });

    test('each pass that finds a type off moves its floor on, and leaves '
        'the others where they were', () {
      final state = const HealthWritePassState()
          .withObservedTypesOff(['spotting', 'ovulationTest'], t0)
          .withObservedTypesOff(['spotting', 'ovulationTest'], after(10));

      expect(state.typeFloors, {
        'spotting': after(10),
        'ovulationTest': after(10),
      });
    });

    // The clock a floor is read from can be corrected backwards.
    test('a floor never moves back', () {
      final later = DateTime.utc(2026, 6, 2, 12);
      final earlier = DateTime.utc(2026, 6, 2, 11);
      final state = const HealthWritePassState()
          .withObservedTypesOff(const ['menstrualFlow'], later)
          .withObservedTypesOff(
              const ['menstrualFlow', 'spotting'], earlier);

      expect(state.typeFloors['menstrualFlow'], later);
      expect(state.typeFloors['spotting'], earlier);
    });

    test('moving a floor does not change the state it was made from', () {
      const empty = HealthWritePassState();
      empty.withObservedTypesOff(['spotting'], t0);
      expect(empty.typeFloors, isEmpty);
      expect(empty.typesOff, isEmpty);
    });
  });

  // Issue #1604. A type's floor used to move only on a pass that found it
  // off, so a row that arrived between the last such pass and the one that
  // found the type on again (a row synced in from another device while the
  // app was closed, or saved in the moment before the app was left) was
  // sent when the type came back.
  group('a type switched back on (issue #1604)', () {
    test('the pass that finds it on moves its floor to that pass, so what '
        'arrived while it was off is not admitted', () {
      final state = const HealthWritePassState()
          .withObservedTypesOff(['spotting'], t0)
          .withObservedTypesOff(const [], after(10));

      expect(state.typesOff, isEmpty);
      expect(state.admitsNew('spotting', t0), isFalse);
      expect(state.admitsNew('spotting', after(9)), isFalse,
          reason: 'arrived after the last look and before the type '
              'returned');
      expect(state.admitsNew('spotting', after(10)), isFalse);
      expect(state.admitsNew('spotting', after(11)), isTrue,
          reason: 'saved after the pass that found the type on');
    });

    test('a type still off keeps its floor moving with each look', () {
      final state = const HealthWritePassState()
          .withObservedTypesOff(['spotting'], t0)
          .withObservedTypesOff(['spotting'], after(5))
          .withObservedTypesOff(['spotting'], after(10));

      expect(state.typeFloors, {'spotting': after(10)});
      expect(state.typesOff, {'spotting'});
    });

    test('a re-enable observed with a corrected-back clock never moves the '
        'floor back', () {
      final state = const HealthWritePassState()
          .withObservedTypesOff(['spotting'], after(10))
          .withObservedTypesOff(const [], after(5));

      expect(state.typeFloors['spotting'], after(10));
      expect(state.typesOff, isEmpty);
    });
  });

  group('how far no-flow days have been cleared', () {
    test('nothing is cleared until something is', () {
      expect(const HealthWritePassState().notYetCleared(t0), isTrue);
    });

    test('a day at or before the mark has been asked for; a later one has '
        'not', () {
      final state = const HealthWritePassState().withClearedThrough(t0);
      expect(state.notYetCleared(after(-1)), isFalse);
      expect(state.notYetCleared(t0), isFalse);
      expect(state.notYetCleared(after(1)), isTrue);
    });

    test('the mark never moves back, and keeps the type floors', () {
      final state = const HealthWritePassState()
          .withObservedTypesOff(['spotting'], t0)
          .withClearedThrough(after(10))
          .withClearedThrough(after(5));
      expect(state.clearedThrough, after(10));
      expect(state.typeFloors, {'spotting': t0});
      expect(state.typesOff, {'spotting'},
          reason: 'the mark does not disturb what the last look saw');
    });
  });

  group('stored', () {
    test('round-trips to the microsecond', () {
      final state = const HealthWritePassState()
          .withObservedTypesOff(['spotting', 'headache'], after(3))
          .withClearedThrough(after(7));

      final read = HealthWritePassState.decode(state.encode())!;

      expect(read.typeFloors, {'spotting': after(3), 'headache': after(3)});
      expect(read.typesOff, {'spotting', 'headache'});
      expect(read.clearedThrough, after(7));
      expect(read.typeFloors.values.every((floor) => floor.isUtc), isTrue);
    });

    test('an empty state is still something stored', () {
      final read =
          HealthWritePassState.decode(const HealthWritePassState().encode());
      expect(read, isNotNull);
      expect(read!.typeFloors, isEmpty);
      expect(read.typesOff, isEmpty);
      expect(read.clearedThrough, isNull);
    });

    test('nothing stored, and anything that cannot be read, is no state', () {
      for (final raw in [null, '', 'not json', '[]', '"text"', '7']) {
        expect(HealthWritePassState.decode(raw), isNull, reason: '$raw');
      }
    });

    test('parts that are not what they should be are left out, not guessed',
        () {
      final read = HealthWritePassState.decode(
        '{"typeFloors":{"spotting":"soon","headache":12,"3":null},'
        '"typesOff":["spotting",7,null],"clearedThroughUs":"never"}',
      )!;
      expect(read.typeFloors.keys, ['headache']);
      expect(read.typesOff, {'spotting'});
      expect(read.clearedThrough, isNull);

      final noFloors =
          HealthWritePassState.decode('{"typeFloors":[],"clearedThroughUs":5}')!;
      expect(noFloors.typeFloors, isEmpty);
      expect(noFloors.typesOff, isEmpty,
          reason: 'a state stored before issue #1604 carries no set');
      expect(
        noFloors.clearedThrough,
        DateTime.fromMicrosecondsSinceEpoch(5, isUtc: true),
      );
    });
  });
}
