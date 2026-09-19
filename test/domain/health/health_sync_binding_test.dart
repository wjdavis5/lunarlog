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

    test('minor profile, minorBindingAllowed false, no transfer -> '
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

    // Issue #882: with the switch on (the production value) a minor is no
    // longer a special deny. It passes on the same owner check an adult
    // passes on, so the owner is allowed with no transfer required.
    test('minor profile, minorBindingAllowed true, owned by the signed-in '
        'account, never transferred -> allowed (minors bind on the same '
        'terms as adults, Issue #882)', () {
      final result = binding.canBind(
        profile: _profile(id: 'p1', isMinor: true),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: true,
      );
      expect(result, HealthSyncCheck.allowed);
      expect(result.isAllowed, isTrue);
    });

    test('minor profile, minorBindingAllowed true, signed in as a different '
        'account than the resolved owner -> notOwner (Issue #882)', () {
      final result = binding.canBind(
        profile: _profile(id: 'p1', isMinor: true),
        signedInUserId: 'caregiver-1',
        ownerUserId: 'owner-1',
        minorBindingAllowed: true,
      );
      expect(result, HealthSyncCheck.notOwner);
      expect(result.isAllowed, isFalse);
    });

    test('minor profile, minorBindingAllowed true, transferred to another '
        "account that is not the caller -> notOwner (Issue #882: the owner "
        'gate now decides, not the transfer target)', () {
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
      expect(result, HealthSyncCheck.notOwner);
    });

    // Issue #882: the pre-#296 transfer-target pin no longer changes the
    // outcome for a resolved owner — the owner gate allows. The missing
    // target still fails the *transfer exception*, which is why this is
    // exactly the case the exception no longer needs to carry alone.
    test('minor profile, transferred, but no transfer target recorded '
        '(a pre-#296 row), resolved owner -> allowed via the owner gate '
        '(Issue #882)', () {
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

    // Issue #296's regression shape, re-evaluated under #882: the transfer
    // target proves "transferred to the signed-in account", but once the
    // flagged switch is on a minor binds on the same owner terms as an
    // adult, so a resolved owner is allowed regardless of the target.
    test('minor profile whose last transfer targeted a different account '
        'is allowed when the caller genuinely resolves as the owner '
        '(Issue #882)', () {
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
      expect(result, HealthSyncCheck.allowed);
    });

    // Issue #296's acceptance scenario: a parent→co-parent handover of a
    // MINOR's profile. The arming parent comes back demoted to co_parent
    // ("that co-parent signed in") — the transfer was addressed to
    // 'co-parent-1', and the former parent is not the resolved owner
    // either. Under #882 the owner gate decides: notOwner.
    test('a parent→co-parent transfer does not satisfy the owner gate for '
        'the demoted parent (Issue #882)', () {
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
      expect(result, HealthSyncCheck.notOwner);
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
        'isMinor reads false — and, with the switch on, still binds on the '
        'owner terms (Issue #882)', () {
      final tenYearsOld = _kNow.year - 10;
      final result = binding.canBind(
        profile: _profile(id: 'p1', isMinor: false, birthYear: tenYearsOld),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: true,
      );
      expect(result, HealthSyncCheck.allowed);
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
    // year of their 18th birthday. With #882's switch on, "counts as a
    // minor" no longer means "denied": the same owner gate applies.
    test('boundary: a 17-year-old by full date (born late in birthYear '
        '+ 18) is still classified a minor and binds on owner terms '
        '(Issue #882)', () {
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
      expect(result, HealthSyncCheck.allowed);
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

    // Issue #882 device-only path: with nobody signed in AND no owner
    // resolved there is no other account the profile could belong to, so
    // the local operator is its owner. This is the no-account path the
    // rest of the app supports and it must now work for health sync too.
    test('adult profile, no account at all (no signedInUserId, no '
        'ownerUserId) -> allowed, locally owned (Issue #882)', () {
      final result = binding.canBind(
        profile: _profile(id: 'p1'),
        signedInUserId: null,
        ownerUserId: null,
        minorBindingAllowed: false,
      );
      expect(result, HealthSyncCheck.allowed);
    });

    test('minor profile, no account at all -> allowed, locally owned '
        '(Issue #882)', () {
      final result = binding.canBind(
        profile: _profile(id: 'p1', isMinor: true),
        signedInUserId: null,
        ownerUserId: null,
        minorBindingAllowed: true,
      );
      expect(result, HealthSyncCheck.allowed);
    });

    test('adult profile, signed in but not the resolved owner -> notOwner '
        '(the device-only exception is narrow)', () {
      final result = binding.canBind(
        profile: _profile(id: 'p1'),
        signedInUserId: 'someone-else',
        ownerUserId: 'owner-1',
        minorBindingAllowed: false,
      );
      expect(result, HealthSyncCheck.notOwner);
    });

    test('an ownerUserId set with nobody signed in -> notOwner (fails '
        'closed; the device-only exception needs BOTH sides null)', () {
      final result = binding.canBind(
        profile: _profile(id: 'p1'),
        signedInUserId: null,
        ownerUserId: 'owner-1',
        minorBindingAllowed: false,
      );
      expect(result, HealthSyncCheck.notOwner);
    });

    // The switch's off position preserves the whole pre-#882 rule,
    // including the coarse birth-year classification and its fail-closed
    // cost.
    test('minorBindingAllowed false: an under-18-by-birth-year profile is '
        'denied even when isMinor reads false (unticking "Minor" cannot '
        'clear the deny)', () {
      final result = binding.canBind(
        profile: _profile(
          id: 'p1',
          isMinor: false,
          birthYear: _kNow.year - 10,
        ),
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: false,
      );
      expect(result, HealthSyncCheck.minorRequiresOwnershipTransfer);
    });

    test('minorBindingAllowed false: a minor with no account at all is '
        'still denied (the switch overrides the device-only exception)', () {
      final result = binding.canBind(
        profile: _profile(id: 'p1', isMinor: true),
        signedInUserId: null,
        ownerUserId: null,
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

    // Issue #882 through the real write guard: a transferred minor whose
    // caller genuinely resolves as the owner passes the owner gate, just
    // like an adult; the transfer target no longer decides once the
    // switch is on.
    test('canWrite allows a transferred minor profile when the caller '
        'resolves as the owner (Issue #882)', () async {
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
      final owner = await binding.canWrite(
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
      expect(owner, HealthSyncCheck.allowed);
    });

    test('canWrite refuses a minor profile for a signed-in non-owner '
        '(Issue #882)', () async {
      await binding.bind(
        profile: _profile(id: 'p1', isMinor: true),
        signedInUserId: 'the-minor-1',
        ownerUserId: 'the-minor-1',
        minorBindingAllowed: true,
      );
      final nonOwner = await binding.canWrite(
        profile: _profile(id: 'p1', isMinor: true),
        signedInUserId: 'caregiver-1',
        ownerUserId: 'the-minor-1',
        minorBindingAllowed: true,
      );
      expect(nonOwner, HealthSyncCheck.notOwner);
    });

    // The P0 the issue reports: a device-only profile (no account at all)
    // must be writable, not denied with notOwner.
    test('canWrite allows a device-only profile bound with no account at '
        'all (Issue #882)', () async {
      await binding.bind(
        profile: _profile(id: 'p1'),
        signedInUserId: null,
        ownerUserId: null,
        minorBindingAllowed: false,
      );
      final result = await binding.canWrite(
        profile: _profile(id: 'p1'),
        signedInUserId: null,
        ownerUserId: null,
        minorBindingAllowed: false,
      );
      expect(result, HealthSyncCheck.allowed);
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

  test('bind allows a minor profile owned by the signed-in account with no '
      'transfer required (Issue #882)', () async {
    final result = await binding.bind(
      profile: _profile(id: 'p1', isMinor: true),
      signedInUserId: 'u1',
      ownerUserId: 'u1',
      minorBindingAllowed: true,
    );
    expect(result, HealthSyncCheck.allowed);
    expect(await binding.boundProfileId(), 'p1');
  });

  test('bind allows a device-only profile with no account at all '
      '(Issue #882)', () async {
    final result = await binding.bind(
      profile: _profile(id: 'p1'),
      signedInUserId: null,
      ownerUserId: null,
      minorBindingAllowed: false,
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
