/// Canonical IANA timezone resolution (finding #23 in #37, issue #46, issue #169).
///
/// Decoupled from the notification scheduler (issue #169): queries the OS
/// directly via [FlutterTimezone] so the result is accurate even if reminders
/// are disabled, permission denied, or scheduler init has not yet completed.
library;

import 'dart:async';

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

typedef TimezoneProvider = FutureOr<String> Function();
typedef PlatformTimeZoneProvider = Future<String?> Function();

PlatformTimeZoneProvider? _globalPlatformTimeZoneProvider;

/// Configures the process-wide platform time zone provider (supplied by the
/// platform/data layer at app bootstrap).
void configurePlatformTimeZoneProvider(PlatformTimeZoneProvider? provider) {
  _globalPlatformTimeZoneProvider = provider;
}

/// Resolves the current canonical IANA timezone identifier.
///
/// Decoupled from the notification scheduler (issue #169): queries the OS
/// directly via [platformTimeZoneProvider] or the configured global provider
/// so the result is accurate even if reminders are disabled, permission denied,
/// or scheduler init has not yet completed.
///
/// If timezone database has not been populated yet, initializes it once.
/// Updates [tz.local] when a valid IANA location is returned.
/// Returns the canonical IANA name (e.g. 'America/New_York', 'Etc/UTC', etc.).
Future<String> resolveCurrentTimeZone({
  PlatformTimeZoneProvider? platformTimeZoneProvider,
}) async {
  if (tz.timeZoneDatabase.locations.isEmpty) {
    tzdata.initializeTimeZones();
  }
  final provider = platformTimeZoneProvider ?? _globalPlatformTimeZoneProvider;
  if (provider != null) {
    try {
      final tzName = await provider();
      if (tzName != null && isValidIanaTimeZone(tzName)) {
        try {
          final loc = tz.getLocation(tzName);
          tz.setLocalLocation(loc);
        } catch (_) {}
        return tzName;
      }
    } catch (_) {}
  }
  return tz.local.name;
}

/// Synchronous fallback returning [tz.local.name] when an async query is
/// not possible. Prefer [resolveCurrentTimeZone].
String resolveCurrentTimeZoneSync() {
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

