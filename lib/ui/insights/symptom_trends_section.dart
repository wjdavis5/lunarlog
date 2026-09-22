/// Symptom patterns, cramp forecasts, and educational library section
/// (Issues #135, #229, #239).
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/l10n/app_localizations.dart';

import '../../domain/insights/cramp_prediction.dart';
import '../../domain/insights/symptom_trends.dart';
import '../../domain/models/local_date.dart';
import '../content/cycle_literacy_library_screen.dart';
import '../l10n/dates.dart' as dates;
import '../theme/lunarlog_colors.dart';

class SymptomTrendsSection extends StatelessWidget {
  const SymptomTrendsSection({
    super.key,
    required this.report,
  });

  final CycleInsightsReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Text(
          l10n.symptomTrendsTitle,
          key: const ValueKey('symptom-trends-heading'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),

        // 1. Cramp Prediction Card (Issue #229)
        if (report.crampPrediction != null) ...[
          _CrampPredictionCard(prediction: report.crampPrediction!),
          const SizedBox(height: 12),
        ],

        // 2. Symptom Patterns Card (Issue #135)
        Card(
          key: const ValueKey('symptom-patterns-card'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.show_chart,
                        size: 20, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      l10n.symptomTrendsRecurring,
                      style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!report.hasEnoughData || report.symptomPatterns.isEmpty) ...[
                  Text(
                    l10n.symptomTrendsEmpty,
                    key: const ValueKey('symptom-trends-empty-text'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else ...[
                  for (final pattern in report.symptomPatterns) ...[
                    _SymptomPatternRow(pattern: pattern),
                    const Divider(height: 16),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    l10n.symptomTrendsDisclaimer,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 3. Flow Distribution Summary
        if (report.flowPattern != null) ...[
          Card(
            key: const ValueKey('flow-pattern-card'),
            child: ListTile(
              leading: Icon(Icons.water_drop_outlined,
                  color: colorScheme.secondary),
              title: Text(l10n.symptomTrendsFlowTitle),
              subtitle: Text(
                l10n.symptomTrendsFlowSubtitle(
                  report.flowPattern!.typicalPeakDay,
                  report.flowPattern!.typicalPeakFlow.name,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 4. Cycle Literacy Library Card (Issue #239)
        Card(
          key: const ValueKey('literacy-library-cta-card'),
          child: ListTile(
            key: const ValueKey('browse-cycle-library-button'),
            leading: Icon(Icons.auto_stories_outlined,
                color: colorScheme.primary),
            title: Text(l10n.symptomTrendsLibraryTitle),
            subtitle: Text(l10n.symptomTrendsLibrarySubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              CycleLiteracyLibraryScreen.route(),
            ),
          ),
        ),
      ],
    );
  }
}

class _CrampPredictionCard extends StatelessWidget {
  const _CrampPredictionCard({required this.prediction});

  final CrampPrediction prediction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final colorScheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toString();
    // Issue #876: a predicted-cramps window is routine, expected
    // information, not an error — so the card wears the calendar's own
    // cramps accent (LunarLogColors.crampsBadge, #895) on an ordinary
    // surface card, matching how the calendar's bolt badge renders it.
    final accent = theme.extension<LunarLogColors>()?.crampsBadge ??
        colorScheme.primary;

    String formatDates(List<LocalDate> datesList) {
      if (datesList.isEmpty) return '';
      return datesList
          .map((d) => dates.formatLocalDateMonthDay(
                d,
                locale: locale,
              ))
          .join(', ');
    }

    final datesText = formatDates(prediction.predictedDates);

    return Card(
      key: const ValueKey('cramp-prediction-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, color: accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.crampPredictionTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              prediction.summaryText,
              key: const ValueKey('cramp-prediction-summary'),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            if (datesText.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                l10n.crampPredictionDates(datesText),
                key: const ValueKey('cramp-prediction-dates'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              l10n.crampPredictionObserved(
                prediction.observedCycleCount,
                prediction.totalCyclesAnalyzed,
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              prediction.disclaimer,
              key: const ValueKey('cramp-prediction-disclaimer'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SymptomPatternRow extends StatelessWidget {
  const _SymptomPatternRow({required this.pattern});

  final SymptomPattern pattern;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final colorScheme = theme.colorScheme;

    final formattedTagName = pattern.tag.replaceAll('_', ' ').capitalize();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                formattedTagName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                pattern.trend.displayName,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          pattern.timingSummary,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          l10n.symptomTrendsLogged(
            pattern.totalOccurrences,
            pattern.cycleCount,
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

extension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
