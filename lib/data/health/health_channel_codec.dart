/// Pure codec for the `lunarlog/health` first-party platform channel
/// (Issue #173) — every map that crosses the channel is built and read
/// here, in one place, with no Flutter imports, so the wire protocol has
/// a single definition both sides of the Dart/native boundary can be
/// reviewed against (the native Swift/Kotlin handlers mirror these keys
/// and result strings; keep them in sync here only).
///
/// **Wire protocol** (StandardMethodCodec — maps of primitives):
///
/// | Method | Args | Result |
/// |---|---|---|
/// | `isAvailable` | none | `bool` |
/// | `bind` | guard args | result string |
/// | `unbind` | none | `null` |
/// | `requestWriteAuthorization` | guard args | result string |
/// | `writeMenstrualFlow` | guard + day + `flow` + `cycleStart` + `recordId` + `recordVersionMs` | result string |
/// | `writeIntermenstrualBleeding` | guard + day + `recordId` + `recordVersionMs` | result string |
/// | `writeMenstrualPeriod` | guard + period + `recordId` + `recordVersionMs` | result string |
/// | `deleteRecords` | guard + `recordIds` | result string |
///
/// *Guard args* (every guarded method): `profileId`, `signedInUserId?`,
/// `ownerUserId?`, `isMinor`, `birthYear?`, `transferredAtMs?`,
/// `minorBindingAllowed`. They are exactly
/// `HealthSyncBinding._evaluate`'s inputs (#153's guard) — the native
/// handler re-evaluates the mirrored predicate from them plus its own
/// natively-stored binding before touching any health API; see
/// `lib/domain/health/health_platform.dart`'s library doc.
///
/// *Day args*: `startMs`, `endMs` (inclusive, next local midnight − 1 s),
/// `endExclusiveMs` (next local midnight), `instantMs` (local midnight),
/// `zoneOffsetMs`, `endZoneOffsetMs` — all UTC epoch milliseconds /
/// offset milliseconds computed here via `day_boundary.dart` (#180's
/// timezone contract), so the native sides never do zone math.
///
/// *Period args* (the `writeMenstrualPeriod` interval record, #202):
/// `startMs` (local midnight of the episode's first day) +
/// `startZoneOffsetMs`, and `endMs` (the *exclusive* local midnight after
/// the episode's last day) + `endZoneOffsetMs` — the two instant/offset
/// pairs a `MenstruationPeriodRecord` needs, both computed here via
/// `day_boundary.dart` from the entry's own `tz`.
///
/// *Result strings*: `allowed`; the [HealthSyncCheck] deny names
/// (`noBinding`, `profileNotBound`, `minorRequiresOwnershipTransfer`,
/// `notOwner`) — deliberately the enum names, so the native mirrors and
/// this file cannot drift on vocabulary; and `unavailable` /
/// `permissionDenied` for platform outcomes. OS-level write failures
/// cross as `FlutterError(code: "writeFailed", ...)` (a
/// [PlatformException] on the Dart side) instead, carrying the
/// diagnostic message.
///
/// **Deferred permissions (issue #186, AC9):** `READ_HEALTH_DATA_HISTORY`
/// (full-history import) and `READ_HEALTH_DATA_IN_BACKGROUND` (background
/// reads) are deliberately NOT declared for v1. Reads are limited to the
/// last 30 days (Health Connect's change-token window) with a
/// user-initiated sync plus a foreground-resume sync — the same
/// background-delivery deferral rationale as #156 (HS-2) — so the Play
/// form needs no extra permission justification. Both the Settings copy
/// and this comment record that decision; the Settings screen states the
/// 30-day limit explicitly rather than silently truncating.
library;

import 'package:lunarlog/domain/health/day_boundary.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/models/local_date.dart';

/// Method names on the `lunarlog/health` channel.
abstract final class HealthChannelMethods {
  static const isAvailable = 'isAvailable';
  static const bind = 'bind';
  static const unbind = 'unbind';
  static const requestWriteAuthorization = 'requestWriteAuthorization';
  static const writeMenstrualFlow = 'writeMenstrualFlow';
  static const writeIntermenstrualBleeding = 'writeIntermenstrualBleeding';
  static const writeMenstrualPeriod = 'writeMenstrualPeriod';
  static const deleteRecords = 'deleteRecords';
}

