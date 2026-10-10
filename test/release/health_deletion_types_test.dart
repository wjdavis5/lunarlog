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

/// The slice of [source] from [start] up to [end] — one `when` branch of
/// the Kotlin channel handler, taken between its own label and the next
/// branch's.
String _between(String source, String start, String end) {
  final from = source.indexOf(start);
  expect(from, isNonNegative, reason: '$start was not found');
  final to = source.indexOf(end, from + start.length);
  expect(to, greaterThan(from), reason: '$end does not follow $start');
  return source.substring(from, to);
}

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

/// The quoted wire names, in order, inside the Kotlin
/// `writtenRecordTypeWires = listOf(...)` literal (Issue #1590).
List<String> _kotlinWireNames(String source) {
  final start = source.indexOf('val writtenRecordTypeWires');
  expect(start, isNonNegative,
      reason: 'writtenRecordTypeWires was not found in the Kotlin source');
  final listOf = source.indexOf('listOf(', start);
  expect(listOf, isNonNegative, reason: 'writtenRecordTypeWires has no listOf');
  final close = source.indexOf(')', listOf);
  expect(close, greaterThan(listOf),
      reason: 'writtenRecordTypeWires is unterminated');
  final block = source.substring(listOf, close);
  return RegExp(r'"(\w+)"')
      .allMatches(block)
      .map((match) => match.group(1)!)
      .toList();
}

