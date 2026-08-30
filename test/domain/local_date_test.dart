import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/local_date.dart';

void main() {
  group('ISO parsing and formatting', () {
    test('round-trips valid calendar dates', () {
      for (final iso in [
        '2026-01-01',
        '2026-12-31',
        '2024-02-29',
        '2026-02-28',
        '0000-01-01',
        '9999-12-31',
      ]) {
        expect(LocalDate.fromIso(iso).iso, iso);
      }
    });

    test('rejects malformed or non-calendar strings', () {
      for (final bad in [
        '2026-2-3',
        'not-a-date',
        '2026-02-30',
        '2023-02-29',
        '2026-13-01',
        '2026-00-10',
        '2026-04-00',
        '20260401',
        '2026-04-01T00:00:00Z',
        '',
      ]) {
        expect(() => LocalDate.fromIso(bad), throwsArgumentError,
            reason: '$bad must be rejected');
      }
    });

    test('constructor validates calendar validity', () {
      expect(() => LocalDate(2023, 2, 29), throwsArgumentError);
      expect(LocalDate(2024, 2, 29).iso, '2024-02-29');
      expect(() => LocalDate(2026, 4, 31), throwsArgumentError);
      expect(() => LocalDate(2026, 0, 10), throwsArgumentError);
    });

    test('fromDateTime takes the date part only', () {
      final dt = DateTime.utc(2026, 5, 9, 18, 30);
      expect(LocalDate.fromDateTime(dt), LocalDate(2026, 5, 9));
    });
  });

  group('civil date arithmetic', () {
    test('addDays crosses month, year and leap boundaries', () {
      expect(LocalDate(2026, 1, 31).addDays(1), LocalDate(2026, 2, 1));
      expect(LocalDate(2026, 2, 28).addDays(1), LocalDate(2026, 3, 1));
      expect(LocalDate(2024, 2, 28).addDays(1), LocalDate(2024, 2, 29));
      expect(LocalDate(2026, 12, 31).addDays(1), LocalDate(2027, 1, 1));
      expect(LocalDate(2026, 3, 1).addDays(-1), LocalDate(2026, 2, 28));
      expect(LocalDate(2024, 3, 1).addDays(-1), LocalDate(2024, 2, 29));
      expect(LocalDate(2026, 1, 1).addDays(-1), LocalDate(2025, 12, 31));
    });

    test('difference counts whole civil days and is antisymmetric', () {
      final a = LocalDate(2026, 2, 28);
      final b = LocalDate(2026, 3, 5);
      expect(b.difference(a), 5);
      expect(a.difference(b), -5);
      expect(a.difference(a), 0);
    });

    test('addDays inverts difference over randomized offsets', () {
      final random = Random(7);
      for (var i = 0; i < 500; i++) {
        final base = LocalDate(2025, 1, 1).addDays(random.nextInt(730));
        final offset = random.nextInt(8001) - 4000;
        final moved = base.addDays(offset);
        expect(moved.difference(base), offset,
            reason: '${base.iso} + $offset days');
        expect(moved.addDays(-offset), base);
      }
    });

    test('comparison and equality', () {
      final a = LocalDate(2026, 5, 1);
      final b = LocalDate(2026, 5, 2);
      expect(a.isBefore(b), isTrue);
      expect(b.isAfter(a), isTrue);
      expect(a.compareTo(b), lessThan(0));
      expect(a, equals(LocalDate(2026, 5, 1)));
      expect(a.hashCode, LocalDate(2026, 5, 1).hashCode);
      final dates = [b, a, LocalDate(2025, 12, 31)]..sort();
      expect(dates, [LocalDate(2025, 12, 31), a, b]);
    });
  });
}
