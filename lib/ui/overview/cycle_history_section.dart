/// The cycle-history section (issue #132, R4/R5): reverse-chronological
/// cycle list with the open cycle pinned on top, per-cycle omit-from-
/// average, automatic outlier flags, the statistics row (average cycle
/// length, average period length, variation), and the confidence framing.
///
/// Omissions are device-local (KTD2) — stated in a caption, not hidden.
/// Read-only callers (archived profile, viewer-role guardian) see the
/// history without omit affordances. Every statistic sits under the fixed
/// non-medical disclaimer (R17), and the vocabulary is cycle-only (R13).
///
/// Issue #223 follow-up: `AnalysisTab` also mounts this section, directly
/// under its own headline statistics card (`ActivePrediction`-derived,
/// 12-cycle window) — this section's own [_statsRow]/disclaimer (a
/// 6-cycle window) would otherwise put two disagreeing numbers on one
/// screen. [showStatistics] and [showDisclaimer] (both default true, so
/// [OverviewPanel]'s mount is unchanged) let a caller that owns the
/// numbers elsewhere suppress this section's copies.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';
import 'package:lunarlog/ui/l10n/dates.dart' as dates;
import 'package:lunarlog/ui/overview/estimate_copy.dart'
    show kEstimateDisclaimer;
import 'package:lunarlog/ui/theme/lunarlog_colors.dart';
import 'package:provider/provider.dart';

/// Issue #160: month names are locale-derived (`lib/ui/l10n/dates.dart`),
/// replacing the `kMonthNames` list this file used to import from the
/// month calendar.
String _formatDate(LocalDate date, BuildContext context) =>
    dates.formatMonthDayYear(
      DateTime(date.year, date.month, date.day),
      locale: dates.calendarLocale(context),
    );

/// Shared with `AnalysisTab` (issue #223 follow-up) so both headline-stat
/// renderings format identically without a second copy of this logic.
String formatDays(double value) => value == value.roundToDouble()
    ? '${value.round()} days'
    : '${value.toStringAsFixed(1)} days';

class CycleHistorySection extends StatefulWidget {
  const CycleHistorySection({
    super.key,
    required this.profileId,
    required this.todayProvider,
    this.readOnly = false,
    this.showStatistics = true,
    this.showDisclaimer = true,
  });

  final String profileId;

  /// "Today" as the device-local civil date; injectable for tests.
  final LocalDate Function() todayProvider;

  final bool readOnly;

  /// Whether this section renders its own statistics row (average cycle
  /// length, average period length, variation). Default true so
  /// [OverviewPanel]'s mount is unchanged; `AnalysisTab` passes false
  /// because its own headline card already owns the numbers on that
  /// screen (issue #223 follow-up).
  final bool showStatistics;

  /// Whether this section renders its own R17 disclaimer. Default true so
  /// [OverviewPanel]'s mount is unchanged; `AnalysisTab` passes false for
  /// the same reason as [showStatistics] — its headline card already
  /// carries the disclaimer.
  final bool showDisclaimer;

  @override
  State<CycleHistorySection> createState() => _CycleHistorySectionState();
}

class _CycleHistorySectionState extends State<CycleHistorySection> {
  late final CycleHistoryService _service = context.read<CycleHistoryService>();
  late final CycleExclusionList _exclusions = context
      .read<CycleExclusionList>();
  late Stream<CycleHistoryView> _views;

  @override
  void initState() {
    super.initState();
    _views = _service.watch(widget.profileId, today: widget.todayProvider);
  }

