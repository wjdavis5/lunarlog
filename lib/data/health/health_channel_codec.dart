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
/// | `writeBasalBodyTemperature` | guard + day + `celsius` + `healthConnectMeasurementLocation` + `recordId` + `recordVersionMs` | result string |
/// | `deleteRecords` | guard + `recordIds` | result string |
/// | `readMenstrualFlow` | guard + `startMs` + `endMs` | a `List` of sample maps, or a result string |
///
/// *Sample maps* (`readMenstrualFlow`): `recordId`, `startMs`, `endMs`, and
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

  /// The read/import method (Issue #217). Its success result is a `List` of
  /// sample maps rather than a result string — see
  /// [decodeHealthReadResult].
  static const readMenstrualFlow = 'readMenstrualFlow';
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
/// per `HKCategoryValueSeverity` (Issue #238): `mild` = 1, `moderate` = 2,
/// `severe` = 3, `unspecified` = 4. `HKCategoryValue.notApplicable` = 0 is
/// a *different* shared "not applicable" value and is deliberately never
/// written — this enum's [HealthSymptomSeverity.unspecified] is the
/// "no severity recorded" case, exactly as
/// [kHealthFlowValueAppleRawValue]'s `unspecified` = 1 is for flow.
///
/// **This table is the single source of truth
/// `AppDelegate.swift`'s symptom-severity enum must match — Dart cannot
/// assert Swift's actual raw values at test time** (see
/// [kHealthFlowValueAppleRawValue]'s doc for the full no-Swift-XCTest
/// rationale). `test/data/health/health_symptom_apple_raw_test.dart` pins
/// these literals and their completeness.
const Map<HealthSymptomSeverity, int> kHealthSymptomSeverityAppleRawValue = {
  HealthSymptomSeverity.mild: 1,
  HealthSymptomSeverity.moderate: 2,
  HealthSymptomSeverity.severe: 3,
  HealthSymptomSeverity.unspecified: 4,
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

/// Parses a `readMenstrualFlow` result into the typed [HealthReadResult].
/// Two wire shapes are accepted: a `List` of sample maps (success) and a
/// result `String` (`unavailable` / `permissionDenied` / a
/// [HealthSyncCheck] deny name). Total — an unrecognised shape or a
/// malformed sample map becomes [HealthReadResult.failed], never a silent
/// empty success (a protocol error must surface).
HealthReadResult decodeHealthReadResult(Object? raw) {
  if (raw is List) {
    final samples = <HealthFlowSample>[];
    for (final entry in raw) {
      final sample = _decodeFlowSample(entry);
      if (sample == null) {
        return HealthReadResult.failed('malformed readMenstrualFlow sample');
      }
      samples.add(sample);
    }
    return HealthReadResult.samples(samples);
  }
  if (raw is String) {
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
        return HealthReadResult.failed('unknown readMenstrualFlow result: $raw');
    }
  }
  return HealthReadResult.failed(
    'unexpected readMenstrualFlow result (${raw.runtimeType}): $raw',
  );
}

/// One sample map from `readMenstrualFlow`, or null when a required key is
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

/// The window-args half of `readMenstrualFlow`: the absolute query bounds as
/// epoch milliseconds. Widened by the caller (`health_import_service.dart`)
/// so a sample recorded in any zone inside the civil window is returned; the
/// precise civil-date filter happens in Dart against the sample's own zone.
Map<String, Object?> encodeReadWindowArgs(DateTime start, DateTime end) => {
      'startMs': start.millisecondsSinceEpoch,
      'endMs': end.millisecondsSinceEpoch,
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
        'isMinor': facts.profile.isMinor,
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
