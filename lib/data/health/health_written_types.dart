/// The single "every OS-health type this app writes" collection (Issue
/// #924), derived from the existing mapping tables rather than a second
/// hand-maintained list — the source of truth `deleteRecords` shares with
/// the write path.
///
/// The bug #924 closes: `deleteRecords` queried only the two menstrual-flow
/// types #186 knew about, so every type #238 and #228 added — the symptom
/// categories, `cervicalMucusQuality`, `ovulationTestResult`, and the
/// `basalBodyTemperature` **quantity** type — was written but never
/// deleted. A record the user deleted stayed in Apple Health / Health
/// Connect forever.
///
/// Deriving the set from [kHealthTypeRegistry] and
/// [kSymptomHealthKitTypeIdentifiers] means a future type cannot reintroduce
/// the bug silently: adding a mapped symptom or an `implemented` registry
/// entry grows these getters, and `test/release/health_deletion_types_test.dart`
/// then fails unless both native halves' deletion lists grew with it. The
/// native halves cannot import Dart, so their lists are text-guarded against
/// these collections rather than generated.
///
/// Pure Dart (R14/R16) — no Flutter/drift imports.
library;

import 'package:lunarlog/domain/health/health_type_registry.dart';

import 'health_symptom_mapping.dart';

/// Every `HKCategoryTypeIdentifier` case name the write path can produce:
/// the flow types (#193) and the fertility types (#228) from the registry's
/// [HealthTypeMappingStatus.implemented] entries, plus every mapped symptom
/// category from #238's [kSymptomHealthKitTypeIdentifiers].
///
/// The values are Swift case names (e.g. `menstrualFlow`,
/// `abdominalCramps`, `cervicalMucusQuality`), matching the way
/// `AppDelegate.swift` resolves identifiers. `menstrualPeriod` contributes
/// nothing here: it is Health-Connect-only (its registry
/// `healthKitIdentifier` is null), and HealthKit has no such type.
Set<String> get kHealthKitWrittenCategoryTypeCaseNames => {
      ..._healthKitCaseNames('HKCategoryTypeIdentifier'),
      ...kSymptomHealthKitTypeIdentifiers.values,
    };

/// Every `HKQuantityTypeIdentifier` case name the write path can produce —
/// today exactly `basalBodyTemperature` (#228), the one non-category type.
/// Kept separate because the native delete must go through a different
/// `HKSampleType` path (`HKObjectType.quantityType(forIdentifier:)`).
Set<String> get kHealthKitWrittenQuantityTypeCaseNames =>
    _healthKitCaseNames('HKQuantityTypeIdentifier');

/// Every HealthKit type this app writes, category and quantity together —
/// the complete set `deleteRecords` must query.
Set<String> get kHealthKitWrittenTypeCaseNames => {
      ...kHealthKitWrittenCategoryTypeCaseNames,
      ...kHealthKitWrittenQuantityTypeCaseNames,
    };

/// Every Health Connect record class name this app writes, from the
/// registry's [HealthTypeMappingStatus.implemented] entries: the flow,
/// period, and intermenstrual types (#193/#202) plus the fertility and
/// measurement types (#228). Symptom categories are deliberately absent —
/// Health Connect has no symptom record type at all (see
/// `health_symptom_mapping.dart`).
Set<String> get kHealthConnectWrittenRecordTypes => {
      for (final entry in kHealthTypeRegistry)
        if (entry.status == HealthTypeMappingStatus.implemented)
          ?entry.healthConnectRecord,
    };

/// The Swift case name for a registry `healthKitIdentifier`, or nothing for
/// an entry that names the other platform's prefix. Strips the
/// `HKCategoryTypeIdentifier` / `HKQuantityTypeIdentifier` prefix, the
/// optional `.` some registry entries carry between prefix and case name
/// (e.g. `HKCategoryTypeIdentifier.cervicalMucusQuality`), and lowercases
/// the first letter — Apple's raw constant is `HKCategoryTypeIdentifier`
/// + PascalCase (`…MenstrualFlow`) while the Swift case is lowerCamelCase
/// (`.menstrualFlow`), and `AppDelegate.swift` uses the case form.
Set<String> _healthKitCaseNames(String prefix) => {
      for (final entry in kHealthTypeRegistry)
        if (entry.status == HealthTypeMappingStatus.implemented)
          if (entry.healthKitIdentifier case final identifier?)
            if (identifier.startsWith(prefix))
              _lowerFirst(
                  identifier.substring(prefix.length).replaceFirst('.', '')),
    };

String _lowerFirst(String value) =>
    value.isEmpty ? value : value[0].toLowerCase() + value.substring(1);
