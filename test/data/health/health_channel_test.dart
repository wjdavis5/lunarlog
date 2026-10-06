/// Unit tests for [MethodChannelHealthPlatform] (Issue #173) — the
/// guard-ordering proof for the `lunarlog/health` channel's Dart half,
/// driven through `TestDefaultBinaryMessengerBinding`'s mock channel
/// handler (the same technique `notification_scheduler_test.dart` uses).
///
/// The property under test is the one `health_channel.dart`'s library doc
/// declares: **every guarded method evaluates `HealthSyncBinding.canWrite`
/// first and returns `refused(check)` without a single channel invocation
/// on a deny** — asserted here as a zero-invocations expectation for each
/// deny reason, so a future edit that reorders guard-after-invoke fails
/// these tests rather than silently weakening the #153 safety property.
/// The native-side mirror of the same predicate (Swift/Kotlin) is
/// documented in those files and proven on devices, not under `flutter
/// test`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_channel.dart';
import 'package:lunarlog/data/health/ios_health_channel.dart';
import 'package:lunarlog/data/health/android_health_channel.dart';
import 'package:lunarlog/domain/health/health_deviation.dart';
import 'package:lunarlog/domain/health/health_import.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';

import '../../support/fake_settings_store.dart';

const _channel = MethodChannel('lunarlog/health');

