/// Profile picker (home when no valid active profile): active profiles by
/// sort order, tap to make active; rename/archive from the row menu; archived
/// profiles live in a collapsed section at the bottom with one-tap unarchive.
/// The app bar carries the sync status glyph when the build has a sync
/// engine (U6); tapping it opens Settings.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/activity_feed_repository.dart';
import 'package:lunarlog/data/repositories/drift_onboarding_cycle_answers_recorder.dart';
import 'package:lunarlog/data/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/onboarding/onboarding_cycle_answers.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/profiles/birth_control_choices.dart';
import 'package:lunarlog/domain/notifications/notification_preferences_service.dart';
import 'package:lunarlog/domain/sharing/ownership_transfer_service.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/ui/account/sync_status_tile.dart';
import 'package:lunarlog/ui/components/empty_state.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_detail_screen.dart';
import 'package:lunarlog/ui/profiles/profile_dialogs.dart';
import 'package:lunarlog/ui/routes.dart';
import 'package:lunarlog/ui/sharing/manage_guardians_screen.dart';
import 'package:provider/provider.dart';

String formatCreatedDate(DateTime utc) {
  final local = utc.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

class ProfilePickerScreen extends StatelessWidget {
  const ProfilePickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ProfileController>();
    final active = controller.activeProfiles;
    final archived = controller.archivedProfiles;
    final hasSync = Provider.of<SyncStatusController?>(context) != null;
    void openSettings() => pushNamedScreen<void>(context, kRouteSettingsScreen);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profiles'),
        actions: [
          if (hasSync) SyncStatusGlyph(onPressed: openSettings),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: openSettings,
          ),
          IconButton(
            tooltip: 'Add profile',
            icon: const Icon(Icons.person_add),
            onPressed: () => _addProfile(context),
          ),
        ],
      ),
      body: active.isEmpty && archived.isEmpty
          ? EmptyState(
              key: const ValueKey('profile-picker-empty'),
              title: 'No profiles yet',
              body: 'Add a profile to start tracking.',
              primaryActionLabel: 'Add profile',
              onPrimaryAction: () => _addProfile(context),
            )
          : ListView(
              children: [
                for (final profile in active)
                  ListTile(
                    title: Text(profile.displayName),
                    subtitle: Text(
                        'Created ${formatCreatedDate(profile.createdAt)}'),
                    onTap: () => controller.selectProfile(profile.id),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Profile actions',
                      onSelected: (action) =>
                          _onRowAction(context, profile, action),
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                            value: 'caregivers', child: Text('Caregivers')),
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(
                            value: 'archive', child: Text('Archive')),
                      ],
                    ),
                  ),
                if (archived.isNotEmpty)
                  ExpansionTile(
                    key: const Key('archived-section'),
                    title: Text('Archived (${archived.length})'),
                    children: [
                      for (final profile in archived)
                        ListTile(
                          title: Text(profile.displayName),
                          subtitle: Text(
                              'Created ${formatCreatedDate(profile.createdAt)}'),
                          onTap: () => Navigator.of(context).push(
                            buildNamedRoute<void>(
                              name: kRouteProfileDetailScreen,
                              builder: (_) => ProfileDetailScreen(
                                profile: profile,
                                readOnly: true,
                              ),
                            ),
                          ),
                          trailing: IconButton(
                            tooltip: 'Unarchive',
                            icon: const Icon(Icons.unarchive),
                            onPressed: () =>
                                controller.unarchiveProfile(profile.id),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
    );
  }

  Future<void> _addProfile(BuildContext context) async {
    final controller = context.read<ProfileController>();
    final result = await showProfileEditDialog(context);
    if (result == null) return;
    final profile = await controller.createProfile(
      displayName: result.displayName,
      isMinor: result.isMinor,
      mode: result.mode,
      birthYear: result.birthYear,
      relationship: result.relationship,
    );
    if (!context.mounted) return;
    await _recordCycleAnswers(context, profile.id, result);
  }

  Future<void> _onRowAction(
      BuildContext context, Profile profile, String action) async {
    final controller = context.read<ProfileController>();
    if (action == 'caregivers') {
      final storage = Provider.of<LunarLogStorage?>(context, listen: false);
      final sharing = Provider.of<SharingService?>(context, listen: false);
      final ownershipTransfer =
          Provider.of<OwnershipTransferService?>(context, listen: false);
      if (storage != null && sharing != null) {
        Navigator.of(context).push(
          buildNamedRoute<void>(
            name: kRouteManageGuardiansScreen,
            builder: (_) => ManageGuardiansScreen(
              profile: profile,
              guardiansRepository: ProfileGuardiansRepository(storage),
              sharingService: sharing,
              currentUserId:
                  context.read<AuthController?>()?.currentUserId,
              ownershipTransferService: ownershipTransfer,
              notificationPreferencesService:
                  Provider.of<NotificationPreferencesService?>(
                      context, listen: false),
              activityRepository: ActivityFeedRepository(storage),
            ),
          ),
        );
      }
    } else if (action == 'rename') {
      final result = await showProfileEditDialog(context, existing: profile);
      if (result == null) return;
      await controller.renameProfile(
        profile,
        displayName: result.displayName,
        isMinor: result.isMinor,
        mode: result.mode,
        birthYear: result.birthYear,
        relationship: result.relationship,
      );
      if (!context.mounted) return;
      await _recordCycleAnswers(context, profile.id, result);
    } else if (action == 'archive') {
      if (await confirmArchiveProfile(context, profile)) {
        await controller.archiveProfile(profile.id);
      }
    }
  }

  /// Persists the two #216 onboarding answers that are editable from the
  /// profile edit dialog (life-stage mode and birth-control method)
  /// through the same recorder seam the first-run flow uses — no-op on a
  /// tree with no storage wired or when nothing changed.
  Future<void> _recordCycleAnswers(
    BuildContext context,
    String profileId,
    ProfileEditResult result,
  ) async {
    final storage = Provider.of<LunarLogStorage?>(context, listen: false);
    if (storage == null) return;
    final l10n = AppLocalizations.of(context);
    await DriftOnboardingCycleAnswersRecorder(storage).record(
      profileId,
      OnboardingCycleAnswers(
        lifecycleMode: result.lifecycleMode,
        birthControlMethod:
            birthControlStoredValue(result.birthControlChoice, l10n),
      ),
    );
  }
}
