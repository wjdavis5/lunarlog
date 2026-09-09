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
      expect(quickLogFlowLevel(FlowLevel.spotting), kQuickLogFlowLevel);
    });

    test('an existing entry already at the default is unchanged', () {
      expect(quickLogFlowLevel(kQuickLogFlowLevel), kQuickLogFlowLevel);
    });

    test('an existing entry above the default is never downgraded', () {
      expect(quickLogFlowLevel(FlowLevel.heavy), FlowLevel.heavy);
    });
  });
}
