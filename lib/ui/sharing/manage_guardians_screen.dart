/// Screen for viewing, inviting, and revoking caregivers for a profile (U8; R1, R3, R4, R6, R8).
library;

import 'package:flutter/material.dart';

import '../../data/db/storage.dart';
import '../../data/repositories/mappers.dart';
import '../../domain/models/profile.dart';
import '../../domain/models/profile_guardian.dart';
import '../../domain/sharing/sharing_service.dart';
import 'invite_guardian_dialog.dart';

class ManageGuardiansScreen extends StatefulWidget {
  const ManageGuardiansScreen({
    super.key,
    required this.profile,
    required this.storage,
    required this.sharingService,
    required this.currentUserId,
  });

  final Profile profile;
  final LunarLogStorage storage;
  final SharingService sharingService;

  /// The signed-in user's id, required for role gating (U8): viewers and
  /// caregivers never see the invite action or revocation controls.
  final String? currentUserId;

  @override
  State<ManageGuardiansScreen> createState() => _ManageGuardiansScreenState();
}

class _ManageGuardiansScreenState extends State<ManageGuardiansScreen> {
  Stream<List<ProfileGuardian>> get _activeGuardians =>
      widget.storage.watchGuardiansForProfile(widget.profile.id).map((rows) =>
          rows
              .map(profileGuardianToDomain)
              .where((g) => g.status == GuardianStatus.accepted)
              .toList());

  /// The caller's own accepted role on this profile, or null when the
  /// caller is not an active guardian (or is unknown).
  GuardianRole? _callerRoleOf(List<ProfileGuardian> activeGuardians) {
    final uid = widget.currentUserId;
    if (uid == null) return null;
    for (final g in activeGuardians) {
      if (g.userId == uid) return g.role;
    }
    return null;
  }

  /// R3/R4 revocation authority: anyone may leave (the server blocks the
  /// sole primary guardian); the primary guardian may revoke anyone; a
  /// co-parent may revoke caregivers and viewers only.
  bool _canRevoke(ProfileGuardian guardian, GuardianRole? callerRole) {
    if (callerRole == null) return false;
    if (guardian.userId == widget.currentUserId) return true;
    if (callerRole == GuardianRole.primaryGuardian) return true;
    if (callerRole == GuardianRole.coParent) {
      return guardian.role != GuardianRole.primaryGuardian &&
          guardian.role != GuardianRole.coParent;
    }
    return false;
  }

  Future<void> _revoke(ProfileGuardian guardian) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${guardian.displayName ?? guardian.role.label}?'),
        content: Text(
          guardian.userId == widget.currentUserId
              ? 'You will leave this profile and no longer receive updates or sync its entries.'
              : 'This caregiver will lose access to ${widget.profile.displayName}\'s calendar and entries.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await widget.sharingService.revokeGuardian(
        profileId: widget.profile.id,
        targetUserId: guardian.userId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed ${guardian.displayName ?? guardian.role.label}')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to remove guardian. Check connection.')),
        );
      }
    }
  }

  void _openInviteDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => InviteGuardianDialog(
        profileId: widget.profile.id,
        profileName: widget.profile.displayName,
        sharingService: widget.sharingService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.profile.displayName} Caregivers'),
      ),
      // U8: only the primary guardian and co-parents can invite; the
      // server enforces it too, so the button is not even offered.
      // A nested StreamBuilder keeps the same proven-settling structure
      // as the body below.
      floatingActionButton:
          StreamBuilder<List<ProfileGuardian>>(
        stream: _activeGuardians,
        builder: (context, snapshot) {
          final callerRole = _callerRoleOf(snapshot.data ?? const []);
          if (callerRole?.canManageGuardians != true) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            onPressed: _openInviteDialog,
            icon: const Icon(Icons.person_add),
            label: const Text('Invite Caregiver'),
          );
        },
      ),
      body: StreamBuilder<List<ProfileGuardian>>(
        stream: _activeGuardians,
        builder: (context, snapshot) {
          final activeGuardians = snapshot.data ?? const [];
          final callerRole = _callerRoleOf(activeGuardians);

          if (activeGuardians.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline, size: 48, color: theme.colorScheme.outline),
                  const SizedBox(height: 12),
                  Text('No caregivers linked yet', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Invite a co-parent or caregiver to sync and share tracking.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: activeGuardians.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final guardian = activeGuardians[index];
              final isMe =
                  widget.currentUserId != null && guardian.userId == widget.currentUserId;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isMe
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    isMe ? Icons.person : Icons.family_restroom,
                    color: isMe
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                title: Row(
                  children: [
                    Text(
                      guardian.displayName?.isNotEmpty == true
                          ? guardian.displayName!
                          : guardian.role.label,
                      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Text('(you)', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
                    ],
                  ],
                ),
                subtitle: Text(guardian.role.label),
                trailing: _canRevoke(guardian, callerRole)
                    ? IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        tooltip: isMe ? 'Leave profile' : 'Remove caregiver',
                        onPressed: () => _revoke(guardian),
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}
