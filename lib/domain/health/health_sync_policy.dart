/// Health-sync write policy (Issue #153) — the load-bearing safety
/// invariant for the whole Health Platform Sync epic (#156 through #246):
/// every future HealthKit/Health Connect write path must call
/// [HealthSyncBinding.canWrite] before writing anything (see
/// `health_sync_binding.dart`), and treat any result other than
/// [HealthSyncCheck.allowed] as a bug to refuse and log, never a silent
/// skip. No platform adapter exists yet — this file, plus
/// [HealthSyncBinding], is the domain + local-storage half that must land
/// before one does.
///
/// **The pure decision itself is private to `health_sync_binding.dart`,
/// not exported from here** — this is a P0 review fix (issue #153): the
/// previous public `canSyncProfile` took `boundProfileId` from the
/// *caller*, and both existing call sites (the settings picker and,
/// fatally, `HealthSyncBinding.bind` itself) passed `profile.id` — the
/// *proposed* value — which neutralised the device-binding check for the
/// one call site that actually persists a binding. Nothing outside
/// `lib/domain/health/` may construct that decision's inputs directly.
/// Call [HealthSyncBinding.canBind] (the settings picker's "would binding
/// this profile be allowed right now?" question, evaluated against the
/// *proposed* id) or [HealthSyncBinding.canWrite] (the real write guard —
/// reads the *actually stored* binding itself via
/// [SettingsKeys.healthStoreProfileId], never a caller-supplied value)
/// instead. Every future platform adapter MUST call
/// [HealthSyncBinding.canWrite] and must not construct the policy input
/// itself.
///
/// Three independent conditions must all hold before writing a profile's
/// data to this device's OS health store:
///
///  1. **Device-local binding**: exactly one profile is bound as "this
///     device's health-store owner" (read from
///     [SettingsKeys.healthStoreProfileId]), and the profile being written
///     is that one. [HealthSyncBinding.canWrite] reads the stored value
///     itself; [HealthSyncBinding.canBind] instead checks the *proposed*
///     binding, since nothing is stored yet at that point.
///  2. **Account ownership**: the signed-in account owns the profile
///     (`profiles.user_id`, server-side). This app's client-side [Profile]
///     model carries no `userId` field of its own — ownership is instead
///     exposed client-side as an accepted [GuardianRole.primaryGuardian]
///     row on the local `profile_guardians` table (see [ownerUserIdFor]),
///     which is what this check actually uses. A guardian device holding
///     any lesser accepted role (`co_parent`, `caregiver`, `viewer`) must
///     never write that profile's data to its own health store, even if
///     the stored binding were somehow misconfigured to point at it —
///     that is exactly the case [HealthSyncCheck.notOwner] exists to
///     catch. A **device-only** profile — nobody signed in AND no owner
///     resolved — is the one exception (Issue #882): there is no other
///     account it could belong to, so the local operator is treated as its
///     owner and the no-account path the rest of the app supports stays
///     usable.
///  3. **Minor gate (Issue #882)**: a profile counts as a minor when either
///     [Profile.isMinor] is set, or it is not set but the profile is at
///     most 18 by coarse-year arithmetic against [Profile.birthYear]
///     (`<= 18`, the fail-closed direction — issue #296; someone born late
///     in year Y is still 17 for most of year Y+18 and a year-only check
///     cannot see the birthday) — unticking "Minor" in the profile dialog
///     must never by itself clear this deny. Since #882 a minor is *not* a
///     special deny: it passes condition 2 on exactly the same terms as an
///     adult. No ownership transfer is required. The transferred-minor
///     exception (transfer targeted the signed-in account itself, i.e.
///     [Profile.transferredAt] non-null *and* [Profile.transferredToUserId]
///     equal to the signed-in user id *and* the signed-in account is the
///     resolved owner) is preserved and still returns allowed, but it only
///     ever holds for a resolved owner, so it agrees with condition 2.
///     `AppConfig.healthSyncMinorBindingAllowed` (`lib/config.dart`) is the
///     switch that keeps the old behaviour recoverable: while it is
///     `false`, a minor is denied outright with
///     [HealthSyncCheck.minorRequiresOwnershipTransfer] regardless of
///     ownership or transfer state, exactly as before #882. That flag is a
///     single hardcoded constant, not a parameter either entry point
///     accepts, precisely so no call site can invent its own per-call
///     bypass.
///
/// The whole decision is mirrored natively — `ios/Runner/AppDelegate.swift`'s
/// `guardDecision` and Android's `HealthConnectAdapter.kt` — and the two
/// sides must agree (a drift re-closes the gate on a real device even
/// though Dart allows it; Issue #882).
///
/// Server-side enforcement of the same consent (a `profiles`-table column
/// gating writes at the database layer, so a compromised or modified
/// client cannot self-attest) is deferred to issue #188 — everything in
/// this file and `health_sync_binding.dart` is client-side only.
///
/// Pure Dart (R14/R16); `test/architecture/layering_test.dart` enforces
/// the import discipline, and
/// `test/architecture/health_sync_binding_scope_test.dart` asserts
/// [SettingsKeys.healthStoreProfileId] is read only inside
/// `lib/domain/health/`.
library;

