/// Issue #848: `DayEntryPolicy.validateDate` — the shared day-entry
/// date-bounds rule. Pure and deterministic: the caller passes `today`, so
/// the clock is never read in here.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/logging/day_entry_policy.dart';
import 'package:lunarlog/domain/models/local_date.dart';

void main() {
  final today = LocalDate(2026, 9, 19);

  group('DayEntryPolicy.validateDate — future bound', () {
    test('an ordinary past date is valid', () {
      final result = DayEntryPolicy.validateDate(
        LocalDate(2026, 9, 1),
        today: today,
      );
      expect(result.isValid, isTrue);
      expect(result.violation, isNull);
    });

    test('today itself is valid', () {
      expect(
        DayEntryPolicy.validateDate(today, today: today).isValid,
        isTrue,
      );
    });

    test('today + 1 is valid (the timezone-travel tolerance)', () {
      final result = DayEntryPolicy.validateDate(
        today.addDays(1),
        today: today,
      );
      expect(result.isValid, isTrue);
    });

    test('today + 2 is rejected as a future date', () {
      final result = DayEntryPolicy.validateDate(
        today.addDays(2),
        today: today,
      );
      expect(result.isValid, isFalse);
      expect(result.violation, DayEntryDateViolation.futureDate);
    });

    test('a far-future date (2999-01-01) is rejected', () {
      final result = DayEntryPolicy.validateDate(
        LocalDate(2999, 1, 1),
        today: today,
      );
      expect(result.violation, DayEntryDateViolation.futureDate);
    });
  });

  group('DayEntryPolicy.validateDate — birth-year bound', () {
    test('a date in the profile birth year itself is valid', () {
      final result = DayEntryPolicy.validateDate(
        LocalDate(2015, 1, 1),
        today: today,
        birthYear: 2015,
      );
      expect(result.isValid, isTrue);
    });

    test('a date whose year precedes the birth year is rejected', () {
      final result = DayEntryPolicy.validateDate(
        LocalDate(2010, 6, 1),
        today: today,
        birthYear: 2015,
      );
      expect(result.isValid, isFalse);
      expect(result.violation, DayEntryDateViolation.beforeBirthYear);
    });

    test('a null birth year leaves the year rule unapplied', () {
      final result = DayEntryPolicy.validateDate(
        LocalDate(2010, 6, 1),
        today: today,
      );
      expect(result.isValid, isTrue);
    });

    test('the future bound wins when both rules would fail', () {
      final result = DayEntryPolicy.validateDate(
        LocalDate(2999, 1, 1),
        today: today,
        birthYear: 2500,
      );
      expect(result.violation, DayEntryDateViolation.futureDate);
    });
  });
}
