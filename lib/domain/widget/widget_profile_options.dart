/// Which profiles a home-screen widget may show and quick-log for
/// (issue #141), derived once here so the Settings picker, the widget
/// payload publisher, and the write executor all decide from one rule.
///
/// Role enforcement is issue #141's own acceptance criterion: a `viewer`
/// on a shared profile gets **no quick-log action** — neither offered on
/// the widget nor honored by the write path. The derivation uses the same
/// `acceptedGuardianFor` seam as the day sheet's read-only gate and the
/// overview's `_effectiveReadOnly`, including its null-vs-empty
/// discipline: an *unknown* role (a local-only operator, a not-yet-synced
/// membership) fails open to "can log" — exactly like every other write
/// surface in the app — while a **known** `viewer` fails closed.
library;

import '../models/profile.dart';
import '../models/profile_guardian.dart';

/// One profile the widget can be pointed at.
class WidgetProfileOption {
  const WidgetProfileOption({
    required this.profileId,
    required this.profileName,
    required this.canQuickLog,
  });

  final String profileId;

  /// Shown only inside the app's own Settings picker — this name never
  /// crosses the widget boundary (the container carries ids only).
  final String profileName;

  /// Whether the operator's accepted role on this profile may log. False
  /// for a known `viewer`; the widget renders no quick-log affordance and
  /// the executor drops the intent if one still arrives.
  final bool canQuickLog;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WidgetProfileOption &&
          other.profileId == profileId &&
          other.profileName == profileName &&
          other.canQuickLog == canQuickLog;

  @override
  int get hashCode => Object.hash(profileId, profileName, canQuickLog);

  @override
  String toString() =>
      'WidgetProfileOption($profileId, canQuickLog: $canQuickLog)';
}

/// Derives the widget's profile options from the live (non-archived)
/// profile list, this operator's guardian rows, and the current user id.
///
/// * Archived and tombstoned profiles never appear (a widget pointing at
///   an archived profile would render a stale state forever).
/// * [currentUserId] null (signed out, local-only device) means no
///   guardian row can match, which `acceptedGuardianFor` already answers
///   null to — fail open, per its doc.
List<WidgetProfileOption> widgetProfileOptions({
  required List<Profile> profiles,
  required List<ProfileGuardian> guardiansForProfile,
  required String? currentUserId,
}) =>
    [
      for (final profile in profiles)
        if (profile.archivedAt == null)
          WidgetProfileOption(
            profileId: profile.id,
            profileName: profile.displayName,
            canQuickLog: canQuickLogFor(
              guardians: guardiansForProfile,
              currentUserId: currentUserId,
            ),
          ),
    ];

/// The write-time role rule for one profile: `true` unless this operator's
/// accepted role is a known `viewer`. Used both when publishing the
/// payload (the rendered button) and — the load-bearing call — inside the
/// executor, against freshly-read rows, so a value that crossed the widget
/// boundary can never authorize a write.
bool canQuickLogFor({
  required List<ProfileGuardian> guardians,
  required String? currentUserId,
}) =>
    acceptedGuardianFor(guardians, currentUserId)?.role.canLog ?? true;
