/// Per-viewer lens resolution for family profiles (Issue #850, D-1).
///
/// Every profile renders one UI to everyone today, the only viewer-dependent
/// branch being `role.canLog → readOnly`. This file resolves the missing
/// presentation axis: which *lens* the current viewer sees a profile through.
/// The subject (the person the profile is about) keeps the existing own-voice
/// screen; every other accepted member sees the profile through the guardian
/// lens (a guardian logistics card and third-person voice — U5+).
///
/// The lens is derived strictly from membership identity — #802's
/// server-stamped [ProfileGuardian.isSubject] plus the accepted membership
/// row — never from `ProfileRelationship`. It is presentation only: it
/// changes no permission, and a viewer still cannot write (D-1, D-8).
///
/// Fail-open by construction, matching [acceptedGuardianFor] and
/// `_effectiveReadOnly`: no signed-in membership (a local-only operator, or a
/// profile whose guardian rows have not synced) resolves to [GuardianLens.subject].
/// A freshly invited guardian briefly sees the subject lens until their row
/// arrives; that is the documented pre-sync posture, called out in the #850 U1
/// PR rather than treated as an error.
///
/// Pure Dart with no drift/Flutter imports, matching
/// `sharing_overview.dart`'s layering; `test/architecture/layering_test.dart`
/// scans every file under `lib/domain` for `package:flutter` imports.
library;

import '../models/profile_guardian.dart';

/// Which front page a viewer sees for a profile: the subject's own-voice
/// screen, or the guardian's logistics view (Issue #850, D-2).
enum GuardianLens {
  /// The viewer is the profile's subject (or is not known to be a member) —
  /// fail open, exactly the operator-first posture `_effectiveReadOnly` uses.
  subject,

  /// The viewer is an accepted member other than the subject — every role
  /// from `caregiver` to `primary_guardian`, since the lens is identity, not
  /// capability.
  guardian,
}

/// Resolves the lens for [currentUserId] among a profile's [guardians]
/// (D-1).
///
/// * The subject's own accepted membership → [GuardianLens.subject].
/// * Any other accepted membership (including a primary guardian who created
///   the profile and is therefore not its subject) → [GuardianLens.guardian].
/// * A null [currentUserId], empty [guardians], or a viewer with only
///   pending/revoked rows → [GuardianLens.subject] (fail open — only
///   `acceptedGuardianFor`'s accepted rows count, so non-accepted rows are
///   ignored outright).
GuardianLens guardianLensFor(
  List<ProfileGuardian> guardians,
  String? currentUserId,
) {
  final member = acceptedGuardianFor(guardians, currentUserId);
  if (member == null || member.isSubject) return GuardianLens.subject;
  return GuardianLens.guardian;
}

/// The accepted guardian row's role for [currentUserId], or null when there
/// is no accepted membership. Delegates to [acceptedGuardianFor] so the lens
/// and its callers resolve identity through the one function that already
/// encodes the null/pending/revoked discipline.
GuardianRole? guardianRoleFor(
  List<ProfileGuardian> guardians,
  String? currentUserId,
) =>
    acceptedGuardianFor(guardians, currentUserId)?.role;
