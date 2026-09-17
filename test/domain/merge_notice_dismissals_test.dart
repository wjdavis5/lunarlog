/// Unit tests for the device-local merge-notice dismissal store (Issue
/// #130): decode tolerance, encode round-trip, idempotent append, and the
/// bounded-list cap. Mirrors `activity_merge_events`'s test posture.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/logging/merge_notice_dismissals.dart';

void main() {
  group('mergeNoticeDismissalsKey', () {
    test('is per-profile', () {
      expect(mergeNoticeDismissalsKey('p1'),
          isNot(mergeNoticeDismissalsKey('p2')));
      expect(mergeNoticeDismissalsKey('p1'), 'merge_notice_dismissed_p1');
    });
  });

  group('decodeMergeNoticeDismissals', () {
    test('null, empty, and non-list values decode to empty', () {
      expect(decodeMergeNoticeDismissals(null), isEmpty);
      expect(decodeMergeNoticeDismissals(''), isEmpty);
      expect(decodeMergeNoticeDismissals('"a string"'), isEmpty);
      expect(decodeMergeNoticeDismissals('42'), isEmpty);
    });

    test('corrupt JSON decodes to empty, never throws', () {
      expect(decodeMergeNoticeDismissals('["broken",'), isEmpty);
    });

    test('non-string elements are skipped', () {
      expect(
        decodeMergeNoticeDismissals('["a", 3, null, "b"]'),
        ['a', 'b'],
      );
    });
  });

  group('encode/decode round-trip', () {
    test('round-trips a list of ids', () {
      const ids = ['x', 'y'];
      expect(decodeMergeNoticeDismissals(encodeMergeNoticeDismissals(ids)),
          ids);
    });
  });

  group('appendMergeNoticeDismissal', () {
    test('appends a new id and keeps insertion order', () {
      expect(appendMergeNoticeDismissal(['a'], 'b'), ['a', 'b']);
    });

    test('a duplicate append is a no-op (idempotent)', () {
      expect(appendMergeNoticeDismissal(['a', 'b'], 'a'), ['a', 'b']);
    });

    test('the input list is never mutated', () {
      const input = ['a'];
      appendMergeNoticeDismissal(input, 'b');
      expect(input, ['a']);
    });

    test('the cap evicts the oldest ids', () {
      final ids = [for (var i = 0; i < 3; i++) 'id$i'];
      final next = appendMergeNoticeDismissal(ids, 'id3', cap: 3);
      expect(next, ['id1', 'id2', 'id3']);
    });
  });
}
