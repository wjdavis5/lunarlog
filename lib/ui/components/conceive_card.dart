/// The Conceive-mode Cycle View card (Issue #204): a fertile-window-first
/// headline over the per-day conception-likelihood curve, shown while
/// `profile_modes.mode = 'conceive'`.
///
/// This is *additive* to the ordinary period estimate below it — Conceive
/// mode does not suppress prediction (`prediction_service.dart`'s
/// `suppressesPrediction` deliberately leaves `conceive` on the ordinary
/// averaging path), it re-frames the Cycle View around fertility. Pure
/// display: the curve itself lives in `lib/domain/conceive.dart`
/// (`ConceptionEstimate`) and is unit-tested there; this widget only
/// renders what the caller computed.
///
/// Every rendered value sits next to the fixed, non-negotiable disclaimer
/// treatment — the shared [kEstimateDisclaimer] is already rendered by the
/// [TodayCard] below this card, and this card carries
/// [kFertileWindowDisclaimer] (the issue #143 contraception warning) and
/// its own [kConceiveDisclaimer]/[kConceiveEvidenceBasis] (issue #204 AC3:
/// the evidence basis must be stated in the UI, distinguished from #143's
/// estimator). None of these are ever softened or omitted.
library;

import 'package:flutter/material.dart';

import 'package:lunarlog/domain/conceive.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/overview/estimate_copy.dart';
import 'package:lunarlog/ui/theme/lunarlog_colors.dart';
import 'package:lunarlog/ui/theme/tokens.dart';

class ConceiveCard extends StatelessWidget {
  const ConceiveCard({
    super.key,
    required this.estimate,
    required this.dateText,
  });

  /// The current conception-likelihood curve (`currentConceptionEstimate`).
  final ConceptionEstimate estimate;

  /// Localized short date formatter (the caller owns localization, exactly
  /// as `PregnancyCard` receives pre-formatted text).
  final String Function(LocalDate) dateText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final colors = theme.extension<LunarLogColors>();
    final band = colors?.fertileBand ?? theme.colorScheme.tertiaryContainer;
    final border = colors?.fertileBorder ?? theme.colorScheme.tertiary;
    final window =
        '${dateText(estimate.fertileWindowStart)} – '
        '${dateText(estimate.fertileWindowEnd)}';
    return Card(
      key: const ValueKey('conceive-card'),
      child: Padding(
        padding: const EdgeInsets.all(LLSpace.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.conceiveTitle,
              key: const ValueKey('conceive-title'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: LLSpace.space2),
            Text(
              l10n.conceiveWindowLabel,
              key: const ValueKey('conceive-window-label'),
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              window,
              key: const ValueKey('conceive-window'),
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: LLSpace.space3),
            _CurveStrip(estimate: estimate, band: band, border: border),
            const SizedBox(height: LLSpace.space2),
            Text(
              l10n.conceivePeakDay(
                dateText(estimate.peakDay),
                (estimate.peakProbability * 100).round(),
              ),
              key: const ValueKey('conceive-peak'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: LLSpace.space3),
            Text(
              kConceiveEvidenceBasis,
              key: const ValueKey('conceive-evidence'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: LLSpace.space2),
            Text(
              kFertileWindowDisclaimer,
              key: const ValueKey('conceive-fertile-disclaimer'),
              style: theme.textTheme.bodySmall,
            ),
            Text(
              kConceiveDisclaimer,
              key: const ValueKey('conceive-disclaimer'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// The per-day curve as a row of seven visually distinct day tiles — each
/// window day is filled with the same tertiary-hue `fertileBand`/`fertileBorder`
/// token the calendar band uses (#143), and the peak day is additionally
/// bold and outlined, so the distinction never rests on colour alone.
/// Semantically each tile announces its date and probability percentage.
class _CurveStrip extends StatelessWidget {
  const _CurveStrip({
    required this.estimate,
    required this.band,
    required this.border,
  });

  final ConceptionEstimate estimate;
  final Color band;
  final Color border;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      key: const ValueKey('conceive-curve'),
      children: [
        for (final day in estimate.days)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(
                key: ValueKey('conceive-day-${day.date.iso}'),
                padding: const EdgeInsets.symmetric(vertical: LLSpace.space2),
                decoration: BoxDecoration(
                  color: band,
                  borderRadius: BorderRadius.circular(LLRadius.rSm),
                  border: Border.all(
                    color: border,
                    width: day.date == estimate.peakDay ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      '${day.date.day}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: day.date == estimate.peakDay
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    Text(
                      '${(day.probability * 100).round()}%',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
