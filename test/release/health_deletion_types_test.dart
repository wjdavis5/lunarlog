/// Issue #924: the regression guard that keeps deletion covering every type
/// the app writes.
///
/// The write path can only reach the OS health store through
/// `AppDelegate.swift` (HealthKit) and `HealthConnectAdapter.kt` (Health
/// Connect), neither of which compiles or runs under `flutter test`. The
/// type sets those native halves delete are therefore text-guarded here
/// against the Dart collections derived from the mapping tables
/// (`health_written_types.dart`), so **adding a written type without adding
/// it to deletion fails this suite** — the exact bug #924 exists to close.
///
/// The native lists are parsed (not merely `contains`-checked) so an
/// unexpected extra type also fails.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_record_ids.dart';
import 'package:lunarlog/data/health/health_symptom_mapping.dart';
import 'package:lunarlog/data/health/health_written_types.dart';
import 'package:lunarlog/domain/health/health_type_registry.dart';
import 'package:lunarlog/domain/models/local_date.dart';

import 'repo_text_helpers.dart';

const _appDelegatePath = 'ios/Runner/AppDelegate.swift';
const _adapterPath =
    'android/app/src/main/kotlin/com/wjdavis5/lunarlog/HealthConnectAdapter.kt';

/// Strips `//` line comments so a commented-out identifier cannot satisfy a
/// parse (mirrors `stripHashComments`'s intent for the other guard tests).
String _stripLineComments(String text) => text
    .split('\n')
    .map((line) {
      final index = line.indexOf('//');
      return index >= 0 ? line.substring(0, index) : line;
    })
    .join('\n');

/// The `.caseName` members of a Swift array literal assigned to
/// [declaration]. Assumes no nested brackets inside the literal (true here).
Set<String> _swiftArrayCases(String source, String declaration) {
  final start = source.indexOf(declaration);
  expect(start, isNonNegative,
      reason: '$declaration was not found in the native source');
  final open = source.indexOf('= [', start);
  expect(open, isNonNegative, reason: '$declaration has no array literal');
  final close = source.indexOf(']', open);
  expect(close, greaterThan(open), reason: '$declaration array is unterminated');
  final block = source.substring(open + 2, close);
  return RegExp(r'\.([A-Za-z]\w*)')
      .allMatches(block)
      .map((match) => match.group(1)!)
      .toSet();
}

/// The `X::class` names inside the Kotlin `writtenRecordTypes = listOf(...)`
/// literal.
Set<String> _kotlinRecordTypes(String source) {
  final start = source.indexOf('writtenRecordTypes');
  expect(start, isNonNegative,
      reason: 'writtenRecordTypes was not found in the Kotlin source');
  final listOf = source.indexOf('listOf(', start);
  expect(listOf, isNonNegative, reason: 'writtenRecordTypes has no listOf');
  final close = source.indexOf(')', listOf);
  expect(close, greaterThan(listOf), reason: 'writtenRecordTypes is unterminated');
  final block = source.substring(listOf, close);
  return RegExp(r'(\w+)::class')
      .allMatches(block)
      .map((match) => match.group(1)!)
      .toSet();
}

String _swiftCaseName(String identifier, String prefix) {
  final remainder = identifier.substring(prefix.length).replaceFirst('.', '');
  return remainder.isEmpty
      ? remainder
      : remainder[0].toLowerCase() + remainder.substring(1);
}

/// Independently re-derives every HealthKit category case name from the
/// registry + symptom table — the "written type set" the native list must
/// equal. Deliberately not calling the accessor under test.
Set<String> _derivedHealthKitCategoryCaseNames() => {
      for (final entry in kHealthTypeRegistry)
        if (entry.status == HealthTypeMappingStatus.implemented)
          if (entry.healthKitIdentifier case final identifier?)
            if (identifier.startsWith('HKCategoryTypeIdentifier'))
              _swiftCaseName(identifier, 'HKCategoryTypeIdentifier'),
      ...kSymptomHealthKitTypeIdentifiers.values,
    };

Set<String> _derivedHealthKitQuantityCaseNames() => {
      for (final entry in kHealthTypeRegistry)
        if (entry.status == HealthTypeMappingStatus.implemented)
          if (entry.healthKitIdentifier case final identifier?)
            if (identifier.startsWith('HKQuantityTypeIdentifier'))
              _swiftCaseName(identifier, 'HKQuantityTypeIdentifier'),
    };

Set<String> _derivedHealthConnectRecordTypes() => {
      for (final entry in kHealthTypeRegistry)
        if (entry.status == HealthTypeMappingStatus.implemented)
          ?entry.healthConnectRecord,
    };

