/// Issue #1555: each native write and delete handler answers for its own
/// type.
///
/// Health Connect shows five write permissions as five switches, and Apple
/// Health seventeen. Before #1555 the app treated them as one: with any one
/// off, the permission status read "denied" and every write stopped. Now
/// some on and some off is "partial", the write pass goes on, and each
/// record is answered for by its own type's permission ("typeOff").
///
/// Neither native half compiles or runs under `flutter test`, so this
/// suite reads the Kotlin and Swift sources as text and pins:
///
/// * that every write handler goes through the one function that checks
///   the record's own type before writing, and that nothing else writes;
/// * that a delete leaves out a type that is off and answers for the types
///   its records can be in;
/// * the status rule on the Swift side (the Kotlin rule is unit tested in
///   `HealthPermissionStateTest.kt`);
/// * that the type names the Dart side sends with a delete are names each
///   native half knows.
///
/// The pure Dart half (which types a record id can be in) is tested here
/// too, against the same written-type collections the #924 guard uses.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_record_ids.dart';
import 'package:lunarlog/data/health/health_symptom_mapping.dart';
import 'package:lunarlog/data/health/health_written_types.dart';
import 'package:lunarlog/domain/models/local_date.dart';

import 'repo_text_helpers.dart';

const _appDelegatePath = 'ios/Runner/AppDelegate.swift';
const _adapterPath =
    'android/app/src/main/kotlin/com/wjdavis5/lunarlog/HealthConnectAdapter.kt';

/// A source file with line endings normalised (a Windows checkout has
/// CRLF) and `//` line comments stripped, so a commented-out line cannot
/// satisfy a match.
String _source(String path) => readRepoFile(path)
    .replaceAll('\r\n', '\n')
    .split('\n')
    .map((line) {
      final index = line.indexOf('//');
      return index >= 0 ? line.substring(0, index) : line;
    })
    .join('\n');

/// The slice of [source] from [start] up to the next [end].
String _between(String source, String start, String end) {
  final from = source.indexOf(start);
  expect(from, isNonNegative, reason: '$start was not found');
  final to = source.indexOf(end, from + start.length);
  expect(to, greaterThan(from), reason: '$end does not follow $start');
  return source.substring(from, to);
}

// A ULID, which is what a day entry's or an observation's id is.
const _entryId = '01ARZ3NDEKTSV4RRFFQ69G5FAV';
const _observationId = '01ARZ3NDEKTSV4RRFFQ69G5FBC';

