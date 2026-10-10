/// The cycle-history section (issue #132, R4/R5): reverse-chronological
/// cycle list with the open cycle pinned on top, per-cycle omit-from-
/// average, automatic outlier flags, the statistics row (average cycle
/// length, average period length, variation), and the confidence framing.
///
/// Omissions sync across devices via `cycle_overrides` (issue #568).
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
///
/// Issue #235: [onCompareSelected] opts a caller into a "Compare cycles"
/// selection mode on top of this same list, per the issue's own framing
/// ("from the cycle history list, allow selecting two cycles") -- rather
/// than a second, parallel list. Null (the default, so every pre-#235
/// caller and test is unaffected) hides the whole affordance; a caller
/// that supplies it is handed exactly two selected cycle starts, oldest
/// first, once the operator picks two and taps Compare, and owns what
/// happens next (both current mounts push
/// `lib/ui/insights/cycle_comparison_screen.dart`). Selecting is a
/// read-only action -- it never gates on [readOnly], so a viewer-role
/// guardian or an archived profile can compare cycles the same as anyone
/// else.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/care_modes.dart' show completedCycleProgress;
import 'package:lunarlog/domain/insights/cycle_comparison.dart'
    show kMinCyclesToCompare;
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';
import 'package:lunarlog/domain/prediction/prediction.dart'
    show
        ActivePrediction,
        CyclePrediction,
        NotEnoughHistory,
        PredictionsDisabled,
        PredictionsSuppressed,
        kMinCompletedValidCycles;
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/components/confidence_chip.dart';
import 'package:lunarlog/ui/components/inline_error.dart';
import 'package:lunarlog/ui/l10n/dates.dart' as dates;
import 'package:lunarlog/ui/overview/estimate_copy.dart'
    show kEstimateDisclaimer;
import 'package:lunarlog/ui/theme/tokens.dart';
import 'package:provider/provider.dart';

/// Issue #160: month names are locale-derived (`lib/ui/l10n/dates.dart`),
/// replacing the `kMonthNames` list this file used to import from the
/// month calendar.
String _formatDate(LocalDate date, BuildContext context) =>
    dates.formatLocalDateMonthDayYear(
      date,
      locale: dates.calendarLocale(context),
    );

/// Shared with `AnalysisTab` (issue #223 follow-up) so both headline-stat
/// renderings format identically without a second copy of this logic.
/// Issue #545: routes the "day"/"days" word through ICU plural via
/// [AppLocalizations.daysValue] instead of always appending "days" (a bare
/// count of exactly 1 rendered as "1 days").
String formatDays(AppLocalizations l10n, double value) {
  final isWhole = value == value.roundToDouble();
  final display = isWhole ? value.round().toString() : value.toStringAsFixed(1);
  return l10n.daysValue(value, display);
}

class CycleHistorySection extends StatefulWidget {
  const CycleHistorySection({
    super.key,
    required this.profileId,
    required this.todayProvider,
    this.readOnly = false,
    this.showStatistics = true,
    this.showDisclaimer = true,
    this.notEnough,
    this.prediction,
    this.onCompareSelected,
  });

  final String profileId;

  /// "Today" as the device-local civil date; injectable for tests.
  final LocalDate Function() todayProvider;

  final bool readOnly;

  /// Issue #816: the caller's live not-enough-history state, when it has
  /// one. The section then shows the header tally ("2 of 3 completed
  /// cycles — estimates start after the next period.") from the engine's
  /// own count, so it can never disagree with the empty state above it.
  /// Null in every other prediction state (and for the archived-profile
  /// mount, which has no prediction but already shows the tally in its
  /// panel's card), so a profile with an estimate gets no progress line.
  final NotEnoughHistory? notEnough;

  /// Issue #1861: the caller's live engine prediction, when it has one.
  /// The chip then renders this prediction's own [CycleConfidence] tier —
  /// the same one the overview caption shows — instead of the section's
  /// own statistical re-derivation, which cannot see birth-control or
  /// lifecycle state. A suppressed or disabled engine state hides the chip
  /// (the overview shows its named card there; a statistical tier beside
  /// it would contradict it). Null (the archived-profile mount) keeps the
  /// section's own derivation.
  final CyclePrediction? prediction;

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

