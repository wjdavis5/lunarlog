/// Shared intl-backed date and calendar-name helpers (issue #160).
///
/// This library is deliberately standalone: it depends only on `intl` (plus
/// `BuildContext` for [calendarLocale]) and never on `AppLocalizations` or
/// any generated localizations machinery, so screens that only need
/// locale-derived date formatting can adopt it without the rest of the l10n
/// scaffolding (the coordination point issue #198 builds on). Every helper
/// takes an explicit locale string defaulting to `en` — the only locale this
/// app ships today — so the pure half is also usable with no widget tree at
/// all, including from unit tests.
///
/// Month and weekday *names* come from intl's compiled date symbols, not
/// hand-rolled constants: the calendar header, the month/year picker, and
/// the semantic day-cell labels all derive their names through here
/// (replacing the old `kMonthNames`/`kWeekdayLabels` lists). The
/// first-day-of-week policy itself lives in
/// `lib/ui/logging/month_calendar.dart` ([kFirstDayOfWeek]) — it is a
/// calendar-layout decision, not a formatting one.
library;

import 'dart:async' show unawaited;

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart' as date_symbols;
import 'package:lunarlog/domain/calendar_preferences.dart';
import 'package:lunarlog/domain/models/local_date.dart';

/// Whether [date_symbols.initializeDateFormatting] has run in this isolate.
/// It is synchronous (it only copies the compiled symbol maps into intl's
/// registry) and idempotent; running it lazily on first use keeps this
/// library standalone — no `flutter_localizations` delegates, no widget
/// tree, no async — which is the whole point of the #198 coordination
/// seam. Without it, a first `DateFormat(..., locale)` construction throws
/// `LocaleDataException` in any context the delegates have not already
/// initialized (a pure unit test, or a widget test under a bare
/// `MaterialApp`).
bool _dateSymbolsReady = false;

void _ensureDateSymbols() {
  if (_dateSymbolsReady) return;
  // Issue #548: returns a Future for API-compatibility reasons only — see
  // this field's own doc comment for why it completes synchronously in
  // practice and is deliberately never awaited here.
  unawaited(date_symbols.initializeDateFormatting());
  _dateSymbolsReady = true;
}

/// The app's fallback locale identifier: the only locale supported today
/// (issue #160 scaffolds localization; translations are follow-on work).
const String kFallbackLocale = 'en';

/// Long-form date, e.g. "September 5, 2026": the estimate and cycle-history
/// date format the overview previously assembled from `kMonthNames`.
String formatMonthDayYear(DateTime date, {String locale = kFallbackLocale}) {
  _ensureDateSymbols();
  return DateFormat('MMMM d, y', locale).format(date);
}

/// Long-form date for a [LocalDate], e.g. "September 5, 2026".
String formatLocalDateMonthDayYear(
  LocalDate date, {
  String locale = kFallbackLocale,
}) =>
    formatMonthDayYear(date.toDateTime(), locale: locale);

/// Month-and-day form, e.g. "September 5": dates inside a sentence that
/// already carries the year (or where the year is implied by "this cycle").
String formatMonthDay(DateTime date, {String locale = kFallbackLocale}) {
  _ensureDateSymbols();
  return DateFormat('MMMM d', locale).format(date);
}

/// Month-and-day form for a [LocalDate], e.g. "September 5".
String formatLocalDateMonthDay(
  LocalDate date, {
  String locale = kFallbackLocale,
}) =>
    formatMonthDay(date.toDateTime(), locale: locale);

/// Locale-aware short numeric date, e.g. "9/5/2026" for `en` (issue #554):
/// for the handful of screens that used to assemble a hand-rolled, always
/// `YYYY-MM-DD` string via manual zero-padding instead of a locale-aware
/// format.
String formatShortDate(DateTime date, {String locale = kFallbackLocale}) {
  _ensureDateSymbols();
  return DateFormat.yMd(locale).format(date);
}

/// Locale-aware short numeric date for a [LocalDate], e.g. "9/5/2026".
String formatLocalDateShortDate(
  LocalDate date, {
  String locale = kFallbackLocale,
}) =>
    formatShortDate(date.toDateTime(), locale: locale);

/// Short weekday-day-month form, e.g. "Tue 8 Sep": compact rows and the
/// relative label below. [preference] (Issue #226) reorders the month/day
/// pair — `monthDay` renders "Tue Sep 8". `system` follows [locale]'s own
/// order (issue #884): month-first ("Tue Sep 8") for `en_US`, day-first
/// ("Tue 8 Sep") for `en_GB`.
String formatShortDayDate(
  DateTime date, {
  String locale = kFallbackLocale,
  DateFormatPreference preference = DateFormatPreference.system,
}) {
  _ensureDateSymbols();
  return DateFormat(shortDayDatePattern(preference, locale: locale), locale)
      .format(date);
}

