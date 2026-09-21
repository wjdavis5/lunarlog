/// The Health Platform Sync type registry (Issue #192 AC7): the closed
/// catalogue of OS-health data types lunarlog maps to, each entry
/// carrying its mapping status. This is the one place a future issue can
/// look to see what exists, what is planned, and what is deliberately
/// absent.
///
/// Issue #228 added the fertility/measurement entries (`cervicalMucus`,
/// `ovulationTest`, `basalBodyTemperature` — implemented) and recorded
/// `pregnancyTestResult` and `progesteroneTestResult` as
/// [HealthTypeMappingStatus.deliberatelyUnsupported].
///
/// Issue #246 owns the four life-stage interval types: `pregnancy`,
/// `lactation`, `menopausalState`, and `bleedingAfterMenopause`. The
/// product modes the work was sequenced behind have landed (pregnancy
/// mode #192, perimenopause mode #196), and #246 has since documented
/// their mappings in pure code — `lib/data/health/health_mode_interval_mapping.dart`
/// derives the interval/point samples from mode transitions and enforces
/// `menopausalState`'s start == end constraint structurally — but the
/// Health Platform Sync adapter still has **no platform plugin**, so
/// there is no write path to call and all four stay
/// [HealthTypeMappingStatus.futureCandidate]: named, mapped, deliberately
/// unwritten.
///
/// iOS 26 added `HKCategoryTypeIdentifier.pregnancy` and `.lactation`
/// (interval samples carrying `HKCategoryValueNotApplicable`), and Apple's
/// Health app shows gestational age across charts once a pregnancy is
/// entered (`developer.apple.com/documentation/updates/healthkit`). Health
/// Connect has no analogue for any of the four, so a future mapping is
/// HealthKit-only — a cross-platform port method (the
/// `HealthPlatformStore` shape, one method per data-type concept) cannot
/// exist until Health Connect grows an analogue or the port gains an
/// iOS-only member.
///
/// Registry entries carry no behavior: nothing reads this list at
/// runtime today. It exists so the *mapping decision* — which types this
/// app will ever write, and under which issue — is recorded in code
/// next to the port it belongs to, not only in issue prose.
///
/// Pure Dart with no Flutter/drift imports (R14/R16) —
/// `test/architecture/layering_test.dart` enforces that.
library;

/// The mapping status of one registry entry.
enum HealthTypeMappingStatus {
  /// A port method exists (`HealthPlatformStore`) and the native halves
  /// implement it: `menstrualFlow` (#193), `intermenstrualBleeding`
  /// (#193), `menstrualPeriod` (#202, Health Connect only), and — Issue
  /// #228 — `cervicalMucus`, `ovulationTest`, and `basalBodyTemperature`.
  implemented,

  /// Named as a future-mapping candidate by a specific issue; no port
  /// method, no channel entry, no write path. Exists so the intent is
  /// discoverable in code and so a future issue extends the port
  /// deliberately rather than re-deriving the list.
  futureCandidate,

  /// **Deliberately not mapped**, with a recorded reason. A future reader
  /// must be able to see this was a decision, not an oversight (Issue
  /// #228's explicit ask): the platform type exists but the product has no
  /// domain value for it, or the feature is sequenced elsewhere. The
  /// [HealthTypeRegistryEntry.reason] field carries the why.
  deliberatelyUnsupported,
}

/// One entry in the registry. [healthKitIdentifier] is Apple's
/// `HKCategoryTypeIdentifier`/`HKQuantityTypeIdentifier` name;
/// [healthConnectRecord] is the Health Connect record type name, or null
/// when the platform has no analogue (which by itself rules out a
/// cross-platform port method until one exists).
class HealthTypeRegistryEntry {
  const HealthTypeRegistryEntry({
    required this.concept,
    required this.status,
    this.healthKitIdentifier,
    this.healthConnectRecord,
    required this.issue,
    this.reason,
  });

  /// The data-type concept, named per the port's one-method-per-concept
  /// rule (`health_platform.dart`).
  final String concept;

  final HealthTypeMappingStatus status;
  final String? healthKitIdentifier;
  final String? healthConnectRecord;

  /// The issue that owns (or will own) the mapping.
  final String issue;

  /// Why a [HealthTypeMappingStatus.deliberatelyUnsupported] type is not
  /// mapped; null for every other status.
  final String? reason;
}

