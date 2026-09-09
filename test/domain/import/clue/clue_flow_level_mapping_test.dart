/// Unit tests for the Issue #247 `ClueFlowLevel` -> `FlowLevel` mapping.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/import/clue/clue_datapoint.dart';
import 'package:lunarlog/domain/import/clue/clue_flow_level_mapping.dart';
import 'package:lunarlog/domain/models/flow_level.dart';

void main() {
  group('flowLevelFromClue', () {
    test('is lossless: every ClueFlowLevel has an exact FlowLevel counterpart', () {
      expect(flowLevelFromClue(ClueFlowLevel.notBleeding), FlowLevel.notBleeding);
      expect(flowLevelFromClue(ClueFlowLevel.light), FlowLevel.light);
      expect(flowLevelFromClue(ClueFlowLevel.medium), FlowLevel.medium);
      expect(flowLevelFromClue(ClueFlowLevel.heavy), FlowLevel.heavy);
      expect(flowLevelFromClue(ClueFlowLevel.superHeavy), FlowLevel.superHeavy);
    });

    test('never collapses superHeavy to heavy or notBleeding to none '
        '(the interim rules docs/import/clue-mapping.md documented before '
        'Issue #247 shipped)', () {
      expect(flowLevelFromClue(ClueFlowLevel.superHeavy), isNot(FlowLevel.heavy));
      expect(flowLevelFromClue(ClueFlowLevel.notBleeding), isNot(FlowLevel.none));
    });
  });
}