/// Short weekday-day-month form for a [LocalDate], e.g. "Tue 8 Sep".
String formatLocalDateShortDayDate(
  LocalDate date, {
  String locale = kFallbackLocale,
  DateFormatPreference preference = DateFormatPreference.system,
}) =>
    formatShortDayDate(
      date.toDateTime(),
      locale: locale,
      preference: preference,
    );

/// Whether [locale]'s own short numeric date orders the day before the
/// month (issue #884): true for `en_GB` ("5 Sep"), false for `en_US`
/// ("Sep 5"). The `system` [DateFormatPreference] resolves through this so
/// "System default" follows the locale instead of a fixed order, rather
/// than maintaining a hand-rolled country list.
bool _localeIsDayFirst(String locale) {
  _ensureDateSymbols();
  final pattern = DateFormat.yMd(locale).pattern ?? '';
  final day = pattern.indexOf('d');
  final month = pattern.indexOf('M');
  // Unknown patterns (neither marker present) fall back to month-first, the
  // generic-`en` ordering this library already rendered for an ambiguous
  // locale.
  return day != -1 && month != -1 && day < month;
}

/// The intl pattern [formatShortDayDate] renders with for [preference]
/// (Issue #226, locale-resolved since issue #884). Public and pure so a test
/// can pin each preference's ordering without running a formatter. `system`
/// derives its ordering from [locale]; `dayMonth`/`monthDay` are explicit
/// user overrides and stay literal.
String shortDayDatePattern(
  DateFormatPreference preference, {
  String locale = kFallbackLocale,
}) =>
    switch (preference) {
      DateFormatPreference.system =>
        _localeIsDayFirst(locale) ? 'EEE d MMM' : 'EEE MMM d',
      DateFormatPreference.dayMonth => 'EEE d MMM',
      DateFormatPreference.monthDay => 'EEE MMM d',
    };

/// The matching standalone-date pattern [formatWeekdayDayDateYear] renders
/// with for [preference] (Issue #226, locale-resolved since issue #884):
/// same ordering rule, plus the year.
String weekdayDayDateYearPattern(
  DateFormatPreference preference, {
  String locale = kFallbackLocale,
}) =>
    switch (preference) {
      DateFormatPreference.system =>
        _localeIsDayFirst(locale) ? 'EEE d MMM y' : 'EEE MMM d y',
      DateFormatPreference.dayMonth => 'EEE d MMM y',
      DateFormatPreference.monthDay => 'EEE MMM d y',
    };

/// The rendered day/month example the Settings "Date format" picker shows
/// (issue #884): one illustrative date ("5 Sep" or "Sep 5") under
/// [preference]'s ordering. `system` resolves through [locale] — the very
/// same decision [formatShortDayDate] uses — so the sample can never
/// advertise an order the day sheet will not render.
String formatShortMonthDayExample(
  DateFormatPreference preference, {
  String locale = kFallbackLocale,
}) {
  _ensureDateSymbols();
  final pattern = switch (preference) {
    DateFormatPreference.system =>
      _localeIsDayFirst(locale) ? 'd MMM' : 'MMM d',
    DateFormatPreference.dayMonth => 'd MMM',
    DateFormatPreference.monthDay => 'MMM d',
  };
  return DateFormat(pattern, locale).format(DateTime(2026, 9, 5));
}

/// Unambiguous weekday-day-month-year form, e.g. "Tue 8 Sep 2026": the form
/// used whenever a date stands alone (no surrounding "this week" context).
/// [preference] (Issue #226) reorders the month/day pair as in
/// [formatShortDayDate].
String formatWeekdayDayDateYear(
  DateTime date, {
  String locale = kFallbackLocale,
  DateFormatPreference preference = DateFormatPreference.system,
}) {
  _ensureDateSymbols();
  return DateFormat(weekdayDayDateYearPattern(preference, locale: locale), locale)
      .format(date);
}

/// Unambiguous weekday-day-month-year form for a [LocalDate], e.g. "Tue 8 Sep 2026".
String formatLocalDateWeekdayDayDateYear(
  LocalDate date, {
  String locale = kFallbackLocale,
  DateFormatPreference preference = DateFormatPreference.system,
}) =>
    formatWeekdayDayDateYear(
      date.toDateTime(),
      locale: locale,
      preference: preference,
    );

