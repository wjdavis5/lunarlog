/// Unit tests for `lib/ui/l10n/dates.dart` (issue #160): the shared
/// intl-backed date forms issue #198 builds on, the locale-derived
/// month/weekday name lists that replaced `kMonthNames`/`kWeekdayLabels`,
/// and the calendar grid's first-day-of-week seam
/// (`kFirstDayOfWeek`/`leadingBlanksFor`/`weekdayHeaderLabels` in
/// `month_calendar.dart`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/calendar_preferences.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/ui/l10n/dates.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart'
    show kFirstDayOfWeek, leadingBlanksFor, weekdayHeaderLabels;

void main() {
  group('human-readable date forms (en)', () {
    test('long and short formats match the shared copy', () {
      expect(formatMonthDayYear(DateTime(2026, 9, 5)), 'September 5, 2026');
      expect(formatMonthDay(DateTime(2026, 8, 30)), 'August 30');
      expect(formatShortDayDate(DateTime(2026, 9, 8)), 'Tue Sep 8');
      expect(formatWeekdayDayDateYear(DateTime(2026, 9, 8)), 'Tue Sep 8 2026');
    });

    test(
        'formatShortDate is locale-aware numeric, replacing the '
        'hand-rolled YYYY-MM-DD several screens used to assemble '
        '(issue #554)', () {
      expect(formatShortDate(DateTime(2026, 9, 5)), '9/5/2026');
    });

    test('relativeDayLabel: today/yesterday/tomorrow, full form otherwise',
        () {
      final today = DateTime(2026, 9, 8);
      expect(relativeDayLabel(today, today), 'Today · Tue Sep 8');
      expect(relativeDayLabel(DateTime(2026, 9, 7), today), 'Yesterday');
      expect(relativeDayLabel(DateTime(2026, 9, 9), today), 'Tomorrow');
      expect(
        relativeDayLabel(DateTime(2026, 9, 5), today),
        'Sat Sep 5 2026',
      );
    });

    test('relativeDayLabel compares civil days, ignoring time-of-day', () {
      final today = DateTime(2026, 9, 8, 6, 30);
      expect(
        relativeDayLabel(DateTime(2026, 9, 8, 23, 59), today),
        'Today · Tue Sep 8',
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
        'Heute · Tue Sep 8',
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

    test('LocalDate overloads match DateTime formats', () {
      expect(
        formatLocalDateMonthDayYear(LocalDate(2026, 9, 5)),
        'September 5, 2026',
      );
      expect(formatLocalDateMonthDay(LocalDate(2026, 8, 30)), 'August 30');
      expect(formatLocalDateShortDate(LocalDate(2026, 9, 5)), '9/5/2026');
      expect(formatLocalDateShortDayDate(LocalDate(2026, 9, 8)), 'Tue Sep 8');
      expect(
        formatLocalDateWeekdayDayDateYear(LocalDate(2026, 9, 8)),
        'Tue Sep 8 2026',
      );
    });

    test(
        'relativeDayLabel handles DST spring-forward transitions without mislabeling (issue #846)',
        () {
      // US DST spring-forward: Sunday 2026-03-08 to Monday 2026-03-09.
      // In local timezones observing DST, March 8 is 23 hours long.
      // Instant-based difference inDays yields 0 (23 ~/ 24 = 0),
      // erroneously mislabeling tomorrow as "Today".
      final march8 = DateTime(2026, 3, 8);
      final march9 = DateTime(2026, 3, 9);
      final march7 = DateTime(2026, 3, 7);

      // From reference of March 8:
      expect(relativeDayLabel(march8, march8), 'Today · Sun Mar 8');
      expect(relativeDayLabel(march9, march8), 'Tomorrow');
      expect(relativeDayLabel(march7, march8), 'Yesterday');

      // From reference of March 9:
      expect(relativeDayLabel(march9, march9), 'Today · Mon Mar 9');
      expect(relativeDayLabel(march8, march9), 'Yesterday');

      // Times of day across the boundary:
      expect(
        relativeDayLabel(DateTime(2026, 3, 9, 0, 1), DateTime(2026, 3, 8, 23, 59)),
        'Tomorrow',
      );
      expect(
        relativeDayLabel(DateTime(2026, 3, 8, 23, 59), DateTime(2026, 3, 9, 0, 1)),
        'Yesterday',
      );
    });

    test(
        'relativeDayLabel handles DST fall-back transitions without mislabeling (issue #846)',
        () {
      // US DST fall-back: Sunday 2026-11-01 to Monday 2026-11-02.
      // In local timezones observing DST, Nov 1 is 25 hours long.
      final nov1 = DateTime(2026, 11, 1);
      final nov2 = DateTime(2026, 11, 2);
      final oct31 = DateTime(2026, 10, 31);

      // From reference of Nov 1:
      expect(relativeDayLabel(nov1, nov1), 'Today · Sun Nov 1');
      expect(relativeDayLabel(nov2, nov1), 'Tomorrow');
      expect(relativeDayLabel(oct31, nov1), 'Yesterday');

      // From reference of Nov 2:
      expect(relativeDayLabel(nov2, nov2), 'Today · Mon Nov 2');
      expect(relativeDayLabel(nov1, nov2), 'Yesterday');
    });

    test(
        'relativeDayLabelForLocalDate computes pure civil day labels across DST boundaries (issue #846)',
        () {
      final march8 = LocalDate(2026, 3, 8);
      final march9 = LocalDate(2026, 3, 9);
      final march7 = LocalDate(2026, 3, 7);

      expect(relativeDayLabelForLocalDate(march8, march8), 'Today · Sun Mar 8');
      expect(relativeDayLabelForLocalDate(march9, march8), 'Tomorrow');
      expect(relativeDayLabelForLocalDate(march7, march8), 'Yesterday');
      expect(relativeDayLabelForLocalDate(march8, march9), 'Yesterday');

      final nov1 = LocalDate(2026, 11, 1);
      final nov2 = LocalDate(2026, 11, 2);
      final oct31 = LocalDate(2026, 10, 31);

      expect(relativeDayLabelForLocalDate(nov1, nov1), 'Today · Sun Nov 1');
      expect(relativeDayLabelForLocalDate(nov2, nov1), 'Tomorrow');
      expect(relativeDayLabelForLocalDate(oct31, nov1), 'Yesterday');
      expect(relativeDayLabelForLocalDate(nov1, nov2), 'Yesterday');
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

    test('full weekday names are Sunday-first (#138 semantics labels)', () {
      expect(fullWeekdayNames(), [
        'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
        'Saturday',
      ]);
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

  group('Issue #226 date-format preference', () {
    test('each preference pins its month/day pattern for the generic en '
        'fallback (month-first since issue #884)', () {
      expect(
          shortDayDatePattern(DateFormatPreference.system), 'EEE MMM d');
      expect(
          shortDayDatePattern(DateFormatPreference.dayMonth), 'EEE d MMM');
      expect(
          shortDayDatePattern(DateFormatPreference.monthDay), 'EEE MMM d');
      expect(weekdayDayDateYearPattern(DateFormatPreference.system),
          'EEE MMM d y');
      expect(weekdayDayDateYearPattern(DateFormatPreference.monthDay),
          'EEE MMM d y');
    });

    test('issue #884: system follows the locale while the explicit overrides '
        'stay literal', () {
      // en_US orders month before day; en_GB orders day before month.
      expect(
          shortDayDatePattern(DateFormatPreference.system, locale: 'en_US'),
          'EEE MMM d');
      expect(
          shortDayDatePattern(DateFormatPreference.system, locale: 'en_GB'),
          'EEE d MMM');
      expect(
          weekdayDayDateYearPattern(DateFormatPreference.system,
              locale: 'en_US'),
          'EEE MMM d y');
      expect(
          weekdayDayDateYearPattern(DateFormatPreference.system,
              locale: 'en_GB'),
          'EEE d MMM y');
      // dayMonth/monthDay never consult the locale.
      for (final locale in ['en_US', 'en_GB', 'de', 'ja']) {
        expect(
            shortDayDatePattern(DateFormatPreference.dayMonth, locale: locale),
            'EEE d MMM');
        expect(
            shortDayDatePattern(DateFormatPreference.monthDay, locale: locale),
            'EEE MMM d');
      }
    });

    test('issue #884: system renders the locale order end to end', () {
      final date = DateTime(2026, 9, 8);
      expect(formatShortDayDate(date, locale: 'en_US'), 'Tue Sep 8');
      // en_GB's own abbreviated month is "Sept".
      expect(formatShortDayDate(date, locale: 'en_GB'), 'Tue 8 Sept');
      expect(
          formatWeekdayDayDateYear(date, locale: 'en_US'), 'Tue Sep 8 2026');
      expect(
          formatWeekdayDayDateYear(date, locale: 'en_GB'), 'Tue 8 Sept 2026');
      // The explicit overrides are locale-independent.
      expect(
        formatShortDayDate(date,
            locale: 'en_GB', preference: DateFormatPreference.monthDay),
        'Tue Sept 8',
      );
      expect(
        formatShortDayDate(date,
            locale: 'en_US', preference: DateFormatPreference.dayMonth),
        'Tue 8 Sep',
      );
    });

    test('issue #884: the Settings sample matches the day sheet ordering', () {
      // 5 Sep 2026 is the illustrative date both surfaces use.
      expect(
        formatShortMonthDayExample(DateFormatPreference.system,
            locale: 'en_US'),
        'Sep 5',
      );
      expect(
        formatShortMonthDayExample(DateFormatPreference.system,
            locale: 'en_GB'),
        '5 Sept',
      );
      // The day sheet (formatShortDayDate) resolves the same order.
      final date = DateTime(2026, 9, 5);
      expect(formatShortDayDate(date, locale: 'en_US'), 'Sat Sep 5');
      expect(formatShortDayDate(date, locale: 'en_GB'), 'Sat 5 Sept');
      // Overrides stay literal regardless of locale.
      expect(
        formatShortMonthDayExample(DateFormatPreference.dayMonth,
            locale: 'en_US'),
        '5 Sep',
      );
      expect(
        formatShortMonthDayExample(DateFormatPreference.monthDay,
            locale: 'en_GB'),
        'Sept 5',
      );
    });

    test('formatShortDayDate reorders per preference', () {
      final date = DateTime(2026, 9, 8);
      expect(formatShortDayDate(date), 'Tue Sep 8');
      expect(
        formatShortDayDate(date, preference: DateFormatPreference.dayMonth),
        'Tue 8 Sep',
      );
      expect(
        formatShortDayDate(date, preference: DateFormatPreference.monthDay),
        'Tue Sep 8',
      );
    });

    test('formatWeekdayDayDateYear reorders per preference', () {
      final date = DateTime(2026, 9, 8);
      expect(formatWeekdayDayDateYear(date), 'Tue Sep 8 2026');
      expect(
        formatWeekdayDayDateYear(
          date,
          preference: DateFormatPreference.monthDay,
        ),
        'Tue Sep 8 2026',
      );
    });

    test('relativeDayLabel forwards the preference into both absolute forms',
        () {
      final today = DateTime(2026, 9, 8);
      expect(
        relativeDayLabel(today, today,
            preference: DateFormatPreference.monthDay),
        'Today · Tue Sep 8',
      );
      expect(
        relativeDayLabel(DateTime(2026, 9, 5), today,
            preference: DateFormatPreference.monthDay),
        'Sat Sep 5 2026',
      );
    });

    test('LocalDate helpers forward the preference', () {
      final date = LocalDate(2026, 9, 8);
      final today = LocalDate(2026, 9, 8);
      expect(
        formatLocalDateShortDayDate(date,
            preference: DateFormatPreference.monthDay),
        'Tue Sep 8',
      );
      expect(
        formatLocalDateWeekdayDayDateYear(date,
            preference: DateFormatPreference.monthDay),
        'Tue Sep 8 2026',
      );
      expect(
        relativeDayLabelForLocalDate(today, today,
            preference: DateFormatPreference.monthDay),
        'Today · Tue Sep 8',
      );
      expect(
        relativeDayLabelForLocalDate(LocalDate(2026, 9, 5), today,
            preference: DateFormatPreference.monthDay),
        'Sat Sep 5 2026',
      );
    });
  });
}
