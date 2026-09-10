/// Shared push site for Manage Guardians (Issue #126).
///
/// The picker, the Settings family-sharing section, and the profile shared
/// chip all route to the same screen with the same provider-built
/// dependencies. Returns the navigation future so callers can refresh
/// outside badges when it completes, or null when the build cannot open
/// the screen at all (no storage or no sharing service — an unconfigured
/// build), in which case callers offer no navigation affordance.
///
/// Issue #151 (merge integration): the same single route also carries the
/// prediction-connection wiring — the service and the publish-now callback
/// are read from the same provider scope here, so Manage Guardians'
/// "Predictions-only sharing" section is reachable from every entry point
/// and no caller needs its own second push of the screen.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/notifications/notification_preferences_service.dart';
import 'package:lunarlog/domain/repositories/activity_feed_repository.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/sharing/ownership_transfer_service.dart';
import 'package:lunarlog/domain/sharing/prediction_connection_service.dart';
import 'package:lunarlog/domain/sharing/prediction_projection_publisher.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/routes.dart';
import 'package:lunarlog/ui/sharing/manage_guardians_screen.dart';
import 'package:provider/provider.dart';

Future<void>? openManageGuardians(BuildContext context, Profile profile) {
  final guardiansRepository =
      Provider.of<ProfileGuardiansRepository?>(context, listen: false);
  final sharing = Provider.of<SharingService?>(context, listen: false);
  if (guardiansRepository == null || sharing == null) return null;
  final ownershipTransfer =
      Provider.of<OwnershipTransferService?>(context, listen: false);
  final notificationPreferences =
      Provider.of<NotificationPreferencesService?>(context, listen: false);
  return Navigator.of(context).push<void>(
    buildNamedRoute<void>(
      name: kRouteManageGuardiansScreen,
      builder: (_) => ManageGuardiansScreen(
        profile: profile,
        guardiansRepository: guardiansRepository,
        sharingService: sharing,
        currentUserId:
            Provider.of<AuthController?>(context, listen: false)?.currentUserId,
        ownershipTransferService: ownershipTransfer,
        predictionConnectionService:
            Provider.of<PredictionConnectionService?>(context, listen: false),
        onPredictionConnectionChanged: (profileId) =>
            Provider.of<PredictionProjectionPublisher?>(
                  context,
                  listen: false,
                )
                ?.publishNow(profileId),
        notificationPreferencesService: notificationPreferences,
        activityRepository:
            Provider.of<ActivityFeedRepository?>(context, listen: false),
      ),
    ),
  );
}
