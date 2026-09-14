/// Unit tests for the pure enum wire-codec methods in lib/data/db/tables.dart.
///
/// LLA-106/LLA-107: FlowLevel.fromDb had no lcov record at all before this
/// file existed -- lib/data/sync/row_codec.dart's `flow()` decoder
/// reimplements the same lookup inline (a linear scan comparing
/// `level.toDb()`) rather than calling this static method, so nothing in
/// the app currently calls it. This suite exercises both FlowLevel.toDb
/// and FlowLevel.fromDb directly, covering every enum member and the
/// unknown-value fallback.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/tables.dart';

void main() {
  group('FlowLevel.toDb', () {
    test('every member has its own wire string', () {
      expect(FlowLevel.none.toDb(), 'none');
      expect(FlowLevel.spotting.toDb(), 'spotting');
      expect(FlowLevel.notBleeding.toDb(), 'not_bleeding');
      expect(FlowLevel.light.toDb(), 'light');
      expect(FlowLevel.medium.toDb(), 'medium');
      expect(FlowLevel.heavy.toDb(), 'heavy');
      expect(FlowLevel.superHeavy.toDb(), 'super_heavy');
    });
  });

  group('FlowLevel.fromDb', () {
    test('every wire string round-trips back to its member', () {
      for (final level in FlowLevel.values) {
        expect(FlowLevel.fromDb(level.toDb()), level);
      }
    });

    test('an unrecognised value degrades to none', () {
      expect(FlowLevel.fromDb('not-a-real-value'), FlowLevel.none);
    });

    test('an empty string degrades to none', () {
      expect(FlowLevel.fromDb(''), FlowLevel.none);
    });
  });
}