import '../models/profile.dart';
import '../models/profile_guardian.dart';

/// The explicit allow/deny outcome of [HealthSyncBinding.canBind] and
/// [HealthSyncBinding.canWrite]. Every non-[allowed] value is a distinct,
/// user-facing reason — never a bare bool — so Settings UI and future
/// write-guard call sites can explain *why* a write or a binding was
/// refused.
enum HealthSyncCheck {
  /// No profile is bound to this device at all (default state).
  noBinding,

  /// A profile is bound to this device, but not the one being checked.
  profileNotBound,

  /// A profile counts as a minor (flagged, or at most 18 by the coarse
  /// birth-year check) **and** `AppConfig.healthSyncMinorBindingAllowed`
  /// is off. This is the pre-#882 rule: while the flag is `false` a minor
  /// is refused outright, regardless of ownership or transfer state.
  /// Since #882 the flag is `true` and a minor binds on the same terms as
  /// an adult, so this result is only reachable in the flag's off
  /// position, which is kept (and tested) as the switch's other state.
  minorRequiresOwnershipTransfer,

  /// The signed-in account does not hold an accepted `primary_guardian`
  /// row for this profile — including the case where it holds a lesser
  /// accepted role (co-parent, caregiver, viewer) instead, or where an
  /// owner is known but nobody (or somebody else) is signed in. A
  /// device-only profile — nobody signed in AND no owner resolved — is
  /// **not** [notOwner] since Issue #882: there is no other account it
  /// could belong to, so it is treated as locally owned.
  notOwner,

  /// Every check passed; the write (or binding) may proceed.
  allowed;

  /// Shorthand for `this == allowed`, so call sites read as a guard rather
  /// than an enum comparison.
  bool get isAllowed => this == allowed;
}

/// The accepted `primary_guardian`'s user id among [guardiansForProfile]
/// (already filtered to one profile — e.g.
/// `ProfileGuardiansRepository.getForProfile`'s result), or null when none
/// is accepted yet, or when more than one accepted `primary_guardian` row
/// is found. [HealthSyncBinding.canBind]/[HealthSyncBinding.canWrite]
/// treat a null result the same as a genuinely absent owner (fails
/// closed): an unsynced or not-yet-accepted guardians table denies rather
/// than allows, and so does a data anomaly that should never happen
/// (`profile_guardians_one_primary_uq` constrains this server-side to at
/// most one) rather than arbitrarily picking one of several candidates.
String? ownerUserIdFor(List<ProfileGuardian> guardiansForProfile) {
  final accepted = <String>[
    for (final guardian in guardiansForProfile)
      if (guardian.role == GuardianRole.primaryGuardian &&
          guardian.status == GuardianStatus.accepted)
        guardian.userId,
  ];
  return accepted.length == 1 ? accepted.single : null;
}
