/// "Family & sharing" section for Settings (Issue #126, AC1).
///
/// Lists every profile with its sharing state — owned versus shared with
/// you, your role on the latter, the co-managed indicator, and the
/// outstanding-invitation badge — each row routing to its Manage Guardians
/// screen. Self-hiding: renders nothing on an unconfigured build (no
/// sharing service), with no profiles, or before the local lists land, so
/// existing Settings trees are untouched. Invite/revoke controls never live
/// here; a viewer sees the same rows read-only and Manage Guardians gates
/// its own actions. Badge rows are best-effort: offline they render
/// badge-free with no error and no spinner.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/sharing/sharing_overview.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/sharing/open_manage_guardians.dart';
import 'package:lunarlog/ui/sharing/profile_sharing_tile.dart';
import 'package:lunarlog/ui/sharing/sharing_overview_controller.dart';
import 'package:provider/provider.dart';

class FamilySharingSection extends StatefulWidget {
  const FamilySharingSection({super.key});

  @override
  State<FamilySharingSection> createState() => _FamilySharingSectionState();
}

class _FamilySharingSectionState extends State<FamilySharingSection> {
  SharingOverviewController? _overview;

  @override
  void initState() {
    super.initState();
    final guardiansRepository =
        Provider.of<ProfileGuardiansRepository?>(context, listen: false);
    if (guardiansRepository != null) {
      final controller = SharingOverviewController(
        guardiansRepository: guardiansRepository,
        currentUserId: Provider.of<AuthController?>(context, listen: false)
            ?.currentUserId,
      );
      controller.addListener(_onOverviewChanged);
      _overview = controller;
    }
  }

  void _onOverviewChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _overview?.removeListener(_onOverviewChanged);
    _overview?.dispose();
    _overview = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    final sharing = Provider.of<SharingService?>(context);
    final profilesRepository = Provider.of<ProfilesRepository?>(context);
    if (overview == null || sharing == null || profilesRepository == null) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<List<Profile>>(
      stream: profilesRepository.watch(),
      builder: (context, snapshot) {
        final profiles = snapshot.data;
        if (profiles == null || profiles.isEmpty) {
          return const SizedBox.shrink();
        }
        overview.observeProfiles([for (final p in profiles) p.id]);
        final owned = [
          for (final p in profiles)
            if (overview.infoFor(p.id).group == ProfileSharingGroup.owned) p,
        ];
        final shared = [
          for (final p in profiles)
            if (overview.infoFor(p.id).group ==
                ProfileSharingGroup.sharedWithMe)
              p,
        ];
        return Column(
          key: const ValueKey('family-sharing-section'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Family & sharing',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            for (final profile in [...owned, ...shared])
              _row(context, overview, sharing, profile),
          ],
        );
      },
    );
  }

  Widget _row(
    BuildContext context,
    SharingOverviewController overview,
    SharingService sharing,
    Profile profile,
  ) {
    final info = overview.infoFor(profile.id);
    return ProfileSharingTile(
      key: ValueKey('family-sharing-row-${profile.id}'),
      profile: profile,
      info: info,
      sharingService: sharing,
      refreshToken: overview.badgeEpoch,
      subtitle: SharingProfileInfo.roleSubtitle(info),
      onTap: () => openManageGuardians(context, profile)
          ?.then((_) => overview.refreshBadges()),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}
