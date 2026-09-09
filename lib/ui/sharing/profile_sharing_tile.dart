/// One profile row for sharing-discoverability surfaces (Issue #126).
///
/// Assembles the co-managed indicator (more than one accepted guardian —
/// visible without opening any menu) and the outstanding-invitation badge
/// next to the caller's own trailing control (the picker's row menu, a
/// settings chevron, or nothing). Invite/revoke controls never live here:
/// viewers and caregivers see the same shared state, and management stays
/// inside Manage Guardians behind its role ladder.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/sharing/sharing_overview.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/ui/sharing/pending_invite_badge.dart';

class ProfileSharingTile extends StatelessWidget {
  const ProfileSharingTile({
    super.key,
    required this.profile,
    required this.info,
    required this.sharingService,
    required this.refreshToken,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  final Profile profile;
  final SharingProfileInfo info;

  /// Null when the build has no sharing service (unconfigured build): the
  /// row still renders its local shared state, but no badge is fetched.
  final SharingService? sharingService;

  /// From the owning screen's [SharingOverviewController.badgeEpoch].
  final int refreshToken;

  final String? subtitle;
  final VoidCallback? onTap;

  /// The caller's own trailing control, rendered after the indicator and
  /// badge (e.g. the picker's row menu).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final showBadge = sharingService != null &&
        SharingProfileInfo.canShowPendingBadge(info.myRole);
    final showIndicator = info.isCoManaged;
    final extraTrailing = trailing;
    return ListTile(
      title: Text(profile.displayName),
      subtitle: subtitle == null ? null : Text(subtitle!),
      onTap: onTap,
      trailing: showBadge || showIndicator || extraTrailing != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showIndicator)
                  Tooltip(
                    message: 'Shared · ${info.acceptedCount} guardians',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.people_outline,
                          key: ValueKey('shared-indicator-${profile.id}'),
                        ),
                        const SizedBox(width: 2),
                        Text('${info.acceptedCount}'),
                      ],
                    ),
                  ),
                if (showBadge) ...[
                  const SizedBox(width: 8),
                  PendingInviteBadge(
                    key: ValueKey('pending-invite-badge-${profile.id}'),
                    profileId: profile.id,
                    sharingService: sharingService!,
                    refreshToken: refreshToken,
                  ),
                ],
                if (extraTrailing != null) ...[
                  const SizedBox(width: 4),
                  extraTrailing,
                ],
              ],
            )
          : null,
    );
  }
}
