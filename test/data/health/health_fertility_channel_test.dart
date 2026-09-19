/// Issue #228: the `writeCervicalMucus` / `writeOvulationTest` /
/// `writeBasalBodyTemperature` channel methods' Dart half. The same
/// guard-ordering property every other write pins holds here — a denied
/// write must not invoke the channel at all — and an allowed one must carry
/// the fully-resolved identifiers the native half translates.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_channel.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';

import '../../support/fake_settings_store.dart';

const _channel = MethodChannel('lunarlog/health');

Profile _profile() => Profile(
  id: 'p1',
  displayName: 'Test',
  isMinor: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

HealthGuardFacts _facts({String? ownerUserId = 'u1'}) => HealthGuardFacts(
  profile: _profile(),
  signedInUserId: 'u1',
  ownerUserId: ownerUserId,
);

HealthCervicalMucusWrite _cervical({HealthGuardFacts? facts}) =>
    HealthCervicalMucusWrite(
      facts: facts ?? _facts(),
      date: LocalDate(2026, 8, 30),
      tzName: 'America/New_York',
      healthKitValue: 'eggWhite',
      healthConnectAppearance: 'APPEARANCE_EGG_WHITE',
      recordId: 'cervical-mucus-entry-1',
      recordVersionMs: 1234567890000,
    );

HealthOvulationTestWrite _ovulation({HealthGuardFacts? facts}) =>
    HealthOvulationTestWrite(
      facts: facts ?? _facts(),
      date: LocalDate(2026, 8, 30),
      tzName: 'America/New_York',
      healthKitResult: 'luteinizingHormoneSurge',
      healthConnectResult: 'RESULT_POSITIVE',
      recordId: 'ovulation-entry-1-luteinizingHormoneSurge',
      recordVersionMs: 1234567890000,
    );

HealthBasalBodyTemperatureWrite _bbt({HealthGuardFacts? facts}) =>
    HealthBasalBodyTemperatureWrite(
      facts: facts ?? _facts(),
      date: LocalDate(2026, 8, 30),
      tzName: 'America/New_York',
      celsius: 36.6,
      healthConnectMeasurementLocation: 'MEASUREMENT_LOCATION_UNKNOWN',
      recordId: 'bbt-obs-1',
      recordVersionMs: 1234567890000,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];
  Object? nextResult;

  setUp(() {
    calls.clear();
    nextResult = 'allowed';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return nextResult;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  MethodChannelHealthPlatform makePlatform({
    Map<String, String> seed = const {SettingsKeys.healthStoreProfileId: 'p1'},
  }) => MethodChannelHealthPlatform(
    binding: HealthSyncBinding(FakeSettingsStore(seed)),
    minorBindingAllowed: true,
  );

  test('a denied cervical-mucus write refuses without touching the channel',
      () async {
    final result = await makePlatform(seed: {})
        .writeCervicalMucus(_cervical(facts: _facts()));
    expect(result, isA<HealthPlatformRefused>());
    expect((result as HealthPlatformRefused).check, HealthSyncCheck.noBinding);
    expect(calls, isEmpty);
  });

  test('a notOwner ovulation write refuses without touching the channel',
      () async {
    final result = await makePlatform().writeOvulationTest(
      _ovulation(facts: _facts(ownerUserId: 'someone-else')),
    );
    expect(result, isA<HealthPlatformRefused>());
    expect((result as HealthPlatformRefused).check, HealthSyncCheck.notOwner);
    expect(calls, isEmpty);
  });

  test('a denied BBT write refuses without touching the channel', () async {
    final result = await makePlatform(seed: {})
        .writeBasalBodyTemperature(_bbt(facts: _facts()));
    expect(result, isA<HealthPlatformRefused>());
    expect(calls, isEmpty);
  });

  test('an allowed cervical-mucus write crosses with both identifiers',
      () async {
    final result = await makePlatform().writeCervicalMucus(_cervical());
    expect(result, isA<HealthPlatformAllowed>());
    final call = calls.single;
    expect(call.method, 'writeCervicalMucus');
    final args = call.arguments as Map<Object?, Object?>;
    expect(args['profileId'], 'p1');
    // Day args for 2026-08-30 America/New_York (EDT, UTC-4).
    expect(
      args['startMs'],
      DateTime.utc(2026, 8, 30, 4).millisecondsSinceEpoch,
    );
    expect(args['healthKitValue'], 'eggWhite');
    expect(args['healthConnectAppearance'], 'APPEARANCE_EGG_WHITE');
    expect(args['recordId'], 'cervical-mucus-entry-1');
    expect(args['recordVersionMs'], 1234567890000);
  });

  test('an allowed ovulation write crosses with both results', () async {
    final result = await makePlatform().writeOvulationTest(_ovulation());
    expect(result, isA<HealthPlatformAllowed>());
    final call = calls.single;
    expect(call.method, 'writeOvulationTest');
    final args = call.arguments as Map<Object?, Object?>;
    expect(args['healthKitResult'], 'luteinizingHormoneSurge');
    expect(args['healthConnectResult'], 'RESULT_POSITIVE');
    expect(args['recordId'], 'ovulation-entry-1-luteinizingHormoneSurge');
  });

  test('an allowed BBT write crosses with Celsius and the location constant',
      () async {
    final result = await makePlatform().writeBasalBodyTemperature(_bbt());
    expect(result, isA<HealthPlatformAllowed>());
    final call = calls.single;
    expect(call.method, 'writeBasalBodyTemperature');
    final args = call.arguments as Map<Object?, Object?>;
    expect(args['celsius'], 36.6);
    expect(
      args['healthConnectMeasurementLocation'],
      'MEASUREMENT_LOCATION_UNKNOWN',
    );
    expect(args['recordId'], 'bbt-obs-1');
  });

  test('a native unavailable answer passes through as unavailable', () async {
    nextResult = 'unavailable';
    expect(
      await makePlatform().writeCervicalMucus(_cervical()),
      isA<HealthPlatformUnavailable>(),
    );
  });

  test('the unsupported platform answers unavailable, never crashes',
      () async {
    const platform = UnsupportedHealthPlatform();
    expect(
      await platform.writeCervicalMucus(_cervical()),
      isA<HealthPlatformUnavailable>(),
    );
    expect(
      await platform.writeOvulationTest(_ovulation()),
      isA<HealthPlatformUnavailable>(),
    );
    expect(
      await platform.writeBasalBodyTemperature(_bbt()),
      isA<HealthPlatformUnavailable>(),
    );
    expect(calls, isEmpty);
  });
}
