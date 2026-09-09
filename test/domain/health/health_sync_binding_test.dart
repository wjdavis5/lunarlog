/// Unit tests for [HealthSyncBinding] (Issue #153): the device-local
/// single-valued binding invariant, backed by a real [FakeSettingsStore]
/// (not a database) — mirrors the existing convention of testing services
/// that only depend on [SettingsStore] against the fake rather than Drift.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';

import '../../support/fake_settings_store.dart';

Profile _profile({String id = 'p1', bool isMinor = false}) => Profile(
      id: id,
      displayName: 'Test Profile',
      isMinor: isMinor,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  late FakeSettingsStore settings;
  late HealthSyncBinding binding;

  setUp(() {
    settings = FakeSettingsStore();
    binding = HealthSyncBinding(settings);
  });
  tearDown(() => settings.close());

  test('no profile mapped initially -> boundProfileId is null', () async {
    expect(await binding.boundProfileId(), isNull);
  });

  test('bind succeeds for an eligible profile and persists the binding',
      () async {
    final result = await binding.bind(
      profile: _profile(id: 'p1'),
      signedInUserId: 'u1',
      ownerUserId: 'u1',
    );
    expect(result, HealthSyncCheck.allowed);
    expect(await binding.boundProfileId(), 'p1');
  });

  test('bind refuses (and persists nothing) for a guardian-only, '
      'non-owner account', () async {
    final result = await binding.bind(
      profile: _profile(id: 'p1'),
      signedInUserId: 'caregiver-1',
      ownerUserId: 'owner-1',
    );
    expect(result, HealthSyncCheck.notOwner);
    expect(await binding.boundProfileId(), isNull);
  });

  test('bind refuses a minor profile without ownership transfer, and '
      'persists nothing', () async {
    final result = await binding.bind(
      profile: _profile(id: 'p1', isMinor: true),
      signedInUserId: 'u1',
      ownerUserId: 'u1',
    );
    expect(result, HealthSyncCheck.minorRequiresTransfer);
    expect(await binding.boundProfileId(), isNull);
  });

  test('bind allows a minor profile when minorBindingAllowed is explicitly '
      'set', () async {
    final result = await binding.bind(
      profile: _profile(id: 'p1', isMinor: true),
      signedInUserId: 'u1',
      ownerUserId: 'u1',
      minorBindingAllowed: true,
    );
    expect(result, HealthSyncCheck.allowed);
    expect(await binding.boundProfileId(), 'p1');
  });

  test('invariant: binding a second profile while one is already bound '
      'replaces it outright (documented design decision — matches the '
      "Settings UI acceptance criterion 'selecting a new profile clears "
      "the previous mapping')", () async {
    await binding.bind(
      profile: _profile(id: 'a'),
      signedInUserId: 'u1',
      ownerUserId: 'u1',
    );
    expect(await binding.boundProfileId(), 'a');

    final second = await binding.bind(
      profile: _profile(id: 'b'),
      signedInUserId: 'u2',
      ownerUserId: 'u2',
    );
    expect(second, HealthSyncCheck.allowed);
    // At most one bound profile, ever: the setting is single-valued, so
    // there is no state in which both 'a' and 'b' are simultaneously bound.
    expect(await binding.boundProfileId(), 'b');
  });

  test('a denied second bind attempt leaves the original binding intact',
      () async {
    await binding.bind(
      profile: _profile(id: 'a'),
      signedInUserId: 'u1',
      ownerUserId: 'u1',
    );

    final denied = await binding.bind(
      profile: _profile(id: 'b'),
      signedInUserId: 'caregiver-1',
      ownerUserId: 'owner-1',
    );
    expect(denied, HealthSyncCheck.notOwner);
    expect(await binding.boundProfileId(), 'a');
  });

  test('unbind clears the binding back to null', () async {
    await binding.bind(
      profile: _profile(id: 'a'),
      signedInUserId: 'u1',
      ownerUserId: 'u1',
    );
    expect(await binding.boundProfileId(), 'a');

    await binding.unbind();
    expect(await binding.boundProfileId(), isNull);
  });

  test('watchBoundProfileId emits the seeded value then every change',
      () async {
    final seen = <String?>[];
    final sub = binding.watchBoundProfileId().listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    await binding.bind(
      profile: _profile(id: 'a'),
      signedInUserId: 'u1',
      ownerUserId: 'u1',
    );
    await pumpEventQueue();
    await binding.unbind();
    await pumpEventQueue();

    expect(seen, [null, 'a', null]);
  });

  test('an empty-string stored value (the unbind convention) reads back as '
      'null, matching awaitingConfirmationEmail\'s idiom', () async {
    await settings.set(SettingsKeys.healthStoreProfileId, '');
    expect(await binding.boundProfileId(), isNull);
  });
}