/// The `("wire", .caseName)` pairs of the `categoryWires` table in
/// Swift's `wireIdentifier(for:)`: the name a delete reports for a type it
/// passed over, by the HealthKit case it stands for.
Map<String, String> _swiftWireNamesByCase(String source) {
  final start = source.indexOf('let categoryWires');
  expect(start, isNonNegative, reason: 'categoryWires was not found');
  final close = source.indexOf('\n    ]', start);
  expect(close, greaterThan(start), reason: 'categoryWires is unterminated');
  return {
    for (final match in RegExp(r'\("(\w+)",\s*\.(\w+)\)')
        .allMatches(source.substring(start, close)))
      match.group(2)!: match.group(1)!,
  };
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

    test('healthRecordMatchesSkippedType correctly matches skipped write types (issue #1583)', () {
      expect(
        healthRecordMatchesSkippedType('cervical-mucus-123', {'cervicalMucus'}),
        isTrue,
      );
      expect(
        healthRecordMatchesSkippedType('cervical-mucus-123', {'ovulationTest'}),
        isFalse,
      );
      expect(
        healthRecordMatchesSkippedType('ovulation-123-positive', {'ovulationTest'}),
        isTrue,
      );
      expect(
        healthRecordMatchesSkippedType('bbt-123', {'basalBodyTemperature'}),
        isTrue,
      );
      expect(
        healthRecordMatchesSkippedType('period-prof-2026-09-01', {'menstrualFlow'}),
        isTrue,
      );
      expect(
        healthRecordMatchesSkippedType('symptom-123-headache', {'symptoms'}),
        isTrue,
      );
      expect(
        healthRecordMatchesSkippedType('symptom-123-headache', {'headache'}),
        isTrue,
      );
      expect(
        healthRecordMatchesSkippedType('symptom-123-headache', {'bloating'}),
        isFalse,
      );
      // What the iOS half sends when one symptom type is off: that type,
      // and 'symptoms' beside it. A record of another symptom type was
      // deleted, and must not read as passed over.
      expect(
        healthRecordMatchesSkippedType(
          'symptom-123-headache',
          {'acne', 'symptoms'},
        ),
        isFalse,
      );
      expect(
        healthRecordMatchesSkippedType(
          'symptom-123-acne',
          {'acne', 'symptoms'},
        ),
        isTrue,
      );
      // Every mapped symptom type is told from every other one, with a
      // day's real id (a ULID) and with one that has hyphens in it.
      final types = kSymptomHealthKitTypeIdentifiers.values.toSet();
      for (final entryId in ['01ARZ3NDEKTSV4RRFFQ69G5FBC', 'entry-2026-06-02']) {
        for (final type in types) {
          final recordId = healthSymptomRecordId(entryId, type);
          expect(
            healthRecordMatchesSkippedType(recordId, {type, 'symptoms'}),
            isTrue,
            reason: recordId,
          );
          expect(
            healthRecordMatchesSkippedType(
              recordId,
              {...types.where((other) => other != type), 'symptoms'},
            ),
            isFalse,
            reason: recordId,
          );
        }
      }
      expect(
        healthRecordMatchesSkippedType('01ARZ3NDEKTSV4RRFFQ69G5FBC', {'menstrualFlow'}),
        isTrue,
      );
      expect(
        healthRecordMatchesSkippedType('01ARZ3NDEKTSV4RRFFQ69G5FBC', {'spotting'}),
        isFalse,
      );
      expect(
        healthRecordMatchesSkippedType('01ARZ3NDEKTSV4RRFFQ69G5FBC', {'spotting'}, isSpotting: true),
        isTrue,
      );
      // Issue #1589: a spotting entry's record without summary may be either
      // type, so either type passed over leaves it remembered.
      expect(
        healthRecordMatchesSkippedType('01ARZ3NDEKTSV4RRFFQ69G5FBC', {'menstrualFlow'}, isSpotting: true),
        isTrue,
      );
      expect(
        healthRecordMatchesSkippedType('01ARZ3NDEKTSV4RRFFQ69G5FBC', {'cervicalMucus'}, isSpotting: true),
        isFalse,
      );
      // Issue #1644: with a known payload summary, only the record's own
      // written type counts as passed over.
      expect(
        healthRecordMatchesSkippedType(
          '01ARZ3NDEKTSV4RRFFQ69G5FBC',
          {'spotting'},
          isSpotting: true,
          payloadSummary: 'marker',
        ),
        isTrue,
      );
      expect(
        healthRecordMatchesSkippedType(
          '01ARZ3NDEKTSV4RRFFQ69G5FBC',
          {'menstrualFlow'},
          isSpotting: true,
          payloadSummary: 'marker',
        ),
        isFalse,
      );
      expect(
        healthRecordMatchesSkippedType(
          '01ARZ3NDEKTSV4RRFFQ69G5FBC',
          {'spotting'},
          isSpotting: true,
          payloadSummary: 'flow:light:0',
        ),
        isFalse,
      );
      expect(
        healthRecordMatchesSkippedType(
          '01ARZ3NDEKTSV4RRFFQ69G5FBC',
          {'menstrualFlow'},
          isSpotting: true,
          payloadSummary: 'flow:light:0',
        ),
        isTrue,
      );
      expect(
        healthRecordMatchesSkippedType('01ARZ3NDEKTSV4RRFFQ69G5FBC', const {}),
        isFalse,
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

    // Review of #1603. A delete names the types it passed over, and Dart
    // lets a symptom record go unless its own type is named. So a symptom
    // type that Swift reported under any other name, or not at all, would
    // be let go while still in Apple Health.
    test('a passed-over symptom type is reported by the name its record '
        'ids carry', () {
      final wires = _swiftWireNamesByCase(swift);
      for (final type in kSymptomHealthKitTypeIdentifiers.values.toSet()) {
        expect(wires[type], type, reason: 'the wire name for .$type');
      }
    });

    test('every written category type has a name to be reported by', () {
      expect(
        _swiftWireNamesByCase(swift).keys.toSet(),
        _swiftArrayCases(swift, 'writtenCategoryTypeIdentifiers'),
      );
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
      expect(kotlin, contains('writes = statusPermissions'));
      expect(kotlin, isNot(contains('foregroundStatusPermissions')));
      // The write path's request sheet still carries writes and reads
      // together (issue #1515 gave the import a request of its own; the
      // #1515 group below pins which request asks for what).
      expect(
        kotlin,
        contains('private val allPermissions = writePermissions + readPermissions'),
      );
      expect(kotlin, contains('permissions = allPermissions'));
    });

    test('"never asked" is told apart from "denied" by remembering the '
        'request (issue #1478)', () {
      // Android cannot tell the two apart from the granted set, and the
      // Dart write pass stops on "denied" before its own authorization
      // request — so answering "denied" on a fresh install meant the write
      // path could never ask. The adapter remembers that it launched the
      // request and decides through the pure HealthPermissionState.
      //
      // Issue #1515: the launch is shared with the import's own request,
      // so the remembering lives in the shared launcher and each request
      // names the marker it sets. The write path's is this one.
      //
      // Issue #1883: the remembering happens once the launch RETURNED.
      // `launch` hands the sheet to the activity and returns before it
      // appears, so a sheet interrupted after that (the process dies
      // behind it) is still remembered — while a launch that throws
      // records nothing and is answered as the failure it always was.
      expect(kotlin, contains('PERMISSION_REQUESTED_KEY'));
      final remembered =
          kotlin.indexOf('prefs.edit().putLong(askedMarker, installStamp)');
      final launched = kotlin.indexOf('launcher.launch(permissions)');
      expect(remembered, isNonNegative);
      expect(launched, isNonNegative);
      expect(launched, lessThan(remembered),
          reason: 'the request is remembered once the launch returned');
      expect('launcher.launch('.allMatches(kotlin), hasLength(1),
          reason: 'one launcher: no request can skip the remembering');
      final writeRequest = _between(
        kotlin,
        '"requestWriteAuthorization" ->',
        '"requestImportAuthorization" ->',
      );
      expect(writeRequest, contains('launchPermissionRequest('));
      expect(writeRequest, contains('askedMarker = PERMISSION_REQUESTED_KEY'));
      expect(kotlin, contains('HealthPermissionState.writeStatusFor('));
      expect(kotlin, contains('writesEverRequested = writesEverRequested()'));
      // The marker counts only for the install that made it: these prefs
      // can reach a new phone through Android's device-to-device transfer,
      // where no Health Connect permission is granted and nothing has been
      // asked. So it is stamped with the install's own first-install time
      // and compared against it, never read as a bare flag.
      expect(kotlin, contains('.firstInstallTime'));
      expect(
        kotlin,
        contains('prefs.contains(key) && prefs.getLong(key, 0L) == installStamp'),
      );
      expect(
        RegExp(r'private fun writesEverRequested\(\): Boolean =\s*'
                r'markerSetByThisInstall\(PERMISSION_REQUESTED_KEY\)')
            .hasMatch(kotlin),
        isTrue,
      );
      expect(kotlin, isNot(contains('putBoolean(')));
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
      for (final wire in ['"granted"', '"notAsked"', '"denied"', '"writingSome"']) {
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

      // Issue #1515: a WRITE grant always counts. A read can be granted on
      // the import's own sheet, which never shows the writes, so a granted
      // read says the person was asked for them only while that sheet has
      // never been raised by this install: one rule, in
      // HealthPermissionState.remembersWritesAsked.
      final seen =
          body.indexOf('HealthPermissionState.remembersWritesAsked(');
      expect(
        RegExp(
          r'HealthPermissionState\.remembersWritesAsked\(\s*'
          r'granted = granted,\s*writes = writePermissions,\s*'
          r'requested = allPermissions,\s*'
          r'importRequestLaunched = importRequestLaunched\(\),\s*\)',
        ).hasMatch(body),
        isTrue,
        reason: 'the rule is asked about the writes, everything the app '
            'requests, and whether the import\'s own sheet was ever raised',
      );
      final remembered = RegExp(
        r'prefs\.edit\(\)\s*\.putLong\(PERMISSION_REQUESTED_KEY, installStamp\)'
        r'\s*\.apply\(\)',
      ).firstMatch(body);
      final answered = body.indexOf('HealthPermissionState.writeStatusFor(');
      expect(body, isNot(contains('provesAsked(granted, allPermissions)')),
          reason: 'a read granted by the import\'s request must not mark the '
              'writes as asked: the write pass would stop before asking');
      expect(seen, isNonNegative,
          reason: 'permissionStatus must look for a grant that shows the '
              'writes were asked for');
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
      final end = kotlin.indexOf('"importPastDataGranted" ->');
      expect(start, isNonNegative);
      expect(end, greaterThan(start),
          reason: 'the read-side handler sits just above '
              'importPastDataGranted');
      handler = kotlin.substring(start, end);
    });

    // Issue #1549: the question "is Access past data on" has a handler
    // of its own, between the two.
    test('importPastDataGranted only looks: one answer from the granted '
        'set, no request, no marker read or set', () {
      final start = kotlin.indexOf('"importPastDataGranted" ->');
      final end = kotlin.indexOf('"permissionStatus" ->');
      expect(start, isNonNegative);
      expect(end, greaterThan(start));
      final pastData = kotlin.substring(start, end);

      expect(pastData, contains('healthConnectClient()'));
      expect(pastData, contains('result.success(false)'));
      expect(pastData, contains('result.success(pastDataGranted(client))'));
      for (final forbidden in [
        'launcher',
        'requestPermissions',
        '.launch(',
        'prefs.',
        'permissionEverRequested',
        'PERMISSION_REQUESTED_KEY',
        'IMPORT_REQUEST_LAUNCHED_KEY',
      ]) {
        expect(pastData, isNot(contains(forbidden)), reason: forbidden);
      }

      // The helper it answers through: the granted set and nothing else.
      final helperStart =
          kotlin.indexOf('private suspend fun pastDataGranted(');
      final helperEnd =
          kotlin.indexOf('private suspend fun applyPastReadStep(');
      expect(helperStart, isNonNegative);
      expect(helperEnd, greaterThan(helperStart));
      final helper = kotlin.substring(helperStart, helperEnd);
      expect(helper, contains('permissionController.getGrantedPermissions()'));
      expect(
        helper,
        contains('HealthPermission.PERMISSION_READ_HEALTH_DATA_HISTORY'),
      );
      expect(helper, isNot(contains('prefs.')));
    });

    // Issue #1549: turning "Access past data" on after the first import
    // used to import nothing, ever: the first whole-range read minted a
    // change token, and every later pass asked only for what changed.
    test('a whole-range read is owed once Access past data is on, and the '
        'adapter remembers whether its last one reached that far', () {
      // Decided at the start of a pass only, never between its pages.
      expect(
        kotlin,
        contains('if (decoded == null) applyPastReadStep(client, profileId)'),
      );
      expect('applyPastReadStep('.allMatches(kotlin), hasLength(2),
          reason: 'declared once and called from that one place');
      // Issue #1556: the companion one-time step, decided the same way — a
      // stored change token minted before the period record joined the read
      // set never returns one, so it is dropped once.
      expect(
        kotlin,
        contains(
            'if (decoded == null) applyPeriodCoverageStep(client, profileId)'),
      );
      expect('applyPeriodCoverageStep('.allMatches(kotlin), hasLength(2),
          reason: 'declared once and called from that one place');
      // What it does with each answer of the rule. Bounded at the #1556
      // step so this substring holds applyPastReadStep's body alone.
      final stepStart =
          kotlin.indexOf('private suspend fun applyPastReadStep(');
      final stepEnd =
          kotlin.indexOf('private suspend fun applyPeriodCoverageStep(');
      expect(stepStart, isNonNegative);
      expect(stepEnd, greaterThan(stepStart));
      final step = kotlin.substring(stepStart, stepEnd);
      expect(
        step,
        matches(RegExp(
          r'PastReadStep\.REREAD ->\s+'
          r'prefs\.edit\(\)\.remove\(changesTokenKey\(profileId\)\)'
          r'\.apply\(\)',
        )),
      );
      expect(
        step,
        matches(RegExp(
          r'PastReadStep\.LOWER ->\s+prefs\.edit\(\)\s+\.putString\(\s+'
          r'reachedPastKey\(profileId\),\s+'
          r'HealthImportCursor\.reachedPastToWire\(false\),',
        )),
      );
      expect(step, contains('PastReadStep.NONE -> Unit'));
      // Lowering never touches the token, and a re-read never the flag.
      expect('changesTokenKey(profileId)'.allMatches(step), hasLength(2),
          reason: 'read once, removed once');
      // Recorded on the first page of a whole-range read, and only
      // lowered on the last: a switch turned on part-way is not "reached".
      final rangeStart =
          kotlin.indexOf('private suspend fun readRangePage(');
      final rangeEnd =
          kotlin.indexOf('private suspend fun mintChangesToken(');
      expect(rangeStart, isNonNegative);
      expect(rangeEnd, greaterThan(rangeStart));
      final range = kotlin.substring(rangeStart, rangeEnd);
      final firstPage = range.indexOf('if (token == null) {');
      final firstRead = range.indexOf('client.readRecords(');
      expect(firstPage, isNonNegative);
      expect(firstRead, greaterThan(firstPage),
          reason: 'recorded before the first page is read');
      expect(
        range.substring(firstPage, firstRead),
        contains('HealthImportCursor.reachedPastToWire('
            'pastDataGranted(client)),'),
      );
      expect(
        'reachedPastToWire(pastDataGranted(client))'.allMatches(kotlin),
        hasLength(1),
        reason: 'only the first page may say the read reached it',
      );
      expect(kotlin, isNot(contains('reachedPastToWire(true)')));
      // Issue #1560: readRangePage never writes the change token directly;
      // it returns commitToken with lowerPast determined by whether past
      // data is granted on the last page.
      expect(range, isNot(contains('.putString(changesTokenKey(')));
      expect(range, contains('lowerPast = !pastDataGranted(client)'));
      // The position is saved only upon commit, after Dart has stored the
      // imported days into SQLite.
      final commitStart = kotlin.indexOf('private fun commitImport(');
      final commitEnd = kotlin.indexOf('private fun changesTokenKey(');
      expect(commitStart, isNonNegative);
      expect(commitEnd, greaterThan(commitStart));
      final commit = kotlin.substring(commitStart, commitEnd);
      expect(
        commit,
        contains('.putString(changesTokenKey(profileId), commit.token)'),
      );
      expect(commit, contains('if (commit.lowerPast) {'));
      expect(
        commit,
        contains('HealthImportCursor.reachedPastToWire(false),'),
      );
      // Unbinding forgets both.
      expect(kotlin, contains('editor.remove(reachedPastKey(it))'));
      // The rule itself is the pure function the Kotlin unit test pins
      // (HealthImportCursorTest), with every combination of its inputs.
      expect(kotlin, contains('HealthImportCursor.pastReadStep('));
      expect(kotlin, contains('HealthImportCursor.reachedPastFromWire('));
    });

    // Issues #1882/#1891: a token Health Connect rejects every time is
    // dropped so the pass recovers; a transient failure is not, because
    // dropping the token would lose every DeletionChange queued behind it
    // (#1594) and force a full-history read. Only the same token failing
    // twice in a row counts as rejected.
    test('a rejected change token is dropped only after failing twice, and '
        'a cancelled read keeps it', () {
      final start = kotlin.indexOf('private suspend fun readSamples(');
      final end = kotlin.indexOf('private suspend fun changesPage(');
      expect(start, isNonNegative);
      expect(end, greaterThan(start));
      final read = kotlin.substring(start, end);
      // Cancellation and a revoked permission both keep the token; a
      // plain failure is handled after them.
      final cancelled = read.indexOf('catch (e: CancellationException)');
      final revoked = read.indexOf('catch (e: SecurityException)');
      final failed = read.indexOf('catch (e: Exception)');
      expect(cancelled, isNonNegative);
      expect(revoked, greaterThan(cancelled));
      expect(failed, greaterThan(revoked));
      // The first failure on a token records it and rethrows...
      final first =
          read.indexOf('if (!changesTokenFailedBefore(profileId, token)) {');
      expect(first, isNonNegative);
      final noted = read.indexOf('noteChangesTokenFailure(profileId, token)');
      expect(noted, greaterThan(first));
      final rethrown = read.indexOf('throw e', noted);
      expect(rethrown, greaterThan(noted));
      // ...and only the second strike drops it and reads the whole range.
      final drop = read.indexOf(
        'prefs.edit().remove(changesTokenKey(profileId))',
        rethrown,
      );
      expect(drop, greaterThan(rethrown));
      expect(
        'prefs.edit().remove(changesTokenKey(profileId))'.allMatches(read),
        hasLength(3),
        reason: 'the whole-history drop, the two-strike drop and the '
            'expired-token drop',
      );
      expect(
        'clearChangesTokenFailure(profileId)'.allMatches(read),
        hasLength(2),
        reason: 'the strike branch and the answered-token path',
      );
      expect(
        read.lastIndexOf('clearChangesTokenFailure(profileId)'),
        greaterThan(drop),
        reason: 'a token that answered clears the strike',
      );
      // The memory is one string per profile: the token that last failed.
      expect(
        kotlin,
        contains('"lunarlog.health.changesTokenFailure.\$profileId"'),
      );
      expect(
        kotlin,
        contains(
          'prefs.getString(changesTokenFailureKey(profileId), null) == token',
        ),
      );
    });

    // Issue #1559: Health Connect changes a record in place and keeps its
    // id. Without the record's own last-modified time the Dart merge
    // cannot tell the other app's correction from hers, and keeps hers.
    test('every imported sample carries its last-modified time', () {
      expect(
        kotlin,
        contains('"modifiedAtMs" to lastModified.toEpochMilli(),'),
      );
      expect(
        'record.metadata.lastModifiedTime'.allMatches(kotlin),
        hasLength(3),
        reason: 'one for each record type the import reads (Issue #1556 '
            'added the period record)',
      );
      expect('sampleMap('.allMatches(kotlin), hasLength(4),
          reason: 'declared once, called for each record type');
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
      // The pass really does read those three types and no further
      // (Issue #1556 added the period record to the read set).
      expect(
        RegExp(r'ReadRecordsRequest\(\s*(\w+)::class')
            .allMatches(kotlin)
            .map((match) => match.group(1))
            .toSet(),
        {
          'MenstruationFlowRecord',
          'IntermenstrualBleedingRecord',
          'MenstruationPeriodRecord',
        },
      );
    });

    test('the request sheet still asks for the same permissions', () {
      // Factoring the two record reads out must not have dropped either
      // from what is requested.
      expect(
        RegExp(r'private\s+val\s+readPermissions\s*=\s*'
                r'pastDataPermissions\(\)'
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

  // Issue #1573: the Health sync screen's button raises Health Connect's
  // own prompt for "Access past data" and nothing else. These guards keep
  // that request to the one permission, keep it from setting either
  // asked-marker (it carries no write and neither record read, so what it
  // was answered proves nothing about them), and keep "is there such a
  // switch" a question that only looks.
  group('Android: the request for past data asks for that alone (#1573)', () {
    late String kotlin;
    late String request;
    late String offered;

    setUpAll(() {
      kotlin = _stripLineComments(readRepoFile(_adapterPath));
      request = _between(
        kotlin,
        '"requestPastDataAccess" ->',
        '"pastDataSwitchOffered" ->',
      );
      offered = _between(
        kotlin,
        '"pastDataSwitchOffered" ->',
        '"importPermissionStatus" ->',
      );
    });

    test('it passes the guard, then asks only where there is such a switch '
        'and the import can already read, for the one permission', () {
      final guarded = request.indexOf(
        'if (!requestGuardAllows(call.method, args, result)) return',
      );
      final checked = request.indexOf('!pastDataOffered()');
      final looked =
          request.indexOf('permissionController.getGrantedPermissions()');
      final decided = request.indexOf(
        'if (!HealthPermissionState.pastDataMayAsk(granted, importReadPermissions))',
      );
      final launched = request.indexOf('launchPermissionRequest(');
      expect(guarded, isNonNegative);
      expect(checked, greaterThan(guarded));
      expect(looked, greaterThan(checked));
      expect(decided, greaterThan(looked));
      expect(launched, greaterThan(decided));
      expect(request, contains('result.success("unavailable")'));
      expect(request, contains('result.success("permissionDenied")'));
      expect(request, contains('permissions = pastDataPermissions()'));
      for (final other in [
        'readPermissions',
        'allPermissions',
        'writePermissions',
        'backgroundReadPermissions',
        'getWritePermission',
        'getReadPermission',
      ]) {
        expect(request, isNot(contains(other)), reason: other);
      }
    });

    test('it sets neither asked-marker', () {
      expect(request, contains('askedMarker = null'));
      expect(request, isNot(contains('PERMISSION_REQUESTED_KEY')));
      expect(request, isNot(contains('IMPORT_REQUEST_LAUNCHED_KEY')));
      expect(request, isNot(contains('prefs.')));
      // And the launcher writes a marker only when it is given one, after
      // a launch that returned (Issue #1883) — a launch that throws is
      // answered as the failure it always was and records nothing.
      final launcher = _between(
        kotlin,
        'private fun launchPermissionRequest(',
        'private fun insert(',
      );
      expect(launcher, contains('askedMarker: String?,'));
      final launched = launcher.indexOf('launcher.launch(permissions)');
      final failure = launcher.indexOf('catch (e: Exception)');
      final marked = launcher.indexOf('markWritePermissionsAsked(permissions)');
      final asked =
          launcher.indexOf('prefs.edit().putLong(askedMarker, installStamp)');
      expect(launched, isNonNegative);
      expect(failure, greaterThan(launched));
      expect(marked, greaterThan(failure));
      expect(asked, greaterThan(marked));
    });

    test('whether there is a switch only looks, and is the feature check',
        () {
      expect(offered, contains('result.success(pastDataOfferedOrNull())'));
      for (final forbidden in [
        'launcher',
        'requestPermissions',
        'launchPermissionRequest',
        '.launch(',
        'prefs.',
        'PERMISSION_REQUESTED_KEY',
        'IMPORT_REQUEST_LAUNCHED_KEY',
      ]) {
        expect(offered, isNot(contains(forbidden)), reason: forbidden);
      }
      final helper = _between(
        kotlin,
        'private fun pastDataOfferedOrNull(): Boolean?',
        'private fun pastDataPermissions(): Set<String>',
      );
      expect(
        helper,
        contains('HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_HISTORY'),
      );
      expect(helper, contains('HealthConnectFeatures.FEATURE_STATUS_AVAILABLE'));
      // A probe that fails is "cannot tell" for the screen, which must not
      // then say the phone has no such switch...
      expect(
        RegExp(r'catch \(_: Exception\) \{\s*null\s*\}').hasMatch(helper),
        isTrue,
      );
      expect(helper, isNot(contains('prefs.')));
      // ...and "not offered" for a request sheet: an unknown permission
      // string must never reach one.
      expect(
        kotlin,
        contains('private fun pastDataOffered(): Boolean = '
            'pastDataOfferedOrNull() == true'),
      );
      // The permission set is that one string, or nothing.
      final permissions = _between(
        kotlin,
        'private fun pastDataPermissions(): Set<String>',
        'private class GuardArgs',
      );
      expect(permissions, contains('if (pastDataOffered())'));
      expect(
        permissions,
        contains('setOf(HealthPermission.PERMISSION_READ_HEALTH_DATA_HISTORY)'),
      );
      expect(permissions, contains('emptySet()'));
      expect(permissions, isNot(contains('getWritePermission')));
    });

    test('Swift has neither call: HealthKit has no such limit', () {
      final swift = readRepoFile('ios/Runner/AppDelegate.swift');
      expect(swift, isNot(contains('requestPastDataAccess')));
      expect(swift, isNot(contains('pastDataSwitchOffered')));
    });
  });

  // Issue #1590: a write type an app update adds is never asked for on a
  // phone that already gave access — the write pass asks once, while no
  // forward-only floor is stamped. These guards keep Android's per-type
  // answer honest (a type is "asked" only once a launched request has
  // carried it, with the old install-wide marker migrated once) and keep
  // the ask for such a type carrying that type alone, because Health
  // Connect drops a whole request once any permission in it was declined
  // twice. On iOS the state is HealthKit's own `.notDetermined`, so no
  // marker exists there and the one sheet is reused.
  group('Android: a write type never asked about is asked for once '
      '(#1590)', () {
    late String kotlin;

    setUpAll(() {
      kotlin = _stripLineComments(readRepoFile(_adapterPath));
    });

    test('every written record type has a wire name, in the same order', () {
      // The parallel list is what a request and the per-type answer speak;
      // a type added to writtenRecordTypes without a wire here would be
      // silently unaskable.
      final records = _kotlinRecordTypes(kotlin);
      final wires = _kotlinWireNames(kotlin);
      expect(wires, hasLength(records.length),
          reason: 'one wire per written record type, in order');
      expect(wires, contains('menstrualFlow'));
      expect(wires, contains('spotting'));
      expect(wires, contains('cervicalMucus'));
      expect(wires, contains('ovulationTest'));
      expect(wires, contains('basalBodyTemperature'));
      // Two records share the menstruation permission and wire; the answer
      // dedupes them.
      expect(
        RegExp(r'fun neverAskedWriteTypes\(\s*granted: Set<String>,\s*'
                r'writes: List<Pair<String, String>>,\s*'
                r'asked: \(String\) -> Boolean,\s*\): List<String> = writes\s*'
                r'\.filter \{ \(permission, _\) -> permission !in granted && !asked\(permission\) \}\s*'
                r'\.map \{ it\.second \}\s*\.distinct\(\)')
            .hasMatch(kotlin),
        isTrue,
        reason: 'HealthPermissionState.neverAskedWriteTypes changed shape — '
            'update HealthPermissionStateTest.kt and this guard together',
      );
    });

    test('a type counts as asked only when a launched request carried it, '
        'with the install-wide marker migrated once', () {
      // The per-permission markers, stamped from the request's own
      // permission set once the launch returned (Issue #1883's rule, the
      // same one the install-wide marker follows).
      expect(
        kotlin,
        contains('const val PERMISSION_REQUESTED_TYPE_PREFIX ='),
      );
      expect(kotlin, contains('markWritePermissionsAsked(permissions)'));
      final launcher = _between(
        kotlin,
        'private fun launchPermissionRequest(',
        'private fun insert(',
      );
      final stamped = launcher.indexOf('markWritePermissionsAsked(permissions)');
      final launched = launcher.indexOf('launcher.launch(permissions)');
      expect(stamped, isNonNegative);
      expect(stamped, greaterThan(launched),
          reason: 'the per-type record is written once the launch returned');
      // Only write permissions: what a read sheet carried says nothing
      // about the writes (Issue #1515).
      expect(
        RegExp(r'private fun markWritePermissionsAsked\(permissions: Set<String>\) \{'
                r'\s*val editor = prefs\.edit\(\)\s*'
                r'for \(permission in permissions\) \{\s*'
                r'if \(permission in writePermissions\) \{\s*'
                r'editor\.putLong\(perWritePermissionKey\(permission\), installStamp\)')
            .hasMatch(kotlin),
        isTrue,
      );
      // The one-time migration for an install whose write sheet predates
      // this tracking: its sheet carried every type that build listed. Also
      // seeded from `permissionStatus`, which the write pass calls on every
      // pass, so an install that never opens the Health sync screen has its
      // list recorded before a later build adds a type. Issue #1881: gated
      // on a LAUNCHED write sheet (writeRequestLaunched), not the
      // install-wide marker — an observed settings grant sets that one with
      // no sheet shown, and seeding from it marked types the person was
      // never asked about as asked.
      expect(
        _between(kotlin, '"permissionStatus" ->', '"grantedWriteTypes" ->'),
        contains('seedAskedWritePermissions()'),
      );
      final seed = _between(
        kotlin,
        'private fun seedAskedWritePermissions()',
        'private fun markWritePermissionsAsked(',
      );
      expect(seed, contains('if (!writeRequestLaunched()) return'));
      expect(seed, contains('if (writePermissionMarkersExist()) return'));
      expect(seed, contains('markWritePermissionsAsked(writePermissions)'));
      // And the answer's "asked" is the marker, with that migration only
      // while no per-type marker exists at all — the lazy fallback follows
      // the same gate (Issue #1881).
      expect(
        RegExp(r'private fun writePermissionAsked\(permission: String\): Boolean =\s*'
                r'markerSetByThisInstall\(perWritePermissionKey\(permission\)\) \|\|\s*'
                r'\(writeRequestLaunched\(\) && !writePermissionMarkersExist\(\)\)')
            .hasMatch(kotlin),
        isTrue,
      );
      // Issue #1881: the launch marker is its own thing, read in one
      // helper and written by the launcher itself — after a launch that
      // returned (Issue #1883), beside the install-wide marker, and only
      // for the write sheet's own requests.
      expect(
        RegExp(r'private fun writeRequestLaunched\(\): Boolean =\s*'
                r'markerSetByThisInstall\(WRITE_REQUEST_LAUNCHED_KEY\)')
            .hasMatch(kotlin),
        isTrue,
      );
      expect(
        launcher,
        contains('if (askedMarker == PERMISSION_REQUESTED_KEY) {'),
      );
      final asked =
          launcher.indexOf('prefs.edit().putLong(askedMarker, installStamp)');
      final launchRecorded = launcher.indexOf(
        'prefs.edit().putLong(WRITE_REQUEST_LAUNCHED_KEY, installStamp)',
      );
      expect(launchRecorded, isNonNegative);
      expect(launchRecorded, greaterThan(asked),
          reason: 'the launch is recorded beside the sheet\'s own marker');
    });

    test('the never-asked query only looks, and seeds the migration', () {
      final handler = _between(
        kotlin,
        '"neverAskedWriteTypes" ->',
        '"openPermissionSettings" ->',
      );
      expect(handler, contains('seedAskedWritePermissions()'));
      expect(handler, contains('permissionController.getGrantedPermissions()'));
      expect(handler, contains('HealthPermissionState.neverAskedWriteTypes('));
      expect(handler, contains('writes = writePermissionWires'));
      expect(handler, contains('asked = ::writePermissionAsked'));
      expect(handler, contains('result.error("unavailable"'),
          reason: 'a failed query must not read as "nothing to ask"');
      for (final forbidden in [
        'launcher',
        'requestPermissions',
        'launchPermissionRequest',
        '.launch(',
        'markWritePermissionsAsked',
        'PERMISSION_REQUESTED_KEY',
      ]) {
        expect(handler, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test('the ask carries the never-asked types alone, and no read '
        'permission', () {
      final request = _between(
        kotlin,
        '"requestWriteAuthorizationForTypes" ->',
        '"requestImportAuthorization" ->',
      );
      final guarded = request.indexOf(
        'if (!requestGuardAllows(call.method, args, result)) return',
      );
      final parsed = request.indexOf('writePermissionsForWires(wires)');
      final launched = request.indexOf('launchPermissionRequest(');
      expect(guarded, isNonNegative);
      expect(parsed, greaterThan(guarded));
      expect(launched, greaterThan(parsed));
      expect(request, contains('askedMarker = PERMISSION_REQUESTED_KEY'));
      expect(request, contains('permissions = permissions'));
      for (final forbidden in [
        'allPermissions',
        'readPermissions',
        'importReadPermissions',
        'pastDataPermissions',
        'backgroundReadPermissions',
        'getReadPermission',
      ]) {
        expect(request, isNot(contains(forbidden)), reason: forbidden);
      }
      // The mapping touches only the write list.
      final map = _between(
        kotlin,
        'private fun writePermissionsForWires(',
        'private val importReadPermissions',
      );
      expect(map, contains('writePermissionWires'));
      expect(map, isNot(contains('getReadPermission')));
      // An empty list raises nothing.
      expect(request, contains('result.success("allowed")'));
    });

    test('iOS answers from HealthKit itself: no marker, the one sheet, and '
        'no types list sent to Swift', () {
      final swift = _stripLineComments(readRepoFile(_appDelegatePath));
      expect(swift, contains('case "neverAskedWriteTypes":'));
      expect(swift, contains('neverAskedWriteTypeWires'));
      expect(
        swift,
        contains(r'store.authorizationStatus(for: $0)'),
        reason: 'the answer is the per-type authorization status',
      );
      // No stored "asked" state on iOS: HealthKit tells not-determined from
      // denied itself, and the request is the one existing sheet.
      expect(swift, isNot(contains('neverAskedMarker')));
      expect(swift, isNot(contains('requestWriteAuthorizationForTypes')));
      final channel = _stripLineComments(
        readRepoFile('lib/data/health/health_channel.dart'),
      );
      expect(
        RegExp(
          r'readAccessDisclosed\s*\?\s*'
          r'HealthChannelMethods\.requestWriteAuthorizationForTypes\s*'
          r':\s*HealthChannelMethods\.requestWriteAuthorization',
        ).hasMatch(channel),
        isTrue,
        reason: 'where read access is disclosed (Android) the subset request '
            'is its own; on iOS it is the one sheet',
      );
      expect(
        RegExp(
          r"payloadArgs: readAccessDisclosed\s*"
          r"\? \(\) => \{'types': types\.toList\(\)\}\s*"
          r": null,",
        ).hasMatch(channel),
        isTrue,
        reason: 'the types argument crosses only where the store asks per '
            'permission (Android)',
      );
    });
  });

  // Issue #1515: the import asks through a request of its own. Someone who
  // let lunarlog read from Health Connect and not write to it used to be
  // shown the write permissions again on every tap of Import, because the
  // import asked through the one request that carried everything. These
  // guards keep the import's request on the reads, keep it from marking the
  // WRITES as asked (which would stop the write pass before its own
  // request), and keep the request off the Swift side, where the import
  // still asks through HealthKit's one sheet.
  group('Android: the import asks only for what it reads (#1515)', () {
    late String kotlin;
    late String importRequest;
    late String writeRequest;
    late String writeStatus;

    setUpAll(() {
      kotlin = _stripLineComments(readRepoFile(_adapterPath));
      writeRequest = _between(
        kotlin,
        '"requestWriteAuthorization" ->',
        // Issue #1590's request for a never-asked type sits between the
        // write path's and the import's.
        '"requestWriteAuthorizationForTypes" ->',
      );
      // Up to the next handler, which since Issue #1573 is the request
      // for past data.
      importRequest = _between(
        kotlin,
        '"requestImportAuthorization" ->',
        '"requestPastDataAccess" ->',
      );
      writeStatus = _between(
        kotlin,
        '"permissionStatus" ->',
        '"openPermissionSettings" ->',
      );
    });

    test('the import\'s request asks for the read set and no write '
        'permission', () {
      expect(importRequest, contains('launchPermissionRequest('));
      // Issue #1573: everything in the read set when this install has
      // raised neither sheet before, and the read set without "access past
      // data" after that, since both sheets carry it
      // (HealthPermissionState.importRequestPermissions, which the JVM
      // tests pin).
      expect(
        RegExp(r'permissions = HealthPermissionState\.importRequestPermissions\(\s*'
                r'reads = readPermissions,\s*'
                r'pastData = pastDataPermissions\(\),\s*'
                r'launchedBefore = permissionEverRequested\(\),\s*\)')
            .hasMatch(importRequest),
        isTrue,
      );
      expect(importRequest, isNot(contains('allPermissions')));
      expect(importRequest, isNot(contains('writePermissions')));
      // And the read set is what it says: "access past data", the two
      // record reads, the background read where it is offered — built
      // from no write permission. (The #1491 group pins the two record
      // reads themselves.)
      expect(
        RegExp(r'private\s+val\s+readPermissions\s*=\s*'
                r'pastDataPermissions\(\)'
                r'\s*\+\s*importReadPermissions\s*\+\s*backgroundReadPermissions\(\)'
                r'\s*\n')
            .hasMatch(kotlin),
        isTrue,
        reason: 'readPermissions changed shape — if a write permission can '
            'reach it, tapping Import asks for write access again',
      );
      final backgroundReads = _between(
        kotlin,
        'private fun backgroundReadPermissions(): Set<String>',
        'private class GuardArgs',
      );
      expect(backgroundReads, isNot(contains('getWritePermission')));
      expect(backgroundReads, isNot(contains('writePermissions')));
      // Issue #1573: "access past data" comes from a helper of its own,
      // which is inside the slice above.
      expect(
        backgroundReads,
        contains('private fun pastDataPermissions(): Set<String>'),
      );
    });

    test('the write path\'s request is unchanged: everything, on one sheet',
        () {
      expect(writeRequest, contains('launchPermissionRequest('));
      expect(writeRequest, contains('permissions = allPermissions'));
      expect(writeRequest, isNot(contains('permissions = readPermissions')));
    });

    test('each request sets its own asked-marker, and the import\'s is '
        'never the write one', () {
      expect(
        importRequest,
        contains('askedMarker = IMPORT_REQUEST_LAUNCHED_KEY'),
      );
      expect(importRequest, isNot(contains('PERMISSION_REQUESTED_KEY')));
      expect(writeRequest, contains('askedMarker = PERMISSION_REQUESTED_KEY'));
      expect(writeRequest, isNot(contains('IMPORT_REQUEST_LAUNCHED_KEY')));
      // Two different stored names, so one can never be read as the other.
      expect(
        kotlin,
        contains('const val PERMISSION_REQUESTED_KEY = '
            '"lunarlog.health.permissionRequested"'),
      );
      expect(
        kotlin,
        contains('const val IMPORT_REQUEST_LAUNCHED_KEY = '
            '"lunarlog.health.importRequestLaunched"'),
      );
    });

    test('both requests pass the one guard before the one launcher', () {
      // The #153 guard and the availability check come before the sheet,
      // for the import's request exactly as for the write path's.
      const guardCall =
          'if (!requestGuardAllows(call.method, args, result)) return';
      for (final request in [writeRequest, importRequest]) {
        final guarded = request.indexOf(guardCall);
        final launched = request.indexOf('launchPermissionRequest(');
        expect(guarded, isNonNegative);
        expect(launched, greaterThan(guarded));
      }
      final guard = _between(
        kotlin,
        'private fun requestGuardAllows(',
        'private fun launchPermissionRequest(',
      );
      final decided = guard.indexOf('guardDecision(storedBoundProfileId, g)');
      final available = guard.indexOf('if (!isAvailable())');
      expect(decided, isNonNegative);
      expect(available, greaterThan(decided));
      final launcher = _between(
        kotlin,
        'private fun launchPermissionRequest(',
        'private fun insert(',
      );
      expect(
        launcher,
        contains('prefs.edit().putLong(askedMarker, installStamp).apply()'),
      );
      expect(launcher, contains('launcher.launch(permissions)'));
      expect(
        'launchPermissionRequest('.allMatches(kotlin),
        hasLength(5),
        reason: 'the declaration, the two requests, the request for past '
            'data (Issue #1573), and the request for a never-asked type '
            '(Issue #1590): nothing else raises a Health Connect sheet',
      );
    });

    // With both record reads granted the import needs nothing, so a tap of
    // Import raises no sheet at all. Asking regardless put Health Connect's
    // "Allow lunarlog to access past data?" sheet in front of someone who
    // had declined that one optional extra, on every tap (seen on an
    // Android 15 emulator, 2026-10-05).
    test('the import asks only when it cannot read', () {
      final looked =
          importRequest.indexOf('permissionController.getGrantedPermissions()');
      final decided = importRequest.indexOf(
          'HealthPermissionState.importMustAsk(granted, importReadPermissions)');
      final answered = importRequest.indexOf('result.success("allowed")');
      final launched = importRequest.indexOf('launchPermissionRequest(');
      expect(looked, isNonNegative);
      expect(decided, greaterThan(looked));
      expect(answered, greaterThan(decided),
          reason: 'nothing to ask: the import goes straight on to its read');
      expect(launched, greaterThan(answered));
      expect(
        RegExp(r'fun importMustAsk\(granted: Set<String>, '
                r'importReads: Set<String>\): Boolean =\s*'
                r'!granted\.containsAll\(importReads\)')
            .hasMatch(kotlin),
        isTrue,
        reason: 'HealthPermissionState.importMustAsk changed shape — update '
            'HealthImportPermissionStateTest.kt and this guard together',
      );
      // The write path's request is not conditional on the reads.
      expect(writeRequest, isNot(contains('importMustAsk')));
    });

    test('the write status is decided on the writes alone: the import\'s '
        'marker and a granted read say nothing about them', () {
      // What "asked" means for the writes: the write request's marker.
      expect(writeStatus, contains('writesEverRequested = writesEverRequested()'));
      expect(writeStatus, isNot(contains('permissionEverRequested()')));
      expect(writeStatus, isNot(contains('IMPORT_REQUEST_LAUNCHED_KEY')));
      expect(writeStatus, isNot(contains('readPermissions')));
      // The decision itself is taken over the write permissions and that
      // marker, and nothing else.
      expect(
        RegExp(
          r'HealthPermissionState\.writeStatusFor\(\s*granted = granted,\s*'
          r'writes = statusPermissions,\s*'
          r'writesEverRequested = writesEverRequested\(\),\s*\)',
        ).hasMatch(writeStatus),
        isTrue,
      );
      // Everything the app requests, and whether the import's own sheet was
      // ever raised, appear once each: in the rule for what a grant already
      // on the device proves (the review of #1515), never in the decision.
      expect('allPermissions'.allMatches(writeStatus), hasLength(1));
      expect('importRequestLaunched()'.allMatches(writeStatus), hasLength(1));
      expect(
        RegExp(
          r'fun remembersWritesAsked\(\s*granted: Set<String>,\s*'
          r'writes: Set<String>,\s*requested: Set<String>,\s*'
          r'importRequestLaunched: Boolean,\s*\): Boolean =\s*'
          r'provesAsked\(granted, writes\) \|\|\s*'
          r'\(!importRequestLaunched && provesAsked\(granted, requested\)\)',
        ).hasMatch(kotlin),
        isTrue,
        reason: 'HealthPermissionState.remembersWritesAsked changed shape — '
            'update HealthPermissionStateTest.kt and this guard together',
      );
      expect(
        RegExp(
          r'fun writeStatusFor\(\s*granted: Set<String>,\s*'
          r'writes: Set<String>,\s*writesEverRequested: Boolean,\s*\)'
          r': String = when \{\s*'
          r'granted\.containsAll\(writes\)\s*->\s*GRANTED\s*'
          r'granted\.any\s*\{\s*it in writes\s*\}\s*->\s*WRITING_SOME\s*'
          r'writesEverRequested\s*->\s*DENIED\s*'
          r'else\s*->\s*NOT_ASKED\s*\}',
        ).hasMatch(kotlin),
        isTrue,
        reason: 'HealthPermissionState.writeStatusFor changed shape — '
            'update HealthPermissionStateTest.kt and this guard together',
      );
    });

    test('the read status counts either request as having asked for the '
        'reads', () {
      // Both requests carry the reads, so either marker is "asked" for the
      // read side — and only for the read side.
      expect(
        RegExp(r'private fun permissionEverRequested\(\): Boolean =\s*'
                r'writesEverRequested\(\)\s*\|\|\s*'
                r'importRequestLaunched\(\)')
            .hasMatch(kotlin),
        isTrue,
      );
      expect(
        'markerSetByThisInstall(IMPORT_REQUEST_LAUNCHED_KEY)'.allMatches(kotlin),
        hasLength(1),
        reason: 'the import\'s marker is read in one place',
      );
      // And that one reader has two callers: the read side's "asked", and
      // the rule for what a granted read proves about the writes.
      expect(
        RegExp(r'[^.\w]importRequestLaunched\(\)').allMatches(kotlin),
        hasLength(3),
        reason: 'its definition and two calls',
      );
    });
  });

  group('iOS: the import still asks through the one HealthKit sheet (#1515)',
      () {
    test('Swift has no requestImportAuthorization handler', () {
      final swift = _stripLineComments(readRepoFile(_appDelegatePath));
      expect(swift, isNot(contains('requestImportAuthorization')));
      // The sheet the import raises there is the write path's: write and
      // read types together, as before.
      expect(swift, contains('case "requestWriteAuthorization":'));
      expect(
        swift,
        contains(RegExp(r'store\.requestAuthorization\(\s*toShare: toShare, '
            r'read: toRead\)')),
      );
    });

    test('the Dart adapter picks the request by the platform fact', () {
      final channel = _stripLineComments(
        readRepoFile('lib/data/health/health_channel.dart'),
      );
      expect(
        RegExp(r'readAccessDisclosed\s*'
                r'\?\s*HealthChannelMethods\.requestImportAuthorization\s*'
                r':\s*HealthChannelMethods\.requestWriteAuthorization')
            .hasMatch(channel),
        isTrue,
        reason: 'where read access is not disclosed (iOS) the import must '
            'keep sending requestWriteAuthorization',
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
