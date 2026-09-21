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
/// | `writeSymptomSamples` | guard + day + `samples` (list of `{typeIdentifier, severity, recordId, recordVersionMs}`) | result string |
/// | `writeCervicalMucus` | guard + day + `healthKitValue` + `healthConnectAppearance` + `recordId` + `recordVersionMs` | result string |
/// | `writeOvulationTest` | guard + day + `healthKitResult` + `healthConnectResult` + `recordId` + `recordVersionMs` | result string |
/// | `writeBasalBodyTemperature` | guard + BBT instant args + `celsius` + `healthConnectMeasurementLocation` + `recordId` + `recordVersionMs` | result string |
/// | `deleteRecords` | guard + `recordIds` | result string |
/// | `permissionStatus` | none | one of `granted` / `notAsked` / `denied` / `unavailable` |
/// | `openPermissionSettings` | none | `null` |
/// | `readMenstrualFlowPage` | guard + `startMs` + `endMs` + `pageSize` + `cursor?` | a page `Map` (`samples` list + `nextCursor`), or a result string |
///
/// *Page result* (`readMenstrualFlowPage`, Issue #992): a `Map` with
/// `'samples'` — a `List` of the sample maps below — and `'nextCursor'` —
/// the opaque cursor string for the next page, omitted or null when the
/// stream is exhausted. A bare `List` is also still accepted by
/// [decodeHealthReadResult] as a legacy single-page/exhausted success, so a
/// result-string protocol error is never silently read as data.
///
/// *Sample maps* (`readMenstrualFlowPage`): `recordId`, `startMs`, `endMs`, and
/// either an iOS-only `tzName` (the sample's IANA zone, #217) or an
/// Android-only `zoneOffsetSeconds` (Health Connect's raw `zoneOffset`,
/// #458) — the #180 "resolve the civil date from the sample's own zone"
/// contract. An optional iOS-only `zoneOffsetInferred` boolean (Issue #902)
/// rides alongside a `zoneOffsetSeconds` the iOS read synthesised from the
/// *device's* zone because the sample carried no `HKMetadataKeyTimeZone`
/// (Apple's own Health app's hand-logged menstruation samples never do): it
/// is true only for that fallback, so Dart places the sample yet reports it
/// as inferred rather than as the sample's own recorded zone. Health Connect
/// never sets it — its `zoneOffset` is the record's own. An optional `kind`
/// distinguishes a `MenstruationFlowRecord`
/// (`menstrualFlow`, the pre-#458 default when absent) from an
/// `IntermenstrualBleedingRecord` (`intermenstrualBleeding`, which carries
/// no `flow`). An optional `flow` intensity is present for menstrual-flow
/// samples; `externalUuid` (iOS) is diagnostic only.
///
/// *Guard args* (every guarded method): `profileId`, `signedInUserId?`,
/// `ownerUserId?`, `isMinor`, `birthYear?`, `transferredAtMs?`,
/// `transferredToUserId?`, `minorBindingAllowed`. They are exactly
/// `HealthSyncBinding._evaluate`'s inputs (#153's guard) — the native
/// handler re-evaluates the mirrored predicate from them plus its own
/// natively-stored binding before touching any health API; see
/// `lib/domain/health/health_platform.dart`'s library doc.
/// `transferredToUserId` (Issue #619, LLA-031) closes a native/Dart
/// defense-in-depth gap: without it, a native guard could not verify the
/// minor-transfer exception's target-account leg
/// (`HealthSyncBinding._minorTransferExceptionHolds`'s `target ==
/// signedInUserId` check) at all, only that *some* transfer had happened.
///
/// *Day args*: `startMs`, `endMs` (inclusive, next local midnight − 1 s),
/// `endExclusiveMs` (next local midnight), `instantMs` (local midnight),
/// `zoneOffsetMs`, `endZoneOffsetMs` — all UTC epoch milliseconds /
/// offset milliseconds computed here via `day_boundary.dart` (#180's
/// timezone contract), so the native sides never do zone math.
///
/// *BBT args* (Issue #920): `startMs` / `endMs` / `instantMs` (all set to
/// the same instant — a point/waking sample, either `observedAt` or 07:00
/// morning local time in the entry's `tzName`, never 23:59:59) and
/// `zoneOffsetMs` (the UTC offset in effect at that instant).
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
/// **Permissions (Issue #992):** `READ_HEALTH_DATA_HISTORY` IS declared
/// and requested on Android as of #992, so the user-initiated import can
/// read the whole Health Connect history rather than the platform's
/// default 30-day pre-grant window. `READ_HEALTH_DATA_IN_BACKGROUND`
/// (background reads) remains deliberately NOT declared — background
/// delivery stays deferred (#156/HS-2), so the import is still
/// user-initiated only and there is no Play background-read declaration to
/// make. On iOS there is no history/background split: the read set is the
/// single menstrual-flow type, and full history is simply the query range.
library;

