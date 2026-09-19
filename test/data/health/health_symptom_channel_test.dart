/// Issue #238: the `writeSymptomSamples` channel method's Dart half. The
/// same guard-ordering property `health_channel_test.dart` pins for every
/// other write holds here — a denied symptom write must not invoke the
/// channel at all — and an allowed one must carry the fully-resolved
/// `(typeIdentifier, severity, recordId, recordVersionMs)` samples.
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

HealthSymptomSamplesWrite _write({HealthGuardFacts? facts}) =>
    HealthSymptomSamplesWrite(
      facts: facts ?? _facts(),
      date: LocalDate(2026, 8, 30),
      tzName: 'America/New_York',
      samples: const [
        HealthSymptomSample(
          healthKitTypeIdentifier: 'abdominalCramps',
          severity: HealthSymptomSeverity.severe,
          recordId: 'symptom-entry-1-abdominalCramps',
          recordVersionMs: 1234567890000,
        ),
        HealthSymptomSample(
          healthKitTypeIdentifier: 'moodChanges',
          severity: HealthSymptomSeverity.unspecified,
          recordId: 'symptom-entry-1-moodChanges',
          recordVersionMs: 1234567890000,
        ),
      ],
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

  test('a denied symptom write refuses without touching the channel', () async {
    final result = await makePlatform(seed: {})
        .writeSymptomSamples(_write(facts: _facts()));

    expect(result, isA<HealthPlatformRefused>());
    expect((result as HealthPlatformRefused).check, HealthSyncCheck.noBinding);
    expect(calls, isEmpty);
  });

  test(
    'a notOwner symptom write refuses without touching the channel',
    () async {
      final result = await makePlatform().writeSymptomSamples(
        _write(facts: _facts(ownerUserId: 'someone-else')),
      );

      expect(result, isA<HealthPlatformRefused>());
      expect((result as HealthPlatformRefused).check, HealthSyncCheck.notOwner);
      expect(calls, isEmpty);
    },
  );

  test(
    'an allowed symptom write crosses the channel with the full envelope',
    () async {
      final result = await makePlatform().writeSymptomSamples(_write());

      expect(result, isA<HealthPlatformAllowed>());
      expect(calls, hasLength(1));
      final call = calls.single;
      expect(call.method, 'writeSymptomSamples');
      final args = call.arguments as Map<Object?, Object?>;
      expect(args['profileId'], 'p1');
      // Day args for 2026-08-30 America/New_York (EDT, UTC-4).
      expect(
        args['startMs'],
        DateTime.utc(2026, 8, 30, 4).millisecondsSinceEpoch,
      );
      final samples = args['samples'] as List<Object?>;
      expect(samples, hasLength(2));
      final first = samples.first as Map<Object?, Object?>;
      expect(first['typeIdentifier'], 'abdominalCramps');
      expect(first['severity'], 'severe');
      expect(first['recordId'], 'symptom-entry-1-abdominalCramps');
      expect(first['recordVersionMs'], 1234567890000);
      final second = samples[1] as Map<Object?, Object?>;
      expect(second['typeIdentifier'], 'moodChanges');
      expect(second['severity'], 'unspecified');
    },
  );

  test('a native unavailable answer passes through as unavailable', () async {
    nextResult = 'unavailable';
    expect(
      await makePlatform().writeSymptomSamples(_write()),
      isA<HealthPlatformUnavailable>(),
    );
  });

  test('the unsupported platform answers unavailable, never crashes', () async {
    const platform = UnsupportedHealthPlatform();
    expect(
      await platform.writeSymptomSamples(_write()),
      isA<HealthPlatformUnavailable>(),
    );
    expect(calls, isEmpty);
  });
}