/// The registry itself: every OS-health type lunarlog maps or has
/// committed to mapping. Append-only — an entry's status may move from
/// [HealthTypeMappingStatus.futureCandidate] to
/// [HealthTypeMappingStatus.implemented] when its issue lands, or to
/// [HealthTypeMappingStatus.deliberatelyUnsupported] when the decision is
/// made not to map it — but a concept is never silently dropped.
const List<HealthTypeRegistryEntry> kHealthTypeRegistry = [
  HealthTypeRegistryEntry(
    concept: 'menstrualFlow',
    status: HealthTypeMappingStatus.implemented,
    healthKitIdentifier: 'HKCategoryTypeIdentifierMenstrualFlow',
    healthConnectRecord: 'MenstruationFlowRecord',
    issue: '#193',
  ),
  HealthTypeRegistryEntry(
    concept: 'intermenstrualBleeding',
    status: HealthTypeMappingStatus.implemented,
    healthKitIdentifier: 'HKCategoryTypeIdentifierIntermenstrualBleeding',
    healthConnectRecord: 'IntermenstrualBleedingRecord',
    issue: '#193',
  ),
  HealthTypeRegistryEntry(
    concept: 'menstrualPeriod',
    status: HealthTypeMappingStatus.implemented,
    // HealthKit encodes episode boundaries via menstrual-flow cycle-start
    // metadata instead (#193) — no analogue, and that is why the port's
    // writeMenstrualPeriod answers `unavailable` on iOS.
    healthKitIdentifier: null,
    healthConnectRecord: 'MenstruationPeriodRecord',
    issue: '#202',
  ),
  // Issue #228: the fertility/measurement types. The mapping tables and
  // every decision live in `lib/data/health/health_fertility_mapping.dart`;
  // the port methods are on `HealthPlatformStore`.
  HealthTypeRegistryEntry(
    concept: 'cervicalMucus',
    status: HealthTypeMappingStatus.implemented,
    healthKitIdentifier: 'HKCategoryTypeIdentifier.cervicalMucusQuality',
    healthConnectRecord: 'CervicalMucusRecord',
    issue: '#228',
  ),
  HealthTypeRegistryEntry(
    concept: 'ovulationTest',
    status: HealthTypeMappingStatus.implemented,
    healthKitIdentifier: 'HKCategoryTypeIdentifier.ovulationTestResult',
    healthConnectRecord: 'OvulationTestRecord',
    issue: '#228',
  ),
  HealthTypeRegistryEntry(
    concept: 'basalBodyTemperature',
    status: HealthTypeMappingStatus.implemented,
    // A *quantity* type on HealthKit, unlike every category type above —
    // written in HKUnit.degreeCelsius().
    healthKitIdentifier: 'HKQuantityTypeIdentifier.basalBodyTemperature',
    healthConnectRecord: 'BasalBodyTemperatureRecord',
    issue: '#228',
  ),
  // Issue #228: deliberately unsupported, with the reason recorded so a
  // future reader can see it was a decision, not an oversight. (`pregnancy`
  // and `lactation`, which #228 had also parked here behind the Modes epic,
  // moved back to future candidates when #246 documented their mappings —
  // see the block below.)
  HealthTypeRegistryEntry(
    concept: 'pregnancyTestResult',
    status: HealthTypeMappingStatus.deliberatelyUnsupported,
    healthKitIdentifier: 'HKCategoryTypeIdentifier.pregnancyTestResult',
    healthConnectRecord: null,
    issue: '#228',
    reason:
        'Not a lunarlog tracking category: pregnancy tests are out of scope '
        'for the household use case, and Health Connect has no '
        'pregnancy-test record at all. Recorded here so the absence is a '
        'decision, not a gap.',
  ),
  HealthTypeRegistryEntry(
    concept: 'progesteroneTestResult',
    status: HealthTypeMappingStatus.deliberatelyUnsupported,
    healthKitIdentifier: 'HKCategoryTypeIdentifier.progesteroneTestResult',
    healthConnectRecord: null,
    issue: '#228',
    reason:
        'Not a lunarlog tracking category and with no Health Connect '
        'analogue: deliberately unsupported alongside pregnancyTestResult.',
  ),
  // Issue #246: the four life-stage interval types. Their mappings are
  // documented and derived in pure code —
  // `lib/data/health/health_mode_interval_mapping.dart` — but the adapter
  // still has no platform plugin, so there is no write path to call and
  // all four stay future candidates: named, mapped, deliberately
  // unwritten. Health Connect has no analogue for any of the four, so
  // each is HealthKit-only.
  //
  // `pregnancy` and `lactation` are open/closed interval samples carrying
  // `HKCategoryValueNotApplicable` (existence, not a value, is the
  // signal), tied to a mode span: pregnancy mode's `mode_started_on` →
  // exit date derives the pregnancy interval ([LifecycleMode.pregnancy]).
  // No lunarlog mode derives lactation today — the shape is pinned by the
  // mapping module's explicit constructor so a future mode wires the same
  // plan type rather than reinventing it.
  //
  // `menopausalState` is a **point-in-time** sample whose start and end
  // date must be **identical** — HealthKit rejects a save where they
  // differ, unlike every interval sample this registry otherwise names.
  // The mapping's `MenopausalStateSample` is built from a single date, so
  // a mismatched pair is unrepresentable. `bleedingAfterMenopause` is an
  // interval sample carrying `HKCategoryValueVaginalBleeding`, written
  // for bleed days logged while perimenopause mode is active — reusing
  // #193's shared flow-value table (`mapFlowToHealthWrite`), not a
  // separate ad hoc mapping.
  HealthTypeRegistryEntry(
    concept: 'pregnancy',
    status: HealthTypeMappingStatus.futureCandidate,
    healthKitIdentifier: 'HKCategoryTypeIdentifier.pregnancy',
    healthConnectRecord: null,
    issue: '#246',
  ),
  HealthTypeRegistryEntry(
    concept: 'lactation',
    status: HealthTypeMappingStatus.futureCandidate,
    healthKitIdentifier: 'HKCategoryTypeIdentifier.lactation',
    healthConnectRecord: null,
    issue: '#246',
  ),
  HealthTypeRegistryEntry(
    concept: 'menopausalState',
    status: HealthTypeMappingStatus.futureCandidate,
    healthKitIdentifier: 'HKCategoryTypeIdentifier.menopausalState',
    healthConnectRecord: null,
    issue: '#246',
  ),
  HealthTypeRegistryEntry(
    concept: 'bleedingAfterMenopause',
    status: HealthTypeMappingStatus.futureCandidate,
    healthKitIdentifier: 'HKCategoryTypeIdentifier.bleedingAfterMenopause',
    healthConnectRecord: null,
    issue: '#246',
  ),
];
