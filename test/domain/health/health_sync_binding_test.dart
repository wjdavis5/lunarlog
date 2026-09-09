/// Unit tests for [HealthSyncBinding] (Issue #153): the device-local
/// single-valued binding invariant, backed by a real [FakeSettingsStore]
/// (not a database) — mirrors the existing convention of testing services
/// that only depend on [SettingsStore] against the fake rather than Drift.
///
/// This file also owns every deny-reason/allow-path test for the shared
/// policy decision (moved here from `health_sync_policy_test.dart` —
/// review fix): the decision is private to this library now, so it can
/// only be exercised through [HealthSyncBinding.canBind] and
/// [HealthSyncBinding.canWrite].
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';

import '../../support/fake_settings_store.dart';

Profile _profile({
  String id = 'p1',
  bool isMinor = false,
  int? birthYear,
  DateTime? transferredAt,
}) =>
    Profile(
      id: id,
      displayName: 'Test Profile',
      isMinor: isMinor,
      birthYear: birthYear,
      transferredAt: transferredAt,
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

  group('canBind (proposed binding)', () {
    test('mapped profile matches, owner signed in -> allowed', () {
      final result = binding.canBind(
        profile: _profile(id: 'p1'),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      expect(result, HealthSyncCheck.allowed);
      expect(result.isAllowed, isTrue);
    });

    test('guardian-only (non-owner) account -> notOwner', () {
      final result = binding.canBind(
        profile: _profile(id: 'p1'),
        signedInUserId: 'caregiver-1',
        ownerUserId: 'owner-1',
        minorBindingAllowed: false,
      );
      expect(result, HealthSyncCheck.notOwner);
      expect(result.isAllowed, isFalse);
    });

    test('signed out (no signedInUserId) -> notOwner, fails closed', () {
      final result = binding.canBind(
        profile: _profile(id: 'p1'),
        signedInUserId: null,
        ownerUserId: 'owner-1',
        minorBindingAllowed: false,
      );
      expect(result, HealthSyncCheck.notOwner);
    });

    test('unresolved owner (guardians not yet synced) -> notOwner, fails '
        'closed rather than allowing', () {
      final result = binding.canBind(
        profile: _profile(id: 'p1'),
        signedInUserId: 'u1',
        ownerUserId: null,
        minorBindingAllowed: false,
      );
      expect(result, HealthSyncCheck.notOwner);
    });

    test('minor profile (isMinor flag), no transfer -> '
        'minorRequiresOwnershipTransfer, refused even for the owner', () {
      final result = binding.canBind(
        profile: _profile(id: 'p1', isMinor: true),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      expect(result, HealthSyncCheck.minorRequiresOwnershipTransfer);
      expect(result.isAllowed, isFalse);
    });

    test('minor profile, transferred to the owner, but '
        'minorBindingAllowed is false -> still refused (the feature-level '
        'switch is a separate, non-bypassable gate)', () {
      final result = binding.canBind(
        profile: _profile(
          id: 'p1',
          isMinor: true,
          transferredAt: DateTime.utc(2026, 1, 1),
        ),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      expect(result, HealthSyncCheck.minorRequiresOwnershipTransfer);
    });

    test('minor profile, minorBindingAllowed true, but never transferred '
        '-> still refused', () {
      final result = binding.canBind(
        profile: _profile(id: 'p1', isMinor: true),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: true,
      );
      expect(result, HealthSyncCheck.minorRequiresOwnershipTransfer);
    });

    test('minor profile, minorBindingAllowed true, transferred, but the '
        'signed-in account is not the resolved owner -> still refused '
        "(transfer alone is not enough — it must be the minor's own "
        'account)', () {
      final result = binding.canBind(
        profile: _profile(
          id: 'p1',
          isMinor: true,
          transferredAt: DateTime.utc(2026, 1, 1),
        ),
        signedInUserId: 'former-guardian-1',
        ownerUserId: 'the-minor-1',
        minorBindingAllowed: true,
      );
      expect(result, HealthSyncCheck.minorRequiresOwnershipTransfer);
    });

    test('minor profile allowed only once every condition holds: '
        'minorBindingAllowed true, transferred, and the signed-in account '
        'is the resolved (new) owner', () {
      final result = binding.canBind(
        profile: _profile(
          id: 'p1',
          isMinor: true,
          transferredAt: DateTime.utc(2026, 1, 1),
        ),
        signedInUserId: 'the-minor-1',
        ownerUserId: 'the-minor-1',
        minorBindingAllowed: true,
      );
      expect(result, HealthSyncCheck.allowed);
    });

    test('under-18-by-birth-year profile is treated as a minor even when '
        'isMinor reads false (review fix — unticking "Minor" in the '
        'profile dialog must not clear this deny)', () {
      final tenYearsOld = DateTime.now().year - 10;
      final result = binding.canBind(
        profile: _profile(id: 'p1', isMinor: false, birthYear: tenYearsOld),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: true,
      );
      expect(result, HealthSyncCheck.minorRequiresOwnershipTransfer);
    });

    test('a birth year 18+ years ago, with isMinor false, is not treated '
        'as a minor', () {
      final adultBirthYear = DateTime.now().year - 40;
      final result = binding.canBind(
        profile:
            _profile(id: 'p1', isMinor: false, birthYear: adultBirthYear),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      expect(result, HealthSyncCheck.allowed);
    });
  });

  group(
      'canWrite (the real write guard — reads the stored binding itself)',
      () {
    test('no profile mapped -> noBinding, no writes possible', () async {
      final result = await binding.canWrite(
        profile: _profile(),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      expect(result, HealthSyncCheck.noBinding);
    });

    test('the stored binding matches, owner signed in -> allowed', () async {
      await binding.bind(
        profile: _profile(id: 'p1'),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      final result = await binding.canWrite(
        profile: _profile(id: 'p1'),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      expect(result, HealthSyncCheck.allowed);
    });

    // The load-bearing regression test for this PR's P0 fix: the previous
    // write guard took `boundProfileId` from the caller, and every real
    // call site passed `profile.id` — the profile it was about to write —
    // which meant the device-binding check could never actually deny
    // anything. `canWrite` must instead read what is *actually* stored,
    // so passing the "wrong" profile (one never bound on this device)
    // must never come back allowed, no matter what the caller supplies for
    // every other parameter — including an owner id that matches the
    // signed-in user, and even when no profile at all is bound yet.
    test('canWrite cannot return allowed for a profile that is not the '
        'stored binding, no matter what the caller passes', () async {
      // Case 1: nothing bound at all — every "would-be-eligible" profile
      // must resolve to noBinding, never allowed.
      final withNothingBound = await binding.canWrite(
        profile: _profile(id: 'target-profile'),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      expect(withNothingBound.isAllowed, isFalse);
      expect(withNothingBound, HealthSyncCheck.noBinding);

      // Case 2: a *different* profile is bound — the target profile must
      // resolve to profileNotBound, never allowed, even though every
      // other input (owner, signed-in user) is fully eligible.
      await binding.bind(
        profile: _profile(id: 'other-bound-profile'),
        signedInUserId: 'owner-of-other',
        ownerUserId: 'owner-of-other',
        minorBindingAllowed: false,
      );
      final withDifferentProfileBound = await binding.canWrite(
        profile: _profile(id: 'target-profile'),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      expect(withDifferentProfileBound.isAllowed, isFalse);
      expect(withDifferentProfileBound, HealthSyncCheck.profileNotBound);
    });

    test('a guardian-only (non-owner) account on the correctly-bound '
        'profile -> notOwner, write refused', () async {
      await binding.bind(
        profile: _profile(id: 'p1'),
        signedInUserId: 'owner-1',
        ownerUserId: 'owner-1',
        minorBindingAllowed: false,
      );
      final result = await binding.canWrite(
        profile: _profile(id: 'p1'),
        signedInUserId: 'caregiver-1',
        ownerUserId: 'owner-1',
        minorBindingAllowed: false,
      );
      expect(result, HealthSyncCheck.notOwner);
    });
  });

  test('no profile mapped initially -> boundProfileId is null', () async {
    expect(await binding.boundProfileId(), isNull);
  });

  test('bind succeeds for an eligible profile and persists the binding',
      () async {
    final result = await binding.bind(
      profile: _profile(id: 'p1'),
      signedInUserId: 'u1',
      ownerUserId: 'u1',
      minorBindingAllowed: false,
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
      minorBindingAllowed: false,
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
      minorBindingAllowed: false,
    );
    expect(result, HealthSyncCheck.minorRequiresOwnershipTransfer);
    expect(await binding.boundProfileId(), isNull);
  });

  test('bind allows a minor profile once it has been transferred to the '
      'signed-in owner and minorBindingAllowed is explicitly set', () async {
    final result = await binding.bind(
      profile: _profile(
        id: 'p1',
        isMinor: true,
        transferredAt: DateTime.utc(2026, 1, 1),
      ),
      signedInUserId: 'the-minor-1',
      ownerUserId: 'the-minor-1',
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
      minorBindingAllowed: false,
    );
    expect(await binding.boundProfileId(), 'a');

    final second = await binding.bind(
      profile: _profile(id: 'b'),
      signedInUserId: 'u2',
      ownerUserId: 'u2',
      minorBindingAllowed: false,
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
      minorBindingAllowed: false,
    );

    final denied = await binding.bind(
      profile: _profile(id: 'b'),
      signedInUserId: 'caregiver-1',
      ownerUserId: 'owner-1',
      minorBindingAllowed: false,
    );
    expect(denied, HealthSyncCheck.notOwner);
    expect(await binding.boundProfileId(), 'a');
  });

  test('unbind clears the binding back to null', () async {
    await binding.bind(
      profile: _profile(id: 'a'),
      signedInUserId: 'u1',
      ownerUserId: 'u1',
      minorBindingAllowed: false,
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
      minorBindingAllowed: false,
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
