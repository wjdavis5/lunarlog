/// Profile picker (home when no valid active profile): active profiles by
/// sort order, tap to make active; rename/archive from the row menu; archived
/// profiles live in a collapsed section at the bottom with one-tap unarchive.
/// The app bar carries the sync status glyph when the build has a sync
/// engine (U6); tapping it opens Settings.
///
/// Issue #126: active profiles are grouped into "My profiles" (held as
/// primary guardian, or not yet known) and "Shared with me" (held via
/// membership, with the operator's role shown). A profile with more than
/// one accepted guardian carries a small shared indicator, and a profile
/// with an outstanding invitation carries a badge — both without opening
/// any menu. Badges are best-effort: offline they render badge-free with
/// no error and no spinner.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/drift_onboarding_cycle_answers_recorder.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/onboarding/onboarding_cycle_answers.dart';
import 'package:lunarlog/domain/sharing/sharing_overview.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/profiles/birth_control_choices.dart';
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
import 'package:lunarlog/ui/sharing/open_manage_guardians.dart';
import 'package:lunarlog/ui/sharing/profile_sharing_tile.dart';
import 'package:lunarlog/ui/sharing/sharing_overview_controller.dart';
import 'package:provider/provider.dart';

String formatCreatedDate(DateTime utc) {
  final local = utc.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

class ProfilePickerScreen extends StatefulWidget {
  const ProfilePickerScreen({super.key});

  @override
  State<ProfilePickerScreen> createState() => _ProfilePickerScreenState();
}

class _ProfilePickerScreenState extends State<ProfilePickerScreen> {
  SharingOverviewController? _overview;

  @override
  void initState() {
    super.initState();
    final storage = Provider.of<LunarLogStorage?>(context, listen: false);
    if (storage != null) {
      final controller = SharingOverviewController(
        storage: storage,
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
    final controller = context.watch<ProfileController>();
    final active = controller.activeProfiles;
    final archived = controller.archivedProfiles;
    final hasSync = Provider.of<SyncStatusController?>(context) != null;
    void openSettings() => pushNamedScreen<void>(context, kRouteSettingsScreen);
    final overview = _overview;
    if (overview != null) {
      overview.observeProfiles([for (final profile in active) profile.id]);
    }
    final sharing = Provider.of<SharingService?>(context);
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
                ..._activeRows(context, overview, sharing, active),
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

  /// Active rows partitioned into "My profiles" and "Shared with me".
  /// Without sharing state (unconfigured build, or nobody shared with
  /// you) this is exactly the old flat list — no headers.
  List<Widget> _activeRows(
    BuildContext context,
    SharingOverviewController? overview,
    SharingService? sharing,
    List<Profile> active,
  ) {
    if (overview == null) {
      return [for (final profile in active) _row(context, null, sharing, profile)];
    }
    final owned = [
      for (final profile in active)
        if (overview.infoFor(profile.id).group == ProfileSharingGroup.owned)
          profile,
    ];
    final shared = [
      for (final profile in active)
        if (overview.infoFor(profile.id).group ==
            ProfileSharingGroup.sharedWithMe)
          profile,
    ];
    if (shared.isEmpty) {
      return [for (final profile in owned) _row(context, overview, sharing, profile)];
    }
    return [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          'My profiles',
          key: ValueKey('my-profiles-header'),
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      for (final profile in owned) _row(context, overview, sharing, profile),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          'Shared with me',
          key: ValueKey('shared-with-me-header'),
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      for (final profile in shared) _row(context, overview, sharing, profile),
    ];
  }

  Widget _row(
    BuildContext context,
    SharingOverviewController? overview,
    SharingService? sharing,
    Profile profile,
  ) {
    final info = overview?.infoFor(profile.id) ?? const SharingProfileInfo.unknown();
    final roleSubtitle = SharingProfileInfo.roleSubtitle(info);
    return ProfileSharingTile(
      key: ValueKey('profile-row-${profile.id}'),
      profile: profile,
      info: info,
      sharingService: sharing,
      refreshToken: overview?.badgeEpoch ?? 0,
      subtitle: roleSubtitle ?? 'Created ${formatCreatedDate(profile.createdAt)}',
      onTap: () => context.read<ProfileController>().selectProfile(profile.id),
      trailing: PopupMenuButton<String>(
        tooltip: 'Profile actions',
        onSelected: (action) => _onRowAction(context, profile, action),
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'caregivers', child: Text('Caregivers')),
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'archive', child: Text('Archive')),
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
      // Returning from Manage Guardians may have cancelled an invitation:
      // refresh outside badges so the change surfaces without a restart.
      openManageGuardians(context, profile)
          ?.then((_) => _overview?.refreshBadges());
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
