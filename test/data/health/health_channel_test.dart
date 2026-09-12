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

    test('minor profile without ownership transfer '
        '(minorRequiresOwnershipTransfer)', () async {
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
      expectRefusedWithoutInvocation(
        result,
        HealthSyncCheck.minorRequiresOwnershipTransfer,
      );
    });

    test('bindProfile, requestWriteAuthorization, and '
        'writeIntermenstrualBleeding all refuse identically '
        '(notOwner)', () async {
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
        await platform.bindProfile(_facts()),
        isA<HealthPlatformUnavailable>(),
      );
      expect(
        await platform.requestWriteAuthorization(_facts()),
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
}
