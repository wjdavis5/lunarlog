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

/// The pinned clock every test in this file evaluates the coarse
/// birth-year minor check against (Issue #296's `now` seam). Chosen so
/// the calendar arithmetic in the boundary tests below is readable at a
/// glance: 2026 minus a birth year IS the coarse age this file asserts.
final DateTime _kNow = DateTime.utc(2026, 9, 8);

Profile _profile({
  String id = 'p1',
  bool isMinor = false,
  int? birthYear,
  DateTime? transferredAt,
  String? transferredToUserId,
}) =>
    Profile(
      id: id,
      displayName: 'Test Profile',
      isMinor: isMinor,
      birthYear: birthYear,
      transferredAt: transferredAt,
      transferredToUserId: transferredToUserId,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  late FakeSettingsStore settings;
  late HealthSyncBinding binding;

  setUp(() {
    settings = FakeSettingsStore();
    binding = HealthSyncBinding(settings, now: () => _kNow);
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

    test('minor profile, transferred to the signed-in owner, but '
        'minorBindingAllowed is false -> still refused (the feature-level '
        'switch is a separate, non-bypassable gate)', () {
      final result = binding.canBind(
        profile: _profile(
          id: 'p1',
          isMinor: true,
          transferredAt: DateTime.utc(2026, 1, 1),
          transferredToUserId: 'u1',
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

    test('minor profile, minorBindingAllowed true, transferred to the '
        "minor's account, but the signed-in account is not the resolved "
        'owner -> still refused (transfer alone is not enough)', () {
      final result = binding.canBind(
        profile: _profile(
          id: 'p1',
          isMinor: true,
          transferredAt: DateTime.utc(2026, 1, 1),
          transferredToUserId: 'the-minor-1',
        ),
        signedInUserId: 'former-guardian-1',
        ownerUserId: 'the-minor-1',
        minorBindingAllowed: true,
      );
      expect(result, HealthSyncCheck.minorRequiresOwnershipTransfer);
    });

    // Issue #296: a transfer with no recorded target cannot prove
    // "transferred to the signed-in account" — a pre-#296 row, or a row
    // from a server that has not applied the #296 migration — fails
    // closed even for the resolved owner with the flag on.
    test('minor profile, transferred, but no transfer target recorded '
        '(a pre-#296 row) -> fails closed for the owner too', () {
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
      expect(result, HealthSyncCheck.minorRequiresOwnershipTransfer);
    });

    // Issue #296's core regression: the transfer must have targeted the
    // signed-in account ITSELF. Here the profile's last transfer went to
    // 'the-minor-1', but the guardians table resolves 'stale-owner-1' as
    // the accepted primary (not-yet-synced rows, or any future ownership
    // path that forgets to re-stamp the target) — that account must not
    // inherit the minor exception merely by being the resolved owner.
    test('minor profile whose last transfer targeted a different account '
        'is denied even when the caller resolves as the owner', () {
      final result = binding.canBind(
        profile: _profile(
          id: 'p1',
          isMinor: true,
          transferredAt: DateTime.utc(2026, 1, 1),
          transferredToUserId: 'the-minor-1',
        ),
        signedInUserId: 'stale-owner-1',
        ownerUserId: 'stale-owner-1',
        minorBindingAllowed: true,
      );
      expect(result, HealthSyncCheck.minorRequiresOwnershipTransfer);
    });

    // Issue #296's acceptance scenario: a parent→co-parent handover of a
    // MINOR's profile. The arming parent comes back demoted to co_parent
    // ("that co-parent signed in") — the transfer was addressed to
    // 'co-parent-1', so it does not satisfy the minor exception for the
    // former parent, and the former parent is not the resolved owner
    // either. (What the transferred-to signal deliberately does NOT
    // distinguish — recorded for #295 — is the *accepting* co-parent's
    // own device: the identity-free token design makes that account
    // structurally identical to the minor's own account. That residual
    // is exactly why healthSyncMinorBindingAllowed stays false.)
    test('a parent→co-parent transfer does not satisfy the minor '
        'exception for the demoted parent', () {
      final result = binding.canBind(
        profile: _profile(
          id: 'p1',
          isMinor: true,
          transferredAt: DateTime.utc(2026, 1, 1),
          transferredToUserId: 'co-parent-1',
        ),
        signedInUserId: 'former-parent-1',
        ownerUserId: 'co-parent-1',
        minorBindingAllowed: true,
      );
      expect(result, HealthSyncCheck.minorRequiresOwnershipTransfer);
    });

    test('minor profile allowed only once every condition holds: '
        'minorBindingAllowed true, transferred TO the signed-in account, '
        'and that account is the resolved (new) owner', () {
      final result = binding.canBind(
        profile: _profile(
          id: 'p1',
          isMinor: true,
          transferredAt: DateTime.utc(2026, 1, 1),
          transferredToUserId: 'the-minor-1',
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
      final tenYearsOld = _kNow.year - 10;
      final result = binding.canBind(
        profile: _profile(id: 'p1', isMinor: false, birthYear: tenYearsOld),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: true,
      );
      expect(result, HealthSyncCheck.minorRequiresOwnershipTransfer);
    });

    test('a birth year 19+ years ago, with isMinor false, is not treated '
        'as a minor', () {
      final adultBirthYear = _kNow.year - 40;
      final result = binding.canBind(
        profile:
            _profile(id: 'p1', isMinor: false, birthYear: adultBirthYear),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      expect(result, HealthSyncCheck.allowed);
    });

    // Issue #296's boundary criterion: someone born December 2008 is 17
    // by full date on the pinned clock (2026-09-08), but year-only
    // arithmetic computes 18 — the previous `< 18` check let them skip
    // the gate entirely. `<= 18` fails closed across the whole calendar
    // year of their 18th birthday.
    test('boundary: a 17-year-old by full date (born late in birthYear '
        '+ 18) is denied as a minor', () {
      final result = binding.canBind(
        profile: _profile(
          id: 'p1',
          isMinor: false,
          birthYear: 2008, // 17 on 2026-09-08; coarse arithmetic says 18
        ),
        signedInUserId: 'the-minor-1',
        ownerUserId: 'the-minor-1',
        minorBindingAllowed: true,
      );
      expect(result, HealthSyncCheck.minorRequiresOwnershipTransfer);
    });

    test('boundary: the fail-closed cost — an actual 18-year-old is also '
        'denied for the rest of birthYear + 18 (the exception path, not '
        'the owner path, still applies)', () {
      final result = binding.canBind(
        profile: _profile(
          id: 'p1',
          isMinor: false,
          birthYear: _kNow.year - 18,
        ),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      expect(result, HealthSyncCheck.minorRequiresOwnershipTransfer);
    });

    test('boundary: 19 whole years back is an adult (owner path)', () {
      final result = binding.canBind(
        profile: _profile(
          id: 'p1',
          isMinor: false,
          birthYear: _kNow.year - 19,
        ),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      expect(result, HealthSyncCheck.allowed);
    });

    test('the clock seam is instance-level, not a per-call parameter: '
        'the pinned clock, not the wall clock, decides the boundary', () {
      // _kNow.year - 18 = 2008: an adult by the real wall clock's
      // arithmetic a year from now would flip; this test pins that the
      // injected clock (2026) is what the gate sees, keeping the
      // boundary deterministic no matter when the suite runs.
      final result = binding.canBind(
        profile: _profile(
          id: 'p1',
          isMinor: false,
          birthYear: 2008,
        ),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      expect(result, HealthSyncCheck.minorRequiresOwnershipTransfer);
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

    // Issue #296 through the real write guard: even with the feature flag
    // on, a transferred minor profile is writable only from the account
    // the last transfer actually targeted.
    test('canWrite denies a transferred minor profile whose last transfer '
        'targeted a different account, flag or no flag', () async {
      await binding.bind(
        profile: _profile(
          id: 'p1',
          isMinor: true,
          transferredAt: DateTime.utc(2026, 1, 1),
          transferredToUserId: 'the-minor-1',
        ),
        signedInUserId: 'the-minor-1',
        ownerUserId: 'the-minor-1',
        minorBindingAllowed: true,
      );
      final wrongAccount = await binding.canWrite(
        profile: _profile(
          id: 'p1',
          isMinor: true,
          transferredAt: DateTime.utc(2026, 1, 1),
          transferredToUserId: 'the-minor-1',
        ),
        signedInUserId: 'stale-owner-1',
        ownerUserId: 'stale-owner-1',
        minorBindingAllowed: true,
      );
      expect(wrongAccount, HealthSyncCheck.minorRequiresOwnershipTransfer);
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

  test('bind allows a minor profile once it has been transferred TO the '
      'signed-in owner and minorBindingAllowed is explicitly set', () async {
    final result = await binding.bind(
      profile: _profile(
        id: 'p1',
        isMinor: true,
        transferredAt: DateTime.utc(2026, 1, 1),
        transferredToUserId: 'the-minor-1',
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