  /// Issue #235: called with exactly two selected cycle starts (oldest
  /// first) when the operator taps Compare after selecting exactly two
  /// cycles. See this file's doc comment.
  final void Function(LocalDate cycleAStart, LocalDate cycleBStart)?
  onCompareSelected;

  @override
  State<CycleHistorySection> createState() => _CycleHistorySectionState();
}

class _CycleHistorySectionState extends State<CycleHistorySection> {
  late final CycleHistoryService _service = context.read<CycleHistoryService>();
  late final CycleExclusionList _exclusions = context
      .read<CycleExclusionList>();
  late Stream<CycleHistoryView> _views;

  /// Issue #235: selection-mode state for the "Compare cycles" affordance
  /// -- entirely local UI state, never persisted (unlike the omission set
  /// above, which is a real device/synced fact).
  bool _comparing = false;
  final Set<LocalDate> _selectedForComparison = {};

  void _toggleComparing() {
    setState(() {
      _comparing = !_comparing;
      _selectedForComparison.clear();
    });
  }

  void _toggleSelected(LocalDate start, bool? checked) {
    setState(() {
      if (checked ?? false) {
        _selectedForComparison.add(start);
      } else {
        _selectedForComparison.remove(start);
      }
    });
  }

  void _openComparison() {
    final onCompareSelected = widget.onCompareSelected;
    if (onCompareSelected == null || _selectedForComparison.length != 2) {
      return;
    }
    final sorted = _selectedForComparison.toList()..sort();
    setState(() {
      _comparing = false;
      _selectedForComparison.clear();
    });
    onCompareSelected(sorted[0], sorted[1]);
  }

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

