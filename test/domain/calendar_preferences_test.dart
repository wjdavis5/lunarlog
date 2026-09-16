/// Unit tests for `lib/domain/calendar_preferences.dart` (Issue #226):
/// the stored-value parsing/encoding of the week-start and date-order
/// preferences, including the absent/unrecognized-value defaults that keep
/// a future value from wedging the app.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/calendar_preferences.dart';

void main() {
  group('CalendarFirstDay', () {
    test('weekday constants match the DateTime numbering', () {
      // `DateTime.monday`/`.sunday` are 1/7; spelled as literals in the
      // enum, so pin them against the dart:core constants here.
      expect(CalendarFirstDay.monday.weekday, DateTime.monday);
      expect(CalendarFirstDay.sunday.weekday, DateTime.sunday);
    });

    test('fromStored parses every stored value and round-trips', () {
      for (final value in CalendarFirstDay.values) {
        expect(CalendarFirstDay.fromStored(value.storedValue), value);
      }
    });

    test(
        'fromStored reads null, empty, and unrecognized values as Sunday '
        '(the pre-#226 layout)', () {
      expect(CalendarFirstDay.fromStored(null), CalendarFirstDay.sunday);
      expect(CalendarFirstDay.fromStored(''), CalendarFirstDay.sunday);
      expect(
        CalendarFirstDay.fromStored('tuesday'),
        CalendarFirstDay.sunday,
      );
    });
  });

  group('DateFormatPreference', () {
    test('fromStored parses every stored value and round-trips', () {
      for (final value in DateFormatPreference.values) {
        expect(DateFormatPreference.fromStored(value.storedValue), value);
      }
    });

    test(
        'fromStored reads null, empty, and unrecognized values as system '
        '(the pre-#226 behaviour)', () {
      expect(DateFormatPreference.fromStored(null), DateFormatPreference.system);
      expect(DateFormatPreference.fromStored(''), DateFormatPreference.system);
      expect(
        DateFormatPreference.fromStored('iso_8601'),
        DateFormatPreference.system,
      );
    });
  });
}
