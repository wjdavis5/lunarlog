/// Displays server-authoritative caregiver attribution for a day entry (U7; R10, R12).
library;

import 'package:flutter/material.dart';

import '../../../domain/models/profile_guardian.dart';

class CaregiverAttributionBadge extends StatelessWidget {
  const CaregiverAttributionBadge({
    super.key,
    required this.loggedByUserId,
    this.lastModifiedByUserId,
    this.currentUserId,
    this.guardians = const [],
  });

  final String? loggedByUserId;
  final String? lastModifiedByUserId;
  final String? currentUserId;
  final List<ProfileGuardian> guardians;

  String _formatUser(String userId) {
    if (currentUserId != null && userId == currentUserId) {
      return 'you';
    }
    final match = guardians.cast<ProfileGuardian?>().firstWhere(
          (g) => g?.userId == userId,
          orElse: () => null,
        );
    if (match != null) {
      if (match.displayName != null && match.displayName!.isNotEmpty) {
        return match.displayName!;
      }
      return match.role.label;
    }
    return 'Caregiver';
  }

  @override
  Widget build(BuildContext context) {
    if (loggedByUserId == null && lastModifiedByUserId == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isModified = lastModifiedByUserId != null &&
        loggedByUserId != null &&
        lastModifiedByUserId != loggedByUserId;

    final loggedByName = loggedByUserId != null ? _formatUser(loggedByUserId!) : null;
    final modifiedByName = isModified ? _formatUser(lastModifiedByUserId!) : null;

    final text = StringBuffer();
    if (loggedByName != null) {
      text.write('Logged by $loggedByName');
    }
    if (modifiedByName != null) {
      if (text.isNotEmpty) text.write(' • ');
      text.write('Modified by $modifiedByName');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_outline,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text.toString(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
