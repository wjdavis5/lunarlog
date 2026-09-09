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

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart' as date_symbols;

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
  date_symbols.initializeDateFormatting();
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

/// Month-and-day form, e.g. "September 5": dates inside a sentence that
/// already carries the year (or where the year is implied by "this cycle").
String formatMonthDay(DateTime date, {String locale = kFallbackLocale}) {
  _ensureDateSymbols();
  return DateFormat('MMMM d', locale).format(date);
}

/// Short weekday-day-month form, e.g. "Tue 8 Sep": compact rows and the
/// relative label below.
String formatShortDayDate(DateTime date, {String locale = kFallbackLocale}) {
  _ensureDateSymbols();
  return DateFormat('EEE d MMM', locale).format(date);
}

/// Unambiguous weekday-day-month-year form, e.g. "Tue 8 Sep 2026": the form
/// used whenever a date stands alone (no surrounding "this week" context).
String formatWeekdayDayDateYear(
  DateTime date, {
  String locale = kFallbackLocale,
}) {
  _ensureDateSymbols();
  return DateFormat('EEE d MMM y', locale).format(date);
}

/// Human-readable relative day header, e.g. "Today · Tue 8 Sep",
/// "Yesterday", "Tomorrow", falling back to [formatWeekdayDayDateYear] for
/// anything further out. Comparison is by civil day (time-of-day ignored).
///
/// The relative words default to their English forms; callers that already
/// hold localized copies may override them via [todayLabel],
/// [yesterdayLabel], and [tomorrowLabel] so this helper needs no
/// `AppLocalizations` dependency of its own.
String relativeDayLabel(
  DateTime date,
  DateTime today, {
  String locale = kFallbackLocale,
  String? todayLabel,
  String? yesterdayLabel,
  String? tomorrowLabel,
}) {
  final day = DateTime(date.year, date.month, date.day);
  final reference = DateTime(today.year, today.month, today.day);
  final difference = day.difference(reference).inDays;
  if (difference == 0) {
    return '${todayLabel ?? 'Today'} · ${formatShortDayDate(date, locale: locale)}';
  }
  if (difference == -1) return yesterdayLabel ?? 'Yesterday';
  if (difference == 1) return tomorrowLabel ?? 'Tomorrow';
  return formatWeekdayDayDateYear(date, locale: locale);
}

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

/// The calendar's ambient locale identifier from the widget tree, for
/// widgets that format dates outside a `build` method that already resolved
/// it. Falls back to [kFallbackLocale] under a bare `MaterialApp` (widget
/// tests) and wherever no [Localizations] ancestor exists.
String calendarLocale(BuildContext context) {
  final locale = Localizations.maybeLocaleOf(context);
  return locale == null ? kFallbackLocale : locale.toString();
}
