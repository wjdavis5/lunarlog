/// Unit tests for `lib/ui/l10n/dates.dart` (issue #160): the shared
/// intl-backed date forms issue #198 builds on, the locale-derived
/// month/weekday name lists that replaced `kMonthNames`/`kWeekdayLabels`,
/// and the calendar grid's first-day-of-week seam
/// (`kFirstDayOfWeek`/`leadingBlanksFor`/`weekdayHeaderLabels` in
/// `month_calendar.dart`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/ui/l10n/dates.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart'
    show kFirstDayOfWeek, leadingBlanksFor, weekdayHeaderLabels;

void main() {
  group('human-readable date forms (en)', () {
    test('long and short formats match the shared copy', () {
      expect(formatMonthDayYear(DateTime(2026, 9, 5)), 'September 5, 2026');
      expect(formatMonthDay(DateTime(2026, 8, 30)), 'August 30');
      expect(formatShortDayDate(DateTime(2026, 9, 8)), 'Tue 8 Sep');
      expect(formatWeekdayDayDateYear(DateTime(2026, 9, 8)), 'Tue 8 Sep 2026');
    });

    test('relativeDayLabel: today/yesterday/tomorrow, full form otherwise',
        () {
      final today = DateTime(2026, 9, 8);
      expect(relativeDayLabel(today, today), 'Today · Tue 8 Sep');
      expect(relativeDayLabel(DateTime(2026, 9, 7), today), 'Yesterday');
      expect(relativeDayLabel(DateTime(2026, 9, 9), today), 'Tomorrow');
      expect(
        relativeDayLabel(DateTime(2026, 9, 5), today),
        'Sat 5 Sep 2026',
      );
    });

    test('relativeDayLabel compares civil days, ignoring time-of-day', () {
      final today = DateTime(2026, 9, 8, 6, 30);
      expect(
        relativeDayLabel(DateTime(2026, 9, 8, 23, 59), today),
        'Today · Tue 8 Sep',
      );
      expect(
        relativeDayLabel(DateTime(2026, 9, 7, 0, 1), today),
        'Yesterday',
      );
    });

    test('relativeDayLabel relative words are caller-overridable', () {
      final today = DateTime(2026, 9, 8);
      expect(
        relativeDayLabel(
          today,
          today,
          todayLabel: 'Heute',
          yesterdayLabel: 'Gestern',
          tomorrowLabel: 'Morgen',
        ),
        'Heute · Tue 8 Sep',
      );
      expect(
        relativeDayLabel(
          DateTime(2026, 9, 7),
          today,
          todayLabel: 'Heute',
          yesterdayLabel: 'Gestern',
          tomorrowLabel: 'Morgen',
        ),
        'Gestern',
      );
    });
  });

  group('locale-derived calendar names (issue #160)', () {
    test('month names come from intl, not a hand-rolled list', () {
      final names = monthNames();
      expect(names, hasLength(12));
      expect(names.first, 'January');
      expect(names[8], 'September');
      expect(names.last, 'December');
    });

    test('short month names match the old substring(0, 3) derivation', () {
      expect(shortMonthNames(), const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ]);
      // Every abbreviation is exactly the full name's first three letters
      // for en — the property the month/year picker relied on.
      for (final (i, short) in shortMonthNames().indexed) {
        expect(short, monthNames()[i].substring(0, 3));
      }
    });

    test('narrow weekday initials are Sunday-first, replacing kWeekdayLabels',
        () {
      expect(narrowWeekdayInitials(), ['S', 'M', 'T', 'W', 'T', 'F', 'S']);
    });
  });

  group('first-day-of-week seam (month_calendar.dart)', () {
    test('default is Sunday, preserving the old grid layout', () {
      expect(kFirstDayOfWeek, DateTime.sunday);
      // 2026-09-01 is a Tuesday: the retired `weekday % 7` arithmetic gave
      // 2 leading blanks for a Sunday-start grid; the seam must agree.
      expect(leadingBlanksFor(2026, 9), 2);
      // 2026-11-01 is a Sunday: no leading blanks.
      expect(leadingBlanksFor(2026, 11), 0);
    });

    test('the seam is overridable: a Monday start shifts every month', () {
      // September 2026 starts Tuesday: one blank for a Monday-start grid.
      expect(leadingBlanksFor(2026, 9, firstDayOfWeek: DateTime.monday), 1);
      // November 2026 starts Sunday: six blanks when the week starts
      // Monday.
      expect(leadingBlanksFor(2026, 11, firstDayOfWeek: DateTime.monday), 6);
    });

    test('weekdayHeaderLabels orders initials from the seam value', () {
      // Sunday start is the identity ordering (the old kWeekdayLabels).
      expect(weekdayHeaderLabels(), ['S', 'M', 'T', 'W', 'T', 'F', 'S']);
      expect(
        weekdayHeaderLabels(firstDayOfWeek: DateTime.monday),
        ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
      );
      expect(
        weekdayHeaderLabels(firstDayOfWeek: DateTime.saturday),
        ['S', 'S', 'M', 'T', 'W', 'T', 'F'],
      );
    });
  });

  group('calendarLocale', () {
    testWidgets('resolves the ambient locale under a MaterialApp', (tester) async {
      late String resolved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              resolved = calendarLocale(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // A bare MaterialApp resolves against the test binding's default
      // platform locale (en_US): locale-derived, but never null, and never
      // anything the intl symbol registry cannot handle.
      expect(resolved, 'en_US');
    });

    testWidgets('falls back to en with no Localizations ancestor',
        (tester) async {
      late String resolved;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            resolved = calendarLocale(context);
            return const SizedBox.shrink();
          },
        ),
      );
      expect(resolved, kFallbackLocale);
    });
  });
}
