/// Symptom patterns, cramp forecasts, and educational library section
/// (Issues #135, #229, #239).
library;

import 'package:flutter/material.dart';

import '../../domain/insights/cramp_prediction.dart';
import '../../domain/insights/symptom_trends.dart';
import '../../domain/models/local_date.dart';
import '../content/cycle_literacy_library_screen.dart';
import '../l10n/dates.dart' as dates;

class SymptomTrendsSection extends StatelessWidget {
  const SymptomTrendsSection({
    super.key,
    required this.report,
  });

  final CycleInsightsReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Text(
          'Symptom Trends & Patterns',
          key: const ValueKey('symptom-trends-heading'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
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
                      'Recurring Symptoms',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!report.hasEnoughData || report.symptomPatterns.isEmpty) ...[
                  Text(
                    'Log symptoms across at least 3 completed cycles to uncover '
                    'recurring patterns and trends.',
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
                    'Patterns reflect descriptive logs only and are not clinical diagnostics.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
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
              title: const Text('Typical Bleed Rhythm'),
              subtitle: Text(
                'Peak flow typically falls on Cycle Day '
                '${report.flowPattern!.typicalPeakDay} (${report.flowPattern!.typicalPeakFlow.name}).',
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
            title: const Text('Cycle Literacy Library'),
            subtitle: const Text(
              'Evidence-based guides on hormones, cycle phases, and body signals.',
            ),
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
    final colorScheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toString();

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
      color: colorScheme.errorContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, color: colorScheme.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Anticipated Cramp Window',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onErrorContainer,
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
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            if (datesText.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Estimated dates: $datesText',
                key: const ValueKey('cramp-prediction-dates'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'Observed in ${prediction.observedCycleCount} of '
              '${prediction.totalCyclesAnalyzed} recorded cycles.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              prediction.disclaimer,
              key: const ValueKey('cramp-prediction-disclaimer'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontSize: 10,
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
                  fontSize: 10,
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
          'Logged ${pattern.totalOccurrences} times across ${pattern.cycleCount} cycles',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontSize: 11,
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
