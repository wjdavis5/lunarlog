/// The overview's read-only "Apple Health noticed…" card (Issue #799,
/// deferred from #217).
///
/// It renders the device-local snapshot [LocalHealthDeviationService]
/// persisted after a health-store import: Apple's own four computed
/// cycle-deviation types, shown as a **clearly labelled second opinion**
/// next to — never merged into — lunarlog's own prediction. Apple derives
/// them from whatever the user logged in Apple Health, which may differ
/// from what lunarlog holds, so the copy says explicitly that these are
/// Apple's estimates and offers a quiet dismissal; the card never changes a
/// prediction, a day entry, or anything in the health store.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/health/health_deviation.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/l10n/dates.dart' as dates;

class HealthDeviationCard extends StatelessWidget {
  const HealthDeviationCard({
    super.key,
    required this.snapshot,
    required this.onDismiss,
  });

  final HealthDeviationSnapshot snapshot;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final locale = dates.calendarLocale(context);
    String fmt(LocalDate date) =>
        dates.formatLocalDateMonthDayYear(date, locale: locale);
    return Card(
      key: const ValueKey('health-deviation-card'),
      color: theme.colorScheme.surfaceContainerHighest,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    l10n.healthDeviationCardTitle,
                    key: const ValueKey('health-deviation-card-title'),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  key: const ValueKey('health-deviation-dismiss'),
                  tooltip: l10n.healthDeviationDismiss,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onDismiss,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                l10n.healthDeviationCardSubtitle,
                key: const ValueKey('health-deviation-card-subtitle'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final insight in snapshot.insights)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: Text(
                  l10n.healthDeviationLine(
                    _kindLabel(insight.kind, l10n),
                    insight.start == insight.end
                        ? l10n.healthDeviationRangeSingle(fmt(insight.start))
                        : l10n.healthDeviationRange(
                            fmt(insight.start),
                            fmt(insight.end),
                          ),
                  ),
                  key: ValueKey('health-deviation-${insight.kind.wire}'),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _kindLabel(HealthDeviationKind kind, AppLocalizations l10n) =>
      switch (kind) {
        HealthDeviationKind.irregularMenstrualCycles =>
          l10n.healthDeviationKindIrregular,
        HealthDeviationKind.infrequentMenstrualCycles =>
          l10n.healthDeviationKindInfrequent,
        HealthDeviationKind.prolongedMenstrualPeriods =>
          l10n.healthDeviationKindProlonged,
        HealthDeviationKind.persistentIntermenstrualBleeding =>
          l10n.healthDeviationKindPersistentIntermenstrualBleeding,
      };
}
