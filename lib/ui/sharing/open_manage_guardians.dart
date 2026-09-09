/// Shared push site for Manage Guardians (Issue #126).
///
/// The picker, the Settings family-sharing section, and the profile shared
/// chip all route to the same screen with the same provider-built
/// dependencies. Returns the navigation future so callers can refresh
/// outside badges when it completes, or null when the build cannot open
/// the screen at all (no storage or no sharing service — an unconfigured
/// build), in which case callers offer no navigation affordance.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/activity_feed_repository.dart';
import 'package:lunarlog/data/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/notifications/notification_preferences_service.dart';
import 'package:lunarlog/domain/sharing/ownership_transfer_service.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/routes.dart';
import 'package:lunarlog/ui/sharing/manage_guardians_screen.dart';
import 'package:provider/provider.dart';

Future<void>? openManageGuardians(BuildContext context, Profile profile) {
  final storage = Provider.of<LunarLogStorage?>(context, listen: false);
  final sharing = Provider.of<SharingService?>(context, listen: false);
  if (storage == null || sharing == null) return null;
  final ownershipTransfer =
      Provider.of<OwnershipTransferService?>(context, listen: false);
  final notificationPreferences =
      Provider.of<NotificationPreferencesService?>(context, listen: false);
  return Navigator.of(context).push<void>(
    buildNamedRoute<void>(
      name: kRouteManageGuardiansScreen,
      builder: (_) => ManageGuardiansScreen(
        profile: profile,
        guardiansRepository: ProfileGuardiansRepository(storage),
        sharingService: sharing,
        currentUserId:
            Provider.of<AuthController?>(context, listen: false)?.currentUserId,
        ownershipTransferService: ownershipTransfer,
        notificationPreferencesService: notificationPreferences,
        activityRepository: ActivityFeedRepository(storage),
      ),
    ),
  );
}
