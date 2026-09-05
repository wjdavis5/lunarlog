/// Profile picker (home when no valid active profile): active profiles by
/// sort order, tap to make active; rename/archive from the row menu; archived
/// profiles live in a collapsed section at the bottom with one-tap unarchive.
/// The app bar carries the sync status glyph when the build has a sync
/// engine (U6); tapping it opens Settings.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/ui/account/sync_status_tile.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_detail_screen.dart';
import 'package:lunarlog/ui/profiles/profile_dialogs.dart';
import 'package:lunarlog/ui/settings/settings_screen.dart';
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
    void openSettings() => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
        );
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
      body: ListView(
        children: [
          for (final profile in active)
            ListTile(
              title: Text(profile.displayName),
              subtitle: Text('Created ${formatCreatedDate(profile.createdAt)}'),
              onTap: () => controller.selectProfile(profile.id),
              trailing: PopupMenuButton<String>(
                tooltip: 'Profile actions',
                onSelected: (action) =>
                    _onRowAction(context, profile, action),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'caregivers', child: Text('Caregivers')),
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'archive', child: Text('Archive')),
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
                    subtitle:
                        Text('Created ${formatCreatedDate(profile.createdAt)}'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
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
    await controller.createProfile(
      displayName: result.displayName,
      isMinor: result.isMinor,
    );
  }

  Future<void> _onRowAction(
      BuildContext context, Profile profile, String action) async {
    final controller = context.read<ProfileController>();
    if (action == 'caregivers') {
      final storage = Provider.of<LunarLogStorage?>(context, listen: false);
      final sharing = Provider.of<SharingService?>(context, listen: false);
      if (storage != null && sharing != null) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ManageGuardiansScreen(
              profile: profile,
              storage: storage,
              sharingService: sharing,
              currentUserId:
                  context.read<AuthController?>()?.currentUserId,
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
      );
    } else if (action == 'archive') {
      if (await confirmArchiveProfile(context, profile)) {
        await controller.archiveProfile(profile.id);
      }
    }
  }
}
