/// Day-boundary and time-zone contract for the Health Platform Sync epic
/// (Issue #180) — the conversion this project's two prior timezone bugs
/// (#38: reminders firing at 09:00 UTC instead of device-local time; #46:
/// a timezone name format contract mismatch) are exactly the kind of
/// regression this file exists to make impossible for the health adapter.
///
/// **The rule every future platform adapter (HealthKit via #173, Health
/// Connect via the same epic) MUST follow:**
///
///  - **Write direction:** an entry stored as `local_date` + `tz` is
///    converted to platform instants via [localDayInterval] (HealthKit
///    category samples, which take a `start`/`end` pair) or
///    [localDayInstant] (Health Connect instant records, which take a
///    single `time`). On Android, the record's `zoneOffset` field MUST be
///    set from [zoneOffsetFor] — i.e. from the entry's own `tz` — **never**
///    from the device's current zone. A traveller's device zone can differ
///    from the zone an entry was actually logged in, and `zoneOffset` is
///    exactly the field that would silently encode the wrong day if that
///    distinction were dropped.
///  - **Import direction:** a platform sample's own instant is converted
///    back to a `local_date` via [localDateForSample], using the sample's
///    **own** zone/offset (HealthKit's `TimeZone` metadata key, or Health
///    Connect's `zoneOffset`) — again, never the device's current zone.
///    The whole point of carrying `tz` per-entry (rather than assuming
///    "today's device zone" at read time) is that an import can run long
///    after the sample was recorded, on a different device, in a different
///    zone.
///  - Every function in this file is pure Dart, has no platform-channel or
///    Flutter dependency, and never reads [DateTime.now] or any ambient
///    device-zone state (mirrors [LocalDate]'s own "pure civil-date math,
///    never instant/Duration math" discipline, R11/KTD5) — the one
///    exception being that [tz.getLocation] itself resolves an IANA name
///    against a shared, explicitly-initialized zone database, not the
///    device's *current* zone setting.
///
/// This file does not wire into any platform adapter yet (#173 lands the
/// HealthKit adapter; the equivalent Health Connect adapter is a later
/// epic issue) — it is the pure contract those adapters must call into,
/// proven independently of either platform SDK.
///
/// **Caller contract (review addition, Issue #180):** every zone-resolving
/// function here ([localDayInterval], [localDayInstant],
/// [localDateForSample] when called with `tzName`, [zoneOffsetFor]) lazily
/// initializes the shared `timezone` package database on first use — the
/// same `tz.timeZoneDatabase.locations.isEmpty` check-then-
/// `tzdata.initializeTimeZones()` pattern `lib/domain/util/timezone.dart`
/// already uses for `resolveCurrentTimeZone`/`isValidIanaTimeZone` — so a
/// caller never has to remember to initialize the database itself before
/// calling into this file. A failure to resolve a zone always surfaces as
/// a typed [TimeZoneResolutionException], which carries a
/// [TimeZoneResolutionReason] distinguishing the two ways resolution can
/// fail: [TimeZoneResolutionReason.unknownZone] (the string is not a zone
/// this database recognizes — almost certainly a bad/malformed `tzName`,
/// the caller's problem) from [TimeZoneResolutionReason.notInitialized]
/// (the database is still empty even after this file's own lazy-init
/// attempt — an environment/bundling problem, e.g. the `timezone`
/// package's data asset failed to load, never a bad zone string). Since
/// every function here initializes the database itself before resolving,
/// a caller should essentially never observe
/// [TimeZoneResolutionReason.notInitialized] in practice; it exists so
/// that if it ever does happen, the exception says so directly instead of
/// masquerading as an ordinary bad-zone-name error.
library;

import 'package:lunarlog/domain/models/local_date.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Distinguishes why [TimeZoneResolutionException] was thrown — see this
/// file's doc comment, "Caller contract".
enum TimeZoneResolutionReason {
  /// The `timezone` package database is still empty even after this
  /// file's own lazy-init attempt — an environment/bundling problem, not a
  /// bad zone string.
  notInitialized,

  /// The database is initialized, but the zone string this exception
  /// carries is not a name or abbreviation it recognizes.
  unknownZone,
}

/// Thrown by every zone-resolving function in this file when [tzName]
/// cannot be resolved to a [tz.Location] — see this file's doc comment,
/// "Caller contract", for how [reason] distinguishes an unknown zone
/// string from a database that failed to initialize.
class TimeZoneResolutionException implements Exception {
  TimeZoneResolutionException(this.reason, this.tzName);

  final TimeZoneResolutionReason reason;
  final String tzName;

  @override
  String toString() => switch (reason) {
        TimeZoneResolutionReason.notInitialized =>
          'TimeZoneResolutionException: timezone database not initialized '
              '(resolving "$tzName")',
        TimeZoneResolutionReason.unknownZone =>
          'TimeZoneResolutionException: unknown time zone "$tzName"',
      };
}

