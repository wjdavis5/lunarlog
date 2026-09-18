/// The Health Platform Sync type registry (Issue #192 AC7): the closed
/// catalogue of OS-health data types lunarlog maps to, each entry
/// carrying its mapping status. This is the one place a future issue can
/// look to see what exists, what is planned, and what is deliberately
/// absent — the `pregnancy`/`lactation` entries below are the
/// future-mapping placeholders issue #192 requires, and the
/// `menopausalState`/`bleedingAfterMenopause` entries are the ones issue
/// #196 requires (registry entries only, **no write path implemented**),
/// sequenced behind Pregnancy mode (A3-10) and Perimenopause mode existing
/// at all respectively.
///
/// iOS 26 added `HKCategoryTypeIdentifier.pregnancy` and
/// `.lactation` (interval samples carrying
/// `HKCategoryValueNotApplicable`), and Apple's Health app shows
/// gestational age across charts once a pregnancy is entered
/// (`developer.apple.com/documentation/updates/healthkit`). Health
/// Connect has no pregnancy/lactation record type today, so these are
/// HealthKit-only candidates — a cross-platform port method (the
/// `HealthPlatformStore` shape, one method per data-type concept) cannot
/// exist for them until Health Connect grows an analogue or the port
/// gains an iOS-only member, which is exactly why they are placeholders
/// here rather than entries in that interface.
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
  /// (#193), `menstrualPeriod` (#202, Health Connect only).
  implemented,

  /// Named as a future-mapping candidate by a specific issue; no port
  /// method, no channel entry, no write path. Exists so the intent is
  /// discoverable in code and so a future issue extends the port
  /// deliberately rather than re-deriving the list.
  futureCandidate,
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
  });

  /// The data-type concept, named per the port's one-method-per-concept
  /// rule (`health_platform.dart`).
  final String concept;

  final HealthTypeMappingStatus status;
  final String? healthKitIdentifier;
  final String? healthConnectRecord;

  /// The issue that owns (or will own) the mapping.
  final String issue;
}

/// The registry itself: every OS-health type lunarlog maps or has
/// committed to mapping. Append-only — an entry's status may move from
/// [HealthTypeMappingStatus.futureCandidate] to
/// [HealthTypeMappingStatus.implemented] when its issue lands, but a
/// concept is never silently dropped.
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
  // Issue #192 AC7: the iOS 26 pregnancy/lactation category types —
  // interval samples carrying HKCategoryValueNotApplicable whose
  // existence (not any value) is the datum. Registry entries only: no
  // port method, no channel codec entry, no write path. A future issue
  // mapping these derives the pregnancy interval from
  // `profile_modes.mode`/`estimated_due_date` (Issue #192) — never from
  // a prediction (the 5.1.3 no-derived-values rule
  // `health_channel.dart` documents).
  HealthTypeRegistryEntry(
    concept: 'pregnancy',
    status: HealthTypeMappingStatus.futureCandidate,
    healthKitIdentifier: 'HKCategoryTypeIdentifier.pregnancy',
    healthConnectRecord: null,
    issue: '#192 (placeholder; future Health Platform Sync issue)',
  ),
  HealthTypeRegistryEntry(
    concept: 'lactation',
    status: HealthTypeMappingStatus.futureCandidate,
    healthKitIdentifier: 'HKCategoryTypeIdentifier.lactation',
    healthConnectRecord: null,
    issue: '#192 (placeholder; future Health Platform Sync issue)',
  ),
  // Issue #196 AC6: the iOS 26 menopause category types — registry entries
  // only (no port method, no channel codec entry, no write path). Health
  // Connect has no menopause-state or post-menopausal-bleeding analogue
  // today, so both are HealthKit-only candidates, which by itself rules out
  // a cross-platform port method until one exists (A3-15: write support is
  // explicitly out of scope for the household's current users).
  //
  // Future implementer note: `menopausalState` is a point-in-time category
  // sample whose start and end date must be **identical** — HealthKit
  // rejects a save where they differ, unlike every interval sample this
  // registry otherwise names. `.bleedingAfterMenopause` is an interval
  // sample carrying `HKCategoryValueVaginalBleeding`.
  HealthTypeRegistryEntry(
    concept: 'menopausalState',
    status: HealthTypeMappingStatus.futureCandidate,
    healthKitIdentifier: 'HKCategoryTypeIdentifier.menopausalState',
    healthConnectRecord: null,
    issue: '#196 (placeholder; future Health Platform Sync issue)',
  ),
  HealthTypeRegistryEntry(
    concept: 'bleedingAfterMenopause',
    status: HealthTypeMappingStatus.futureCandidate,
    healthKitIdentifier: 'HKCategoryTypeIdentifier.bleedingAfterMenopause',
    healthConnectRecord: null,
    issue: '#196 (placeholder; future Health Platform Sync issue)',
  ),
];
