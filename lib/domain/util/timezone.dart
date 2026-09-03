/// Canonical IANA timezone resolution (finding #23 in #37, issue #46).
///
/// Paired with the timezone resolution in #38: uses [tz.local.name] when
/// initialized, or defaults to initialization via [tzdata.initializeTimeZones].
library;

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Resolves the current canonical IANA timezone identifier.
///
/// If timezone database has not been populated yet, initializes it once.
/// Returns the canonical IANA name of [tz.local] (e.g. 'America/New_York',
/// 'Etc/UTC', etc.).
String resolveCurrentTimeZone() {
  if (tz.timeZoneDatabase.locations.isEmpty) {
    tzdata.initializeTimeZones();
  }
  return tz.local.name;
}

/// Returns true if [tzName] is a recognized canonical IANA timezone identifier
/// present in the tz database.
bool isValidIanaTimeZone(String tzName) {
  if (tz.timeZoneDatabase.locations.isEmpty) {
    tzdata.initializeTimeZones();
  }
  return tz.timeZoneDatabase.locations.containsKey(tzName);
}