Profile _profile({
  String id = 'p1',
  bool isMinor = false,
  int? birthYear = 1990,
  DateTime? transferredAt,
}) =>
    Profile(
      id: id,
      displayName: 'Test',
      isMinor: isMinor,
      birthYear: birthYear,
      transferredAt: transferredAt,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

HealthGuardFacts _facts({
  Profile? profile,
  String? signedInUserId = 'u1',
  String? ownerUserId = 'u1',
}) =>
    HealthGuardFacts(
      profile: profile ?? _profile(),
      signedInUserId: signedInUserId,
      ownerUserId: ownerUserId,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The recorded invocations the guard-ordering assertions count.
  final calls = <MethodCall>[];
  // What the fake native side answers for the next invocation (default:
  // a successful write).
  Object? nextResult;
  Object? nextError;

  setUp(() {
    calls.clear();
    nextResult = 'allowed';
    nextError = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (nextError != null) throw nextError!;
      return nextResult;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  MethodChannelHealthPlatform makePlatform({
    Map<String, String> seed = const {
      SettingsKeys.healthStoreProfileId: 'p1',
    },
    bool minorBindingAllowed = true,
  }) =>
      MethodChannelHealthPlatform(
        binding: HealthSyncBinding(FakeSettingsStore(seed)),
        minorBindingAllowed: minorBindingAllowed,
        readAccessDisclosed: true,
      );

  const flowWriteRecordId = '01ARZ3NDEKTSV4RRFFQ69G5FAV';
  const flowWriteRecordVersionMs = 1234567890000;

  final flowWrite = HealthMenstrualFlowWrite(
    facts: _facts(),
    date: LocalDate(2026, 8, 30),
    tzName: 'America/New_York',
    flow: HealthFlowValue.heavy,
    cycleStart: true,
    recordId: flowWriteRecordId,
    recordVersionMs: flowWriteRecordVersionMs,
  );

  group('guard ordering: a denied write never reaches the channel', () {
    void expectRefusedWithoutInvocation(
      HealthPlatformResult result,
      HealthSyncCheck reason,
    ) {
      expect(result, isA<HealthPlatformRefused>());
      expect((result as HealthPlatformRefused).check, reason);
      expect(calls, isEmpty,
          reason: 'a denied write must not invoke the channel at all');
    }

    test('no profile bound (noBinding)', () async {
      final result = await makePlatform(seed: {}).writeMenstrualFlow(flowWrite);
      expectRefusedWithoutInvocation(result, HealthSyncCheck.noBinding);
    });

    test('a different profile bound (profileNotBound)', () async {
      final result = await makePlatform().writeMenstrualFlow(
        HealthMenstrualFlowWrite(
          facts: _facts(profile: _profile(id: 'p2')),
          date: LocalDate(2026, 8, 30),
          tzName: 'America/New_York',
          flow: HealthFlowValue.light,
          cycleStart: false,
          recordId: flowWriteRecordId,
          recordVersionMs: flowWriteRecordVersionMs,
        ),
      );
      expectRefusedWithoutInvocation(result, HealthSyncCheck.profileNotBound);
    });

    test('guardian-only session on the bound profile (notOwner)', () async {
      final result = await makePlatform().writeMenstrualFlow(
        HealthMenstrualFlowWrite(
          facts: _facts(ownerUserId: 'someone-else'),
          date: LocalDate(2026, 8, 30),
          tzName: 'America/New_York',
          flow: HealthFlowValue.medium,
          cycleStart: false,
          recordId: flowWriteRecordId,
          recordVersionMs: flowWriteRecordVersionMs,
        ),
      );
      expectRefusedWithoutInvocation(result, HealthSyncCheck.notOwner);
    });

    test('minor profile with the minor switch off '
        '(minorRequiresOwnershipTransfer)', () async {
      final result = await makePlatform(minorBindingAllowed: false)
          .writeMenstrualFlow(
        HealthMenstrualFlowWrite(
          facts: _facts(profile: _profile(isMinor: true, birthYear: null)),
          date: LocalDate(2026, 8, 30),
          tzName: 'America/New_York',
          flow: HealthFlowValue.light,
          cycleStart: false,
          recordId: flowWriteRecordId,
          recordVersionMs: flowWriteRecordVersionMs,
        ),
      );
      expectRefusedWithoutInvocation(
        result,
        HealthSyncCheck.minorRequiresOwnershipTransfer,
      );
    });

    // Issue #882: with the switch on (production) a minor owned by the
    // signed-in account is allowed, so the write path reaches the channel.
    test('minor profile owned by the signed-in account is allowed and the '
        'write reaches the channel (Issue #882)', () async {
      final result = await makePlatform().writeMenstrualFlow(
        HealthMenstrualFlowWrite(
          facts: _facts(profile: _profile(isMinor: true, birthYear: null)),
          date: LocalDate(2026, 8, 30),
          tzName: 'America/New_York',
          flow: HealthFlowValue.light,
          cycleStart: false,
          recordId: flowWriteRecordId,
          recordVersionMs: flowWriteRecordVersionMs,
        ),
      );
      expect(result, isA<HealthPlatformAllowed>());
      expect(calls, hasLength(1));
    });

    test('bindProfile, requestWriteAuthorization, '
        'requestImportAuthorization, '
        'writeIntermenstrualBleeding, and writeMenstrualPeriod all refuse '
        'identically (notOwner)', () async {
      final platform = makePlatform();
      final notOwnerFacts = _facts(ownerUserId: 'someone-else');
      expectRefusedWithoutInvocation(
        await platform.bindProfile(notOwnerFacts),
        HealthSyncCheck.notOwner,
      );
      expectRefusedWithoutInvocation(
        await platform.requestWriteAuthorization(notOwnerFacts),
        HealthSyncCheck.notOwner,
      );
      // Issue #1515: the import's own request is a health-API touch like
      // the write path's, behind the same guard.
      expectRefusedWithoutInvocation(
        await platform.requestImportAuthorization(notOwnerFacts),
        HealthSyncCheck.notOwner,
      );
      expectRefusedWithoutInvocation(
        await platform.writeIntermenstrualBleeding(
          HealthIntermenstrualBleedingWrite(
            facts: notOwnerFacts,
            date: LocalDate(2026, 8, 30),
            tzName: 'America/New_York',
            recordId: flowWriteRecordId,
            recordVersionMs: flowWriteRecordVersionMs,
          ),
        ),
        HealthSyncCheck.notOwner,
      );
      // #202: the period-record write is behind the same guard and is
      // refused with zero channel invocations on a deny, like every write.
      expectRefusedWithoutInvocation(
        await platform.writeMenstrualPeriod(
          HealthMenstrualPeriodWrite(
            facts: notOwnerFacts,
            start: LocalDate(2026, 8, 30),
            end: LocalDate(2026, 9, 1),
            tzName: 'America/New_York',
            recordId: flowWriteRecordId,
            recordVersionMs: flowWriteRecordVersionMs,
          ),
        ),
        HealthSyncCheck.notOwner,
      );
    });

    // Issue #924: a deletion is a health-API touch and goes through the
    // same guard as every write — a denied binding must block it with zero
    // channel invocations, exactly like a denied write.
    test('deleteRecords refuses on a denied binding without invoking the '
        'channel', () async {
      final result =
          await makePlatform(seed: {}).deleteRecords(_facts(), const [flowWriteRecordId]);
      expectRefusedWithoutInvocation(result, HealthSyncCheck.noBinding);
    });
  });

  group('an allowed write crosses the channel with the full envelope', () {
    test('writeMenstrualFlow sends guard args + day args + payload', () async {
      await makePlatform(minorBindingAllowed: false).writeMenstrualFlow(flowWrite);

      expect(calls, hasLength(1));
      final call = calls.single;
      expect(call.method, 'writeMenstrualFlow');
      final args = call.arguments as Map<Object?, Object?>;
      // Guard args — the native mirror's inputs.
      expect(args['profileId'], 'p1');
      expect(args['signedInUserId'], 'u1');
      expect(args['ownerUserId'], 'u1');
      expect(args['isMinor'], false);
      expect(args['birthYear'], 1990);
      expect(args['transferredAtMs'], isNull);
      expect(args['minorBindingAllowed'], false);
      // Day args — 2026-08-30 America/New_York (EDT, UTC-4).
      expect(args['startMs'], DateTime.utc(2026, 8, 30, 4).millisecondsSinceEpoch);
      expect(args['instantMs'], DateTime.utc(2026, 8, 30, 4).millisecondsSinceEpoch);
      expect(args['endMs'],
          DateTime.utc(2026, 8, 31, 4).millisecondsSinceEpoch - 1000);
      expect(args['endExclusiveMs'],
          DateTime.utc(2026, 8, 31, 4).millisecondsSinceEpoch);
      expect(args['zoneOffsetMs'], -4 * 3600 * 1000);
      expect(args['endZoneOffsetMs'], -4 * 3600 * 1000);
      // Payload.
      expect(args['flow'], 'heavy');
      expect(args['cycleStart'], true);
      // Issue #186 sync mechanics: the source record id and version ride
      // the write for clientRecordId / HKMetadataKeyExternalUUID stamping.
      expect(args['recordId'], flowWriteRecordId);
      expect(args['recordVersionMs'], flowWriteRecordVersionMs);
    });

    test('deleteRecords sends guard args + recordIds', () async {
      await makePlatform().deleteRecords(
        _facts(),
        const [flowWriteRecordId, '01ARZ3NDEKTSV4RRFFQ69G5FBC'],
      );

      expect(calls, hasLength(1));
      final call = calls.single;
      expect(call.method, 'deleteRecords');
      final args = call.arguments as Map<Object?, Object?>;
      expect(args['profileId'], 'p1');
      expect(args['recordIds'],
          [flowWriteRecordId, '01ARZ3NDEKTSV4RRFFQ69G5FBC']);
    });

    test('writeIntermenstrualBleeding sends guard + day args, no flow key',
        () async {
      await makePlatform().writeIntermenstrualBleeding(
        HealthIntermenstrualBleedingWrite(
          facts: _facts(),
          date: LocalDate(2026, 8, 30),
          tzName: 'America/New_York',
          recordId: flowWriteRecordId,
          recordVersionMs: flowWriteRecordVersionMs,
        ),
      );
      expect(calls, hasLength(1));
      expect(calls.single.method, 'writeIntermenstrualBleeding');
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['profileId'], 'p1');
      expect(args['instantMs'], isNotNull);
      expect(args.containsKey('flow'), isFalse);
      expect(args.containsKey('cycleStart'), isFalse);
      // Issue #186: the record id/version ride this write too.
      expect(args['recordId'], flowWriteRecordId);
      expect(args['recordVersionMs'], flowWriteRecordVersionMs);
    });

    test('bindProfile and requestWriteAuthorization send guard args',
        () async {
      final platform = makePlatform();
      await platform.bindProfile(_facts());
      await platform.requestWriteAuthorization(_facts());
      expect(calls.map((c) => c.method), ['bind', 'requestWriteAuthorization']);
      for (final call in calls) {
        expect((call.arguments as Map<Object?, Object?>)['profileId'], 'p1');
      }
    });

    test('writeMenstrualPeriod sends guard args + the interval envelope '
        '(start/end instants and offsets from the entry tz, #202)', () async {
      // 2026-08-30..2026-09-01 America/New_York (EDT, UTC-4): start = 08-30
      // 04:00Z; end = the last instant of 09-01, 09-02 03:59:59Z (issue
      // #1478: on the last day, not the midnight after it); both offsets
      // -4h.
      await makePlatform(minorBindingAllowed: false).writeMenstrualPeriod(
        HealthMenstrualPeriodWrite(
          facts: _facts(),
          start: LocalDate(2026, 8, 30),
          end: LocalDate(2026, 9, 1),
          tzName: 'America/New_York',
          recordId: flowWriteRecordId,
          recordVersionMs: flowWriteRecordVersionMs,
        ),
      );

      expect(calls, hasLength(1));
      final call = calls.single;
      expect(call.method, 'writeMenstrualPeriod');
      final args = call.arguments as Map<Object?, Object?>;
      expect(args['profileId'], 'p1');
      expect(args['startMs'], DateTime.utc(2026, 8, 30, 4).millisecondsSinceEpoch);
      expect(args['startZoneOffsetMs'], -4 * 3600 * 1000);
      expect(
        args['endMs'],
        DateTime.utc(2026, 9, 2, 3, 59, 59).millisecondsSinceEpoch,
      );
      expect(args['endZoneOffsetMs'], -4 * 3600 * 1000);
      // #186 sync mechanics ride this write too.
      expect(args['recordId'], flowWriteRecordId);
      expect(args['recordVersionMs'], flowWriteRecordVersionMs);
    });
  });

  group('native answers decode to typed results', () {
    test('a native deny string becomes refused(check) — the mirror talking',
        () async {
      nextResult = 'notOwner';
      final result = await makePlatform().writeMenstrualFlow(flowWrite);
      expect(result, isA<HealthPlatformRefused>());
      expect((result as HealthPlatformRefused).check, HealthSyncCheck.notOwner);
      expect(calls, hasLength(1),
          reason: 'the Dart guard allowed; the native mirror refused');
    });

    test('unavailable and permissionDenied pass through', () async {
      nextResult = 'unavailable';
      expect(
        await makePlatform().writeMenstrualFlow(flowWrite),
        isA<HealthPlatformUnavailable>(),
      );
      nextResult = 'permissionDenied';
      expect(
        await makePlatform().writeMenstrualFlow(flowWrite),
        isA<HealthPlatformPermissionDenied>(),
      );
    });

    test('an unknown native string becomes a failed result', () async {
      nextResult = 'someNewNativeOutcome';
      final result = await makePlatform().writeMenstrualFlow(flowWrite);
      expect(result, isA<HealthPlatformFailed>());
      expect((result as HealthPlatformFailed).message, contains('unknown'));
    });

    test('a writeFailed PlatformException carries its diagnostic', () async {
      nextError = PlatformException(
        code: 'writeFailed',
        message: 'save failed: no authorization',
      );
      final result = await makePlatform().writeMenstrualFlow(flowWrite);
      expect(result, isA<HealthPlatformFailed>());
      final failed = result as HealthPlatformFailed;
      expect(failed.message, contains('writeFailed'));
      expect(failed.message, contains('no authorization'));
    });

    test('a missing native handler is unavailable, never a crash', () async {
      nextError = MissingPluginException();
      expect(
        await makePlatform().writeMenstrualFlow(flowWrite),
        isA<HealthPlatformUnavailable>(),
      );
    });
  });

  group('unguarded and best-effort methods', () {
    test('isAvailable passes the bool through, null/false default to false',
        () async {
      nextResult = true;
      expect(await makePlatform().isAvailable(), isTrue);
      nextResult = false;
      expect(await makePlatform().isAvailable(), isFalse);
      nextResult = null;
      expect(await makePlatform().isAvailable(), isFalse);
      expect(calls.map((c) => c.method), everyElement('isAvailable'));
    });

    test('isAvailable swallows a missing handler', () async {
      nextError = MissingPluginException();
      expect(await makePlatform().isAvailable(), isFalse);
    });

    test('unbindProfile is best effort: a PlatformException never escapes',
        () async {
      nextError = PlatformException(code: 'anything');
      await makePlatform().unbindProfile();
      expect(calls.map((c) => c.method), ['unbind']);
    });
  });

  group('a write whose day envelope cannot be computed', () {
    test('an unresolvable time zone fails AFTER the guard, without a call',
        () async {
      final result = await makePlatform().writeMenstrualFlow(
        HealthMenstrualFlowWrite(
          facts: _facts(),
          date: LocalDate(2026, 8, 30),
          tzName: 'Not/AZone',
          flow: HealthFlowValue.light,
          cycleStart: false,
          recordId: flowWriteRecordId,
          recordVersionMs: flowWriteRecordVersionMs,
        ),
      );
      expect(result, isA<HealthPlatformFailed>());
      expect((result as HealthPlatformFailed).message, contains('time zone'));
      expect(calls, isEmpty,
          reason: 'a bad zone must not cross the channel either');
    });

    test('a guard denial wins even when the zone is also bad', () async {
      final result = await makePlatform(seed: {}).writeMenstrualFlow(
        HealthMenstrualFlowWrite(
          facts: _facts(),
          date: LocalDate(2026, 8, 30),
          tzName: 'Not/AZone',
          flow: HealthFlowValue.light,
          cycleStart: false,
          recordId: flowWriteRecordId,
          recordVersionMs: flowWriteRecordVersionMs,
        ),
      );
      expect(result, isA<HealthPlatformRefused>());
      expect(
        (result as HealthPlatformRefused).check,
        HealthSyncCheck.noBinding,
      );
    });
  });

  group('UnsupportedHealthPlatform and createHealthPlatform', () {
    test('the unsupported platform fails cleanly, never crashes', () async {
      const platform = UnsupportedHealthPlatform();
      expect(await platform.isAvailable(), isFalse);
      // Issue #1549: no store, so no read reaches anything.
      expect(await platform.importReachesPastData(), isFalse);
      expect(
        await platform.writeMenstrualFlow(flowWrite),
        isA<HealthPlatformUnavailable>(),
      );
      expect(
        await platform.writeIntermenstrualBleeding(
          HealthIntermenstrualBleedingWrite(
            facts: _facts(),
            date: LocalDate(2026, 8, 30),
            tzName: 'America/New_York',
            recordId: flowWriteRecordId,
            recordVersionMs: flowWriteRecordVersionMs,
          ),
        ),
        isA<HealthPlatformUnavailable>(),
      );
      expect(
        await platform.writeMenstrualPeriod(
          HealthMenstrualPeriodWrite(
            facts: _facts(),
            start: LocalDate(2026, 8, 30),
            end: LocalDate(2026, 9, 1),
            tzName: 'America/New_York',
            recordId: flowWriteRecordId,
            recordVersionMs: flowWriteRecordVersionMs,
          ),
        ),
        isA<HealthPlatformUnavailable>(),
      );
      expect(
        await platform.bindProfile(_facts()),
        isA<HealthPlatformUnavailable>(),
      );
      expect(
        await platform.requestWriteAuthorization(_facts()),
        isA<HealthPlatformUnavailable>(),
      );
      expect(
        await platform.requestImportAuthorization(_facts()),
        isA<HealthPlatformUnavailable>(),
      );
      expect(calls, isEmpty, reason: 'no channel exists to call');
      await platform.unbindProfile(); // completes without throwing
    });

    test('the factory pins each platform\'s adapter', () {
      HealthPlatformStore build(TargetPlatform platform) =>
          createHealthPlatform(
            platform,
            binding: HealthSyncBinding(FakeSettingsStore()),
            minorBindingAllowed: true,
          );

      expect(build(TargetPlatform.iOS), isA<IOSHealthChannel>());
      expect(build(TargetPlatform.android), isA<AndroidHealthChannel>());
      expect(build(TargetPlatform.windows), isA<UnsupportedHealthPlatform>());
      expect(build(TargetPlatform.macOS), isA<UnsupportedHealthPlatform>());
      expect(build(TargetPlatform.linux), isA<UnsupportedHealthPlatform>());
      expect(build(TargetPlatform.fuchsia), isA<UnsupportedHealthPlatform>());
    });

    test('with no override, the test default (android) still pins Android',
        () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(
        createHealthPlatform(
          null,
          binding: HealthSyncBinding(FakeSettingsStore()),
          minorBindingAllowed: true,
        ),
        isA<AndroidHealthChannel>(),
      );
    });
  });

  group('readMenstrualFlowPage (Issues #217/#992)', () {
    final start = DateTime.utc(1970, 1, 1);
    final end = DateTime.utc(2026, 9, 17);

    Future<HealthReadResult> page({
      String? cursor,
      MethodChannelHealthPlatform? platform,
    }) =>
        (platform ?? makePlatform()).readMenstrualFlowPage(
          _facts(),
          start: start,
          end: end,
          pageSize: kHealthImportPageSize,
          cursor: cursor,
        );

    test('a denied read refuses with zero channel invocations', () async {
      final result = await page(platform: makePlatform(seed: {}));
      expect(result, isA<HealthReadRefused>());
      expect((result as HealthReadRefused).check, HealthSyncCheck.noBinding);
      expect(calls, isEmpty);
    });

    test('an allowed read crosses the channel with the guard, window, page '
        'size and cursor', () async {
      nextResult = <String, Object?>{
        'samples': [
          {
            'recordId': 'uuid-1',
            'flow': 'light',
            'startMs': 1000,
            'endMs': 2000,
            'tzName': 'UTC',
          },
        ],
        'nextCursor': 'page-2',
      };
      final result = await page(cursor: 'page-1');

      expect(calls, hasLength(1));
      final call = calls.single;
      expect(call.method, 'readMenstrualFlowPage');
      final args = call.arguments as Map<Object?, Object?>;
      expect(args['profileId'], 'p1');
      expect(args['startMs'], start.millisecondsSinceEpoch);
      expect(args['endMs'], end.millisecondsSinceEpoch);
      expect(args['pageSize'], kHealthImportPageSize);
      expect(args['cursor'], 'page-1');
      final samples = result as HealthReadSamples;
      expect(samples.samples.single.recordId, 'uuid-1');
      expect(samples.nextCursor, 'page-2');
    });

    test('a first page sends no cursor key at all', () async {
      nextResult = <String, Object?>{'samples': <Object?>[]};
      await page();
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args.containsKey('cursor'), isFalse);
    });

    test('a platform unavailable error maps to HealthReadUnavailable', () async {
      nextError = PlatformException(code: 'unavailable');
      expect(await page(), isA<HealthReadUnavailable>());
    });

    test('a permissionDenied platform error maps to the read denial', () async {
      nextError = PlatformException(code: 'permissionDenied');
      expect(await page(), isA<HealthReadPermissionDenied>());
    });

    test('the unsupported platform reads as unavailable', () async {
      const platform = UnsupportedHealthPlatform();
      final result = await platform.readMenstrualFlowPage(
        _facts(),
        start: start,
        end: end,
        pageSize: kHealthImportPageSize,
      );
      expect(result, isA<HealthReadUnavailable>());
    });

    test('createHealthImportSource pins each platform', () {
      HealthImportSource build(TargetPlatform platform) =>
          createHealthImportSource(
            platform,
            binding: HealthSyncBinding(FakeSettingsStore()),
            minorBindingAllowed: true,
          );

      expect(build(TargetPlatform.iOS), isA<IOSHealthChannel>());
      expect(build(TargetPlatform.android), isA<AndroidHealthChannel>());
      expect(build(TargetPlatform.windows), isA<UnsupportedHealthPlatform>());
    });
  });

  // Issue #799: the computed cycle-deviation read — the same guard ordering
  // as the flow read, and the one place the Dart side proves the exact
  // identifier strings it sends (matched to the Swift table by
  // `test/release/health_deviation_read_types_test.dart`).
  group('readCycleDeviations (Issue #799)', () {
    final start = DateTime.utc(2026, 1, 1);
    final end = DateTime.utc(2026, 6, 30);

    test('a denied read refuses with zero channel invocations', () async {
      final result = await makePlatform(seed: {}).readCycleDeviations(
        _facts(),
        start: start,
        end: end,
      );
      expect(result, isA<HealthDeviationRefused>());
      expect((result as HealthDeviationRefused).check, HealthSyncCheck.noBinding);
      expect(calls, isEmpty);
    });

    test('an allowed read crosses the channel with the guard, window, and '
        'every canonical identifier', () async {
      nextResult = <Object?>[
        {
          'kind': 'irregularMenstrualCycles',
          'recordId': 'dev-1',
          'startMs': 1000,
          'endMs': 2000,
          'zoneOffsetSeconds': -14400,
          'zoneOffsetInferred': true,
        },
      ];
      final result = await makePlatform().readCycleDeviations(
        _facts(),
        start: start,
        end: end,
      );

      expect(calls, hasLength(1));
      final call = calls.single;
      expect(call.method, 'readCycleDeviations');
      final args = call.arguments as Map<Object?, Object?>;
      expect(args['profileId'], 'p1');
      expect(args['startMs'], start.millisecondsSinceEpoch);
      expect(args['endMs'], end.millisecondsSinceEpoch);
      expect(args['kinds'], [
        for (final kind in HealthDeviationKind.values) kind.healthKitIdentifier,
      ]);
      final sample =
          (result as HealthDeviationSamples).samples.single;
      expect(sample.kind, HealthDeviationKind.irregularMenstrualCycles);
      expect(sample.offset, const Duration(hours: -4));
      expect(sample.offsetInferred, isTrue);
    });

    test('an unknown wire field is a failed result, never a silent skip',
        () async {
      nextResult = <Object?>[
        {'kind': 'bogus', 'recordId': 'x', 'startMs': 1, 'endMs': 2},
      ];
      final result = await makePlatform().readCycleDeviations(
        _facts(),
        start: start,
        end: end,
      );
      expect(result, isA<HealthDeviationFailed>());
    });

    test('platform outcomes map to their typed variants', () async {
      nextError = PlatformException(code: 'unavailable');
      expect(
        await makePlatform().readCycleDeviations(_facts(),
            start: start, end: end),
        isA<HealthDeviationUnavailable>(),
      );
      nextError = PlatformException(code: 'permissionDenied');
      expect(
        await makePlatform().readCycleDeviations(_facts(),
            start: start, end: end),
        isA<HealthDeviationPermissionDenied>(),
      );
      nextError = MissingPluginException();
      expect(
        await makePlatform().readCycleDeviations(_facts(),
            start: start, end: end),
        isA<HealthDeviationUnavailable>(),
      );
    });

    test('the unsupported platform reads as unavailable', () async {
      const platform = UnsupportedHealthPlatform();
      final result = await platform.readCycleDeviations(
        _facts(),
        start: start,
        end: end,
      );
      expect(result, isA<HealthDeviationUnavailable>());
    });
  });

  // Issue #959: the OS permission methods and their exact wire vocabulary.
  // The native halves cannot run here, so these pin the method names and
  // result strings the Swift/Kotlin handlers must mirror.
  group('OS permission state (Issue #959)', () {
    test('permissionStatus sends the pinned method name and decodes every '
        'wire value', () async {
      for (final status in HealthPermissionStatus.values) {
        calls.clear();
        nextResult = status.toWire();
        expect(await makePlatform().permissionStatus(), status);
        expect(calls.single.method, 'permissionStatus');
      }
    });

    test('an unknown native string degrades to unavailable, never denied',
        () async {
      nextResult = 'readDenied';
      expect(
        await makePlatform().permissionStatus(),
        HealthPermissionStatus.unavailable,
      );
    });

    test('a platform error or a missing handler is unavailable, never a crash',
        () async {
      nextError = PlatformException(code: 'anything');
      expect(
        await makePlatform().permissionStatus(),
        HealthPermissionStatus.unavailable,
      );
      nextError = MissingPluginException();
      expect(
        await makePlatform().permissionStatus(),
        HealthPermissionStatus.unavailable,
      );
    });

    test('openPermissionSettings sends the pinned method name and is '
        'best-effort', () async {
      await makePlatform().openPermissionSettings();
      expect(calls.single.method, 'openPermissionSettings');

      nextError = PlatformException(code: 'anything');
      await makePlatform().openPermissionSettings();
      expect(calls.last.method, 'openPermissionSettings');
    });

    test('the unsupported platform reports unavailable and opens nothing',
        () async {
      const platform = UnsupportedHealthPlatform();
      expect(
        await platform.permissionStatus(),
        HealthPermissionStatus.unavailable,
      );
      await platform.openPermissionSettings();
      expect(calls, isEmpty, reason: 'no channel exists to call');
    });
  });

  // Issue #1491: the read-side probe the background import is gated on.
  // Health Connect says which reads are granted, so on Android the
  // question crosses the channel under its own name. HealthKit never says,
  // so on iOS it is answered from the write probe and the read-side name
  // is never sent to a Swift handler that does not exist.
  group('read-side permission state (Issue #1491)', () {
    MethodChannelHealthPlatform makeUndisclosed() => MethodChannelHealthPlatform(
          binding: HealthSyncBinding(FakeSettingsStore()),
          minorBindingAllowed: true,
          readAccessDisclosed: false,
        );

    HealthPlatformStore build(TargetPlatform platform) => createHealthPlatform(
          platform,
          binding: HealthSyncBinding(FakeSettingsStore()),
          minorBindingAllowed: true,
        );

    test('importPermissionStatus sends its own pinned method name, with no '
        'arguments, and decodes every wire value', () async {
      for (final status in HealthPermissionStatus.values) {
        calls.clear();
        nextResult = status.toWire();
        expect(await makePlatform().importPermissionStatus(), status);
        expect(calls.single.method, 'importPermissionStatus');
        expect(calls.single.arguments, isNull);
      }
    });

    test('an unknown string, a platform error or a missing handler is '
        'unavailable — which stops a background pass, never lets it read',
        () async {
      nextResult = 'readDenied';
      expect(
        await makePlatform().importPermissionStatus(),
        HealthPermissionStatus.unavailable,
      );
      nextResult = 'granted';
      nextError = PlatformException(code: 'anything');
      expect(
        await makePlatform().importPermissionStatus(),
        HealthPermissionStatus.unavailable,
      );
      nextError = MissingPluginException();
      expect(
        await makePlatform().importPermissionStatus(),
        HealthPermissionStatus.unavailable,
      );
    });

    // Issue #1549: Health Connect hides data older than about a month
    // before the first grant unless "Access past data" is on. The screen
    // asks before it says an empty read means an empty store.
    test('importReachesPastData sends its own pinned method name, with no '
        'arguments, and only a clear yes is yes', () async {
      nextResult = true;
      expect(await makePlatform().importReachesPastData(), isTrue);
      expect(calls.single.method, 'importPastDataGranted');
      expect(calls.single.arguments, isNull);

      for (final answer in <Object?>[false, null, 'granted', 1]) {
        nextResult = answer;
        expect(
          await makePlatform().importReachesPastData(),
          isFalse,
          reason: '$answer is not a yes',
        );
      }
    });

    test('a platform error or a missing handler is "cannot tell", which '
        'is no: the screen must not then call the store empty', () async {
      nextResult = true;
      nextError = PlatformException(code: 'anything');
      expect(await makePlatform().importReachesPastData(), isFalse);
      nextError = MissingPluginException();
      expect(await makePlatform().importReachesPastData(), isFalse);
    });

    test('where the store does not disclose read access there is no such '
        'limit to ask about: yes, and nothing is sent', () async {
      calls.clear();
      nextResult = false;
      expect(await makeUndisclosed().importReachesPastData(), isTrue);
      expect(calls, isEmpty);
    });

    test('where the store does not disclose read access, the answer is the '
        'write probe\'s and the read-side method is never sent', () async {
      for (final status in HealthPermissionStatus.values) {
        calls.clear();
        nextResult = status.toWire();
        expect(await makeUndisclosed().importPermissionStatus(), status);
        expect(calls.single.method, 'permissionStatus');
      }
    });

    test('the write probe is the same call whichever way the read-side '
        'question is answered', () async {
      nextResult = 'denied';
      expect(
        await makeUndisclosed().permissionStatus(),
        HealthPermissionStatus.denied,
      );
      expect(
        await makePlatform().permissionStatus(),
        HealthPermissionStatus.denied,
      );
      expect(
        calls.map((call) => call.method),
        everyElement('permissionStatus'),
      );
    });

    test('the iOS adapter asks Swift only for the write probe; the Android '
        'adapter asks Kotlin for the read-side one', () async {
      nextResult = 'granted';

      final ios = build(TargetPlatform.iOS);
      expect((ios as MethodChannelHealthPlatform).readAccessDisclosed, isFalse);
      expect(await ios.importPermissionStatus(), HealthPermissionStatus.granted);
      expect(calls.single.method, 'permissionStatus');

      calls.clear();
      final android = build(TargetPlatform.android);
      expect(
        (android as MethodChannelHealthPlatform).readAccessDisclosed,
        isTrue,
      );
      expect(
        await android.importPermissionStatus(),
        HealthPermissionStatus.granted,
      );
      expect(calls.single.method, 'importPermissionStatus');
    });

    test('the unsupported platform reports unavailable', () async {
      const platform = UnsupportedHealthPlatform();
      expect(
        await platform.importPermissionStatus(),
        HealthPermissionStatus.unavailable,
      );
      expect(calls, isEmpty, reason: 'no channel exists to call');
    });
  });

  // Issue #1515: the import asks through a request of its own. On Android
  // that is a separate channel method, answered by a Kotlin handler that
  // asks Health Connect for the reads and for no write permission — so
  // tapping Import never puts the write permissions in front of someone
  // who declined them. On iOS nothing changes: the import still asks
  // through the one HealthKit sheet, and the read-only name is never sent
  // to a Swift handler that does not exist. Which of the two it is turns
  // on the same platform fact the read-side probe turns on.
  group('the import\'s own permission request (Issue #1515)', () {
    MethodChannelHealthPlatform makeUndisclosed() => MethodChannelHealthPlatform(
          binding: HealthSyncBinding(
            FakeSettingsStore({SettingsKeys.healthStoreProfileId: 'p1'}),
          ),
          minorBindingAllowed: true,
          readAccessDisclosed: false,
        );

    HealthPlatformStore build(TargetPlatform platform) => createHealthPlatform(
          platform,
          binding: HealthSyncBinding(
            FakeSettingsStore({SettingsKeys.healthStoreProfileId: 'p1'}),
          ),
          minorBindingAllowed: true,
        );

    test('where read access is disclosed it sends its own pinned method '
        'name, with the guard args, and never the write path\'s', () async {
      final result = await makePlatform().requestImportAuthorization(_facts());

      expect(result, isA<HealthPlatformAllowed>());
      expect(calls.single.method, 'requestImportAuthorization');
      expect(
        (calls.single.arguments as Map<Object?, Object?>)['profileId'],
        'p1',
      );
    });

    test('the write path\'s request is the same call it always was',
        () async {
      await makePlatform().requestWriteAuthorization(_facts());
      await makeUndisclosed().requestWriteAuthorization(_facts());

      expect(
        calls.map((call) => call.method),
        ['requestWriteAuthorization', 'requestWriteAuthorization'],
      );
    });

    test('where read access is not disclosed it is the write path\'s one '
        'sheet, exactly as before, and the read-only name is never sent',
        () async {
      final result = await makeUndisclosed().requestImportAuthorization(
        _facts(),
      );

      expect(result, isA<HealthPlatformAllowed>());
      expect(calls.single.method, 'requestWriteAuthorization');
      expect(
        (calls.single.arguments as Map<Object?, Object?>)['profileId'],
        'p1',
      );
    });

    test('native answers decode as they do for every guarded call', () async {
      nextResult = 'permissionDenied';
      expect(
        await makePlatform().requestImportAuthorization(_facts()),
        isA<HealthPlatformPermissionDenied>(),
      );
      nextResult = 'unavailable';
      expect(
        await makePlatform().requestImportAuthorization(_facts()),
        isA<HealthPlatformUnavailable>(),
      );
      nextResult = 'allowed';
      nextError = MissingPluginException();
      expect(
        await makePlatform().requestImportAuthorization(_facts()),
        isA<HealthPlatformUnavailable>(),
      );
    });

    test('the iOS adapter sends Swift only requestWriteAuthorization; the '
        'Android adapter sends Kotlin requestImportAuthorization', () async {
      await build(TargetPlatform.iOS).requestImportAuthorization(_facts());
      expect(calls.single.method, 'requestWriteAuthorization');

      calls.clear();
      await build(TargetPlatform.android).requestImportAuthorization(_facts());
      expect(calls.single.method, 'requestImportAuthorization');
    });

    test('the platform fact is readable through the probe the screen holds',
        () {
      HealthPermissionProbe probe(TargetPlatform platform) => build(platform);

      expect(probe(TargetPlatform.iOS).readAccessDisclosed, isFalse);
      expect(probe(TargetPlatform.android).readAccessDisclosed, isTrue);
      expect(probe(TargetPlatform.windows).readAccessDisclosed, isFalse);
      expect(
        const UnsupportedHealthPlatform().readAccessDisclosed,
        isFalse,
        reason: 'no health store discloses nothing',
      );
    });
  });
}
