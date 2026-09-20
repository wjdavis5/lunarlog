/// The Perimenopause-mode Cycle View card (Issue #196): a comparison-first
/// headline that replaces the ordinary days-late framing while
/// `profile_modes.mode = 'perimenopause'`.
///
/// **Why this card and not a countdown.** Clue calls the days-late
/// countdown actively unhelpful when a cycle is changing for physiological
/// reasons. Prediction is already suppressed for this mode (Issue #528), so
/// the ordinary estimate card is gone; this card leads instead with a
/// cycle-to-cycle comparison and offers Issue #235's full side-by-side
/// screen for the detail. It reuses `deriveCycleComparison` (the same pure
/// data shaping the Analysis tab's comparison uses) and
/// [CycleComparisonScreen] — it does not build a second comparison surface
/// (Issue #235 AC3, and this issue's own "via #235" requirement).
///
/// The compared pair is the profile's last two cycles
/// (`perimenopauseComparisonStarts`, `lib/domain/perimenopause.dart`), which
/// is exactly the "current vs. previous" selection the comparison view's
/// own doc comment names as this issue's caller.
///
/// Read-only by construction: this card only reads entries/exclusions and
/// navigates; it never writes, so a viewer-role guardian or archived profile
/// needs no separate gating beyond the overview's existing read-only
/// posture.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/episodes/episodes.dart';
import '../../domain/insights/cycle_comparison.dart';
import '../../domain/models/day_entry.dart';
import '../../domain/models/local_date.dart';
import '../../domain/perimenopause.dart';
import '../../domain/prediction/cycle_history.dart' show CycleExclusionList;
import '../../domain/repositories/day_entries_repository.dart';
import '../../l10n/app_localizations.dart';
import '../insights/cycle_comparison_screen.dart';
import '../theme/tokens.dart';

class PerimenopauseCard extends StatefulWidget {
  const PerimenopauseCard({
    super.key,
    required this.profileId,
    this.todayProvider = LocalDate.today,
    this.dayEntriesRepository,
    this.exclusions,
  });

  final String profileId;

  /// "Today" as the device-local civil date; injectable for tests.
  final LocalDate Function() todayProvider;

  /// Injectable for tests; falls back to `context.read<DayEntriesRepository?>()`
  /// like `CycleComparisonScreen.dayEntriesRepository` does.
  final DayEntriesRepository? dayEntriesRepository;

  /// Injectable for tests; falls back to `context.read<CycleExclusionList?>()`.
  final CycleExclusionList? exclusions;

  @override
  State<PerimenopauseCard> createState() => _PerimenopauseCardState();
}

class _PerimenopauseCardState extends State<PerimenopauseCard> {
  StreamSubscription<List<DayEntry>>? _entriesSub;
  StreamSubscription<Set<LocalDate>>? _exclusionsSub;
  List<DayEntry> _entries = const [];
  Set<LocalDate> _excluded = const {};

  @override
  void initState() {
    super.initState();
    _watchEntries();
    _watchExclusions();
  }

  void _watchEntries() {
    final repository =
        widget.dayEntriesRepository ?? context.read<DayEntriesRepository?>();
    if (repository == null) return;
    _entriesSub = repository.watchForProfile(widget.profileId).listen((entries) {
      if (!mounted) return;
      setState(() => _entries = entries);
    });
  }

  void _watchExclusions() {
    final exclusions = widget.exclusions ?? context.read<CycleExclusionList?>();
    if (exclusions == null) return;
    _exclusionsSub = exclusions.watch(widget.profileId).listen((excluded) {
      if (!mounted) return;
      setState(() => _excluded = excluded);
    });
  }

  @override
  void dispose() {
    unawaited(_entriesSub?.cancel());
    unawaited(_exclusionsSub?.cancel());
    super.dispose();
  }

  /// The current-vs-previous comparison, or null when fewer than two cycles
  /// are logged. Uses the same `deriveCycleComparison` the Analysis tab's
  /// comparison screen uses, over the same exclusion set.
  CycleComparisonData? _comparisonData(List<Episode> episodes, LocalDate today) {
    final starts = perimenopauseComparisonStarts(episodes);
    if (starts == null) return null;
    return deriveCycleComparison(
      episodes: episodes,
      entries: _entries,
      today: today,
      cycleAStart: starts.previous,
      cycleBStart: starts.current,
      excludedCycleStarts: _excluded,
    );
  }

  Future<void> _openComparison(
    PerimenopauseComparisonStarts starts,
  ) =>
      Navigator.of(context).push(
        CycleComparisonScreen.route(
          profileId: widget.profileId,
          cycleAStart: starts.previous,
          cycleBStart: starts.current,
          todayProvider: widget.todayProvider,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final episodes = deriveEpisodes(bleedDatesOf(_entries));
    final starts = perimenopauseComparisonStarts(episodes);
    final data = _comparisonData(episodes, widget.todayProvider());
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Card(
      key: const ValueKey('perimenopause-card'),
      child: Padding(
        padding: const EdgeInsets.all(LLSpace.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.perimenopauseTitle,
              key: const ValueKey('perimenopause-title'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: LLSpace.space2),
            Text(
              l10n.perimenopauseBody,
              key: const ValueKey('perimenopause-body'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: LLSpace.space3),
            if (data == null || starts == null)
              _notEnough(context)
            else
              _changeSummary(context, data, starts),
          ],
        ),
      ),
    );
  }

  Widget _notEnough(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      key: const ValueKey('perimenopause-not-enough'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.perimenopauseNotEnoughTitle,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: LLSpace.space1),
        Text(l10n.perimenopauseNotEnoughBody, style: theme.textTheme.bodySmall),
      ],
    );
  }

  /// The change-spotting headline: a length-change line and a bleed-day
  /// comparison, then the button into the full #235 view. The current
  /// cycle's length is only compared once it has ended
  /// ([CycleComparisonStats.lengthDeltaDays] is null for an open cycle), so
  /// the card never implies an ongoing cycle finished shorter or longer.
  Widget _changeSummary(
    BuildContext context,
    CycleComparisonData data,
    PerimenopauseComparisonStarts starts,
  ) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      key: const ValueKey('perimenopause-change-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Weight (the ramp's semibold), not colour, carries the "this
        // changed" emphasis — the a11y rule that status is never
        // colour-only (#204's precedent).
        Text(
          _lengthChangeText(l10n, data),
          key: const ValueKey('perimenopause-length-change'),
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: LLSpace.space1),
        Text(
          l10n.perimenopauseBleedDays(
            l10n.daysCount(data.sideB.bleedDayCount),
            l10n.daysCount(data.sideA.bleedDayCount),
          ),
          key: const ValueKey('perimenopause-bleed-days'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: LLSpace.space3),
        OutlinedButton(
          key: const ValueKey('perimenopause-compare-button'),
          onPressed: () => _openComparison(starts),
          child: Text(l10n.perimenopauseCompareButton),
        ),
      ],
    );
  }

  String _lengthChangeText(AppLocalizations l10n, CycleComparisonData data) {
    final delta = data.stats.lengthDeltaDays;
    if (delta == null) return l10n.perimenopauseLengthUnknown;
    if (delta == 0) return l10n.perimenopauseLengthSame;
    final count = l10n.daysCount(delta.abs());
    return delta > 0
        ? l10n.perimenopauseLengthLonger(count)
        : l10n.perimenopauseLengthShorter(count);
  }
}
