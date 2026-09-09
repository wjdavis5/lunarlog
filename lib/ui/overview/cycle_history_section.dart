/// The cycle-history section (issue #132, R4/R5): reverse-chronological
/// cycle list with the open cycle pinned on top, per-cycle omit-from-
/// average, automatic outlier flags, the statistics row (average cycle
/// length, average period length, variation), and the confidence framing.
///
/// Omissions are device-local (KTD2) — stated in a caption, not hidden.
/// Read-only callers (archived profile, viewer-role guardian) see the
/// history without omit affordances. Every statistic sits under the fixed
/// non-medical disclaimer (R17), and the vocabulary is cycle-only (R13).
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart' show kMonthNames;
import 'package:lunarlog/ui/overview/overview_panel.dart'
    show kEstimateDisclaimer;
import 'package:provider/provider.dart';

String _formatDate(LocalDate date) =>
    '${kMonthNames[date.month - 1]} ${date.day}, ${date.year}';

String _formatDays(double value) => value == value.roundToDouble()
    ? '${value.round()} days'
    : '${value.toStringAsFixed(1)} days';

class CycleHistorySection extends StatefulWidget {
  const CycleHistorySection({
    super.key,
    required this.profileId,
    required this.todayProvider,
    this.readOnly = false,
  });

  final String profileId;

  /// "Today" as the device-local civil date; injectable for tests.
  final LocalDate Function() todayProvider;

  final bool readOnly;

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
            _statsRow(context, view),
            const SizedBox(height: 4),
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
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _confidenceChip(BuildContext context, CycleHistoryView view) {
    final theme = Theme.of(context);
    // TODO(#209): consume LunarLogColors.confidence* instead of this
    // colorScheme-role mapping, so this chip shares the same badge palette
    // as the rest of the app.
    final color = switch (view.confidence!) {
      CycleConfidence.high => theme.colorScheme.primary,
      CycleConfidence.learning => theme.colorScheme.tertiary,
      CycleConfidence.irregular => theme.colorScheme.error,
    };
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
              : _formatDays(view.meanCycleLengthDays!),
        ),
        _stat(
          theme,
          label: 'Avg period',
          value: view.meanPeriodLengthDays == null
              ? '—'
              : _formatDays(view.meanPeriodLengthDays!),
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
              color: theme.colorScheme.outline,
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
    if (item.isOpen) return _openRow(theme, item);
    return Opacity(
      opacity: item.omitted ? 0.55 : 1,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        key: ValueKey('history-item-$iso'),
        title: Text(_formatDate(item.start)),
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

  Widget _openRow(ThemeData theme, CycleHistoryItem item) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      key: const ValueKey('history-open-item'),
      leading: Icon(
        Icons.radio_button_checked,
        size: 18,
        color: theme.colorScheme.primary,
      ),
      title: Text('Current cycle — started ${_formatDate(item.start)}'),
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
