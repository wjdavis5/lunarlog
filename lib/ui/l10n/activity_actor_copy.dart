/// Localized copy for the activity feed's actor naming (Issue #545, moved
/// out of `lib/domain/activity/activity_feed.dart`, which hardcoded English
/// ("you"/"a guardian") and called the since-deleted `GuardianRole.label`
/// getter directly — a domain-layer copy violation of the same shape the
/// issue's other …FailureCopy mappers fix). The `en` ARB values are
/// character-identical to the literals this replaces, so this is
/// copy-neutral.
library;

import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/l10n/guardian_role_copy.dart';

/// Resolves a user id for display, mirroring the attribution badge's ladder
/// (issue #124): "you" for the current user, then the guardian's display
/// name, then the role label, then the neutral "a guardian" — and null for
/// a null id, so an unattributed row renders without an actor phrase and a
/// raw uuid is never shown. Names come from guardian rows of any status: a
/// revoked guardian's own past entries still deserve their name.
String? activityActorLabel(
  AppLocalizations l10n,
  String? userId,
  String? currentUserId,
  List<ProfileGuardian> guardians,
) {
  if (userId == null) return null;
  if (currentUserId != null && userId == currentUserId) {
    return l10n.activityActorYou;
  }
  for (final guardian in guardians) {
    if (guardian.userId == userId) {
      final name = guardian.displayName;
      if (name != null && name.isNotEmpty) return name;
      return guardianRoleLabel(l10n, guardian.role);
    }
  }
  return l10n.activityActorGuardianFallback;
}
