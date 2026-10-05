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

  // Issue #959: the OS permission state is write-only for a reason — iOS
  // read authorization is opaque by Apple's design and must never be
  // reported as a refusal. These guards keep the native `permissionStatus`
  // handlers on the write types / requested set, so a future edit that
  // consults read access fails here rather than shipping a false denial.
  group('iOS permissionStatus consults only the write types (#959)', () {
    late String swift;

    setUpAll(() {
      swift = _stripLineComments(readRepoFile(_appDelegatePath));
    });

    test('authorizationStatus is queried over writtenSampleTypes', () {
      expect(swift, contains('store.authorizationStatus(for: type)'));
      expect(swift, contains('for type in writtenSampleTypes'));
    });

    test('the read type is never the subject of an authorizationStatus query',
        () {
      // The read set is the single menstrual-flow type; it must not appear
      // in an authorizationStatus call (the regression this guards).
      expect(
        swift,
        isNot(contains('authorizationStatus(for: menstrualFlowType)')),
      );
      expect(swift, contains('UIApplication.openSettingsURLString'));
    });
  });

  group('Android permissionStatus consults only the write permissions '
      '(#959, #1478)', () {
    late String kotlin;

    setUpAll(() {
      kotlin = _stripLineComments(readRepoFile(_adapterPath));
    });

    test('the status is the SDK check plus getGrantedPermissions over the '
        'write permissions, and nothing a read could deny', () {
      expect(kotlin, contains('permissionController.getGrantedPermissions()'));
      // Issue #1478: the set the "granted" answer requires is the write
      // set itself — the Android half now matches the iOS half above. It
      // used to be every requested permission but the background read
      // (#1211's foregroundStatusPermissions), which made declining an
      // optional READ permission ("Access past data") a denial of the
      // writes.
      expect(
        RegExp(r'private\s+val\s+statusPermissions\s*=\s*writePermissions\b')
            .hasMatch(kotlin),
        isTrue,
        reason: 'permissionStatus must be decided on the write permissions',
      );
      expect(kotlin, contains('required = statusPermissions'));
      expect(kotlin, isNot(contains('foregroundStatusPermissions')));
      // The request sheet still carries writes and reads together.
      expect(kotlin, contains('requested = allPermissions'));
      expect(kotlin, contains('launcher.launch(allPermissions)'));
    });

    test('"never asked" is told apart from "denied" by remembering the '
        'request (issue #1478)', () {
      // Android cannot tell the two apart from the granted set, and the
      // Dart write pass stops on "denied" before its own authorization
      // request — so answering "denied" on a fresh install meant the write
      // path could never ask. The adapter remembers that it launched the
      // request, sets that BEFORE launching (an interrupted sheet has still
      // been shown), and decides through the pure HealthPermissionState.
      expect(kotlin, contains('PERMISSION_REQUESTED_KEY'));
      final remembered = kotlin.indexOf(
          'prefs.edit().putLong(PERMISSION_REQUESTED_KEY, installStamp)');
      final launched = kotlin.indexOf('launcher.launch(allPermissions)');
      expect(remembered, isNonNegative);
      expect(launched, isNonNegative);
      expect(remembered, lessThan(launched),
          reason: 'the request is remembered before the sheet is launched');
      expect(kotlin, contains('HealthPermissionState.statusFor('));
      expect(kotlin, contains('everRequested = permissionEverRequested()'));
      // The marker counts only for the install that made it: these prefs
      // can reach a new phone through Android's device-to-device transfer,
      // where no Health Connect permission is granted and nothing has been
      // asked. So it is stamped with the install's own first-install time
      // and compared against it, never read as a bare flag.
      expect(kotlin, contains('.firstInstallTime'));
      expect(
        kotlin,
        contains('prefs.getLong(PERMISSION_REQUESTED_KEY, 0L) == installStamp'),
      );
      expect(kotlin, isNot(contains('putBoolean(PERMISSION_REQUESTED_KEY')));
      // The decision itself, in the order that matters: granted first,
      // then asked-and-not-granted, and only then not-asked.
      final decision = RegExp(
        r'granted\.containsAll\(required\)\s*->\s*GRANTED\s*'
        r'everRequested\s*\|\|\s*provesAsked\(granted,\s*requested\)\s*->\s*DENIED\s*'
        r'else\s*->\s*NOT_ASKED',
      );
      expect(decision.hasMatch(kotlin), isTrue,
          reason: 'HealthPermissionState.statusFor changed shape — update '
              'HealthPermissionStateTest.kt and this guard together');
      expect(
        RegExp(r'fun provesAsked\(granted: Set<String>, requested: Set<String>\)'
                r': Boolean =\s*granted\.any\s*\{\s*it in requested\s*\}')
            .hasMatch(kotlin),
        isTrue,
      );
      for (final wire in ['"granted"', '"notAsked"', '"denied"']) {
        expect(kotlin, contains(wire));
      }
    });

    // The review of issue #1478. Access granted without this install's own
    // sheet — by an older build's, or in Health Connect's settings — leaves
    // no marker. Removed altogether later, it would read "not yet asked";
    // and with a forward-only cursor already in place the write pass never
    // asks again, so every write would fail behind a screen with no link to
    // Health Connect's settings. So permissionStatus sets the marker as
    // soon as it sees a grant.
    test('a grant seen by permissionStatus is remembered as asked, so a '
        'later revocation reads "denied" (issue #1478 review)', () {
      final handler = kotlin.indexOf('"permissionStatus" ->');
      final nextHandler = kotlin.indexOf('"openPermissionSettings" ->');
      expect(handler, isNonNegative);
      expect(nextHandler, greaterThan(handler));
      final body = kotlin.substring(handler, nextHandler);

      final seen = body.indexOf(
          'HealthPermissionState.provesAsked(granted, allPermissions)');
      final remembered = RegExp(
        r'prefs\.edit\(\)\s*\.putLong\(PERMISSION_REQUESTED_KEY, installStamp\)'
        r'\s*\.apply\(\)',
      ).firstMatch(body);
      final answered = body.indexOf('HealthPermissionState.statusFor(');
      expect(seen, isNonNegative,
          reason: 'permissionStatus must look for a grant of any requested '
              'permission');
      expect(remembered, isNotNull,
          reason: 'and set the marker when it finds one');
      expect(remembered!.start, greaterThan(seen));
      expect(remembered.start, lessThan(answered),
          reason: 'the marker is set before the status is decided');
    });

    test('the settings deep link is Health Connect settings', () {
      expect(kotlin, contains('ACTION_HEALTH_CONNECT_SETTINGS'));
    });
  });

  // Issue #1491: the background import is gated on a read-side status of
  // its own. Gated on `permissionStatus` (the writes), it never ran for a
  // person who let lunarlog read from Health Connect and not write to it.
  // These guards keep the Kotlin handler on the reads the import performs,
  // keep it from ever asking or remembering, and keep the question off the
  // Swift side, where HealthKit could not answer it.
  group('Android importPermissionStatus consults only the reads the import '
      'performs (#1491)', () {
    late String kotlin;
    late String handler;

    setUpAll(() {
      kotlin = _stripLineComments(readRepoFile(_adapterPath));
      final start = kotlin.indexOf('"importPermissionStatus" ->');
      final end = kotlin.indexOf('"permissionStatus" ->');
      expect(start, isNonNegative);
      expect(end, greaterThan(start),
          reason: 'the read-side handler sits just above permissionStatus');
      handler = kotlin.substring(start, end);
    });

    test('the required set is the two record reads and nothing else', () {
      // The set literal: from its declaration to the line that closes it.
      const declaration = 'private val importReadPermissions = setOf(';
      final start = kotlin.indexOf(declaration);
      expect(start, isNonNegative,
          reason: 'importReadPermissions changed shape — update this guard');
      final close = RegExp(r'\n\s*\)\s*\n').firstMatch(kotlin.substring(start));
      expect(close, isNotNull);
      final body = kotlin.substring(start, start + close!.start);
      expect(
        RegExp(r'getReadPermission\((\w+)::class\)')
            .allMatches(body)
            .map((match) => match.group(1))
            .toSet(),
        {'MenstruationFlowRecord', 'IntermenstrualBleedingRecord'},
        reason: 'exactly the record types readSamples reads',
      );
      // Neither optional extra: "access past data" only widens a read, and
      // the worker checks the background read itself.
      expect(body, isNot(contains('PERMISSION_READ_HEALTH_DATA')));
      expect(body, isNot(contains('getWritePermission')));
      expect(body, isNot(contains('backgroundReadPermissions')));
      // The pass really does read those two types and no third.
      expect(
        RegExp(r'ReadRecordsRequest\(\s*(\w+)::class')
            .allMatches(kotlin)
            .map((match) => match.group(1))
            .toSet(),
        {'MenstruationFlowRecord', 'IntermenstrualBleedingRecord'},
      );
    });

    test('the request sheet still asks for the same permissions', () {
      // Factoring the two record reads out must not have dropped either
      // from what is requested.
      expect(
        RegExp(r'private\s+val\s+readPermissions\s*=\s*setOf\(\s*'
                r'HealthPermission\.PERMISSION_READ_HEALTH_DATA_HISTORY,\s*\)'
                r'\s*\+\s*importReadPermissions\s*\+\s*backgroundReadPermissions\(\)')
            .hasMatch(kotlin),
        isTrue,
      );
      expect(
        kotlin,
        contains('private val allPermissions = writePermissions + readPermissions'),
      );
    });

    test('the status is the SDK check plus getGrantedPermissions over that '
        'set', () {
      expect(handler, contains('healthConnectClient()'));
      expect(handler, contains('result.success("unavailable")'));
      expect(handler, contains('permissionController.getGrantedPermissions()'));
      expect(handler, contains('HealthPermissionState.importStatusFor('));
      expect(handler, contains('importReads = importReadPermissions'));
      expect(handler, contains('requested = allPermissions'));
      expect(handler, isNot(contains('statusPermissions')));
      expect(handler, isNot(contains('writePermissions')));
    });

    test('it only looks: no permission request, and the asked-marker is read '
        'but never set', () {
      expect(handler, isNot(contains('launcher')));
      expect(handler, isNot(contains('requestPermissions')));
      expect(handler, isNot(contains('.launch(')));
      expect(handler, contains('everRequested = permissionEverRequested()'));
      // Setting the marker here would change what permissionStatus answers
      // for the write path: a first write pass would read "denied" where it
      // should read "not yet asked", and stop before it could ask.
      expect(handler, isNot(contains('prefs.edit()')));
      expect(handler, isNot(contains('PERMISSION_REQUESTED_KEY')));
      expect(handler, isNot(contains('provesAsked')));
    });

    test('the decision is the write-side one over the read set, not a second '
        'rule', () {
      expect(
        RegExp(
          r'fun importStatusFor\(\s*granted: Set<String>,\s*'
          r'importReads: Set<String>,\s*requested: Set<String>,\s*'
          r'everRequested: Boolean,\s*\): String = statusFor\(\s*'
          r'granted = granted,\s*required = importReads,\s*'
          r'requested = requested,\s*everRequested = everRequested,\s*\)',
        ).hasMatch(kotlin),
        isTrue,
        reason: 'HealthPermissionState.importStatusFor changed shape — '
            'update HealthImportPermissionStateTest.kt and this guard together',
      );
    });
  });

  group('iOS answers the read-side status in Dart, from the write types '
      '(#1491)', () {
    test('Swift has no importPermissionStatus handler to guess with', () {
      // HealthKit never discloses read access, so a native answer could
      // only be invented. The iOS adapter never sends the method.
      expect(
        _stripLineComments(readRepoFile(_appDelegatePath)),
        isNot(contains('importPermissionStatus')),
      );
    });

    test('each platform pin states whether its store discloses read access',
        () {
      final ios = _stripLineComments(
        readRepoFile('lib/data/health/ios_health_channel.dart'),
      );
      final android = _stripLineComments(
        readRepoFile('lib/data/health/android_health_channel.dart'),
      );
      expect(ios, contains('readAccessDisclosed: false'));
      expect(android, contains('readAccessDisclosed: true'));
    });
  });
}
