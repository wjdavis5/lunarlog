/// Unit tests for `FlowLevel` (Issue #247): the `toDb`/`fromDb` wire-string
/// round trips (including the new `superHeavy`/`notBleeding` values and the
/// deprecated `spotting` alias), `fromDb`'s degrade-to-`none` fallback for
/// garbage input, and `isBleed`'s bleed/non-bleed classification of every
/// value.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/flow_level.dart';

void main() {
  group('toDb', () {
    test('every value maps to its documented wire string', () {
      expect(FlowLevel.none.toDb(), 'none');
      // ignore: deprecated_member_use_from_same_package
      expect(FlowLevel.spotting.toDb(), 'spotting');
      expect(FlowLevel.notBleeding.toDb(), 'not_bleeding');
      expect(FlowLevel.light.toDb(), 'light');
      expect(FlowLevel.medium.toDb(), 'medium');
      expect(FlowLevel.heavy.toDb(), 'heavy');
      expect(FlowLevel.superHeavy.toDb(), 'super_heavy');
    });
  });

  group('fromDb', () {
    test('every wire string round-trips back to its own value', () {
      for (final level in FlowLevel.values) {
        expect(FlowLevel.fromDb(level.toDb()), level);
      }
    });

    test('an unrecognised or null value degrades to none rather than throwing', () {
      expect(FlowLevel.fromDb('garbage'), FlowLevel.none);
      expect(FlowLevel.fromDb(''), FlowLevel.none);
      expect(FlowLevel.fromDb(null), FlowLevel.none);
    });
  });

  group('isBleed', () {
    test('every real bleed level (including superHeavy) is a bleed day', () {
      expect(isBleed(FlowLevel.light), isTrue);
      expect(isBleed(FlowLevel.medium), isTrue);
      expect(isBleed(FlowLevel.heavy), isTrue);
      expect(isBleed(FlowLevel.superHeavy), isTrue);
    });

    test('none, notBleeding, and the deprecated spotting alias are not bleed days', () {
      expect(isBleed(FlowLevel.none), isFalse);
      expect(isBleed(FlowLevel.notBleeding), isFalse);
      // ignore: deprecated_member_use_from_same_package
      expect(isBleed(FlowLevel.spotting), isFalse);
    });
  });
}
