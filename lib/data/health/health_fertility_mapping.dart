/// The pure lunarlog fertility-signal → OS-health-store mapping (Issue
/// #228): the single, reviewable table that turns the two fertility
/// categories the #253 taxonomy shipped — `discharge` (cervical mucus) and
/// `tests` (ovulation tests) — plus the `bbt` numeric observation #255
/// stores, into the identifiers each platform's write path needs.
///
/// Like `health_flow_mapping.dart` and `health_symptom_mapping.dart`,
/// every decision-shaped thing lives here in pure Dart (no platform,
/// channel, or I/O dependency) so it carries full `flutter test` coverage;
/// the Swift/Kotlin halves only translate an already-resolved identifier
/// into a platform record and add no mapping logic of their own. This is
/// the #238 pattern, deliberately not re-invented.
///
/// ## Cervical mucus
///
/// The live domain value is a `discharge`-category tag code. HealthKit has
/// a single `HKCategoryTypeIdentifier.cervicalMucusQuality` enum; Health
/// Connect's `CervicalMucusRecord` has **two** orthogonal fields
/// (`appearance` and `sensation`) where HealthKit has one.
///
/// | lunarlog code | HealthKit `cervicalMucusQuality` | Health Connect `appearance` |
/// |---|---|---|
/// | `sticky` | `sticky` | `APPEARANCE_STICKY` |
/// | `creamy` | `creamy` | `APPEARANCE_CREAMY` |
/// | `egg_white` | `eggWhite` | `APPEARANCE_EGG_WHITE` |
///
/// Health Connect's `sensation` is always written as `SENSATION_UNKNOWN`:
/// the domain has no sensation concept and none was added purely to satisfy
/// Android (the issue's explicit instruction). The platform requires the
/// field, so the honest "unknown" constant is how the requirement is met.
///
/// `atypical` is **deliberately unsupported**, not silently mapped to a
/// neighbour: HealthKit has no atypical/unusual value. (Health Connect does
/// expose `APPEARANCE_UNUSUAL`, but mapping only that platform would make
/// the same logged day diverge across platforms, and Google's "unusual" is
/// an attention/unwellness flag that is not proven to mean Clue's
/// "atypical".) `none` is a positive "no discharge today" assertion (see
/// `kPositiveAssertionCodes`), so no sample is written for it — the same
/// "a sample for the common empty day would bury the signal" rule
/// `health_flow_mapping.dart` applies to `FlowLevel.none`.
///
/// ## Ovulation test
///
/// The live domain values are the `tests`-category ovulation codes. The
/// platform enums differ in vocabulary:
///
/// | lunarlog code | HealthKit `ovulationTestResult` | Health Connect `result` |
/// |---|---|---|
/// | `ovulation_negative` | `negative` | `RESULT_NEGATIVE` |
/// | `ovulation_positive` | `luteinizingHormoneSurge` | `RESULT_POSITIVE` |
/// | `ovulation_peak` | `luteinizingHormoneSurge` | `RESULT_POSITIVE` |
///
/// `positive` and `peak` collapse onto the same platform value: HealthKit
/// has no separate "peak" case, and Health Connect's own documentation for
/// `RESULT_POSITIVE` states it "may also be referred [to] as 'peak'
/// fertility". The positive-vs-peak distinction is the one understood loss
/// in this table.
///
/// HealthKit's `estrogenSurge` and Health Connect's `RESULT_HIGH` are
/// dual-hormone-monitor values with **no live domain source** (the domain
/// has no "high fertility" value), so they are deliberately unsupported —
/// see [kUnsupportedOvulationHealthKitResults] /
/// [kUnsupportedOvulationHealthConnectResults]. `indeterminate` /
/// `RESULT_INCONCLUSIVE` likewise have no live domain value (the app's
/// operator either records a result or records nothing), so they are
/// unreachable rather than mapped.
///
/// The two pregnancy-test codes in the same `tests` category are
/// deliberately unsupported here (the type registry records
/// `pregnancyTestResult` for the same reason).
///
/// ## Basal body temperature (BBT) — the first non-enum type
///
/// BBT is a numeric `Observation` (`category: 'bbt'`, `valueNum`, `unit`)
/// rather than a tag, and it is a **quantity** type on HealthKit
/// (`HKQuantityTypeIdentifier.basalBodyTemperature`, written in
/// `HKUnit.degreeCelsius()`), not a category — a different native code
/// path. Dart converts every value to Celsius (via the #255
/// `convertTemperature`) before it crosses the channel, so neither native
/// half does unit math.
///
/// Health Connect's `BasalBodyTemperatureRecord` requires a
/// `measurementLocation`. The live domain has no measurement-location
/// field, so the honest `MEASUREMENT_LOCATION_UNKNOWN` constant is written
/// — never a guessed oral/vaginal location. HealthKit has no such field.
///
/// ### Source separation is a hard requirement
///
/// A wearable- or platform-sourced BBT value must never be conflated with a
/// manually tracked one. [Observation] already carries an
/// [ObservationSource], and `computeMeasurementMutations` already refuses to
/// let a manual edit adopt a non-manual row. This mapping preserves the
/// separation in the write direction: [resolveBasalBodyTemperature] returns
/// null — writing nothing — unless the row is a value the operator tracked
/// ([ObservationSource.manual]) or imported from another tracker
/// ([ObservationSource.clueImport]). A row the platform itself or a wearable
/// produced ([ObservationSource.appleHealth]/[ObservationSource.healthConnect]/
/// [ObservationSource.wearable]) is never echoed back, which is also the
/// one-way rule `health_flow_write_service.dart` enforces for every type. An
/// `excluded` BBT point is likewise not written: the operator marked it an
/// outlier to leave out of analysis, so re-asserting it to the OS would
/// misstate the tracked set.
library;

