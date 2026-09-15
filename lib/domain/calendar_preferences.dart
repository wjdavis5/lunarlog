/// Device-local calendar-display preferences (Issue #226): the week-start
/// day and the compact date-order preference, both persisted through
/// [SettingsStore] string values and parsed here. Pure Dart by design —
/// `lib/ui/l10n/dates.dart` and the Settings UI both consume it, so it
/// carries no Flutter dependency (the same posture as the domain layer's
/// other pure value modules).
///
/// Storage values are stable strings (`'sunday'`/`'monday'`,
/// `'system'`/`'day_month'`/`'month_day'`); an absent or unrecognized
/// value reads as the app's historical default ([CalendarFirstDay.sunday]
/// for the week start, [DateFormatPreference.system] for date order), the
/// same forward-compatibility posture `themeModeFromStored` established
/// for the appearance override — a future value can never wedge the app.
library;

/// The day a calendar grid's weeks start on. Deliberately a two-value set:
/// Sunday (the app's historical default, `kFirstDayOfWeek` in
/// `lib/ui/logging/month_calendar.dart`) and Monday (the ISO 8601 week
/// start most non-US locales expect). Deriving a default from the active
/// locale remains follow-on work, exactly as that seam's own doc comment
/// records.
enum CalendarFirstDay {
  sunday('sunday', 7),
  monday('monday', 1);

  const CalendarFirstDay(this.storedValue, this.weekday);

  /// The string persisted in [SettingsKeys.calendarFirstDayOfWeek].
  final String storedValue;

  /// The `DateTime` weekday constant (`DateTime.monday`..`DateTime.sunday`;
  /// Dart has no static const access into those, so the literals are
  /// spelled here once) — the unit `leadingBlanksFor` and
  /// `weekdayHeaderLabels` in `lib/ui/logging/month_calendar.dart` consume.
  final int weekday;

  /// Parses a stored value; null (never set) or anything unrecognized
  /// reads as [CalendarFirstDay.sunday], the pre-#226 layout.
  static CalendarFirstDay fromStored(String? stored) => switch (stored) {
        'monday' => CalendarFirstDay.monday,
        _ => CalendarFirstDay.sunday,
      };
}

/// The order a compact month-and-day date renders in: the locale's own
/// order, or an explicit day-first ("5 Sep") / month-first ("Sep 5")
/// override. Consumed by `lib/ui/l10n/dates.dart`'s short-date helpers
/// (`formatShortDayDate` and the `relativeDayLabel` built on it), which
/// map each value onto an `intl` pattern — #198's fuller date-formatting
/// pass builds on the same seam.
enum DateFormatPreference {
  system('system'),
  dayMonth('day_month'),
  monthDay('month_day');

  const DateFormatPreference(this.storedValue);

  /// The string persisted in [SettingsKeys.dateFormat].
  final String storedValue;

  /// Parses a stored value; null (never set) or anything unrecognized
  /// reads as [DateFormatPreference.system] — the locale's own order,
  /// which is what every date rendered before this setting existed.
  static DateFormatPreference fromStored(String? stored) => switch (stored) {
        'day_month' => DateFormatPreference.dayMonth,
        'month_day' => DateFormatPreference.monthDay,
        _ => DateFormatPreference.system,
      };
}
