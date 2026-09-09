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
import 'package:lunarlog/ui/overview/estimate_copy.dart'
    show kEstimateDisclaimer;

import '../theme/lunarlog_colors.dart';
import 'cycle_wheel.dart';
import 'inline_error.dart';

class TodayCard extends StatefulWidget {
  const TodayCard({
    super.key,
    required this.cycleDay,
    required this.duringEpisode,
    required this.cycleLengthDays,
    required this.periodLengthDays,
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
          ),
        ),
        const SizedBox(height: 12),
        _estimateRow(theme),
        const SizedBox(height: 8),
        Text(
          kEstimateDisclaimer,
          key: const ValueKey('overview-disclaimer'),
          style: theme.textTheme.bodySmall,
        ),
        if (widget.canLog) ...[
          const SizedBox(height: 12),
          _logTodayButton(),
          if (_error != null) ...[
            const SizedBox(height: 4),
            InlineError(
              key: const ValueKey('today-card-error'),
              message: "Couldn't record today's entry — try again.",
              onRetry: _busy ? null : _handleTap,
            ),
          ],
        ],
      ],
    );
  }

  Widget _estimateRow(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            widget.estimateText,
            key: const ValueKey('overview-next-period'),
            style: theme.textTheme.titleMedium,
          ),
        ),
        if (widget.showConfidenceChip) ...[
          const SizedBox(width: 8),
          // #138: the chip's bare tier word ("High") reads ambiguously on
          // its own — the wrapper announces the same phrase the calendar's
          // future-day explainer uses, reusing its ARB key rather than
          // adding a near-duplicate string.
          Semantics(
            label: AppLocalizations.of(
              context,
            ).futureExplainerConfidence(widget.tier.label.toLowerCase()),
            excludeSemantics: true,
            child: _ConfidenceChip(tier: widget.tier),
          ),
        ],
      ],
    );
  }

  /// Issue #316 review item 5: names the flow level the tap actually
  /// writes ([kQuickLogFlowLevel], read rather than a literal) via a
  /// [Tooltip], which doubles as its semantics label -- the button's
  /// visible "Period started today" copy never names a flow level itself.
  Widget _logTodayButton() {
    return Tooltip(
      message: 'Logs a ${kQuickLogFlowLevel.name}-flow period start for '
          'today',
      child: FilledButton.icon(
        key: const ValueKey('today-card-log-action'),
        onPressed: _busy ? null : _handleTap,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.water_drop_outlined, size: 18),
        label: const Text('Period started today'),
      ),
    );
  }
}

/// Compact confidence badge (issue #209 item 2; feeds the same tier
/// vocabulary as the panel's own `overview-tier-caption`, just as a short
/// label rather than the full explanatory sentence -- the two can render
/// side by side without repeating each other word for word).
class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.tier});

  final CycleConfidence tier;

  Color _colorFor(LunarLogColors colors) => switch (tier) {
        CycleConfidence.high => colors.confidenceHigh,
        CycleConfidence.learning => colors.confidenceLearning,
        CycleConfidence.irregular => colors.confidenceIrregular,
        CycleConfidence.provisional => colors.confidenceProvisional,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<LunarLogColors>();
    final color = colors == null
        ? theme.colorScheme.onSurfaceVariant
        : _colorFor(colors);
    return Container(
      key: const ValueKey('today-card-confidence-chip'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Text(
        // Issue #218: the chip's label routes through AppLocalizations
        // (via the shared tier-vocabulary mapper) rather than the domain
        // enum's own `label`, so the new `provisional` tier renders
        // localized copy like every other surfaced string.
        tierLabel(AppLocalizations.of(context), tier),
        style: theme.textTheme.labelMedium?.copyWith(color: color),
      ),
    );
  }
}