/// Resolves [tzName] to a [tz.Location], lazily initializing the shared
/// `timezone` package database on first use (mirrors
/// `lib/domain/util/timezone.dart`'s pattern). Throws
/// [TimeZoneResolutionException] instead of letting a raw
/// [tz.LocationNotFoundException] escape — see this file's doc comment,
/// "Caller contract", for what [TimeZoneResolutionReason] distinguishes.
tz.Location _resolveLocation(String tzName) {
  if (tz.timeZoneDatabase.locations.isEmpty) {
    tzdata.initializeTimeZones();
  }
  try {
    return tz.getLocation(tzName);
  } on tz.LocationNotFoundException {
    throw TimeZoneResolutionException(
      tz.timeZoneDatabase.locations.isEmpty
          ? TimeZoneResolutionReason.notInitialized
          : TimeZoneResolutionReason.unknownZone,
      tzName,
    );
  }
}

/// The UTC instants bracketing local calendar day [date] in the IANA zone
/// [tzName], for an INTERVAL sample (HealthKit's `HKCategorySample`
/// `start`/`end`).
///
/// `start` is local midnight of [date]; `end` is local midnight of the
/// following day minus one second — this project's existing
/// last-second-of-the-day convention (matches how a whole civil day is
/// already represented elsewhere in this codebase), not HealthKit's own
/// half-open-interval semantics, which the adapter is responsible for
/// reconciling against the actual HealthKit API shape it targets.
///
/// Throws [TimeZoneResolutionException] if [tzName] cannot be resolved —
/// see this file's doc comment, "Caller contract".
({DateTime start, DateTime end}) localDayInterval(LocalDate date, String tzName) {
  final location = _resolveLocation(tzName);
  final start = tz.TZDateTime(location, date.year, date.month, date.day);
  final nextDay = date.addDays(1);
  final nextMidnight =
      tz.TZDateTime(location, nextDay.year, nextDay.month, nextDay.day);
  final end = nextMidnight.subtract(const Duration(seconds: 1));
  return (start: start.toUtc(), end: end.toUtc());
}

/// The single UTC instant for local midnight of [date] in the IANA zone
/// [tzName], for a POINT sample (Health Connect's instant records, which
/// carry one `time` rather than a `start`/`end` pair).
///
/// Throws [TimeZoneResolutionException] if [tzName] cannot be resolved
/// (see [localDayInterval]'s doc comment).
DateTime localDayInstant(LocalDate date, String tzName) {
  final location = _resolveLocation(tzName);
  return tz.TZDateTime(location, date.year, date.month, date.day).toUtc();
}

/// Resolves the [LocalDate] an imported platform sample belongs to, using
/// the SAMPLE'S OWN zone or offset — never the device's current zone
/// (`tz.local`). Exactly one of [tzName] or [offset] must be supplied:
/// [tzName] for a HealthKit sample carrying an IANA zone name, [offset]
/// for a Health Connect record carrying only a raw `zoneOffset` `Duration`
/// (Health Connect's instant records do not carry an IANA name, only the
/// UTC offset in effect when the record was written).
///
/// Named [tzName] rather than the issue sketch's `tz`, since this file
/// imports the `timezone` package under the conventional `tz` prefix
/// (matching every other timezone-consuming file in this codebase,
/// e.g. `lib/data/notifications/notification_scheduler.dart`) — a
/// same-named parameter would shadow that prefix for the whole function
/// body.
///
/// Throws [ArgumentError] if both or neither of [tzName]/[offset] are
/// supplied, or [TimeZoneResolutionException] if [tzName] cannot be
/// resolved (see this file's doc comment, "Caller contract").
LocalDate localDateForSample(
  DateTime instant, {
  String? tzName,
  Duration? offset,
}) {
  if ((tzName == null) == (offset == null)) {
    throw ArgumentError(
      'localDateForSample requires exactly one of tzName or offset '
      '(got tzName=$tzName, offset=$offset)',
    );
  }
  if (tzName != null) {
    final location = _resolveLocation(tzName);
    final local = tz.TZDateTime.from(instant, location);
    return LocalDate(local.year, local.month, local.day);
  }
  final local = instant.toUtc().add(offset!);
  return LocalDate(local.year, local.month, local.day);
}

/// The UTC offset in effect at local midnight of [date] in the IANA zone
/// [tzName] — Health Connect's `zoneOffset` field for a write on that
/// date. DST-aware: the returned [Duration] differs across a
/// spring-forward/fall-back transition, which is exactly why this is
/// computed per-date rather than cached once per zone.
///
/// Throws [TimeZoneResolutionException] if [tzName] cannot be resolved
/// (see [localDayInterval]'s doc comment).
Duration zoneOffsetFor(LocalDate date, String tzName) {
  final location = _resolveLocation(tzName);
  return tz.TZDateTime(location, date.year, date.month, date.day)
      .timeZoneOffset;
}
