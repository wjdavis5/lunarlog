/// Unit tests for `clue_datapoint.dart`'s standalone value types (Issue
/// #190 review): [ClueFlowLevelBleed.isBleed] mirrors
/// `lib/domain/models/flow_level.dart`'s top-level `isBleed(FlowLevel)`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/import/clue/clue_datapoint.dart';

void main() {
  group('ClueFlowLevel.isBleed', () {
    test('notBleeding is the only level that is not a bleed', () {
      expect(ClueFlowLevel.notBleeding.isBleed, isFalse);
    });

    test('every other level counts as a bleed, superHeavy included', () {
      expect(ClueFlowLevel.light.isBleed, isTrue);
      expect(ClueFlowLevel.medium.isBleed, isTrue);
      expect(ClueFlowLevel.heavy.isBleed, isTrue);
      expect(ClueFlowLevel.superHeavy.isBleed, isTrue);
    });
  });
}
