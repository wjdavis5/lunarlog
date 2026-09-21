/// The cycle-end recap card (issue #852): the one in-app moment that marks a
/// cycle completing, mounted at the top of the Analysis tab when the
/// completed-cycle count increments.
///
/// It is a card, not a modal wall: it never covers the log actions and is
/// dismissible in one tap. Dismissal is recorded by the caller
/// ([AnalysisTab]) in the device-local [cycleRecapSettingKey] record, so the
/// same cycle never reappears.
///
/// **In-app only — no notification of any kind.** A push saying anything
/// about a cycle completing is a health disclosure on a lock screen, which
/// is exactly what issue #844 removed from the reminder action labels. This
/// widget and [CycleRecap] never reach the notification stack.
///
/// **No streaks, badges, or achievements** (reaffirmed on #852). Every line
/// is either a logged fact (the cycle's length, a symptom pattern) or the
/// engine's own estimate and confidence vocabulary — never a reward.
///
/// The card says only what [CycleRecap] carries: below the engine's estimate
/// threshold it shows the logged length and an explicit "still learning"
/// line, and under effective irregular framing — the composed mode +
/// `Profile.irregularFraming` flag (issue #853), which reaches this card as
/// the caller's resolved [irregularFraming] — it never uses range or
/// this-vs-last comparison language (the false-precision posture
/// `CareModeCopy` already takes for the late banner and the tier caption).
library;

import 'package:flutter/material.dart';

import '../../domain/insights/cycle_recap.dart';
import '../../l10n/app_localizations.dart';
import '../overview/cycle_history_section.dart' show formatDays;
import '../theme/tokens.dart';

class CycleRecapCard extends StatelessWidget {
  const CycleRecapCard({
    super.key,
    required this.recap,
    required this.irregularFraming,
    required this.onDismiss,
    this.onCompare,
  });

  final CycleRecap recap;

  /// The profile's *effective* irregular framing, resolved by the caller
  /// with `irregularFramingInEffect` (issue #853: mode composed with the
  /// stored flag and the engine tier, never the raw `ProfileMode` axis).
  /// True suppresses range and comparison language, per this file's doc
  /// comment.
  final bool irregularFraming;

  /// Records the dismissal and hides the card.
  final VoidCallback onDismiss;

  /// Opens the #235 comparison for [CycleRecap.previousCycleStart] vs
  /// [CycleRecap.cycleStart]. Null (or no completed previous cycle) omits
  /// the action.
  final VoidCallback? onCompare;

