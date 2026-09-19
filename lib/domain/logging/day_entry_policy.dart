/// Issue #848: the date-bounds policy every day-entry *write* path shares.
///
/// Before this, the only future-date block in the app lived on the calendar
/// cell itself (`lib/ui/logging/month_calendar.dart`), so every write that
/// bypassed the calendar — restore/import, the bulk import seam, the
/// health import, the quick-log FAB, or `sync_push` — happily accepted
/// `2999-01-01`, and nothing anywhere compared an entry's date against the
/// profile's `birth_year`. The local date check that did exist
/// (`_validateLocalDate` in `lib/data/db/storage_local_writes.dart`) checked
/// shape only.
///
/// Pure Dart, no Flutter and no clock read inside: the caller passes
/// [DayEntryPolicy.validateDate]'s [today], matching this repo's clock-seam
/// discipline (`LocalDate.today()` is read only at the boundary).
library;

import '../models/local_date.dart';

/// Which date-bounds rule rejected a day entry. Typed rather than a bare
/// bool so a caller can report the reason honestly, following the failure
/// shape each write path already uses.
enum DayEntryDateViolation {
  /// The date is more than one calendar day after the caller's [today].
  /// The tolerated extra day is deliberate: a real user in a time zone
  /// ahead of the device's notion of today can legitimately log a date the
  /// device still considers tomorrow.
  futureDate,

  /// The date's calendar year precedes the profile's known `birth_year`.
  /// Only the year is compared — the stored `birth_year` carries no month
  /// or day, so a date in the birth year itself is left alone.
  beforeBirthYear,
}

/// [DayEntryPolicy.validateDate]'s result: a typed, reportable outcome.
class DayEntryDateValidation {
  /// The date satisfies both rules.
  const DayEntryDateValidation.valid() : violation = null;

  /// The date is more than one calendar day after `today`.
  const DayEntryDateValidation.futureDate()
      : violation = DayEntryDateViolation.futureDate;

  /// The date's year precedes the profile's `birth_year`.
  const DayEntryDateValidation.beforeBirthYear()
      : violation = DayEntryDateViolation.beforeBirthYear;

  /// The rule that failed, or null when the date is valid.
  final DayEntryDateViolation? violation;

  /// Whether the date is accepted.
  bool get isValid => violation == null;
}

/// The shared day-entry date-bounds policy (Issue #848). Stateless; the
/// private constructor keeps it a namespace rather than an instance.
abstract final class DayEntryPolicy {
  const DayEntryPolicy._();

  /// Validates [date] against [today] and, when known, the profile's
  /// [birthYear].
  ///
  /// * A date after `today + 1 day` fails with
  ///   [DayEntryDateViolation.futureDate]. The +1 tolerance absorbs
  ///   time-zone travel: a user whose local calendar is one day ahead of
  ///   this device's is still logging a real "today".
  /// * A date whose year is before [birthYear] fails with
  ///   [DayEntryDateViolation.beforeBirthYear]. A null [birthYear] (an
  ///   unknown subject birth year) leaves the second rule unapplied.
  ///
  /// [today] is read by the caller at the boundary and passed in — this
  /// function never reads a clock itself, so it is deterministic and
  /// trivially testable.
  static DayEntryDateValidation validateDate(
    LocalDate date, {
    required LocalDate today,
    int? birthYear,
  }) {
    if (date.isAfter(today.addDays(1))) {
      return const DayEntryDateValidation.futureDate();
    }
    if (birthYear != null && date.year < birthYear) {
      return const DayEntryDateValidation.beforeBirthYear();
    }
    return const DayEntryDateValidation.valid();
  }
}