  /// #543: re-subscribes after a stream error — `InlineError`'s Retry
  /// callback below.
  void _retry() {
    setState(() {
      _views = _service.watch(widget.profileId, today: widget.todayProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CycleHistoryView>(
      stream: _views,
      builder: (context, snapshot) {
        // #543: error, loading, and "no history yet" used to all render
        // `SizedBox.shrink()` — a genuine failure was invisible. Loading and
        // empty still render nothing (this is a secondary section below the
        // main estimate card, not worth a spinner of its own), but an error
        // now surfaces with a retry instead of silently vanishing.
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.only(top: LLSpace.space3),
            child: InlineError(
              key: const ValueKey('cycle-history-error'),
              message: AppLocalizations.of(context).cycleHistoryLoadError,
              onRetry: _retry,
            ),
          );
        }
        final view = snapshot.data;
        if (view == null || !view.hasHistory) {
          return const SizedBox.shrink();
        }
        return _card(context, view);
      },
    );
  }

  Widget _card(BuildContext context, CycleHistoryView view) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // Issue #1861: the chip mirrors the engine's own tier when the caller
    // supplied its live prediction, so the history badge and the overview
    // caption can never disagree (this file's #213 contract — the section's
    // own re-derivation cannot see birth-control or lifecycle state). A
    // suppressed or disabled engine state hides the chip rather than
    // framing a statistical tier the overview contradicts.
    final confidence = switch (widget.prediction) {
      ActivePrediction(:final tier) => tier,
      PredictionsSuppressed() || PredictionsDisabled() => null,
      _ => view.confidence,
    };
    return Card(
      key: const ValueKey('history-card'),
      margin: const EdgeInsets.only(top: LLSpace.space3),
      child: Padding(
        padding: const EdgeInsets.all(LLSpace.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: LLSpace.space2,
              runSpacing: LLSpace.space1,
              children: [
                Text(
                  l10n.cycleHistoryTitle,
                  style: theme.textTheme.titleMedium,
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: LLSpace.space2,
                  runSpacing: LLSpace.space1,
                  children: [
                    if (widget.onCompareSelected != null &&
                        view.items.length >= kMinCyclesToCompare)
                      _compareToggleButton(context),
                    if (confidence != null)
                      ConfidenceChip(
                        key: const ValueKey('history-confidence'),
                        tier: confidence,
                      ),
                  ],
                ),
              ],
            ),
            if (widget.notEnough != null) ...[
              const SizedBox(height: LLSpace.space1),
              Text(
                completedCycleProgress(
                  widget.notEnough!.usableCycleCount,
                  kMinCompletedValidCycles,
                ),
                key: const ValueKey('history-progress'),
                style: theme.textTheme.bodySmall,
              ),
            ] else if (confidence != null) ...[
              const SizedBox(height: LLSpace.space1),
              Text(
                confidence.summary,
                key: const ValueKey('history-confidence-summary'),
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: LLSpace.space3),
            if (widget.showStatistics) ...[
              _statsRow(context, view),
              const SizedBox(height: LLSpace.space1),
            ],
            if (widget.showDisclaimer)
              Text(
                kEstimateDisclaimer,
                key: const ValueKey('history-disclaimer'),
                style: theme.textTheme.bodySmall,
              ),
            const Divider(height: LLSpace.space5),
            for (final item in view.items) _itemRow(context, item),
            if (_omissionsSync(context, view)) ...[
              const SizedBox(height: LLSpace.space1),
              Text(
                l10n.cycleHistorySyncNote,
                key: const ValueKey('history-sync-note'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (_comparing) ...[
              const SizedBox(height: LLSpace.space2),
              _comparisonFooter(context),
            ],
          ],
        ),
      ),
    );
  }

  /// Whether "Omissions sync across your devices" is true here and about
  /// something on the card.
  ///
  /// The line used to close every history card. It was there with no
  /// account on the device, where an omission goes nowhere; and under a
  /// card holding only the cycle in progress, where there is no Omit to
  /// press and so no omission to speak of. It needs a row that offers
  /// Omit or Include (a completed cycle that is not an automatic outlier,
  /// for someone who may change it) and a signed-in account for the
  /// choice to sync to.
  bool _omissionsSync(BuildContext context, CycleHistoryView view) {
    if (widget.readOnly) return false;
    if (!view.items.any((item) => !item.isOpen && !item.outlier)) return false;
    final auth = Provider.of<AuthController?>(context);
    return auth?.state.hasUsableSession ?? false;
  }

  /// Issue #235: enters/exits selection mode. Only rendered when a caller
  /// opted in via [CycleHistorySection.onCompareSelected] and there are at
  /// least [kMinCyclesToCompare] cycles to pick from.
  Widget _compareToggleButton(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextButton(
      key: const ValueKey('history-compare-toggle'),
      onPressed: _toggleComparing,
      child: Text(
        _comparing
            ? l10n.cycleComparisonCancelButton
            : l10n.cycleComparisonToggleButton,
      ),
    );
  }

  /// Issue #235: the "N of 2 selected" hint plus the Compare button,
  /// shown below the list while [_comparing].
  Widget _comparisonFooter(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.cycleComparisonSelectedCount(_selectedForComparison.length),
            key: const ValueKey('history-compare-count'),
          ),
        ),
        const SizedBox(width: LLSpace.space2),
        FilledButton(
          key: const ValueKey('history-compare-open'),
          onPressed:
              _selectedForComparison.length == 2 ? _openComparison : null,
          child: Text(l10n.cycleComparisonOpenButton),
        ),
      ],
    );
  }

  /// Issue #235: the selection checkbox shown in place of a row's usual
  /// trailing content while [_comparing] -- wrapped in [Semantics] since a
  /// bare [Checkbox] only announces its checked state, not what it is
  /// for. Disabled (greyed, `onChanged: null`) once two cycles are already
  /// selected and this one is not among them, so a third tap cannot
  /// silently replace an earlier pick.
  Widget _selectionCheckbox(BuildContext context, CycleHistoryItem item) {
    final l10n = AppLocalizations.of(context);
    final selected = _selectedForComparison.contains(item.start);
    final atCap = _selectedForComparison.length >= 2 && !selected;
    return Semantics(
      label: item.isOpen
          ? l10n.cycleComparisonSelectCurrentCycleSemantic
          : l10n.cycleComparisonSelectCycleSemantic(
              _formatDate(item.start, context),
            ),
      child: Checkbox(
        key: ValueKey('history-compare-select-${item.start.iso}'),
        value: selected,
        onChanged: atCap
            ? null
            : (checked) => _toggleSelected(item.start, checked),
      ),
    );
  }

  Widget _statsRow(BuildContext context, CycleHistoryView view) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Row(
      key: const ValueKey('history-stats'),
      children: [
        _stat(
          theme,
          label: l10n.cycleHistoryAvgCycle,
          value: view.meanCycleLengthDays == null
              ? '—'
              : formatDays(l10n, view.meanCycleLengthDays!),
        ),
        _stat(
          theme,
          label: l10n.cycleHistoryAvgPeriod,
          value: view.meanPeriodLengthDays == null
              ? '—'
              : formatDays(l10n, view.meanPeriodLengthDays!),
        ),
        _stat(
          theme,
          label: l10n.cycleHistoryVariation,
          value: view.variationDays == null
              ? '—'
              : l10n.daysCount(view.variationDays!),
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
    final l10n = AppLocalizations.of(context);
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
            ? Text(l10n.cycleComparisonExcludedBadge)
            : item.outlier
            ? Text(
                l10n.cycleHistoryOutlier,
                key: ValueKey('history-outlier-$iso'),
              )
            : null,
        trailing: _trailing(context, item),
      ),
    );
  }

  /// Only ever called with a completed (non-open) item -- [_itemRow]
  /// routes an open item to [_openRow]/[_openRowTrailing] instead.
  Widget? _trailing(BuildContext context, CycleHistoryItem item) {
    // Issue #235: selection mode replaces the usual omit/include controls
    // with the compare checkbox.
    if (_comparing) return _selectionCheckbox(context, item);
    final length = AppLocalizations.of(context).daysCount(item.lengthDays!);
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
        const SizedBox(width: LLSpace.space2),
        TextButton(
          key: ValueKey(
            item.omitted
                ? 'history-include-${item.start.iso}'
                : 'history-omit-${item.start.iso}',
          ),
          onPressed: () => item.omitted
              ? _exclusions.include(widget.profileId, item.start)
              : _exclusions.omit(widget.profileId, item.start),
          child: Text(
            item.omitted
                ? AppLocalizations.of(context).cycleHistoryInclude
                : AppLocalizations.of(context).cycleHistoryOmit,
          ),
        ),
      ],
    );
  }

  /// Issue #816: the open cycle is visibly *not* part of the completed-cycle
  /// tally the header shows ("2 of 3 completed cycles") — the bare "Current
  /// cycle" label alone left the user counting its row as a completed one.
  /// An omitted (skipped) open cycle keeps its more specific subtitle.
  Widget _openRow(
    BuildContext context,
    ThemeData theme,
    CycleHistoryItem item,
  ) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      key: const ValueKey('history-open-item'),
      leading: Icon(
        Icons.radio_button_checked,
        size: 18,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        l10n.cycleHistoryCurrentCycleStarted(
          _formatDate(item.start, context),
        ),
      ),
      subtitle: item.omitted
          ? Text(l10n.cycleHistorySkippedExcluded)
          : Text(l10n.cycleHistoryOpenCycleNotCounted),
      trailing: _openRowTrailing(context, item),
    );
  }

  Widget? _openRowTrailing(BuildContext context, CycleHistoryItem item) {
    if (_comparing) return _selectionCheckbox(context, item);
    if (!item.omitted || widget.readOnly) return null;
    return TextButton(
      key: const ValueKey('history-undo-skip'),
      onPressed: () => _exclusions.include(widget.profileId, item.start),
      child: Text(AppLocalizations.of(context).cycleHistoryUndo),
    );
  }
}