  bool get _suppressComparison =>
      irregularFraming || recap.lengthChangeDays == null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Card(
      key: const ValueKey('cycle-recap-card'),
      child: Padding(
        padding: const EdgeInsets.all(LLSpace.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    l10n.cycleRecapTitle(recap.cycleNumber),
                    key: const ValueKey('cycle-recap-title'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: const ValueKey('cycle-recap-dismiss'),
                  onPressed: onDismiss,
                  tooltip: l10n.cycleRecapDismissLabel,
                  icon: const Icon(Icons.close, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: LLSpace.space1),
            Text(
              l10n.cycleRecapLength(
                formatDays(l10n, recap.cycleLengthDays.toDouble()),
              ),
              key: const ValueKey('cycle-recap-length'),
              style: theme.textTheme.bodyMedium,
            ),
            ..._estimateFacts(theme, l10n),
            ..._recurringFacts(theme, l10n),
            if (!_suppressComparison && onCompare != null) ...[
              const SizedBox(height: LLSpace.space2),
              TextButton(
                key: const ValueKey('cycle-recap-compare'),
                onPressed: onCompare,
                child: Text(l10n.cycleRecapCompareAction),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Estimate-backed lines: the thin-history learning note instead of any
  /// estimate, or the usual range plus an honest change since the last
  /// recap (a tier transition, or a displayed-mean shift the #178
  /// thresholds already judged meaningful).
  List<Widget> _estimateFacts(
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    if (recap.isLearning) {
      return [
        const SizedBox(height: LLSpace.space1),
        Text(
          l10n.cycleRecapStillLearning,
          key: const ValueKey('cycle-recap-learning'),
          style: theme.textTheme.bodyMedium,
        ),
      ];
    }

    final widgets = <Widget>[];
    final mean = recap.meanCycleLengthDays;
    final spread = recap.spreadDays;
    if (!_suppressComparison && mean != null && spread != null) {
      widgets.add(const SizedBox(height: LLSpace.space1));
      widgets.add(Text(
        l10n.cycleRecapUsualRange(_rangeText(l10n, mean, spread)),
        key: const ValueKey('cycle-recap-range'),
        style: theme.textTheme.bodyMedium,
      ));
    }

    if (!_suppressComparison) {
      final comparison = _comparisonText(l10n);
      if (comparison != null) {
        widgets.add(const SizedBox(height: LLSpace.space1));
        widgets.add(Text(
          comparison,
          key: const ValueKey('cycle-recap-comparison'),
          style: theme.textTheme.bodyMedium,
        ));
      }
    }

    final change = _statisticChangeText(l10n);
    if (change != null) {
      widgets.add(const SizedBox(height: LLSpace.space1));
      widgets.add(Text(
        change,
        key: const ValueKey('cycle-recap-statistic-change'),
        style: theme.textTheme.bodyMedium,
      ));
    }
    return widgets;
  }

  String? _comparisonText(AppLocalizations l10n) {
    final delta = recap.lengthChangeDays;
    if (delta == null) return null;
    if (delta > 0) return l10n.cycleRecapLongerThanPrevious(delta);
    if (delta < 0) return l10n.cycleRecapShorterThanPrevious(-delta);
    return l10n.cycleRecapSameAsPrevious;
  }

  /// A tier transition first (the plainest "the record got smarter" fact),
  /// otherwise a displayed-mean shift the #178 thresholds already decided
  /// was meaningful. Never both, so the card states one change at most.
  String? _statisticChangeText(AppLocalizations l10n) {
    if (!recap.statisticChange) return null;
    if (recap.tierChanged) {
      final previous = recap.previousConfidence;
      final moreConfident = previous != null &&
          recap.confidence.index < previous.index;
      return moreConfident
          ? l10n.cycleRecapEstimatesMoreConfident
          : l10n.cycleRecapEstimatesLessConfident;
    }
    final shift = recap.meanCycleShiftDays;
    if (shift == null || shift == 0) return null;
    return l10n.cycleRecapAverageMoved(
      formatDays(l10n, shift.abs().toDouble()),
    );
  }

  List<Widget> _recurringFacts(ThemeData theme, AppLocalizations l10n) {
    final widgets = <Widget>[];
    final hasCrampLine = recap.crampCycleDays != null &&
        !recap.recurringSymptoms.any((s) => s.tag == 'cramps');
    for (final symptom in recap.recurringSymptoms) {
      widgets.add(const SizedBox(height: LLSpace.space1));
      widgets.add(Text(
        l10n.cycleRecapRecurringSymptom(
          _symptomLabel(symptom.tag),
          _cycleDayList(symptom.cycleDays),
        ),
        key: ValueKey('cycle-recap-symptom-${symptom.tag}'),
        style: theme.textTheme.bodyMedium,
      ));
    }
    if (hasCrampLine) {
      widgets.add(const SizedBox(height: LLSpace.space1));
      widgets.add(Text(
        l10n.cycleRecapCrampDays(_cycleDayList(recap.crampCycleDays!)),
        key: const ValueKey('cycle-recap-cramps'),
        style: theme.textTheme.bodyMedium,
      ));
    }
    return widgets;
  }

  /// Turns a taxonomy tag code into a readable, sentence-cased label — the
  /// same `replaceAll('_', ' ')` presentation `SymptomTrendsSection` uses,
  /// no taxonomy lookup of its own.
  String _symptomLabel(String tag) {
    final words = tag.replaceAll('_', ' ').trim();
    if (words.isEmpty) return words;
    return words[0].toUpperCase() + words.substring(1);
  }

  /// Compresses a sorted day list into "1–2" for a consecutive run, or
  /// "1, 3" when the days are not consecutive. Pure formatting; the days
  /// themselves are the engine's own.
  String _cycleDayList(List<int> days) {
    if (days.isEmpty) return '';
    final sorted = [...days]..sort();
    var consecutive = true;
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i] != sorted[i - 1] + 1) {
        consecutive = false;
        break;
      }
    }
    if (sorted.length > 1 && consecutive) {
      return '${sorted.first}\u2013${sorted.last}';
    }
    return sorted.join(', ');
  }

  /// "27–31 days", or a single "30 days" when the spread rounds to zero, so
  /// a steady history never renders a self-contradicting "30–30 days".
  String _rangeText(AppLocalizations l10n, double mean, double spread) {
    final low = (mean - spread).round();
    final high = (mean + spread).round();
    if (low >= high) return formatDays(l10n, mean);
    return l10n.daysValue(high, '$low\u2013$high');
  }
}
