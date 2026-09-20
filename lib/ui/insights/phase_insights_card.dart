/// Phase insights card displaying the active biological hormonal subphase (Issue #236).
library;

import 'package:flutter/material.dart';

import '../../domain/content/cycle_literacy_library.dart';
import '../../domain/models/local_date.dart';
import '../../domain/prediction/cycle_subphase.dart';
import '../../domain/prediction/prediction.dart';
import '../content/cycle_literacy_article_sheet.dart';

class PhaseInsightsCard extends StatelessWidget {
  const PhaseInsightsCard({
    super.key,
    required this.prediction,
    required this.today,
  });

  final ActivePrediction prediction;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final info = deriveSubphase(prediction: prediction, today: today);
    final primaryArticle =
        CycleLiteracyLibrary.getArticleById(info.subphase.primaryArticleId);

    return Card(
      key: ValueKey('phase-insights-card-${info.subphase.id}'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Phase Name & Range Tag
            Row(
              children: [
                Expanded(
                  child: Text(
                    info.subphase.displayName,
                    key: const ValueKey('phase-name-text'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    info.cycleDayRangeText,
                    key: const ValueKey('phase-range-text'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Hormonal Biology Explainer
            Text(
              info.biologicalExplainer,
              key: const ValueKey('phase-explainer-text'),
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),

            // What to Track Guidance
            Text(
              'Helpful to track:',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              info.subphase.whatToTrack,
              key: const ValueKey('phase-tracking-text'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),

            // Statistical Uncertainty Hedging
            if (info.isHedged && info.hedgedNotice != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        info.hedgedNotice!,
                        key: const ValueKey('phase-hedged-notice'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Contextual Article Button
            if (primaryArticle != null) ...[
              OutlinedButton.icon(
                key: const ValueKey('phase-article-button'),
                icon: const Icon(Icons.menu_book_outlined, size: 16),
                label: Text('Read: ${primaryArticle.title}'),
                onPressed: () =>
                    CycleLiteracyArticleSheet.show(context, primaryArticle),
              ),
              const SizedBox(height: 8),
            ],

            // Provenance footnote
            Text(
              'Source: ${info.source} · Rev: ${info.reviewDate}',
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
