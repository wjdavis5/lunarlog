/// Phase insights card displaying the active biological hormonal subphase (Issue #236).
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/l10n/app_localizations.dart';

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
    final l10n = AppLocalizations.of(context);
    final colorScheme = theme.colorScheme;

    // Issue #1118: any non-statistical basis — a pack-driven (pill/patch/
    // ring) prediction, or a hormonal method with no recorded start date —
    // carries no ovulatory signal, so the card must show no subphase or
    // ovulation content. See [PredictionBasis]'s own doc comment.
    if (prediction.basis != PredictionBasis.statistical) {
      // Issue #1133: the two non-statistical bases get different copy. The
      // pack-driven branch's "follows your pack schedule" clause is false
      // for the no-start-date branch, whose estimate comes from the
      // profile's own history (device-confirmed by the owner on QA pass
      // 154) — so that branch says what is missing and how to switch.
      final body = prediction.basis == PredictionBasis.statisticalOnHormonalMethod
          ? l10n.phaseInsightsHormonalNoStartDateBody
          : l10n.phaseInsightsHormonalContraceptionBody;
      return Card(
        key: const ValueKey('phase-insights-regimen-schedule'),
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            body,
            key: const ValueKey('phase-regimen-schedule-text'),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ),
      );
    }

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

            // Hormonal Biology Explainer. The lead-in frames it as a
            // typical ovulatory cycle rather than a fact about this
            // person's cycle today (issue #1118; teen cycles are often
            // anovulatory — ACOG CO 651).
            Text(
              '${l10n.phaseInsightsTypicalCycleLead} ${info.biologicalExplainer}',
              key: const ValueKey('phase-explainer-text'),
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),

            // What to Track Guidance
            Text(
              l10n.phaseInsightsHelpfulToTrack,
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
                label: Text(
                  l10n.phaseInsightsReadArticle(primaryArticle.title),
                ),
                onPressed: () =>
                    CycleLiteracyArticleSheet.show(context, primaryArticle),
              ),
              const SizedBox(height: 8),
            ],

            // Provenance footnote
            Text(
              l10n.phaseInsightsSource(info.source, info.reviewDate),
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