/// The [HealthSyncCheck] name as it appears on the wire — the enum's own
/// name, used verbatim by the native guard mirrors, so a mismatch shows
/// up as an unknown result string rather than a silent misread.
String healthSyncCheckToWire(HealthSyncCheck check) => check.name;

/// Parses a result string into the typed [HealthPlatformResult]. Total:
/// never throws; an unrecognized string becomes
/// `HealthPlatformResult.failed` (a protocol error — e.g. a newer native
/// side — must surface, not silently degrade), and a `refused` carrying
/// `allowed` (a native bug) likewise degrades to `failed` rather than
/// read as success.
HealthPlatformResult decodeHealthResult(Object? raw) {
  if (raw is! String) {
    return HealthPlatformResult.failed(
      'unexpected channel result (${raw.runtimeType}): $raw',
    );
  }
  switch (raw) {
    case 'allowed':
      return const HealthPlatformResult.allowed();
    case 'unavailable':
      return const HealthPlatformResult.unavailable();
    case 'permissionDenied':
      return const HealthPlatformResult.permissionDenied();
    default:
      final check = _checkFromWire(raw);
      if (check != null && check != HealthSyncCheck.allowed) {
        return HealthPlatformResult.refused(check);
      }
      return HealthPlatformResult.failed('unknown channel result: $raw');
  }
}

HealthSyncCheck? _checkFromWire(String raw) {
  for (final check in HealthSyncCheck.values) {
    if (check.name == raw) return check;
  }
  return null;
}

/// The guard-args half of every guarded call. [minorBindingAllowed] is
/// passed in by the adapter (sourced from
/// `AppConfig.healthSyncMinorBindingAllowed` in production wiring —
/// never invented by a call site; see [HealthGuardFacts]).
Map<String, Object?> encodeGuardArgs(
  HealthGuardFacts facts, {
  required bool minorBindingAllowed,
}) => {
        'profileId': facts.profile.id,
        'signedInUserId': facts.signedInUserId,
        'ownerUserId': facts.ownerUserId,
        'isMinor': facts.profile.isMinor,
        'birthYear': facts.profile.birthYear,
        'transferredAtMs': facts.profile.transferredAt?.millisecondsSinceEpoch,
        'minorBindingAllowed': minorBindingAllowed,
      };

/// The day-args half: every instant/offset the two platforms may need
/// for one civil day, as UTC epoch milliseconds and offset milliseconds
/// (StandardMessageCodec int64). Computed via `day_boundary.dart` — an
/// unresolvable `tzName` throws [TimeZoneResolutionException], which the
/// adapter (not the caller) catches and turns into
/// `HealthPlatformResult.failed` so the port stays total.
Map<String, Object?> encodeDayArgs(LocalDate date, String tzName) {
  final interval = localDayInterval(date, tzName);
  return {
        'startMs': interval.start.millisecondsSinceEpoch,
        'endMs': interval.end.millisecondsSinceEpoch,
        'endExclusiveMs':
            localDayEndExclusive(date, tzName).millisecondsSinceEpoch,
        'instantMs': localDayInstant(date, tzName).millisecondsSinceEpoch,
        'zoneOffsetMs': zoneOffsetFor(date, tzName).inMilliseconds,
        'endZoneOffsetMs': endZoneOffsetFor(date, tzName).inMilliseconds,
  };
}

/// The period-args half for one `writeMenstrualPeriod` (Issue #202): the
/// instant/offset pair for the interval record's start (local midnight of
/// [start]) and its end (the *exclusive* local midnight after [end], plus
/// that instant's own offset — on a DST-transition day it differs from the
/// start offset, which is exactly why they are computed together here).
/// All from the entry's own `tzName` via `day_boundary.dart` (#180's
/// timezone contract — never the device's current zone); the native side
/// does no zone math.
Map<String, Object?> encodePeriodDayArgs(
  LocalDate start,
  LocalDate end,
  String tzName,
) {
  return {
    'startMs': localDayInstant(start, tzName).millisecondsSinceEpoch,
    'startZoneOffsetMs': zoneOffsetFor(start, tzName).inMilliseconds,
    'endMs': localDayEndExclusive(end, tzName).millisecondsSinceEpoch,
    'endZoneOffsetMs': endZoneOffsetFor(end, tzName).inMilliseconds,
  };
}
