/// The side-by-side cycle comparison widget (Issue #235): renders two
/// cycles' flow and tag timelines aligned on cycle day. Deliberately thin
/// and self-contained -- all the shaping (which days align, what each
/// day's flow/tags are, the compared statistics) already happened in
/// [CycleComparisonData] (`lib/domain/insights/cycle_comparison.dart`),
/// this file only lays it out. That split is what lets #196
/// (Perimenopause mode) reuse this exact widget as its primary Cycle View
/// rather than building a second comparison surface (issue #235 AC3):
/// any caller that can produce a [CycleComparisonData] -- from a manual
/// two-cycle pick here, or #196's own "current vs. previous" selection --
/// gets the same rendering.
///
/// Read-only by construction: nothing here mutates data, so this widget
/// needs no separate read-only mode for a viewer-role guardian or an
/// archived profile (issue #235 scope) -- the caller only needs to be
/// able to *reach* this screen in those cases, not this widget to behave
/// differently once it does.
///
/// Accessibility (issue #235 scope): every flow value is text, never a
/// color-only swatch (R9-style "no information by colour alone" — the
/// swatch is decorative, the label carries the fact); day rows wrap
/// rather than truncate at 200% text scale (`Expanded`/`Wrap`, no fixed
/// heights); each day's content is grouped under one [Semantics] label
/// per side so a screen-reader user hears "Day 3, cycle starting August
/// 5: Medium flow, cramps, fatigue" as one announcement instead of
/// several disconnected fragments.
library;

import 'package:flutter/material.dart';

import '../../domain/insights/cycle_comparison.dart';
import '../../domain/models/flow_level.dart';
import '../../domain/models/local_date.dart';
import '../../domain/tags.dart';
import '../components/empty_state.dart';
import '../l10n/dates.dart' as dates;
import '../overview/cycle_history_section.dart' show formatDays;
import '../theme/lunarlog_colors.dart';
import '../theme/tokens.dart';

import 'package:lunarlog/l10n/app_localizations.dart';

class CycleComparisonView extends StatelessWidget {
  const CycleComparisonView({super.key, required this.data});

  /// Null renders the honest "nothing to compare" empty state (issue #235
  /// AC: a not-enough-cycles caller, or a stale/invalid selection, must
  /// never render a broken or misleadingly partial comparison).
  final CycleComparisonData? data;

  @override
  Widget build(BuildContext context) {
    final data = this.data;
    if (data == null) {
      final l10n = AppLocalizations.of(context);
      return EmptyState(
        key: const ValueKey('cycle-comparison-empty'),
        title: l10n.cycleComparisonNotEnoughTitle,
        body: l10n.cycleComparisonNotEnoughBody,
        crossAxisAlignment: CrossAxisAlignment.start,
      );
    }
    return ListView(
      key: const ValueKey('cycle-comparison-view'),
      padding: const EdgeInsets.all(LLSpace.space4),
      children: [
        _headerRow(context, data),
        const SizedBox(height: LLSpace.space3),
        _statsCard(context, data),
        const SizedBox(height: LLSpace.space3),
        const Divider(),
        for (var day = 1; day <= data.maxCycleDay; day++)
          _dayRow(context, data, day),
      ],
    );
  }