/// Human-readable relative day header for a [LocalDate] civil date pair,
/// e.g. "Today · Tue 8 Sep", "Yesterday", "Tomorrow", falling back to
/// [formatLocalDateWeekdayDayDateYear] for anything further out.
///
/// Civil date math is pure integer difference (`date.difference(today)`),
/// immune to DST transitions and local midnight hour lengths (issue #846).
String relativeDayLabelForLocalDate(
  LocalDate date,
  LocalDate today, {
  String locale = kFallbackLocale,
  String? todayLabel,
  String? yesterdayLabel,
  String? tomorrowLabel,
  DateFormatPreference preference = DateFormatPreference.system,
}) {
  final difference = date.difference(today);
  if (difference == 0) {
    return '${todayLabel ?? 'Today'} · ${formatShortDayDate(date.toDateTime(), locale: locale, preference: preference)}';
  }
  if (difference == -1) return yesterdayLabel ?? 'Yesterday';
  if (difference == 1) return tomorrowLabel ?? 'Tomorrow';
  return formatWeekdayDayDateYear(
    date.toDateTime(),
    locale: locale,
    preference: preference,
  );
}

/// Human-readable relative day header, e.g. "Today · Tue 8 Sep",
/// "Yesterday", "Tomorrow", falling back to [formatWeekdayDayDateYear] for
/// anything further out. Comparison is by civil day (time-of-day ignored).
///
/// Both [date] and [today] are converted to [LocalDate] so that civil day
/// difference is computed without instant/duration arithmetic across DST
/// boundaries (issue #846).
///
/// The relative words default to their English forms; callers that already
/// hold localized copy may override them via [todayLabel],
/// [yesterdayLabel], and [tomorrowLabel] so this helper needs no
/// `AppLocalizations` dependency of its own. [preference] (Issue #226)
/// reorders the month/day pair inside both absolute forms.
String relativeDayLabel(
  DateTime date,
  DateTime today, {
  String locale = kFallbackLocale,
  String? todayLabel,
  String? yesterdayLabel,
  String? tomorrowLabel,
  DateFormatPreference preference = DateFormatPreference.system,
}) =>
    relativeDayLabelForLocalDate(
      LocalDate.fromDateTime(date),
      LocalDate.fromDateTime(today),
      locale: locale,
      todayLabel: todayLabel,
      yesterdayLabel: yesterdayLabel,
      tomorrowLabel: tomorrowLabel,
      preference: preference,
    );

/// Full month names ("January".."December"), locale-derived. Index 0 is
/// January; callers with a 1-based calendar month use `names[month - 1]`.
List<String> monthNames({String locale = kFallbackLocale}) {
  _ensureDateSymbols();
  return List<String>.unmodifiable(
    DateFormat('MMMM', locale).dateSymbols.MONTHS,
  );
}

/// Three-letter month abbreviations ("Jan".."Dec"), locale-derived. Matches
/// what the month/year picker previously derived via
/// `kMonthNames[m].substring(0, 3)`.
List<String> shortMonthNames({String locale = kFallbackLocale}) {
  _ensureDateSymbols();
  return List<String>.unmodifiable(
    DateFormat('MMM', locale).dateSymbols.SHORTMONTHS,
  );
}

/// Narrow weekday initials, e.g. `['S', 'M', 'T', 'W', 'T', 'F', 'S']` for
/// `en`. The list is **Sunday-first** (intl's date-symbol order); a grid
/// whose weeks start on another day reorders it (see
/// `weekdayHeaderLabels` in `month_calendar.dart`).
List<String> narrowWeekdayInitials({String locale = kFallbackLocale}) {
  _ensureDateSymbols();
  return List<String>.unmodifiable(
    DateFormat('EEEE', locale).dateSymbols.NARROWWEEKDAYS,
  );
}

/// Full weekday names ("Sunday".."Saturday"), locale-derived. Issue #138:
/// the calendar's weekday header keeps the narrow initial as its visual
/// child but carries the matching entry of this list as its Semantics
/// label, so a screen reader hears "Sunday" instead of an ambiguous
/// single letter (two "S" and two "T" initials per week). Sunday-first,
/// same order contract as [narrowWeekdayInitials] — index with
/// `dateTime.weekday % 7` or reorder for a non-Sunday week start.
List<String> fullWeekdayNames({String locale = kFallbackLocale}) {
  _ensureDateSymbols();
  return List<String>.unmodifiable(
    DateFormat('EEEE', locale).dateSymbols.WEEKDAYS,
  );
}

/// The calendar's ambient locale identifier from the widget tree, for
/// widgets that format dates outside a `build` method that already resolved
/// it. Falls back to [kFallbackLocale] under a bare `MaterialApp` (widget
/// tests) and wherever no [Localizations] ancestor exists.
String calendarLocale(BuildContext context) {
  final locale = Localizations.maybeLocaleOf(context);
  return locale == null ? kFallbackLocale : locale.toString();
}
