/// Canonical IANA timezone resolution (finding #23 in #37, issue #46, issue #169).
///
/// Decoupled from the notification scheduler (issue #169): queries the OS
/// directly via [FlutterTimezone] so the result is accurate even if reminders
/// are disabled, permission denied, or scheduler init has not yet completed.
library;

import 'dart:async';

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

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

/// The fixed-offset zone designator this app writes for a Health Connect
/// record that carries only a raw `zoneOffset` (Issue #458): `UTC`,
/// `UTC+05:30`, `UTC-04:00`. A Health Connect `MenstruationFlowRecord` /
/// `IntermenstrualBleedingRecord` has no IANA name, only the offset in
/// effect when it was written; this preserves that offset faithfully so an
/// imported `(local_date, tz)` pair stays internally consistent without
/// inventing a device zone.
String fixedOffsetZoneName(Duration offset) {
  if (offset == Duration.zero) return 'UTC';
  final sign = offset.isNegative ? '-' : '+';
  final abs = offset.abs();
  final hours = abs.inHours.toString().padLeft(2, '0');
  final minutes = (abs.inMinutes % 60).toString().padLeft(2, '0');
  return 'UTC$sign$hours:$minutes';
}

/// Whether [value] is a [fixedOffsetZoneName] designator — accepted
/// alongside [isValidIanaTimeZone] wherever a stored `tz` is validated
/// (e.g. restore-from-file), so an entry imported from Health Connect
/// round-trips through JSON export/import.
bool isFixedOffsetZoneName(String value) {
  if (value == 'UTC') return true;
  final match = RegExp(r'^UTC([+-])(\d{2}):(\d{2})$').firstMatch(value);
  if (match == null) return false;
  final hours = int.parse(match.group(2)!);
  final minutes = int.parse(match.group(3)!);
  return hours <= 18 && minutes < 60;
}