import 'package:lunarlog/domain/models/measurement_unit.dart';
import 'package:lunarlog/domain/models/observation.dart';

/// The `observations.category` value a basal-body-temperature row is logged
/// under (the #240/#255 generic observations child table; the day sheet's
/// `computeMeasurementMutations` writes exactly this string).
const String kBbtObservationCategory = 'bbt';

// ---------------------------------------------------------------------------
// Cervical mucus
// ---------------------------------------------------------------------------

/// The live `discharge`-category codes that map, and their HealthKit
/// `HKCategoryValueCervicalMucusQuality` case name. Every other live code is
/// either explicitly unsupported or not exported — see
/// [kUnsupportedCervicalMucusTags] / [kNotExportedCervicalMucusTags].
const Map<String, String> kCervicalMucusHealthKitValues = {
  'sticky': 'sticky',
  'creamy': 'creamy',
  'egg_white': 'eggWhite',
};

/// The same live codes and their Health Connect `CervicalMucusRecord`
/// appearance constant. The `sensation` field is always
/// `SENSATION_UNKNOWN` (see the library doc) and does not appear here.
const Map<String, String> kCervicalMucusHealthConnectAppearances = {
  'sticky': 'APPEARANCE_STICKY',
  'creamy': 'APPEARANCE_CREAMY',
  'egg_white': 'APPEARANCE_EGG_WHITE',
};

/// Deliberately unsupported `discharge`-category codes, each with its
/// reason. This is a documented decision, not an unimplemented gap.
const Map<String, String> kUnsupportedCervicalMucusTags = {
  'atypical':
      'HealthKit cervicalMucusQuality has no atypical/unusual value, and '
      'mapping only Health Connect\'s APPEARANCE_UNUSUAL would make the same '
      'logged day diverge across platforms while asserting a meaning '
      '(attention/unwellness) not proven to match Clue\'s "atypical".',
};

/// `discharge`-category codes with no health-store sample: `none` is a
/// positive "no discharge today" assertion (like `FlowLevel.none`), and a
/// sample for the common empty day would bury the signal.
const Set<String> kNotExportedCervicalMucusTags = {'none'};

/// How one live `discharge` code is handled by the health export.
sealed class CervicalMucusHealthExport {
  const CervicalMucusHealthExport();
}

