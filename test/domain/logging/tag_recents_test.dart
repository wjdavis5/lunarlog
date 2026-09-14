/// Unit tests for the per-profile "recently used tags" pure logic (Issue
/// #234): [withRecordedTagUse]'s move-to-front/dedupe/cap transform and the
/// [encodeTagRecents]/[decodeTagRecents] JSON round trip.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/logging/tag_recents.dart';

void main() {
  group('withRecordedTagUse', () {
    test('adds a new code to the front of an empty list', () {
      expect(withRecordedTagUse(const [], 'cramps'), ['cramps']);
    });

    test('moves an already-present code to the front rather than '
        'duplicating it', () {
      final result =
          withRecordedTagUse(['headache', 'cramps', 'bloating'], 'cramps');
      expect(result, ['cramps', 'headache', 'bloating']);
    });

    test('caps at the given length, evicting the oldest', () {
      final result = withRecordedTagUse(
        ['a', 'b', 'c'],
        'd',
        cap: 3,
      );
      expect(result, ['d', 'a', 'b']);
    });

    test('defaults to kTagRecentsCap', () {
      var recents = <String>[];
      for (var i = 0; i < kTagRecentsCap + 3; i++) {
        recents = withRecordedTagUse(recents, 'code-$i');
      }
      expect(recents, hasLength(kTagRecentsCap));
      // Most-recent-first: the last three added evicted the oldest three.
      expect(recents.first, 'code-${kTagRecentsCap + 2}');
    });
  });

  group('encodeTagRecents / decodeTagRecents', () {
    test('round-trips a multi-profile map', () {
      final recents = {
        'p1': ['cramps', 'headache'],
        'p2': ['sad'],
      };
      final decoded = decodeTagRecents(encodeTagRecents(recents));
      expect(decoded, recents);
    });

    test('round-trips an empty map as an empty document', () {
      expect(decodeTagRecents(encodeTagRecents(const {})), isEmpty);
    });

    test('null and empty input decode to an empty map', () {
      expect(decodeTagRecents(null), isEmpty);
      expect(decodeTagRecents(''), isEmpty);
    });

    test('unparseable JSON degrades to an empty map, never throws', () {
      expect(decodeTagRecents('not json'), isEmpty);
    });

    test('a non-map root degrades to an empty map', () {
      expect(decodeTagRecents('[1,2,3]'), isEmpty);
    });

    test('a missing or malformed "profiles" key degrades to an empty map',
        () {
      expect(decodeTagRecents('{"v":1}'), isEmpty);
      expect(decodeTagRecents('{"v":1,"profiles":"nope"}'), isEmpty);
    });

    test('a profile entry that is not a list is dropped, others survive',
        () {
      final decoded = decodeTagRecents(
        '{"v":1,"profiles":{"p1":"not-a-list","p2":["sad"]}}',
      );
      expect(decoded, {'p2': ['sad']});
    });

    test('non-string elements within a profile list are dropped, not the '
        'whole profile', () {
      final decoded = decodeTagRecents(
        '{"v":1,"profiles":{"p1":["cramps",42,"headache",null]}}',
      );
      expect(decoded, {
        'p1': ['cramps', 'headache'],
      });
    });
  });
}