  Widget _headerRow(BuildContext context, CycleComparisonData data) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _sideHeader(context, data.sideA)),
        const SizedBox(width: LLSpace.space3),
        Expanded(child: _sideHeader(context, data.sideB)),
      ],
    );
  }

  Widget _sideHeader(BuildContext context, CycleComparisonSide side) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final dateText = _formatDate(context, side.cycleStart);
    final heading = side.isOpen
        ? l10n.cycleComparisonCurrentCycleHeading(dateText)
        : l10n.cycleComparisonSideHeading(dateText);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          key: ValueKey('cycle-comparison-heading-${side.cycleStart.iso}'),
          style: theme.textTheme.titleSmall,
        ),
        if (side.excluded) ...[
          const SizedBox(height: LLSpace.space1),
          _excludedBadge(context, side.cycleStart),
        ],
        const SizedBox(height: LLSpace.space1),
        _lengthAndBleedDays(context, side),
      ],
    );
  }

  /// Text badge, not a color-only chip (issue #235 scope: no information
  /// conveyed by colour alone) — the icon is decorative. Not styled as an
  /// error (this is a status fact about the cycle, not a failure with
  /// anything to retry — `test/architecture/inline_error_text_color_test
  /// .dart` reserves `colorScheme.error`-styled `Text` for that).
  Widget _excludedBadge(BuildContext context, LocalDate cycleStart) {
    final theme = Theme.of(context);
    return Semantics(
      label: AppLocalizations.of(context).cycleComparisonExcludedBadge,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.block,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: LLSpace.space1),
          Flexible(
            child: Text(
              AppLocalizations.of(context).cycleComparisonExcludedBadge,
              key: ValueKey('cycle-comparison-excluded-${cycleStart.iso}'),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lengthAndBleedDays(BuildContext context, CycleComparisonSide side) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final lengthValue =
        side.lengthDays == null ? l10n.cycleComparisonOngoingLabel : formatDays(l10n, side.lengthDays!.toDouble());
    return Wrap(
      spacing: LLSpace.space3,
      runSpacing: LLSpace.space1,
      children: [
        _statChip(theme, l10n.cycleComparisonLengthLabel, lengthValue),
        _statChip(
          theme,
          l10n.cycleComparisonBleedDaysLabel,
          l10n.daysCount(side.bleedDayCount),
        ),
      ],
    );
  }

  Widget _statChip(ThemeData theme, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }

  Widget _statsCard(BuildContext context, CycleComparisonData data) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final lengthDelta = data.stats.lengthDeltaDays;
    return Card(
      key: const ValueKey('cycle-comparison-stats-card'),
      child: Padding(
        padding: const EdgeInsets.all(LLSpace.space3),
        child: Wrap(
          spacing: LLSpace.space4,
          runSpacing: LLSpace.space2,
          children: [
            _statChip(
              theme,
              l10n.cycleComparisonLengthDifferenceLabel,
              lengthDelta == null
                  ? l10n.cycleComparisonLengthDifferenceUnknown
                  : l10n.daysCount(lengthDelta.abs()),
            ),
            _statChip(
              theme,
              l10n.cycleComparisonBleedDaysDifferenceLabel,
              l10n.daysCount(data.stats.bleedDayCountDelta.abs()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayRow(BuildContext context, CycleComparisonData data, int day) {
    final rowA = _rowAt(data.sideA, day);
    final rowB = _rowAt(data.sideB, day);
    final l10n = AppLocalizations.of(context);
    return Padding(
      key: ValueKey('cycle-comparison-day-$day'),
      padding: const EdgeInsets.symmetric(vertical: LLSpace.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              l10n.cycleComparisonDayHeading(day),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          Expanded(child: _dayCell(context, rowA)),
          const SizedBox(width: LLSpace.space3),
          Expanded(child: _dayCell(context, rowB)),
        ],
      ),
    );
  }

  CycleComparisonDayRow? _rowAt(CycleComparisonSide side, int cycleDay) =>
      cycleDay <= side.days.length ? side.days[cycleDay - 1] : null;

  Widget _dayCell(BuildContext context, CycleComparisonDayRow? row) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    if (row == null) {
      return Text(
        l10n.cycleComparisonCycleEndedLabel,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }
    final flow = row.flow;
    final flowText =
        flow == null ? l10n.cycleComparisonNoEntryLabel : flowLabel(flow);
    final label = _dayCellSemanticLabel(l10n, row, flowText);
    return Semantics(
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _flowDot(context, flow),
              const SizedBox(width: LLSpace.space1),
              Flexible(
                child: Text(flowText, style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
          if (row.tags.isNotEmpty) ...[
            const SizedBox(height: LLSpace.space1),
            Text(
              _tagsText(row.tags),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  String _dayCellSemanticLabel(
    AppLocalizations l10n,
    CycleComparisonDayRow row,
    String flowText,
  ) {
    final dayLabel = l10n.cycleComparisonDayHeading(row.cycleDay);
    if (row.tags.isEmpty) return '$dayLabel: $flowText';
    return '$dayLabel: $flowText, ${_tagsText(row.tags)}';
  }

  String _tagsText(List<String> tags) =>
      tags.map((code) => tagByCode(code)?.display ?? code).join(', ');

  /// Decorative color swatch alongside [flowText] above — never the only
  /// carrier of the flow information (issue #235 scope). Falls back to a
  /// plain outline color when no [LunarLogColors] theme extension is
  /// present, mirroring `CycleHistorySection._fallbackColorFor`.
  Widget _flowDot(BuildContext context, FlowLevel? flow) {
    final theme = Theme.of(context);
    final colors = theme.extension<LunarLogColors>();
    final color = _flowColor(theme, colors, flow);
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  /// Split into three small steps (rather than one branchy method) so a
  /// theme with no [LunarLogColors] extension -- an edge this file treats
  /// the same defensive way `CycleHistorySection._fallbackColorFor` does,
  /// not expected to occur in production -- costs little CRAP-gate budget
  /// even though no test exercises it directly.
  Color _flowColor(ThemeData theme, LunarLogColors? colors, FlowLevel? flow) {
    if (flow == null || !isBleed(flow)) return theme.colorScheme.outlineVariant;
    if (colors == null) return theme.colorScheme.primary;
    return _bleedColorFrom(colors, flow);
  }

  /// Only ever called with a real bleed level ([_flowColor]'s guard
  /// excludes every other [FlowLevel]), so light/medium/(heavy or
  /// superHeavy) is exhaustive without a dead catch-all arm.
  Color _bleedColorFrom(LunarLogColors colors, FlowLevel flow) => switch (flow) {
        FlowLevel.light => colors.flowLight,
        FlowLevel.medium => colors.flowMedium,
        _ => colors.flowHeavy,
      };

  String _formatDate(BuildContext context, LocalDate date) =>
      dates.formatLocalDateMonthDayYear(
        date,
        locale: dates.calendarLocale(context),
      );
}
