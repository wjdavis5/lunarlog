/// Localized copy for [GuardianRole] (Issue #545): the domain enum itself
/// keeps `toDb`/`fromDb`/its capability getters, but its former `label` and
/// `readOnlyReason` getters hardcoded English inside `lib/domain` — deleted
/// in favor of these mappers. The `en` ARB values are character-identical
/// to the literals they replace, so this is copy-neutral.
library;

import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/sharing/sharing_overview.dart';
import 'package:lunarlog/l10n/app_localizations.dart';

String guardianRoleLabel(AppLocalizations l10n, GuardianRole role) =>
    switch (role) {
      GuardianRole.primaryGuardian => l10n.guardianRoleLabelPrimaryGuardian,
      GuardianRole.coParent => l10n.guardianRoleLabelCoParent,
      GuardianRole.caregiver => l10n.guardianRoleLabelCaregiver,
      GuardianRole.viewer => l10n.guardianRoleLabelViewer,
    };

/// Copy explaining why a role's day sheet (and other write surfaces) is
/// read-only (Issue #3 gap-closure plan, Unit U6; R13). Null for every role
/// that [GuardianRole.canLog] — only a role that cannot log has a reason to
/// surface, and it must read distinctly from the archived-profile reason so
/// a viewer session is never mistaken for an archived one.
String? guardianRoleReadOnlyReason(AppLocalizations l10n, GuardianRole role) =>
    switch (role) {
      GuardianRole.viewer => l10n.guardianRoleReadOnlyReasonViewer,
      _ => null,
    };

/// The role line for a profile row (Issue #126, moved out of
/// `lib/domain/sharing/sharing_overview.dart` per Issue #545): shared
/// profiles name the group and the role; owned profiles name the role only
/// when known, otherwise null so the caller falls back to its own subtitle
/// (e.g. created date) instead of guessing.
String? sharingProfileRoleSubtitle(
  AppLocalizations l10n,
  SharingProfileInfo info,
) {
  final role = info.myRole;
  if (info.group == ProfileSharingGroup.sharedWithMe) {
    return l10n.profilePickerSharedRoleSubtitle(guardianRoleLabel(l10n, role!));
  }
  return role == null ? null : guardianRoleLabel(l10n, role);
}