void main() {
  group('which store types a record id can be in', () {
    test('a day\'s own record is a flow sample or a spotting marker: the id '
        'does not say which, so both count', () {
      for (final id in [
        healthFlowRecordId(_entryId),
        healthSpottingRecordId(_observationId),
      ]) {
        final types = healthStoreTypesForRecordId(id)!;
        expect(types.healthKit, {'menstrualFlow', 'intermenstrualBleeding'});
        expect(
          types.healthConnect,
          {'MenstruationFlowRecord', 'IntermenstrualBleedingRecord'},
        );
      }
    });

    test('a symptom names its own HealthKit type, and no Health Connect '
        'type: Health Connect has none', () {
      for (final type in kSymptomHealthKitTypeIdentifiers.values.toSet()) {
        final types =
            healthStoreTypesForRecordId(healthSymptomRecordId(_entryId, type))!;
        expect(types.healthKit, {type});
        expect(types.healthConnect, isEmpty);
      }
    });

    test('the fertility and measurement records each have one type on each '
        'platform', () {
      final mucus =
          healthStoreTypesForRecordId(healthCervicalMucusRecordId(_entryId))!;
      expect(mucus.healthKit, {'cervicalMucusQuality'});
      expect(mucus.healthConnect, {'CervicalMucusRecord'});

      final ovulation = healthStoreTypesForRecordId(
        healthOvulationRecordId(_entryId, 'luteinizingHormoneSurge'),
      )!;
      expect(ovulation.healthKit, {'ovulationTestResult'});
      expect(ovulation.healthConnect, {'OvulationTestRecord'});

      final bbt = healthStoreTypesForRecordId(healthBbtRecordId(_observationId))!;
      expect(bbt.healthKit, {'basalBodyTemperature'});
      expect(bbt.healthConnect, {'BasalBodyTemperatureRecord'});
    });

    test('the period record is Health Connect only', () {
      final period = healthStoreTypesForRecordId(
        healthPeriodRecordId('01ARZ3NDEKTSV4RRFFQ69G5FPR', LocalDate(2026, 9, 1)),
      )!;
      expect(period.healthKit, isEmpty);
      expect(period.healthConnect, {'MenstruationPeriodRecord'});
    });

    test('every name is one the written-type collections know, and between '
        'them the builders reach every written type', () {
      final all = healthStoreTypesForRecordIds([
        healthFlowRecordId(_entryId),
        healthSpottingRecordId(_observationId),
        for (final type in kSymptomHealthKitTypeIdentifiers.values)
          healthSymptomRecordId(_entryId, type),
        healthCervicalMucusRecordId(_entryId),
        healthOvulationRecordId(_entryId, 'negative'),
        healthBbtRecordId(_observationId),
        healthPeriodRecordId('01ARZ3NDEKTSV4RRFFQ69G5FPR', LocalDate(2026, 9, 1)),
      ])!;
      // A written type added without a builder, or a builder whose types
      // this function does not know, fails here.
      expect(all.healthKit, kHealthKitWrittenTypeCaseNames);
      expect(all.healthConnect, kHealthConnectWrittenRecordTypes);
    });

    test('an id that is not one of the builders\' is not guessed at', () {
      // A dash and no known prefix: not a ULID, so not a day's own record.
      expect(healthStoreTypesForRecordId('some-other-scheme'), isNull);
      // A symptom prefix with a type this app does not write.
      expect(
        healthStoreTypesForRecordId('symptom-$_entryId-hotFlashes'),
        isNull,
      );
      // One unrecognised id makes the whole call unrecognised: the native
      // half then has to cover every type.
      expect(
        healthStoreTypesForRecordIds([_entryId, 'some-other-scheme']),
        isNull,
      );
    });

    test('several ids need the types of all of them', () {
      final types = healthStoreTypesForRecordIds([
        healthSymptomRecordId(_entryId, 'acne'),
        healthBbtRecordId(_observationId),
      ])!;
      expect(types.healthKit, {'acne', 'basalBodyTemperature'});
      expect(types.healthConnect, {'BasalBodyTemperatureRecord'});
      // No ids at all need nothing.
      final none = healthStoreTypesForRecordIds(const [])!;
      expect(none.healthKit, isEmpty);
      expect(none.healthConnect, isEmpty);
    });
  });

  group('Android: each write answers for its own type', () {
    late String kotlin;
    late String insert;

    setUpAll(() {
      kotlin = _source(_adapterPath);
      insert = _between(
        kotlin,
        'private fun insert(',
        'private suspend fun readSamples(',
      );
    });

    test('every write handler ends in the one insert function', () {
      const handlers = {
        '"writeMenstrualFlow" ->': '"writeIntermenstrualBleeding" ->',
        '"writeIntermenstrualBleeding" ->': '"writeMenstrualPeriod" ->',
        // The period record needs the permission the flow record needs:
        // getWritePermission answers the same string for both classes.
        '"writeMenstrualPeriod" ->': '"writeSymptomSamples" ->',
        '"writeCervicalMucus" ->': '"writeOvulationTest" ->',
        '"writeOvulationTest" ->': '"writeBasalBodyTemperature" ->',
        '"writeBasalBodyTemperature" ->': '"deleteRecords" ->',
      };
      for (final handler in handlers.entries) {
        final body = _between(kotlin, handler.key, handler.value);
        expect(
          body,
          contains('insert(client, listOf(record), result)'),
          reason: handler.key,
        );
        expect(body, isNot(contains('insertRecords(')), reason: handler.key);
      }
      // Health Connect has no symptom types, so that handler writes nothing.
      final symptoms =
          _between(kotlin, '"writeSymptomSamples" ->', '"writeCervicalMucus" ->');
      expect(symptoms, isNot(contains('insert(')));
      expect(symptoms, contains('result.success("unavailable")'));
    });

    test('nothing writes except that function, and it looks at the record\'s '
        'own permission first', () {
      expect('insertRecords('.allMatches(kotlin), hasLength(1));
      final needed = insert.indexOf(
        '.map { HealthPermission.getWritePermission(it::class) }',
      );
      final granted =
          insert.indexOf('client.permissionController.getGrantedPermissions()');
      final decided =
          insert.indexOf('if (HealthPermissionState.typeOff(granted, needed)) {');
      final answered =
          insert.indexOf('result.success(HealthPermissionState.TYPE_OFF)');
      final written = insert.indexOf('client.insertRecords(records)');
      expect(needed, isNonNegative,
          reason: 'the permission is the record\'s own type\'s');
      expect(granted, greaterThan(needed));
      expect(decided, greaterThan(granted));
      expect(answered, greaterThan(decided));
      expect(written, greaterThan(answered),
          reason: 'a type that is off is answered before any write');
      expect(
        insert.substring(answered, written),
        contains('return@launch'),
        reason: 'and nothing is attempted for it',
      );
    });

    test('the answer and the rule are the ones the Kotlin unit test pins', () {
      expect(kotlin, contains('const val TYPE_OFF = "typeOff"'));
      expect(kotlin, contains('const val PARTIAL = "partial"'));
      expect(
        RegExp(r'fun typeOff\(granted: Set<String>, needed: Set<String>\)'
                r': Boolean =\s*!granted\.containsAll\(needed\)')
            .hasMatch(kotlin),
        isTrue,
        reason: 'HealthPermissionState.typeOff changed shape — update '
            'HealthPermissionStateTest.kt and this guard together',
      );
    });
  });

  group('Android: a delete answers for the types its records can be in', () {
    late String kotlin;
    late String delete;

    setUpAll(() {
      kotlin = _source(_adapterPath);
      delete = _between(kotlin, '"deleteRecords" ->', '"readMenstrualFlowPage" ->');
    });

    test('a type that is off is left out of the loop, and the others are '
        'still deleted from', () {
      final looked =
          delete.indexOf('client.permissionController.getGrantedPermissions()');
      final loop = delete.indexOf('for (recordType in writtenRecordTypes)');
      final permission = delete.indexOf(
        'val permission = HealthPermission.getWritePermission(recordType)',
      );
      final skipped = delete.indexOf(
        'if (HealthPermissionState.typeOff(granted, setOf(permission))) {',
      );
      final deleted = delete.indexOf('client.deleteRecords(');
      expect(looked, isNonNegative);
      expect(loop, greaterThan(looked));
      expect(permission, greaterThan(loop));
      expect(skipped, greaterThan(permission));
      expect(deleted, greaterThan(skipped));
      expect(
        delete.substring(skipped, deleted),
        contains('continue'),
        reason: 'the type is skipped, not a reason to stop',
      );
      expect('client.deleteRecords('.allMatches(kotlin), hasLength(1));
    });

    test('the answer is "typeOff" when a type the call has to cover was off',
        () {
      expect(
        delete,
        contains(
          'permissionsToCover(args?.get("healthConnectTypes") as? List<*>)',
        ),
      );
      expect(
        RegExp(
          r'result\.success\(\s*'
          r'if \(HealthPermissionState\.typeOff\(granted, toCover\)\) \{\s*'
          r'HealthPermissionState\.TYPE_OFF\s*\} else \{\s*"allowed"\s*\}\)',
        ).hasMatch(delete),
        isTrue,
      );
    });

    test('a call that names no types, or one this build does not know, has '
        'to cover every written type', () {
      final cover = _between(
        kotlin,
        'private fun permissionsToCover(',
        'private val importReadPermissions',
      );
      expect(
        cover,
        contains('val named = names?.map { recordTypesByName[it as? String] }'),
      );
      expect(
        cover,
        contains(
          'if (named == null || named.any { it == null }) '
          'return writePermissions',
        ),
      );
    });

    test('the names it knows are exactly the written record types, each '
        'under its own name', () {
      final map = _between(
        kotlin,
        'private val recordTypesByName',
        'private fun permissionsToCover(',
      );
      final entries = RegExp(r'"(\w+)" to (\w+)::class').allMatches(map).toList();
      expect(
        {for (final entry in entries) entry.group(1)},
        kHealthConnectWrittenRecordTypes,
        reason: 'a written type the Dart side can name and Kotlin cannot '
            'makes every delete that names it cover all types',
      );
      for (final entry in entries) {
        expect(entry.group(1), entry.group(2),
            reason: 'spelled out, since a release build renames the classes');
      }
    });
  });

  group('iPhone: each write answers for its own type', () {
    late String swift;
    late String save;

    setUpAll(() {
      swift = _source(_appDelegatePath);
      save = swift.substring(
        swift.indexOf('private static func save(_ samples: [HKSample]'),
      );
    });

    test('every write handler ends in the one save function', () {
      const handlers = {
        'case "writeMenstrualFlow":': 'case "writeIntermenstrualBleeding":',
        'case "writeIntermenstrualBleeding":': 'case "writeSymptomSamples":',
        'case "writeSymptomSamples":': 'case "writeCervicalMucus":',
        'case "writeCervicalMucus":': 'case "writeOvulationTest":',
        'case "writeOvulationTest":': 'case "writeBasalBodyTemperature":',
        'case "writeBasalBodyTemperature":': 'case "deleteRecords":',
      };
      for (final handler in handlers.entries) {
        final body = _between(swift, handler.key, handler.value);
        expect(
          RegExp(r'\n\s+save\(\[?\w+\]?, result: result\)\n').hasMatch(body),
          isTrue,
          reason: handler.key,
        );
        expect(body, isNot(contains('store.save(')), reason: handler.key);
      }
      // HealthKit has no period record, so there is no such handler.
      expect(swift, isNot(contains('case "writeMenstrualPeriod":')));
    });

    test('nothing saves except that function, and it keeps only the samples '
        'whose own type is authorized', () {
      expect('store.save('.allMatches(swift), hasLength(1));
      final kept = save.indexOf(
        'let allowed = samples.filter { mayWrite(\$0.sampleType) }',
      );
      final none = save.indexOf('guard !allowed.isEmpty else {');
      final answered = save.indexOf('result("typeOff")');
      final saved = save.indexOf('try await store.save(allowed)');
      expect(kept, isNonNegative);
      // The symptom write carries up to twelve types in one call: the ones
      // that are on are saved, and "typeOff" is the answer only when every
      // sample was dropped.
      expect(none, greaterThan(kept));
      expect(answered, greaterThan(none));
      expect(saved, greaterThan(answered));
      expect(save.substring(answered, saved), contains('return'));
      expect(save, isNot(contains('store.save(samples)')),
          reason: 'saving the unfiltered list fails the whole batch on one '
              'type that is off');
    });

    test('"may write" is the type\'s own share authorization, and never a '
        'guess at read access', () {
      expect(
        RegExp(
          r'private static func mayWrite\(_ type: HKSampleType\) -> Bool \{\s*'
          r'store\.authorizationStatus\(for: type\) == \.sharingAuthorized\s*\}',
        ).hasMatch(swift),
        isTrue,
      );
    });
  });

  group('iPhone: a delete answers for the types its records can be in', () {
    late String swift;
    late String delete;

    setUpAll(() {
      swift = _source(_appDelegatePath);
      delete = _between(
        swift,
        'case "deleteRecords":',
        'case "readMenstrualFlowPage":',
      );
    });

    test('a type that is off is left out of the query, and the others are '
        'still deleted from', () {
      final loop = delete.indexOf('for sampleType in writtenSampleTypes {');
      final skipped =
          delete.indexOf('guard mayWrite(sampleType) else { continue }');
      final queried = delete.indexOf('try await querySamples(');
      final deleted = delete.indexOf('try await delete(toDelete)');
      expect(loop, isNonNegative);
      expect(skipped, greaterThan(loop));
      expect(queried, greaterThan(skipped));
      expect(deleted, greaterThan(queried));
    });

    test('the answer is "typeOff" when a type the call has to cover was off, '
        'where it used to be "allowed"', () {
      expect(
        delete,
        contains(
          'let toCover = typesToCover(args?["healthKitTypes"] as? [String])',
        ),
      );
      expect(
        delete,
        contains(
          'result(toCover.allSatisfy(mayWrite) ? "allowed" : "typeOff")',
        ),
      );
      expect(delete, isNot(contains('result("allowed")')));
    });

    test('a call that names no types, or one this build does not know, has '
        'to cover every written type', () {
      final cover = _between(
        swift,
        'private static func typesToCover(',
        'static func caseName(of type: HKSampleType)',
      );
      expect(cover, contains('guard let names else { return writtenSampleTypes }'));
      expect(
        RegExp(
          r'let type = writtenSampleTypes\.first\(where: '
          r'\{ caseName\(of: \$0\) == name \}\)\s*'
          r'else \{ return writtenSampleTypes \}',
        ).hasMatch(cover),
        isTrue,
      );
    });

    test('the names it knows are the case names the Dart side sends', () {
      // The Dart side names a type by its Swift case name
      // (kHealthKitWrittenTypeCaseNames); Swift reads the same name back
      // out of the type's own identifier.
      final caseName = swift.substring(
        swift.indexOf('static func caseName(of type: HKSampleType)'),
      );
      expect(
        caseName,
        contains(
          'for prefix in ["HKCategoryTypeIdentifier", '
          '"HKQuantityTypeIdentifier"]',
        ),
      );
      expect(
        caseName,
        contains('return name.prefix(1).lowercased() + name.dropFirst()'),
      );
    });
  });

  group('iPhone: some types authorized and some denied is partial', () {
    late String swift;

    setUpAll(() => swift = _source(_appDelegatePath));

    test('the status counts what is authorized and what is denied over the '
        'written types, and decides through writeStatus', () {
      final handler = _between(
        swift,
        'case "permissionStatus":',
        'case "openPermissionSettings":',
      );
      expect(handler, contains('for type in writtenSampleTypes {'));
      expect(handler, contains('switch store.authorizationStatus(for: type) {'));
      expect(
        RegExp(r'case \.sharingDenied:\s*denied \+= 1').hasMatch(handler),
        isTrue,
      );
      expect(
        RegExp(r'case \.sharingAuthorized:\s*authorized \+= 1')
            .hasMatch(handler),
        isTrue,
      );
      expect(
        RegExp(
          r'writeStatus\(\s*authorized: authorized, denied: denied, '
          r'total: writtenSampleTypes\.count\)',
        ).hasMatch(handler),
        isTrue,
      );
      // One denied type no longer answers "denied" by itself.
      expect(handler, isNot(contains('result("denied")')));
    });

    test('the rule: all authorized is granted; none denied is not yet asked; '
        'some authorized and some denied is partial; none authorized is '
        'denied', () {
      expect(
        RegExp(
          r'static func writeStatus\(authorized: Int, denied: Int, '
          r'total: Int\) -> String \{\s*'
          r'if authorized == total \{ return "granted" \}\s*'
          r'if denied == 0 \{ return "notAsked" \}\s*'
          r'return authorized > 0 \? "partial" : "denied"\s*\}',
        ).hasMatch(swift),
        isTrue,
        reason: 'writeStatus changed shape — the Dart write pass treats '
            '"partial" as allowed and stops on "denied"',
      );
    });
  });
}
