/// Health-sync write policy (Issue #153) — the load-bearing safety
/// invariant for the whole Health Platform Sync epic (#156 through #246):
/// every future HealthKit/Health Connect write path must call
/// [canSyncProfile] before writing anything, and treat any result other
/// than [HealthSyncCheck.allowed] as a bug to refuse and log, never a
/// silent skip. No platform adapter exists yet — this file, plus
/// [HealthSyncBinding] in `health_sync_binding.dart`, is the domain +
/// local-storage half that must land before one does.
///
/// Two independent conditions must both hold before writing a profile's
/// data to this device's OS health store:
///
///  1. **Device-local binding**: exactly one profile is bound as "this
///     device's health-store owner" ([boundProfileId], read from
///     [SettingsKeys.healthStoreProfileId] via [HealthSyncBinding]), and
///     the profile being written is that one.
///  2. **Account ownership**: the signed-in account owns the profile
///     (`profiles.user_id`, server-side). This app's client-side [Profile]
///     model carries no `userId` field of its own — ownership is instead
///     exposed client-side as an accepted [GuardianRole.primaryGuardian]
///     row on the local `profile_guardians` table (see [ownerUserIdFor]),
///     which is what this check actually uses. A guardian device holding
///     any lesser accepted role (`co_parent`, `caregiver`, `viewer`) must
///     never write that profile's data to its own health store, even if
///     [boundProfileId] were somehow misconfigured to point at it — that is
///     exactly the case [HealthSyncCheck.notOwner] exists to catch.
///
/// A minor profile ([Profile.isMinor]) is denied by default regardless of
/// binding or ownership (issue #153's explicit product decision): binding
/// a minor's health data requires transferring that profile to the minor's
/// own account first, via the existing transfer flow (issue #4).
/// [minorBindingAllowed] exists purely so flipping that decision later is a
/// one-line default change at every call site, not a rewrite of this
/// function.
///
/// Pure Dart (R14/R16); `test/architecture/layering_test.dart` enforces the
/// import discipline.
library;

import '../models/profile.dart';
import '../models/profile_guardian.dart';

/// The explicit allow/deny outcome of [canSyncProfile]. Every non-[allowed]
/// value is a distinct, user-facing reason — never a bare bool — so
/// Settings UI and future write-guard call sites can explain *why* a write
/// or a binding was refused.
enum HealthSyncCheck {
  /// No profile is bound to this device at all (default state).
  noBinding,

  /// A profile is bound to this device, but not the one being checked.
  profileNotBound,

  /// The profile is a minor and [canSyncProfile]'s `minorBindingAllowed`
  /// was not set — binding a minor requires transferring ownership to the
  /// minor's own account first (issue #4), never a device-local override.
  minorRequiresTransfer,

  /// The signed-in account does not hold an accepted `primary_guardian`
  /// row for this profile — including the case where it holds a lesser
  /// accepted role (co-parent, caregiver, viewer) instead.
  notOwner,

  /// Every check passed; the write (or binding) may proceed.
  allowed;

  /// Shorthand for `this == allowed`, so call sites read as a guard rather
  /// than an enum comparison.
  bool get isAllowed => this == allowed;
}

/// Whether [profile]'s data may be written to this device's OS health
/// store (or bound as this device's health-store profile) right now.
///
/// Pure and total — never throws. [boundProfileId] is the device-local
/// setting's current value (null when unset); [ownerUserId] is the
/// resolved accepted-`primary_guardian` user id for this profile (see
/// [ownerUserIdFor]), or null when none is known yet (an unsynced
/// guardians table fails closed here, same as a genuinely absent owner).
///
/// Check order is deny-reason-first, evaluated independently — a caller
/// asking "would binding this profile be allowed?" passes
/// `boundProfileId: profile.id` (the proposed value) so only the minor and
/// ownership checks can produce a deny; [HealthSyncBinding.bind] and the
/// Settings picker both do exactly that.
HealthSyncCheck canSyncProfile({
  required Profile profile,
  required String? boundProfileId,
  required String? signedInUserId,
  required String? ownerUserId,
  bool minorBindingAllowed = false,
}) {
  if (boundProfileId == null) return HealthSyncCheck.noBinding;
  if (profile.id != boundProfileId) return HealthSyncCheck.profileNotBound;
  if (profile.isMinor && !minorBindingAllowed) {
    return HealthSyncCheck.minorRequiresTransfer;
  }
  final isOwner = signedInUserId != null &&
      ownerUserId != null &&
      signedInUserId == ownerUserId;
  if (!isOwner) return HealthSyncCheck.notOwner;
  return HealthSyncCheck.allowed;
}

/// The accepted `primary_guardian`'s user id among [guardiansForProfile]
/// (already filtered to one profile — e.g.
/// `ProfileGuardiansRepository.getForProfile`'s result), or null when none
/// is accepted yet. [canSyncProfile] treats a null result the same as a
/// genuinely absent owner (fails closed): an unsynced or not-yet-accepted
/// guardians table denies rather than allows.
String? ownerUserIdFor(List<ProfileGuardian> guardiansForProfile) {
  for (final guardian in guardiansForProfile) {
    if (guardian.role == GuardianRole.primaryGuardian &&
        guardian.status == GuardianStatus.accepted) {
      return guardian.userId;
    }
  }
  return null;
}