void main() {
  group('the Dart accessors are genuinely derived from the tables', () {
    test('HealthKit category case names', () {
      expect(
        kHealthKitWrittenCategoryTypeCaseNames,
        _derivedHealthKitCategoryCaseNames(),
      );
    });

    test('HealthKit quantity case names', () {
      expect(
        kHealthKitWrittenQuantityTypeCaseNames,
        _derivedHealthKitQuantityCaseNames(),
      );
    });

    test('Health Connect record types', () {
      expect(kHealthConnectWrittenRecordTypes, _derivedHealthConnectRecordTypes());
    });

    test('the flow types are present and menstrualPeriod is Health-Connect-only',
        () {
      expect(kHealthKitWrittenCategoryTypeCaseNames, contains('menstrualFlow'));
      expect(
          kHealthKitWrittenCategoryTypeCaseNames, contains('intermenstrualBleeding'));
      // #202's period record has no HealthKit analogue (null identifier).
      expect(kHealthKitWrittenCategoryTypeCaseNames, isNot(contains('menstrualPeriod')));
      expect(kHealthConnectWrittenRecordTypes, contains('MenstruationPeriodRecord'));
    });

    test('the #238/#228 types that #924 exists to cover are all present', () {
      for (final type in [
        'cervicalMucusQuality',
        'ovulationTestResult',
      ]) {
        expect(kHealthKitWrittenCategoryTypeCaseNames, contains(type));
      }
      expect(kHealthKitWrittenQuantityTypeCaseNames, {'basalBodyTemperature'});
    });

    test('the combined HealthKit set is category + quantity', () {
      expect(
        kHealthKitWrittenTypeCaseNames,
        {
          ...kHealthKitWrittenCategoryTypeCaseNames,
          ...kHealthKitWrittenQuantityTypeCaseNames,
        },
      );
    });
  });

  group('the shared record-id builders are the wire scheme', () {
    // Pins the exact strings the write path stamps as clientRecordId /
    // HKMetadataKeyExternalUUID. The deletion coordinator derives the same
    // ids through these builders, so a changed scheme that is not mirrored
    // here (and in the write path) fails loudly rather than silently
    // orphaning samples.
    test('every builder produces the documented record id', () {
      expect(healthFlowRecordId('entry'), 'entry');
      expect(healthSpottingRecordId('obs'), 'obs');
      expect(healthSymptomRecordId('entry', 'headache'), 'symptom-entry-headache');
      expect(healthCervicalMucusRecordId('entry'), 'cervical-mucus-entry');
      expect(
        healthOvulationRecordId('entry', 'negative'),
        'ovulation-entry-negative',
      );
      expect(healthBbtRecordId('obs'), 'bbt-obs');
      expect(
        healthPeriodRecordId('profile', LocalDate(2026, 9, 1)),
        'period-profile-2026-09-01',
      );
    });
  });

  group('iOS deleteRecords covers every written HealthKit type', () {
    late String swift;

    setUpAll(() {
      swift = _stripLineComments(readRepoFile(_appDelegatePath));
    });

    test('the category list matches the written set exactly', () {
      expect(
        _swiftArrayCases(swift, 'writtenCategoryTypeIdentifiers'),
        _derivedHealthKitCategoryCaseNames(),
      );
    });

    test('the quantity list matches the written set exactly', () {
      expect(
        _swiftArrayCases(swift, 'writtenQuantityTypeIdentifiers'),
        _derivedHealthKitQuantityCaseNames(),
      );
    });

    test('authorization and deletion share the one resolved list', () {
      // `writtenSampleTypes` is what both the authorization sheet and the
      // delete query loop over, so the two cannot drift.
      expect(swift, contains('let toShare = Set(writtenSampleTypes)'));
      expect(swift, contains('for sampleType in writtenSampleTypes'));
      // The old symptom-only list must be gone — its survival is exactly
      // how a written type could be authorized but never deleted.
      expect(swift, isNot(contains('symptomCategoryTypes')));
    });

    test('the stale "two types this app writes" comment is gone', () {
      expect(swift, isNot(contains('the two types this app writes')));
      expect(swift, isNot(contains('the two types this app')));
    });
  });

  group('Android deleteRecords covers every written Health Connect type', () {
    late String kotlin;

    setUpAll(() {
      kotlin = _stripLineComments(readRepoFile(_adapterPath));
    });

    test('the record-type list matches the written set exactly', () {
      expect(
        _kotlinRecordTypes(kotlin),
        _derivedHealthConnectRecordTypes(),
      );
    });

    test('permissions and deletion share the one list', () {
      expect(
        kotlin,
        contains('writtenRecordTypes.map { HealthPermission.getWritePermission(it) }'),
      );
      expect(kotlin, contains('for (recordType in writtenRecordTypes)'));
    });
  });
}