/// The code maps to both platforms' appearance identifiers.
final class CervicalMucusHealthMapped extends CervicalMucusHealthExport {
  const CervicalMucusHealthMapped({
    required this.tagCode,
    required this.healthKitValue,
    required this.healthConnectAppearance,
  });

  final String tagCode;

  /// The `HKCategoryValueCervicalMucusQuality` case name.
  final String healthKitValue;

  /// The `CervicalMucusRecord` appearance constant name.
  final String healthConnectAppearance;
}

/// The code is deliberately not exported; [reason] says why.
final class CervicalMucusHealthUnsupported extends CervicalMucusHealthExport {
  const CervicalMucusHealthUnsupported(this.tagCode, this.reason);

  final String tagCode;
  final String reason;
}

/// The code is real data with no exportable appearance (`none`).
final class CervicalMucusHealthNotExported extends CervicalMucusHealthExport {
  const CervicalMucusHealthNotExported(this.tagCode);

  final String tagCode;
}

/// Classifies [code] (total: an unknown code — a custom registry tag, a
/// future peer's vocabulary — is [CervicalMucusHealthNotExported], never an
/// error).
CervicalMucusHealthExport classifyCervicalMucusExport(String code) {
  final healthKit = kCervicalMucusHealthKitValues[code];
  final healthConnect = kCervicalMucusHealthConnectAppearances[code];
  if (healthKit != null && healthConnect != null) {
    return CervicalMucusHealthMapped(
      tagCode: code,
      healthKitValue: healthKit,
      healthConnectAppearance: healthConnect,
    );
  }
  final reason = kUnsupportedCervicalMucusTags[code];
  if (reason != null) return CervicalMucusHealthUnsupported(code, reason);
  return CervicalMucusHealthNotExported(code);
}

/// A day's resolved cervical-mucus sample, or null when the day's discharge
/// tags produce none. At most one: `discharge` is single-select in the day
/// sheet, but this takes any iterable and keeps the first mapped code.
class ResolvedCervicalMucus {
  const ResolvedCervicalMucus({
    required this.tagCode,
    required this.healthKitValue,
    required this.healthConnectAppearance,
  });

  final String tagCode;
  final String healthKitValue;
  final String healthConnectAppearance;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedCervicalMucus &&
          other.tagCode == tagCode &&
          other.healthKitValue == healthKitValue &&
          other.healthConnectAppearance == healthConnectAppearance;

  @override
  int get hashCode => Object.hash(tagCode, healthKitValue, healthConnectAppearance);
}