import 'package:lunarlog/domain/health/day_boundary.dart';
import 'package:lunarlog/domain/health/health_import.dart';
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
  static const writeSymptomSamples = 'writeSymptomSamples';

  /// Issue #228's three fertility/measurement writes.
  static const writeCervicalMucus = 'writeCervicalMucus';
  static const writeOvulationTest = 'writeOvulationTest';
  static const writeBasalBodyTemperature = 'writeBasalBodyTemperature';

  static const deleteRecords = 'deleteRecords';

  /// The two OS-permission methods (Issue #959). Unguarded: they read the
  /// OS consent state for the types this app writes and open the platform
  /// settings screen, neither of which touches user health data.
  static const permissionStatus = 'permissionStatus';
  static const openPermissionSettings = 'openPermissionSettings';


  /// The read/import method (Issue #217, paged in #992). Its success
  /// result is a page `Map` (`samples` + `nextCursor`) rather than a result
  /// string — see [decodeHealthReadResult].
  static const readMenstrualFlowPage = 'readMenstrualFlowPage';
}

/// The canonical Apple SDK raw integer for each [HealthFlowValue], per
/// `HKCategoryValueVaginalBleeding` (iOS 18+) and the deprecated
/// `HKCategoryValueMenstrualFlow` it replaced — identical raw values on
/// both: `unspecified` = 1, `light` = 2, `medium` = 3, `heavy` = 4.
/// `HKCategoryValue.notApplicable` = 0 is a *different*, shared
/// "no intensity" value used by types like `intermenstrualBleeding` — this
/// enum's `unspecified` is never that. Confusing the two (declaring
/// `unspecified = 0`) is exactly the off-by-one Issue #619's LLA-021
/// found and fixed in `ios/Runner/AppDelegate.swift`'s
/// `MenstrualFlowRawValue`.
///
/// **This is the single source of truth `AppDelegate.swift`'s
/// `MenstrualFlowRawValue` enum must match — Dart has no mechanism to
/// assert Swift's actual raw values at test time.** `ios/RunnerTests/`
/// exists as a Swift XCTest target, but nothing in
/// `.github/workflows/ci.yml` runs `xcodebuild test` against it (the
/// "iOS Simulator tests" job runs Flutter integration tests instead), so
/// there is no automated cross-language check at all. Until that changes,
/// `test/data/health/health_flow_value_apple_raw_test.dart` pins this
/// table's own literals and completeness so a native reimplementation of
/// the flow enum has an explicit, reviewed reference to diff against.
/// Values verified against the Apple SDK via Microsoft Learn's
/// `HKCategoryValueMenstrualFlow`/`HKCategoryValueVaginalBleeding`
/// references (dotnet/macios bindings generated directly from Apple's own
/// headers), not from memory — see the introducing PR's description for
/// the exact sources.
const Map<HealthFlowValue, int> kHealthFlowValueAppleRawValue = {
  HealthFlowValue.unspecified: 1,
  HealthFlowValue.light: 2,
  HealthFlowValue.medium: 3,
  HealthFlowValue.heavy: 4,
};

/// The canonical Apple SDK raw integer for each [HealthSymptomSeverity],
/// per `HKCategoryValueSeverity` (Issue #238, corrected in #917):
/// Apple defines (HKCategoryValues.h:209-215):
///   HKCategoryValueSeverityUnspecified = 0
///   HKCategoryValueSeverityNotPresent  = 1
///   HKCategoryValueSeverityMild        = 2
///   HKCategoryValueSeverityModerate    = 3
///   HKCategoryValueSeveritySevere      = 4
///
/// lunarlog writes: `unspecified` = 0, `mild` = 2, `moderate` = 3, `severe` = 4.
/// `HKCategoryValueSeverityNotPresent` = 1 is deliberately never written —
/// lunarlog only writes symptoms when present.
///
/// **This table is the single source of truth
/// `AppDelegate.swift`'s symptom-severity mapping must match — Dart cannot
/// assert Swift's actual raw values at test time** (see
/// [kHealthFlowValueAppleRawValue]'s doc for the full no-Swift-XCTest
/// rationale). `test/data/health/health_symptom_apple_raw_test.dart` pins
/// these literals and their completeness.
const Map<HealthSymptomSeverity, int> kHealthSymptomSeverityAppleRawValue = {
  HealthSymptomSeverity.unspecified: 0,
  HealthSymptomSeverity.mild: 2,
  HealthSymptomSeverity.moderate: 3,
  HealthSymptomSeverity.severe: 4,
};

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

