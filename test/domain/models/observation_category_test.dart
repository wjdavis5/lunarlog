/// Unit tests for the typed `ObservationCategory` projection (Issue #847):
/// the total known-code mapping, lossless unknown round-tripping, family
/// classification, and the exhaustive `switch` the sealed hierarchy buys.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/observation_category.dart';

/// A category-driven classification written as an exhaustive `switch` over
/// every subclass: this function fails to compile if a new
/// [ObservationCategory] subtype is added without a branch, which is
/// exactly the compiler help the pre-#847 string comparisons never gave.
String _classify(ObservationCategory category) => switch (category) {
      SpottingCategory() => 'spotting',
      PainCategory() => 'pain',
      BbtCategory() => 'bbt',
      WeightCategory() => 'weight',
      BirthControlCategory() => 'birth-control',
      UnknownObservationCategory() => 'unknown',
    };

void main() {
  group('known set totality', () {
    test('known holds exactly the categories the app branches on', () {
      expect(
        ObservationCategory.known.map((c) => c.wireCode).toSet(),
        {
          'spotting',
          'pain',
          'bbt',
          'weight',
          'birth_control_pill',
          'birth_control_shot',
          'birth_control_implant',
          'birth_control_patch',
          'birth_control_ring',
          'birth_control_iud',
        },
      );
    });

    test('every known member carries a non-empty wire code', () {
      for (final category in ObservationCategory.known) {
        expect(category.wireCode, isNotEmpty);
      }
    });

    test('fromCode returns the matching member for every known code', () {
      for (final category in ObservationCategory.known) {
        expect(ObservationCategory.fromCode(category.wireCode), category);
      }
    });

    test('wireCode -> fromCode round-trips every known member', () {
      for (final category in ObservationCategory.known) {
        expect(
          ObservationCategory.fromCode(category.wireCode).wireCode,
          category.wireCode,
        );
      }
    });

    test('fromCode never degrades an unknown code onto a known member', () {
      expect(ObservationCategory.fromCode('mood'), isNot(ObservationCategory.pain));
      expect(ObservationCategory.fromCode('mood'),
          isA<UnknownObservationCategory>());
    });
  });

  group('unknown codes round-trip losslessly', () {
    test('a code this build does not know comes back byte-identical', () {
      for (final code in ['mood', 'energy', 'a_brand_new_category']) {
        final parsed = ObservationCategory.fromCode(code);
        expect(parsed, isA<UnknownObservationCategory>());
        expect(parsed.wireCode, code);
        expect(ObservationCategory.fromCode(parsed.wireCode).wireCode, code);
      }
    });

    test('the custom factory keeps its code verbatim', () {
      expect(ObservationCategory.custom('mood').wireCode, 'mood');
      expect(
        ObservationCategory.custom('mood'),
        ObservationCategory.custom('mood'),
      );
    });
  });

  group('classification', () {
    test('isMeasurement is true only for bbt and weight', () {
      expect(ObservationCategory.bbt.isMeasurement, isTrue);
      expect(ObservationCategory.weight.isMeasurement, isTrue);
      expect(ObservationCategory.spotting.isMeasurement, isFalse);
      expect(ObservationCategory.pain.isMeasurement, isFalse);
      expect(ObservationCategory.birthControlPill.isMeasurement, isFalse);
      expect(ObservationCategory.custom('mood').isMeasurement, isFalse);
    });

    test('isBirthControl is true for the six intake categories only', () {
      for (final category in ObservationCategory.known) {
        final expected = category.wireCode.startsWith('birth_control_');
        expect(category.isBirthControl, expected);
      }
      expect(ObservationCategory.custom('birth_control_other').isBirthControl,
          isFalse);
    });
  });

  group('equality and display', () {
    test('equal by wire code, with matching hashCode', () {
      expect(ObservationCategory.spotting, ObservationCategory.fromCode('spotting'));
      expect(
        ObservationCategory.custom('mood').hashCode,
        ObservationCategory.custom('mood').hashCode,
      );
    });

    test('toString is the wire code', () {
      expect(ObservationCategory.birthControlIud.toString(),
          'birth_control_iud');
      expect(ObservationCategory.custom('mood').toString(), 'mood');
    });

    test('an exhaustive switch classifies every member and unknown code', () {
      expect(_classify(ObservationCategory.spotting), 'spotting');
      expect(_classify(ObservationCategory.pain), 'pain');
      expect(_classify(ObservationCategory.bbt), 'bbt');
      expect(_classify(ObservationCategory.weight), 'weight');
      expect(_classify(ObservationCategory.birthControlPill), 'birth-control');
      expect(_classify(ObservationCategory.custom('mood')), 'unknown');
    });
  });
}
