/// The Pregnancy-mode Cycle View card (Issue #192): replaces the ordinary
/// cycle countdown (which never renders in Pregnancy mode — prediction is
/// suppressed, #528) with a week-of-pregnancy counter derived from the
/// synced `profile_modes.estimated_due_date` and the days remaining to
/// it. Pure display: the week math lives in `lib/domain/pregnancy.dart`
/// (`pregnancyWeekOf`) and is unit-tested there; this widget only renders
/// what the caller computed.
///
/// A null due date renders the quiet "not recorded" line instead — an
/// honest no-data state, never a fabricated week.
library;

import 'package:flutter/material.dart';

import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/theme/tokens.dart';

class PregnancyCard extends StatelessWidget {
  const PregnancyCard({
    super.key,
    this.week,
    this.dueDateText,
  });

  /// The gestational week (0-based, `pregnancyWeekOf`), or null when no
  /// due date is recorded.
  final int? week;

  /// The localized due-date text (month-day-year), or null alongside
  /// [week].
  final String? dueDateText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final week = this.week;
    final dueDateText = this.dueDateText;
    return Card(
      key: const ValueKey('pregnancy-card'),
      child: Padding(
        padding: const EdgeInsets.all(LLSpace.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (week != null) ...[
              Text(
                l10n.pregnancyWeekTitle(week),
                key: const ValueKey('pregnancy-week'),
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: LLSpace.space1),
              Text(
                l10n.pregnancyDueOn(dueDateText ?? ''),
                key: const ValueKey('pregnancy-due-date'),
                style: theme.textTheme.bodyMedium,
              ),
            ] else
              Text(
                l10n.pregnancyDueDateMissing,
                key: const ValueKey('pregnancy-due-date-missing'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