/// Parses a `permissionStatus` result into the typed [HealthPermissionStatus]
/// (Issue #959). The native halves send exactly one of the
/// [HealthPermissionStatus] wire strings; anything else — a non-string, an
/// unknown string from a newer native side, or corruption — degrades to
/// [HealthPermissionStatus.unavailable] rather than inventing a status.
/// This is deliberately not a `failed` state because the status is advisory
/// UI state, not a health-store operation, and "we can't tell" must render
/// as unavailable rather than as a denial.
HealthPermissionStatus decodeHealthPermissionStatus(Object? raw) =>
    raw is String
        ? HealthPermissionStatus.fromWire(raw) ??
            HealthPermissionStatus.unavailable
        : HealthPermissionStatus.unavailable;


/// Parses a `readMenstrualFlowPage` result into the typed [HealthReadResult].
/// Two wire shapes are accepted: a page `Map` (`samples` list plus an
/// optional `nextCursor` string) or a bare `List` of sample maps (a
/// legacy/no-cursor success), and a result `String` (`unavailable` /
/// `permissionDenied` / a [HealthSyncCheck] deny name). Total — an
/// unrecognised shape, a non-string cursor, or a malformed sample map
/// becomes [HealthReadResult.failed], never a silent empty success (a
/// protocol error must surface).
HealthReadResult decodeHealthReadResult(Object? raw) {
  if (raw is Map) return _decodeReadPage(raw);
  if (raw is List) return _decodeSampleList(raw, nextCursor: null);
  if (raw is String) return _decodeReadString(raw);
  return HealthReadResult.failed(
    'unexpected readMenstrualFlowPage result (${raw.runtimeType}): $raw',
  );
}

/// The page-Map branch of [decodeHealthReadResult] (split out to keep both
/// functions' complexity low enough for the quality gate).
HealthReadResult _decodeReadPage(Map<Object?, Object?> raw) {
  final rawSamples = raw['samples'];
  if (rawSamples is! List) {
    return HealthReadResult.failed(
      'readMenstrualFlowPage result has no samples list',
    );
  }
  final cursor = raw['nextCursor'];
  if (cursor != null && cursor is! String) {
    return HealthReadResult.failed(
      'readMenstrualFlowPage cursor is not a string: $cursor',
    );
  }
  // A cursor, when present, must be a non-empty string. An empty string is
  // treated as "no cursor" (some SDKs spell exhaustion that way) so a native
  // side that sends '' instead of null cannot trap the Dart loop in a
  // repeated-cursor stop on the first page.
  final cursorText = cursor as String?;
  final nextCursor =
      (cursorText == null || cursorText.isEmpty) ? null : cursorText;
  return _decodeSampleList(rawSamples, nextCursor: nextCursor);
}

/// The result-String branch of [decodeHealthReadResult] (`unavailable` /
/// `permissionDenied` / a deny name).
HealthReadResult _decodeReadString(String raw) {
  switch (raw) {
    case 'unavailable':
      return const HealthReadResult.unavailable();
    case 'permissionDenied':
      return const HealthReadResult.permissionDenied();
    default:
      final check = _checkFromWire(raw);
      if (check != null && check != HealthSyncCheck.allowed) {
        return HealthReadResult.refused(check);
      }
      return HealthReadResult.failed(
        'unknown readMenstrualFlowPage result: $raw',
      );
  }
}

/// Decodes a list of sample maps into [HealthReadSamples], carrying
/// [nextCursor] through. A single malformed map fails the whole page rather
/// than dropping it silently.
HealthReadResult _decodeSampleList(Object? raw, {String? nextCursor}) {
  if (raw is! List) return HealthReadResult.failed('samples is not a list');
  final samples = <HealthFlowSample>[];
  for (final entry in raw) {
    final sample = _decodeFlowSample(entry);
    if (sample == null) {
      return HealthReadResult.failed('malformed readMenstrualFlowPage sample');
    }
    samples.add(sample);
  }
  return HealthReadResult.samples(samples, nextCursor: nextCursor);
}