  @override
  void didUpdateWidget(CycleHistorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId) {
      _views = _service.watch(widget.profileId, today: widget.todayProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CycleHistoryView>(
      stream: _views,
      builder: (context, snapshot) {
        final view = snapshot.data;
        if (view == null || view.items.isEmpty) {
          return const SizedBox.shrink();
        }
        return _card(context, view);
      },
    );
  }

  Widget _card(BuildContext context, CycleHistoryView view) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('history-card'),
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Cycle history',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (view.confidence != null) _confidenceChip(context, view),
              ],
            ),
            if (view.confidence != null) ...[
              const SizedBox(height: 4),
              Text(
                view.confidence!.summary,
                key: const ValueKey('history-confidence-summary'),
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            if (widget.showStatistics) ...[
              _statsRow(context, view),
              const SizedBox(height: 4),
            ],
            if (widget.showDisclaimer)
              Text(
                kEstimateDisclaimer,
                key: const ValueKey('history-disclaimer'),
                style: theme.textTheme.bodySmall,
              ),
            const Divider(height: 24),
            for (final item in view.items) _itemRow(context, item),
            const SizedBox(height: 4),
            Text(
              'Omissions stay on this device — other devices are not affected.',
              key: const ValueKey('history-device-local-note'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Issue #209: consumes [LunarLogColors.confidenceHigh]/
  /// [LunarLogColors.confidenceLearning]/[LunarLogColors.confidenceIrregular]
  /// so this chip shares the same badge palette as `TodayCard`'s own
  /// confidence chip, rather than an ad hoc `ColorScheme`-role mapping. A
  /// theme with no [LunarLogColors] extension (a bare `ThemeData()` in an
  /// older test harness) falls back to the previous role mapping instead
  /// of throwing.
  Widget _confidenceChip(BuildContext context, CycleHistoryView view) {
    final theme = Theme.of(context);
    final colors = theme.extension<LunarLogColors>();
    final color = colors == null
        ? _fallbackColorFor(theme, view.confidence!)
        : _colorFor(colors, view.confidence!);
    return Container(
      key: const ValueKey('history-confidence'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        view.confidence!.label,
        style: theme.textTheme.labelMedium?.copyWith(color: color),
      ),
    );
  }

  Color _colorFor(LunarLogColors colors, CycleConfidence tier) =>
      switch (tier) {
        CycleConfidence.high => colors.confidenceHigh,
        CycleConfidence.learning => colors.confidenceLearning,
        CycleConfidence.irregular => colors.confidenceIrregular,
        CycleConfidence.provisional => colors.confidenceProvisional,
      };

  Color _fallbackColorFor(ThemeData theme, CycleConfidence tier) =>
      switch (tier) {
        CycleConfidence.high => theme.colorScheme.primary,
        CycleConfidence.learning => theme.colorScheme.tertiary,
        CycleConfidence.irregular => theme.colorScheme.error,
        CycleConfidence.provisional => theme.colorScheme.secondary,
      };

  Widget _statsRow(BuildContext context, CycleHistoryView view) {
    final theme = Theme.of(context);
    return Row(
      key: const ValueKey('history-stats'),
      children: [
        _stat(
          theme,
          label: 'Avg cycle',
          value: view.meanCycleLengthDays == null
              ? '—'
              : formatDays(view.meanCycleLengthDays!),
        ),
        _stat(
          theme,
          label: 'Avg period',
          value: view.meanPeriodLengthDays == null
              ? '—'
              : formatDays(view.meanPeriodLengthDays!),
        ),
        _stat(
          theme,
          label: 'Variation',
          value: view.variationDays == null
              ? '—'
              : '${view.variationDays} days',
        ),
      ],
    );
  }

  Widget _stat(
    ThemeData theme, {
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(value, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }

  Widget _itemRow(BuildContext context, CycleHistoryItem item) {
    final theme = Theme.of(context);
    final iso = item.start.iso;
    if (item.isOpen) return _openRow(context, theme, item);
    return Opacity(
      opacity: item.omitted ? 0.55 : 1,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        key: ValueKey('history-item-$iso'),
        title: Text(_formatDate(item.start, context)),
        subtitle: item.omitted
            ? const Text('Excluded from averages')
            : item.outlier
            ? Text(
                'Outlier — never averaged',
                key: ValueKey('history-outlier-$iso'),
              )
            : null,
        trailing: _trailing(item),
      ),
    );
  }

  Widget? _trailing(CycleHistoryItem item) {
    if (item.isOpen) return null;
    final length = '${item.lengthDays} days';
    if (item.outlier) {
      // Outliers are excluded automatically (the 15–60 window); a manual
      // omit on top would be a no-op, so none is offered.
      return Text(length);
    }
    if (widget.readOnly) return Text(length);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(length),
        const SizedBox(width: 8),
        TextButton(
          key: ValueKey(
            item.omitted
                ? 'history-include-${item.start.iso}'
                : 'history-omit-${item.start.iso}',
          ),
          onPressed: () => item.omitted
              ? _exclusions.include(widget.profileId, item.start)
              : _exclusions.omit(widget.profileId, item.start),
          child: Text(item.omitted ? 'Include' : 'Omit'),
        ),
      ],
    );
  }

  Widget _openRow(BuildContext context, ThemeData theme, CycleHistoryItem item) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      key: const ValueKey('history-open-item'),
      leading: Icon(
        Icons.radio_button_checked,
        size: 18,
        color: theme.colorScheme.primary,
      ),
      title: Text('Current cycle — started ${_formatDate(item.start, context)}'),
      subtitle: item.omitted
          ? const Text('Skipped — excluded from averages')
          : null,
      trailing: item.omitted && !widget.readOnly
          ? TextButton(
              key: const ValueKey('history-undo-skip'),
              onPressed: () =>
                  _exclusions.include(widget.profileId, item.start),
              child: const Text('Undo'),
            )
          : null,
    );
  }
}
