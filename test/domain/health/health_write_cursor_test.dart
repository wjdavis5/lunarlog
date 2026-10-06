/// The health write cursor's two stored forms (Issue #1577): the
/// microsecond value refines the millisecond one, and counts only while
/// they agree.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/health/health_write_cursor.dart';

void main() {
  final instant = DateTime.utc(2026, 6, 1, 14, 0, 0, 861, 455);
  final ms = instant.millisecondsSinceEpoch;
  final us = instant.microsecondsSinceEpoch;

  test('the microsecond value is used when it is inside that millisecond',
      () {
    final cursor = healthWriteCursorFrom(milliseconds: ms, microseconds: us);
    expect(cursor, instant);
    expect(cursor.isUtc, isTrue);
    // The row the cursor was taken from is not after it.
    expect(instant.isAfter(cursor), isFalse);
    // The first and last microsecond of the millisecond both count.
    for (final within in [ms * 1000, ms * 1000 + 999]) {
      expect(
        healthWriteCursorFrom(milliseconds: ms, microseconds: within),
        DateTime.fromMicrosecondsSinceEpoch(within, isUtc: true),
      );
    }
  });

  test('with no microsecond value it is the start of the millisecond', () {
    final cursor = healthWriteCursorFrom(milliseconds: ms, microseconds: null);
    expect(cursor, DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true));
    expect(cursor.isUtc, isTrue);
    // Which is before the row, so that row is written once more.
    expect(instant.isAfter(cursor), isTrue);
  });

  test('a microsecond value from another millisecond is ignored, earlier '
      'or later', () {
    final start = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    for (final other in [ms * 1000 - 1, (ms + 1) * 1000, us + 5000000]) {
      expect(
        healthWriteCursorFrom(milliseconds: ms, microseconds: other),
        start,
        reason: '$other',
      );
    }
  });
}
