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
///     catch.
///  3. **Minor gate**: a profile counts as a minor when either
///     [Profile.isMinor] is set, or it is not set but the profile is at
///     most 18 by coarse-year arithmetic against [Profile.birthYear]
///     (`<= 18`, the fail-closed direction — issue #296; someone born late
///     in year Y is still 17 for most of year Y+18 and a year-only check
///     cannot see the birthday) — unticking "Minor" in the profile dialog
///     must never by itself clear this deny. A minor profile is refused
///     unless the last ownership transfer targeted the signed-in account
///     *itself* — [Profile.transferredAt] non-null *and*
///     [Profile.transferredToUserId] (issue #296's server-stamped
///     "transferred to whom" signal, written only by
///     `accept_ownership_transfer`) equal to the signed-in user id *and*
///     the signed-in account is the profile's resolved owner (never a
///     device-local override) — *and*
///     `AppConfig.healthSyncMinorBindingAllowed` (`lib/config.dart`) is
///     `true`. A missing target (a pre-#296 row, or a row from a server
///     that has not applied the #296 migration) fails closed. That flag is
///     a single hardcoded constant, not a parameter
///     either entry point accepts, precisely so no future call site can
///     invent its own per-call bypass — the same mistake condition 1's
///     fix above closes. It is `false` in every build today, so this path
///     is categorically closed regardless of transfer state until a
///     platform adapter exists to exercise it. One honest limit, recorded
///     for #295: the transferred-to signal proves the last transfer was
///     addressed to the signed-in account; the data model has no
///     profile-subject-to-account link, so "the minor's own account"
///     versus "another adult account the parent handed the link to" is
///     still not distinguishable client-side — which is exactly why the
///     flag above stays `false` until #295 (and #188's server-side
///     consent) land.
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

  /// The profile counts as a minor (flagged, or at most 18 by the coarse
  /// birth-year check) and at least one of: ownership has never
  /// transferred ([Profile.transferredAt] is null), the last transfer did
  /// not target the signed-in account ([Profile.transferredToUserId] is
  /// null or names another account — issue #296), the signed-in account is
  /// not the profile's resolved owner, or
  /// `AppConfig.healthSyncMinorBindingAllowed` is off. Binding a minor
  /// requires all of them — issue #4's transfer flow addressed to this
  /// account, then that account signed in and resolving as the owner, then
  /// the feature itself enabled — never a device-local override.
  minorRequiresOwnershipTransfer,

  /// The signed-in account does not hold an accepted `primary_guardian`
  /// row for this profile — including the case where it holds a lesser
  /// accepted role (co-parent, caregiver, viewer) instead, or where
  /// ownership has not resolved at all yet (an unsynced guardians table,
  /// or no signed-in session).
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
