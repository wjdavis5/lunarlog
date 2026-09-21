/// Issue #130: the day sheet's quiet, dismissible same-date merge notice.
///
/// One row per recorded discard (`day_entry_merge_events`) for the date,
/// shown to EVERY guardian — the surviving guardian should know their
/// value overwrote something, not only the loser. Informational tone, one
/// sentence per event, never an error. The losing author additionally
/// sees their discarded text and a tap-to-restore affordance (the event
/// row retains the text for the 30-day recovery window).
///
/// Never in a push notification, never in a crash report: the section
/// renders in-app only, and the retained text's key is deny-listed in
/// `lib/observability/scrub.dart`'s `sentryDenyListedKeys`.
///
/// Guardian-name resolution mirrors `CaregiverAttributionBadge`'s
/// (display name, else role label, else a generic word; 'you' for the
/// signed-in user) — display attribution only, never a permission input.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/l10n/guardian_role_copy.dart';

import '../../../domain/logging/day_entry_merge_event.dart';
import '../../../domain/models/profile_guardian.dart';

class DayEntryMergeNoticeSection extends StatelessWidget {
  const DayEntryMergeNoticeSection({
    super.key,
    required this.events,
    required this.currentUserId,
    required this.guardians,
    required this.onDismiss,
    required this.onRestoreNote,
    required this.onRestoreFlow,
  });

  /// The undismissed, window-filtered merge disclosures for this date
  /// (empty renders nothing — a tags-only merge or a same-id convergence
  /// never produces an event, so neither ever shows a notice).
  final List<DayEntryMergeEvent> events;

  /// The signed-in user's id, or null while signed out: decides whether
  /// the recovery affordance renders (only the losing author may restore
  /// their own discarded value).
  final String? currentUserId;

  /// The profile's guardian list, for resolving author ids to names.
  final List<ProfileGuardian> guardians;

  /// Dismisses one notice — device-local by contract; the callback the day
  /// sheet wires never touches the synced row.
  final void Function(DayEntryMergeEvent event) onDismiss;

  /// Restores the losing author's discarded note text into the note field
  /// (only offered when [currentUserId] is the losing author).
  final void Function(DayEntryMergeEvent event) onRestoreNote;

  /// Restores the losing author's discarded flow level into the flow
  /// selection (same gating as [onRestoreNote]).
  final void Function(DayEntryMergeEvent event) onRestoreFlow;

  String _formatUser(AppLocalizations l10n, String? userId) {
    if (userId == null) return l10n.mergeNoticeAnotherGuardian;
    if (currentUserId != null && userId == currentUserId) {
      return l10n.mergeNoticeYou;
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
    return l10n.mergeNoticeAnotherGuardian;
  }

  /// The possessive form for a notice sentence: "your" for the signed-in
  /// user (never "you's"), `` '<name>'s `` otherwise.
  String _possessive(AppLocalizations l10n, String? userId) {
    final user = _formatUser(l10n, userId);
    if (currentUserId != null && userId == currentUserId) {
      return l10n.mergeNoticeYour;
    }
    if (userId == null) return l10n.mergeNoticeAnotherGuardianPossessive;
    return '$user\'s';
  }

  /// One informational sentence naming the field that lost a value and
  /// whose value was kept (AC).
  String _noticeText(AppLocalizations l10n, DayEntryMergeEvent event) {
    final winner = _possessive(l10n, event.winningAuthorUserId);
    final loser = _possessive(l10n, event.losingAuthorUserId);
    return switch (event.field) {
      DayEntryMergeEventField.note => l10n.mergeNoticeNoteBody(winner, loser),
      DayEntryMergeEventField.flow => l10n.mergeNoticeFlowBody(winner, loser),
      // Issue #871: never reaches this section (filtered out of the day
      // sheet's read — a guardian-note convergence is not a day-entry
      // merge), but the closed enum keeps the switch exhaustive.
      DayEntryMergeEventField.guardianNote => l10n.mergeNoticeGuardianNoteBody,
    };
  }

  bool _isLosingAuthor(DayEntryMergeEvent event) =>
      currentUserId != null && event.losingAuthorUserId == currentUserId;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const ValueKey('merge-notice-section'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final event in events)
            _MergeNoticeRow(
              key: ValueKey('merge-notice-${event.id}'),
              text: _noticeText(l10n, event),
              lostText: event.field == DayEntryMergeEventField.note
                  ? event.losingValueText
                  : null,
              canRestore: _isLosingAuthor(event),
              restoreLabel: switch (event.field) {
                DayEntryMergeEventField.note => l10n.mergeNoticeRestoreNote,
                DayEntryMergeEventField.flow => l10n.mergeNoticeRestoreFlow,
                DayEntryMergeEventField.guardianNote =>
                  l10n.mergeNoticeRestoreNote,
              },
              onDismiss: () => onDismiss(event),
              onRestore: () => switch (event.field) {
                    DayEntryMergeEventField.note => onRestoreNote(event),
                    DayEntryMergeEventField.flow => onRestoreFlow(event),
                    DayEntryMergeEventField.guardianNote => onRestoreNote(event),
                  },
            ),
        ],
      ),
    );
  }
}

class _MergeNoticeRow extends StatelessWidget {
  const _MergeNoticeRow({
    super.key,
    required this.text,
    required this.lostText,
    required this.canRestore,
    required this.restoreLabel,
    required this.onDismiss,
    required this.onRestore,
  });

  final String text;
  final String? lostText;
  final bool canRestore;
  final String restoreLabel;
  final VoidCallback onDismiss;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.info_outline,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                // The losing author's recovery surface: the discarded text
                // itself (kept for exactly this), with a tap-to-restore
                // affordance. Other guardians see the one-sentence notice
                // only.
                if (canRestore && lostText != null && lostText!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    lostText!,
                    key: const ValueKey('merge-notice-lost-text'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                if (canRestore)
                  TextButton.icon(
                    key: ValueKey('merge-notice-restore'),
                    onPressed: onRestore,
                    icon: const Icon(Icons.restore, size: 16),
                    label: Text(restoreLabel),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('merge-notice-dismiss'),
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 16),
            tooltip: AppLocalizations.of(context).mergeNoticeDismissTooltip,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
