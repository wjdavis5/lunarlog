/// The Today card (issue #209; B-29, B-10, A2-39, A2-40): wraps
/// [CycleWheel] with the next-period estimate, a compact confidence chip,
/// the existing R17 disclaimer, and the primary one-tap "Period started
/// today" quick-log action -- hidden entirely when [canLog] is false (a
/// `viewer`-role guardian; see `GuardianRole.canLog`).
///
/// [OverviewPanel] mounts this at the top of its active-estimate content
/// and owns the actual write ([onLogToday]) so this widget never talks to
/// a repository directly -- it only renders state handed to it and calls
/// back on a tap. The write itself goes through the same
/// `DayEntriesRepository` upsert path as the day sheet
/// (`lib/domain/logging/quick_log.dart`'s [quickLogFlowLevel] keeps a
/// second tap from downgrading an already-logged flow level).
///
/// This card is also where [OverviewPanel]'s former standalone phase
/// headline, next-period-estimate line, and disclaimer now live -- moved
/// here rather than duplicated, so the estimate card shows each exactly
/// once (the wheel's centre label replaces the old plain-text phase
/// headline).
///
/// Issue #316 review item 1: a throwing [onLogToday] used to propagate out
/// of an unawaited callback with no visible failure -- the button quietly
/// re-enabled (its own `finally`) while the user was left believing the tap
/// had worked. It is now caught here and surfaced as an [InlineError] with
/// a Retry that simply re-runs the same write.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/logging/quick_log.dart' show kQuickLogFlowLevel;
import 'package:lunarlog/domain/prediction/prediction.dart'
    show CycleConfidence;
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/l10n/tiers.dart';

import '../theme/haptics.dart';
import '../theme/tokens.dart';
import 'confidence_chip.dart';
import 'cycle_wheel.dart';
import 'inline_error.dart';

class TodayCard extends StatefulWidget {
  const TodayCard({
    super.key,
    required this.cycleDay,
    required this.duringEpisode,
    required this.cycleLengthDays,
    required this.periodLengthDays,
    this.daysUntilNextPeriod,
    this.irregularFraming = false,
    required this.estimateText,
    required this.tier,
    required this.showConfidenceChip,
    required this.canLog,
    required this.onLogToday,
  });

  /// 1-based day of the current cycle (matches
  /// `ActivePrediction.cycleDay`).
  final int cycleDay;

  /// Whether today falls inside a logged bleed episode.
  final bool duringEpisode;

  /// The cycle's typical length in days -- [CycleWheel]'s full lap.
  final int cycleLengthDays;

  /// The typical bleed length in days -- [CycleWheel]'s predicted band.
  final int periodLengthDays;

  /// Days until next period (issue #807).
  final int? daysUntilNextPeriod;

  /// Issue #853: the effective composed irregular framing — switches the
  /// wheel's overdue unit and semantics off "late" wording. Forwarded to
  /// [CycleWheel]; see that widget's own doc for the resolution rule.
  final bool irregularFraming;

  /// The fully-formatted next-period estimate line (issue #131/#213: the
  /// mode's own label plus either the single date or the range), computed
  /// by the caller so this widget never re-derives date formatting.
  final String estimateText;

  /// This cycle's confidence tier -- feeds the compact chip.
  final CycleConfidence tier;

  /// Whether the confidence chip renders at all (issue #131: `irregular`
  /// care mode already reframes confidence in its own quieter wording
  /// elsewhere on the panel, so it silences this chip too -- the same
  /// flag that already silences the panel's tier caption).
  final bool showConfidenceChip;

  /// False for a `viewer`-role guardian (or an archived/read-only view):
  /// the quick-log action is omitted entirely rather than shown disabled.
  final bool canLog;

  /// Performs the actual "period started today" write. Awaited so the
  /// button can show a brief busy state and guard against a double tap
  /// firing the write twice while the first is still in flight.
  final Future<void> Function() onLogToday;

  @override
  State<TodayCard> createState() => _TodayCardState();
}

class _TodayCardState extends State<TodayCard> {
  bool _busy = false;

  /// Set when [widget.onLogToday] throws (issue #316 review item 1); shown
  /// as an [InlineError] below the button rather than left to propagate
  /// silently. Cleared at the start of every tap, including a Retry.
  Object? _error;

  Future<void> _handleTap() async {
    if (_busy) return;
    LLHaptics.action();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onLogToday();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      key: const ValueKey('today-card'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: CycleWheel(
            cycleDay: widget.cycleDay,
            duringEpisode: widget.duringEpisode,
            cycleLengthDays: widget.cycleLengthDays,
            periodLengthDays: widget.periodLengthDays,
            daysUntilNextPeriod: widget.daysUntilNextPeriod,
            irregularFraming: widget.irregularFraming,
          ),
        ),
        if (!widget.duringEpisode) ...[
          const SizedBox(height: LLSpace.space2),
          Center(
            child: Text(
              l10n.cycleWheelCenterCycleDay(widget.cycleDay),
              key: const ValueKey('today-card-cycle-day'),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        const SizedBox(height: LLSpace.space3),
        _estimateRow(context, theme),
        if (widget.canLog) ...[
          const SizedBox(height: LLSpace.space3),
          _logTodayButton(l10n),
          if (_error != null) ...[
            const SizedBox(height: LLSpace.space1),
            InlineError(
              key: const ValueKey('today-card-error'),
              message: l10n.todayCardRecordEntryError,
              onRetry: _busy ? null : _handleTap,
            ),
          ],
        ],
      ],
    );
  }

  Widget _estimateRow(BuildContext context, ThemeData theme) {
    Widget buildChip() => Semantics(
      label: AppLocalizations.of(context).futureExplainerConfidence(
        tierShortLabel(AppLocalizations.of(context), widget.tier),
      ),
      excludeSemantics: true,
      // Issue #209 item 2: the compact confidence badge. It feeds the same
      // tier vocabulary as the panel's `overview-tier-caption`, as a short
      // label rather than the full explanatory sentence.
      child: ConfidenceChip(
        key: const ValueKey('today-card-confidence-chip'),
        tier: widget.tier,
      ),
    );

    // The estimate always gets the card's full width, and the chip sits
    // beside it only where both fit on one line. In a Row the chip took
    // its width first and the estimate wrapped in what was left: on an
    // ordinary phone that broke the date in two ("October / 1, 2026"),
    // and at accessibility text scales it broke words (issue #836, which
    // stacked the two for large text only). A Wrap does both jobs.
    return Wrap(
      key: const ValueKey('today-card-estimate-row'),
      spacing: LLSpace.space2,
      runSpacing: LLSpace.space1,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          widget.estimateText,
          key: const ValueKey('overview-next-period'),
          style: theme.textTheme.titleMedium,
        ),
        if (widget.showConfidenceChip) buildChip(),
      ],
    );
  }

  /// Issue #316 review item 5: names the flow level the tap actually
  /// writes ([kQuickLogFlowLevel], read rather than a literal) via a
  /// [Tooltip], which doubles as its semantics label -- the button's
  /// visible "Period started today" copy never names a flow level itself.
  Widget _logTodayButton(AppLocalizations l10n) {
    return Tooltip(
      message: l10n.todayCardLogsFlowTooltip(kQuickLogFlowLevel.name),
      child: FilledButton.icon(
        key: const ValueKey('today-card-log-action'),
        onPressed: _busy ? null : _handleTap,
        icon: _busy
            ? const SizedBox(
                width: LLSpace.space4,
                height: LLSpace.space4,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.water_drop_outlined, size: 18),
        label: Text(l10n.todayCardLogPeriodStartedToday),
      ),
    );
  }
}
