/// Unit tests for the "Period started today" quick-log rule (issue #209).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/logging/quick_log.dart';
import 'package:lunarlog/domain/models/flow_level.dart';

void main() {
  group('quickLogFlowLevel', () {
    test('no existing entry writes the quick-log default', () {
      expect(quickLogFlowLevel(null), kQuickLogFlowLevel);
    });

    test('an existing entry below the default is raised to it', () {
      expect(quickLogFlowLevel(FlowLevel.none), kQuickLogFlowLevel);
      // ignore: deprecated_member_use_from_same_package
      expect(quickLogFlowLevel(FlowLevel.spotting), kQuickLogFlowLevel);
      // Issue #247: notBleeding is an explicit "not bleeding today"
      // assertion, still below the quick-log default -- a "period started
      // today" tap still raises it, same as none/spotting.
      expect(quickLogFlowLevel(FlowLevel.notBleeding), kQuickLogFlowLevel);
    });

    test('an existing entry already at the default is unchanged', () {
      expect(quickLogFlowLevel(kQuickLogFlowLevel), kQuickLogFlowLevel);
    });

    test('an existing entry above the default is never downgraded', () {
      expect(quickLogFlowLevel(FlowLevel.heavy), FlowLevel.heavy);
      // Issue #247.
      expect(quickLogFlowLevel(FlowLevel.superHeavy), FlowLevel.superHeavy);
    });

    test(
        'FlowLevel\'s declaration order is load-bearing for the .index '
        'comparison this rule runs on (review finding, PR #335) -- pinned '
        'directly so a reorder fails loudly here rather than only '
        'changing quick-log behaviour by accident', () {
      expect(FlowLevel.values, [
        FlowLevel.none,
        // ignore: deprecated_member_use_from_same_package
        FlowLevel.spotting,
        FlowLevel.notBleeding,
        FlowLevel.light,
        FlowLevel.medium,
        FlowLevel.heavy,
        FlowLevel.superHeavy,
      ]);
    });
  });

  group('quickLogChangesFlow (issue #1412: what the confirmation may claim)',
      () {
    test('a day with no entry yet is changed: the tap creates it', () {
      expect(quickLogChangesFlow(null), isTrue);
    });

    test('a day logged below the default is changed: the tap raises it', () {
      expect(quickLogChangesFlow(FlowLevel.none), isTrue);
      // ignore: deprecated_member_use_from_same_package
      expect(quickLogChangesFlow(FlowLevel.spotting), isTrue);
      expect(quickLogChangesFlow(FlowLevel.notBleeding), isTrue);
      expect(quickLogChangesFlow(FlowLevel.light), isTrue);
    });

    test('a day already at the default or heavier stays as it was', () {
      expect(quickLogChangesFlow(kQuickLogFlowLevel), isFalse);
      expect(quickLogChangesFlow(FlowLevel.heavy), isFalse);
      expect(quickLogChangesFlow(FlowLevel.superHeavy), isFalse);
    });

    test('agrees with quickLogFlowLevel for every level', () {
      for (final level in FlowLevel.values) {
        expect(
          quickLogChangesFlow(level),
          quickLogFlowLevel(level) != level,
          reason: level.name,
        );
      }
    });
  });
}
