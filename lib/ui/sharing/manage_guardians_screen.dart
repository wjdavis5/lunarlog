/// Screen for viewing, inviting, and revoking caregivers for a profile (U8;
/// R1, R3, R4, R6, R8). Guardian rows come from [ProfileGuardiansRepository]
/// (R14/R16): no Drift row type crosses into this file.
library;

import 'package:flutter/material.dart';

import '../../data/repositories/profile_guardians_repository.dart';
import '../../domain/models/profile.dart';
import '../../domain/models/profile_guardian.dart';
import '../../domain/notifications/notification_preferences_service.dart';
import '../../domain/sharing/sharing_service.dart';
import 'invite_guardian_dialog.dart';
import 'notification_preferences_screen.dart';

class ManageGuardiansScreen extends StatefulWidget {
  const ManageGuardiansScreen({
    super.key,
    required this.profile,
    required this.guardiansRepository,
    required this.sharingService,
    required this.currentUserId,
    this.notificationPreferencesService,
  });

  final Profile profile;
  final ProfileGuardiansRepository guardiansRepository;
  final SharingService sharingService;

  /// The signed-in user's id, required for role gating (U8): viewers and
  /// caregivers never see the invite action or revocation controls.
  final String? currentUserId;

  /// Issue #5, U8: when present, an AppBar "Notifications" action opens
  /// [NotificationPreferencesScreen]. Null (an unconfigured build, or a
  /// platform/build with push unavailable) hides the action entirely - this
  /// is what keeps R17 true with zero conditionals in the caller.
  final NotificationPreferencesService? notificationPreferencesService;

  @override
  State<ManageGuardiansScreen> createState() => _ManageGuardiansScreenState();
}

class _ManageGuardiansScreenState extends State<ManageGuardiansScreen> {
  /// Every guardian row for this profile, any status; null means the
  /// initial pull hasn't landed locally yet (#13). Nothing writes a local
  /// guardian row when a profile is created, so a freshly created or
  /// not-yet-synced profile has zero rows here — that must not be read as
  /// "synced, and the caller isn't a manager" (see [_callerRoleOf] and the
  /// FAB gate below, which only hide controls once rows have actually
  /// arrived).
  Stream<List<ProfileGuardian>?> get _guardianRows =>
      widget.guardiansRepository
          .watchForProfile(widget.profile.id)
          .map((rows) => rows.isEmpty ? null : rows);

  List<ProfileGuardian> _acceptedOf(List<ProfileGuardian>? rows) =>
      (rows ?? const [])
          .where((g) => g.status == GuardianStatus.accepted)
          .toList();

  /// The caller's own accepted role on this profile, or null when the
  /// caller is not an active guardian, is unknown, or [rows] hasn't
  /// synced yet.
  GuardianRole? _callerRoleOf(List<ProfileGuardian>? rows) {
    if (rows == null) return null;
    final uid = widget.currentUserId;
    if (uid == null) return null;
    for (final g in _acceptedOf(rows)) {
      if (g.userId == uid) return g.role;
    }
    return null;
  }

  /// R3/R4 revocation authority: a primary guardian may leave only when
  /// another accepted primary guardian remains — the server rejects a
  /// sole primary guardian's self-leave with
  /// `object_not_in_prerequisite_state` (#5); any other caller may always
  /// leave; the primary guardian may revoke anyone; a co-parent may
  /// revoke caregivers and viewers only.
  bool _canRevoke(
    ProfileGuardian guardian,
    GuardianRole? callerRole,
    List<ProfileGuardian> activeGuardians,
  ) {
    if (callerRole == null) return false;
    final isSelf = guardian.userId == widget.currentUserId;
    if (isSelf) {
      if (callerRole != GuardianRole.primaryGuardian) return true;
      return activeGuardians.any((g) =>
          g.role == GuardianRole.primaryGuardian &&
          g.userId != widget.currentUserId);
    }
    if (callerRole == GuardianRole.primaryGuardian) return true;
    if (callerRole == GuardianRole.coParent) {
      return guardian.role != GuardianRole.primaryGuardian &&
          guardian.role != GuardianRole.coParent;
    }
    return false;
  }

  /// Best-effort accurate messaging for the self-leave-as-sole-primary
  /// race (#5): the button is already hidden once the client knows the
  /// caller is the only accepted primary guardian (see [_canRevoke]), but
  /// a concurrent revoke on another device can still make that true
  /// between the tap and this RPC call landing. [SharingFailure] has no
  /// dedicated case for the server's `object_not_in_prerequisite_state`
  /// here — adding one belongs to the sharing service, which this pass
  /// doesn't own — so this infers the scenario from context instead of
  /// the raw error code: only a self-leave attempt by a primary guardian
  /// can hit that specific rejection.
  String _revokeErrorMessage(Object error, ProfileGuardian guardian) {
    final isSelfPrimaryLeave = guardian.userId == widget.currentUserId &&
        guardian.role == GuardianRole.primaryGuardian;
    if (isSelfPrimaryLeave) {
      return "You're now the only primary guardian, so you can't leave. "
          'Add another primary guardian first, then try again.';
    }
    if (error is SharingUnauthorizedFailure) {
      return 'You do not have permission for this action.';
    }
    return 'Failed to remove guardian. Check connection.';
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_revokeErrorMessage(e, guardian))),
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

    final notificationPreferencesService = widget.notificationPreferencesService;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.profile.displayName} Caregivers'),
        actions: [
          if (notificationPreferencesService != null)
            IconButton(
              key: const ValueKey('notifications-action'),
              tooltip: 'Notifications',
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NotificationPreferencesScreen(
                    profile: widget.profile,
                    preferencesService: notificationPreferencesService,
                  ),
                ),
              ),
            ),
        ],
      ),
      // U8: only the primary guardian and co-parents can invite; the
      // server enforces it too, so the button is not even offered. Rows
      // still null (#13, not yet pulled) leaves the FAB visible — the
      // same default as before role gating existed — until we actually
      // know the caller isn't a manager.
      // A nested StreamBuilder keeps the same proven-settling structure
      // as the body below.
      floatingActionButton:
          StreamBuilder<List<ProfileGuardian>?>(
        stream: _guardianRows,
        builder: (context, snapshot) {
          final rows = snapshot.data;
          final callerRole = _callerRoleOf(rows);
          final knownNonManager =
              rows != null && callerRole?.canManageGuardians != true;
          if (knownNonManager) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            onPressed: _openInviteDialog,
            icon: const Icon(Icons.person_add),
            label: const Text('Invite Caregiver'),
          );
        },
      ),
      body: StreamBuilder<List<ProfileGuardian>?>(
        stream: _guardianRows,
        builder: (context, snapshot) {
          final rows = snapshot.data;
          final activeGuardians = _acceptedOf(rows);
          final callerRole = _callerRoleOf(rows);

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
            itemBuilder: (context, index) => _guardianTile(
              context,
              activeGuardians[index],
              callerRole,
              activeGuardians,
            ),
          );
        },
      ),
    );
  }

  Widget _guardianTile(
    BuildContext context,
    ProfileGuardian guardian,
    GuardianRole? callerRole,
    List<ProfileGuardian> activeGuardians,
  ) {
    final theme = Theme.of(context);
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
      trailing: _canRevoke(guardian, callerRole, activeGuardians)
          ? IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: isMe ? 'Leave profile' : 'Remove caregiver',
              onPressed: () => _revoke(guardian),
            )
          : null,
    );
  }
}
