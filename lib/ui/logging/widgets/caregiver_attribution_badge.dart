/// Displays server-authoritative caregiver attribution for a day entry (U7; R10, R12).
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/l10n/guardian_role_copy.dart';

import '../../../domain/models/profile_guardian.dart';

class CaregiverAttributionBadge extends StatelessWidget {
  const CaregiverAttributionBadge({
    super.key,
    required this.loggedByUserId,
    this.lastModifiedByUserId,
    this.currentUserId,
    this.guardians = const [],
    this.source = 'manual',
  });

  final String? loggedByUserId;
  final String? lastModifiedByUserId;
  final String? currentUserId;
  final List<ProfileGuardian> guardians;

  /// Raw `day_entries.source`/`observations.source` string (Issue #159).
  /// Any non-`manual` value renders as an import badge instead of guardian
  /// attribution — see [_sourceLabel] and the acceptance criteria: never
  /// fall back to "logged by \<guardian\>" for a row whose source isn't
  /// manual.
  final String source;

  String _formatUser(AppLocalizations l10n, String userId) {
    if (currentUserId != null && userId == currentUserId) {
      return l10n.caregiverAttributionYou;
    }
    final match = guardians.cast<ProfileGuardian?>().firstWhere(
          (g) => g?.userId == userId,
          orElse: () => null,
        );
    if (match != null) {
      if (match.displayName != null && match.displayName!.isNotEmpty) {
        return match.displayName!;
      }
      return guardianRoleLabel(l10n, match.role);
    }
    return l10n.caregiverAttributionGuardianFallback;
  }

  /// Issue #159: one label per non-`manual` source, "Imported" as the
  /// generic fallback for a value this build doesn't recognise (a future
  /// addition, a row from a newer client) — mirrors `ObservationSource`'s
  /// degrade-rather-than-throw precedent.
  String _sourceLabel(AppLocalizations l10n, String source) =>
      switch (source) {
        'clue_import' => l10n.caregiverAttributionImportedClue,
        'healthkit' || 'apple_health' => l10n.caregiverAttributionImportedHealth,
        'health_connect' =>
          l10n.caregiverAttributionImportedHealthConnect,
        'file_import' => l10n.caregiverAttributionImportedFile,
        'wearable' => l10n.caregiverAttributionImportedWearable,
        _ => l10n.caregiverAttributionImportedGeneric,
      };

  String _attributionText(AppLocalizations l10n) {
    final isModified = lastModifiedByUserId != null &&
        loggedByUserId != null &&
        lastModifiedByUserId != loggedByUserId;
    final loggedByName =
        loggedByUserId != null ? _formatUser(l10n, loggedByUserId!) : null;
    final modifiedByName =
        isModified ? _formatUser(l10n, lastModifiedByUserId!) : null;

    final text = StringBuffer();
    if (loggedByName != null) {
      text.write(l10n.caregiverAttributionLoggedBy(loggedByName));
    }
    if (modifiedByName != null) {
      if (text.isNotEmpty) text.write(' • ');
      text.write(l10n.caregiverAttributionModifiedBy(modifiedByName));
    }
    return text.toString();
  }

  @override
  Widget build(BuildContext context) {
    final isImported = source != 'manual';
    if (!isImported && loggedByUserId == null && lastModifiedByUserId == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // Issue #159 (acceptance criteria): a non-manual row never falls back
    // to "logged by <guardian>" — the import source is the whole story.
    final text = isImported
        ? _sourceLabel(l10n, source)
        : _attributionText(l10n);

    return Semantics(
      // #138: the badge is one announcement ("Logged by Dad"), not a
      // decorative icon followed by stray text — container keeps it a
      // single focus stop, and the icon inside is explicitly decorative.
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.people_outline,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              // #138 (AC4): no ellipsis — at 200% text scale the badge
              // wraps inside the heading's Wrap instead of truncating who
              // logged the entry, which is the one fact this badge exists
              // to carry.
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