/// One sample map from `readMenstrualFlowPage`, or null when a required key is
/// missing/typed wrong. Optional keys (`tzName`, `zoneOffsetSeconds`,
/// `zoneOffsetInferred`, `externalUuid`) are genuinely nullable. [start]/[end]
/// cross as epoch-millisecond numbers and become UTC instants; the sample's
/// own zone rides [HealthFlowSample.tzName] (iOS IANA) or
/// [HealthFlowSample.offset] (Android raw offset) — the #180 import
/// contract, the conversion to a civil date happens in Dart, never from the
/// device's current zone. `zoneOffsetInferred` marks the one bounded
/// exception (#902): when it is true the offset is this phone's zone, not
/// the sample's.
HealthFlowSample? _decodeFlowSample(Object? entry) {
  if (entry is! Map) return null;
  final recordId = entry['recordId'];
  final kind = HealthSampleKind.fromWire(entry['kind'] as String?);
  final flow = HealthFlowValue.fromWire(entry['flow'] as String?);
  final startMs = (entry['startMs'] as num?)?.toInt();
  final endMs = (entry['endMs'] as num?)?.toInt();
  if (recordId is! String ||
      kind == null ||
      startMs == null ||
      endMs == null ||
      (kind == HealthSampleKind.menstrualFlow && flow == null)) {
    return null;
  }
  final offsetSeconds = (entry['zoneOffsetSeconds'] as num?)?.toInt();
  return HealthFlowSample(
    recordId: recordId,
    kind: kind,
    flow: flow,
    start: DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true),
    end: DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true),
    tzName: entry['tzName'] as String?,
    offset:
        offsetSeconds == null ? null : Duration(seconds: offsetSeconds),
    offsetInferred: entry['zoneOffsetInferred'] as bool? ?? false,
    externalUuid: entry['externalUuid'] as String?,
  );
}

/// The window-args half of `readMenstrualFlowPage` (Issue #992): the
/// absolute query bounds as epoch milliseconds, the page size, and the
/// optional opaque cursor. The bounds are the full import range
/// (`health_import_service.dart` widens the upper edge so a sample recorded
/// in any zone today is returned); the precise civil-date filter happens in
/// Dart against the sample's own zone. `pageSize` is always sent so both
/// native halves use the Dart-declared value, and `cursor` rides as a plain
/// optional string (absent/null on the first page).
Map<String, Object?> encodeReadWindowArgs(
  DateTime start,
  DateTime end, {
  required int pageSize,
  String? cursor,
}) => {
      'startMs': start.millisecondsSinceEpoch,
      'endMs': end.millisecondsSinceEpoch,
      'pageSize': pageSize,
      'cursor': ?cursor,
    };

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
        // Issue #820: carry the DERIVED minor status (birth year wins when
        // present), not the raw stored flag. The native mirrors still OR
        // this with their own birth-year arithmetic, so an already-derived
        // value leaves their result unchanged in every case.
        'isMinor': facts.profile.isMinorAsOf(DateTime.now()),
        'birthYear': facts.profile.birthYear,
        'transferredAtMs': facts.profile.transferredAt?.millisecondsSinceEpoch,
        'transferredToUserId': facts.profile.transferredToUserId,
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

/// The BBT-args half for one `writeBasalBodyTemperature` (Issue #920):
/// a point/waking measurement (start == end == instant), resolving
/// [observedAt] when present or 07:00 morning local time in [tzName].
/// All from the entry's own [tzName] via `day_boundary.dart` (#180's
/// timezone contract — never the device's current zone).
Map<String, Object?> encodeBbtArgs(
  LocalDate date,
  String tzName, {
  DateTime? observedAt,
}) {
  final bbt = basalBodyTemperatureInstant(
    date: date,
    tzName: tzName,
    observedAt: observedAt,
  );
  final instantMs = bbt.instant.millisecondsSinceEpoch;
  return {
    'startMs': instantMs,
    'endMs': instantMs,
    'instantMs': instantMs,
    'zoneOffsetMs': bbt.offset.inMilliseconds,
  };
}