/// Resolves one day's [tags] to its cervical-mucus sample, or null when
/// none of them is a mapped discharge code.
ResolvedCervicalMucus? resolveCervicalMucus(Iterable<String> tags) {
  for (final tag in tags) {
    final export = classifyCervicalMucusExport(tag);
    if (export is CervicalMucusHealthMapped) {
      return ResolvedCervicalMucus(
        tagCode: export.tagCode,
        healthKitValue: export.healthKitValue,
        healthConnectAppearance: export.healthConnectAppearance,
      );
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Ovulation test
// ---------------------------------------------------------------------------

/// The live `tests`-category ovulation codes that map, and their HealthKit
/// `HKCategoryValueOvulationTestResult` case name. `positive` and `peak`
/// collapse onto `luteinizingHormoneSurge` (HealthKit has no peak case).
const Map<String, String> kOvulationTestHealthKitResults = {
  'ovulation_negative': 'negative',
  'ovulation_positive': 'luteinizingHormoneSurge',
  'ovulation_peak': 'luteinizingHormoneSurge',
};

/// The same live codes and their Health Connect `OvulationTestRecord`
/// result constant. `positive` and `peak` both map to `RESULT_POSITIVE`
/// (Health Connect's own docs describe it as the possible "peak" result).
const Map<String, String> kOvulationTestHealthConnectResults = {
  'ovulation_negative': 'RESULT_NEGATIVE',
  'ovulation_positive': 'RESULT_POSITIVE',
  'ovulation_peak': 'RESULT_POSITIVE',
};

/// Deliberately unsupported `tests`-category codes, each with its reason.
/// The two pregnancy-test codes live in the same taxonomy category as the
/// ovulation codes but are a different clinical test; the type registry
/// records `pregnancyTestResult` as unsupported for the same decision.
const Map<String, String> kUnsupportedOvulationTestTags = {
  'pregnancy_negative':
      'A pregnancy test, not an ovulation test: the type registry records '
      'HealthKit pregnancyTestResult as deliberately unsupported (issue '
      '#228), and Health Connect has no pregnancy-test record at all.',
  'pregnancy_positive':
      'A pregnancy test, not an ovulation test: the type registry records '
      'HealthKit pregnancyTestResult as deliberately unsupported (issue '
      '#228), and Health Connect has no pregnancy-test record at all.',
};

/// HealthKit ovulation-test results with no live domain source: the
/// dual-hormone-monitor `estrogenSurge`. The domain has no "high fertility"
/// value, so this is deliberately unsupported rather than guessed.
const Set<String> kUnsupportedOvulationHealthKitResults = {'estrogenSurge'};

/// Health Connect ovulation-test results with no live domain source: the
/// dual-hormone-monitor `RESULT_HIGH`. Same decision as
/// [kUnsupportedOvulationHealthKitResults].
const Set<String> kUnsupportedOvulationHealthConnectResults = {'RESULT_HIGH'};

/// How one live `tests`-category ovulation code is handled by the export.
sealed class OvulationTestHealthExport {
  const OvulationTestHealthExport();
}

/// The code maps to both platforms' result identifiers.
final class OvulationTestHealthMapped extends OvulationTestHealthExport {
  const OvulationTestHealthMapped({
    required this.tagCode,
    required this.healthKitResult,
    required this.healthConnectResult,
  });

  final String tagCode;

  /// The `HKCategoryValueOvulationTestResult` case name.
  final String healthKitResult;

  /// The `OvulationTestRecord` result constant name.
  final String healthConnectResult;
}

/// The code is deliberately not exported; [reason] says why.
final class OvulationTestHealthUnsupported extends OvulationTestHealthExport {
  const OvulationTestHealthUnsupported(this.tagCode, this.reason);

  final String tagCode;
  final String reason;
}

/// The code is real data with no exportable result.
final class OvulationTestHealthNotExported extends OvulationTestHealthExport {
  const OvulationTestHealthNotExported(this.tagCode);

  final String tagCode;
}

/// Classifies [code] (total, like [classifyCervicalMucusExport]).
OvulationTestHealthExport classifyOvulationTestExport(String code) {
  final healthKit = kOvulationTestHealthKitResults[code];
  final healthConnect = kOvulationTestHealthConnectResults[code];
  if (healthKit != null && healthConnect != null) {
    return OvulationTestHealthMapped(
      tagCode: code,
      healthKitResult: healthKit,
      healthConnectResult: healthConnect,
    );
  }
  final reason = kUnsupportedOvulationTestTags[code];
  if (reason != null) return OvulationTestHealthUnsupported(code, reason);
  return OvulationTestHealthNotExported(code);
}

/// One resolved ovulation-test sample, before the write service attaches the
/// source record id/version and day envelope.
class ResolvedOvulationTest {
  const ResolvedOvulationTest({
    required this.tagCode,
    required this.healthKitResult,
    required this.healthConnectResult,
  });

  /// The lunarlog taxonomy code that produced this sample.
  final String tagCode;
  final String healthKitResult;
  final String healthConnectResult;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedOvulationTest &&
          other.tagCode == tagCode &&
          other.healthKitResult == healthKitResult &&
          other.healthConnectResult == healthConnectResult;

  @override
  int get hashCode => Object.hash(tagCode, healthKitResult, healthConnectResult);
}

/// Resolves one day's [tags] into the set of ovulation-test samples to
/// write, **deduplicated by [ResolvedOvulationTest.healthKitResult]**: a day
/// carrying both `ovulation_positive` and `ovulation_peak` writes one
/// `luteinizingHormoneSurge` sample (the platform cannot distinguish them),
/// while a negative and a positive result write one each. The first tag that
/// resolved to a given result supplies the [ResolvedOvulationTest.tagCode].
List<ResolvedOvulationTest> resolveOvulationTests(Iterable<String> tags) {
  final byResult = <String, ResolvedOvulationTest>{};
  for (final tag in tags) {
    final export = classifyOvulationTestExport(tag);
    if (export is! OvulationTestHealthMapped) continue;
    byResult.putIfAbsent(
      export.healthKitResult,
      () => ResolvedOvulationTest(
        tagCode: export.tagCode,
        healthKitResult: export.healthKitResult,
        healthConnectResult: export.healthConnectResult,
      ),
    );
  }
  return byResult.values.toList(growable: false);
}

// ---------------------------------------------------------------------------
// Basal body temperature
// ---------------------------------------------------------------------------

/// The Health Connect `BasalBodyTemperatureRecord.measurementLocation`
/// constant written when the domain has no measurement-location value. The
/// domain does not add one here; the honest "unknown" is written instead of
/// guessing a site. Kept in Dart (not hardcoded in Kotlin) so the decision
/// is reviewable and unit-tested, and so a future domain field has one place
/// to change.
const String kBbtHealthConnectMeasurementLocationUnknown =
    'MEASUREMENT_LOCATION_UNKNOWN';

/// Whether a `bbt` observation's [source] is a value the operator tracked
/// (or imported from another tracker) — the only sources eligible for a
/// platform write. Platform- and wearable-sourced values are excluded so
/// they are never conflated with manually tracked BBT (see the library
/// doc's source-separation note).
bool isManuallyTrackedBbtSource(ObservationSource source) =>
    source == ObservationSource.manual || source == ObservationSource.clueImport;

/// One resolved BBT sample, in the platform's storage-neutral canonical
/// unit (Celsius) plus the platform constants the write needs.
class ResolvedBasalBodyTemperature {
  const ResolvedBasalBodyTemperature({
    required this.celsius,
    required this.healthConnectMeasurementLocation,
    required this.source,
  });

  /// The temperature in Celsius — HealthKit writes it in
  /// `HKUnit.degreeCelsius()`, Health Connect as `Temperature.celsius`.
  final double celsius;

  /// The Health Connect measurement-location constant to write; always
  /// [kBbtHealthConnectMeasurementLocationUnknown] today.
  final String healthConnectMeasurementLocation;

  /// The source row's provenance, preserved end to end: a value written from
  /// here is known to be manual/clue-import, never platform/watch-sourced.
  final ObservationSource source;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedBasalBodyTemperature &&
          other.celsius == celsius &&
          other.healthConnectMeasurementLocation ==
              healthConnectMeasurementLocation &&
          other.source == source;

  @override
  int get hashCode =>
      Object.hash(celsius, healthConnectMeasurementLocation, source);
}

/// Resolves one [observation] to its BBT write, or null when it is not a BBT
/// row, is not a manually tracked/imported value (source separation), is
/// marked excluded, or carries no numeric value. The unit is normalised to
/// Celsius through #255's [convertTemperature]; [BbtUnit.fromDb] is the
/// same degradation the rest of the app uses, so an unrecognised/null unit
/// reads as Celsius rather than mis-denominating a value.
ResolvedBasalBodyTemperature? resolveBasalBodyTemperature(
  Observation observation,
) {
  if (observation.category != kBbtObservationCategory) return null;
  if (!isManuallyTrackedBbtSource(observation.source)) return null;
  if (observation.excluded) return null;
  final value = observation.valueNum;
  if (value == null) return null;
  final from = BbtUnit.fromDb(observation.unit);
  return ResolvedBasalBodyTemperature(
    celsius: convertTemperature(value, from: from, to: BbtUnit.celsius),
    healthConnectMeasurementLocation:
        kBbtHealthConnectMeasurementLocationUnknown,
    source: observation.source,
  );
}
