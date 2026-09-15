/// The Analysis tab (issue #223, A2-18/A2-19): the screen mounted at the
/// app shell's "Insights" destination (`components/app_shell.dart`) — the
/// shell keeps that nav-bar label (issue #182 already shipped it), but this
/// screen's own heading is "Analysis" per the issue and Clue's own naming.
///
/// [ActivePrediction] already computes average cycle length
/// (`meanCycleLengthDays`), average period length (`meanPeriodLengthDays`),
/// and variability (`spreadDays`/`tier`) on every stream emission (issue
/// #213) — none of it reached the UI before this issue (A2-19). This tab
/// renders those as its headline section: all three statistics render in
/// every care mode (`CareModeCopy.showsTierCaption` only scopes the tier
/// caption — the short label naming the tier — never the digits
/// themselves; `irregular` mode still shows plain "±N days" rather than
/// losing the number entirely). The same fixed non-medical disclaimer
/// (R17) [OverviewPanel] uses ([kEstimateDisclaimer]) sits under this
/// headline. Below [kMinCompletedValidCycles] valid cycles,
/// [CyclePredictionService.watch] itself emits [NotEnoughHistory] (the same
/// gate [OverviewPanel] renders against), so this tab shows the same honest
/// "not enough history yet" copy rather than a misleading chart.
///
/// [CycleHistorySection] (issue #132) is mounted below the headline as the
/// scrollable cycle-history list this tab hosts; it already honours
/// [CycleExclusionList] on its own, and the prediction stream above already
/// excludes omitted cycles ([CyclePredictionService.watch] combines the
/// exclusion list into every emission) so no extra wiring is needed here
/// for that. This tab's headline card owns the statistics shown on this
/// screen (issue #223 follow-up), so [CycleHistorySection] is mounted with
/// its own `showStatistics`/`showDisclaimer` both false — otherwise its
/// own 6-cycle-window stats row and its own disclaimer would sit directly
/// under the headline's 12-cycle-window numbers, disagreeing on one
/// screen.
///
/// Issue #314: `OverviewPanel` (Today tab) no longer embeds this same
/// [CycleHistorySection] — this tab is now its only mount, and the single
/// `CycleHistoryService.watch` subscription per profile that follows from
/// that. `OverviewPanel` instead carries a "See cycle history" link that
/// switches to this tab through the #313 tab-switch seam.
///
/// This tab's read-only gating mirrors [OverviewPanel]'s: within the app
/// shell a profile is always the active, non-archived one (an archived
/// profile's read-only view stays on the old `ProfileDetailScreen`, per
/// #182), so only the guardian-viewer-role half of [OverviewPanel]'s
/// `_effectiveReadOnly` applies here — computed the same way, from a
/// [ProfileGuardiansRepository] the app shell hands down and the same
/// [AuthController]/[acceptedGuardianFor] lookup, so a viewer-role guardian
/// cannot omit a cycle from this tab's history either.
///
/// #135 (statistics/trends) mounts as an additional entry in [_sections]
/// below — that section-list shape is the seam this issue leaves open.
/// #135 mounts here.
///
/// Issue #143: the headline card also renders an "Estimated fertile
/// window" row (dates plus, per [CareModeCopy.showsTierCaption], the tier
/// name) and [kFertileWindowDisclaimer] right under it — both gated on
/// [CareModeCopy.showsFertileWindow], hidden in the same not-enough-history
/// state the rest of the card already is, and available on every profile
/// including `isMinor` ones (#142) with no separate check here.
///
/// Issue #235: [CycleHistorySection] is mounted here with
/// `onCompareSelected` wired to push [CycleComparisonScreen] -- the
/// side-by-side comparison this tab is the primary entry point for (the
/// archived-profile mount in `profile_detail_screen.dart` wires the same
/// callback for its own, separate [CycleHistorySection] instance).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/episodes/episodes.dart';
import '../../domain/insights/bbt_chart.dart' as bbt;
import '../../domain/insights/cycle_insights_calculator.dart';
import '../../domain/models/day_entry.dart';
import '../../domain/models/measurement_unit.dart';
import '../../domain/models/observation.dart';
import '../../domain/repositories/day_entries_repository.dart';
import '../../domain/repositories/observations_repository.dart';
import '../../domain/repositories/profile_guardians_repository.dart';
import '../../domain/care_modes.dart';
import '../../domain/models/local_date.dart';
import '../../domain/models/profile_guardian.dart';
import '../../domain/models/profile_mode.dart';
import '../../domain/prediction/fertile_window.dart';
import '../../domain/prediction/prediction.dart';
import '../../domain/prediction/prediction_service.dart';
import '../account/auth_controller.dart';
import '../components/async_snapshot_view.dart';
import '../components/empty_state.dart';
import '../components/predictions_disabled_card.dart';
import '../components/predictions_suppressed_card.dart';
import '../help/help_card_view.dart';
import 'bbt_chart.dart';

import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/l10n/dates.dart' as dates;
import 'package:lunarlog/ui/l10n/tiers.dart';

import '../overview/cycle_history_section.dart';
import '../overview/overview_panel.dart'
    show kEstimateDisclaimer, kFertileWindowDisclaimer;
import '../sharing/guardian_watch_mixin.dart';
import '../theme/tokens.dart';
import 'cycle_comparison_screen.dart';
import 'phase_insights_card.dart';
import 'symptom_trends_section.dart';

class AnalysisTab extends StatefulWidget {
  const AnalysisTab({
    super.key,
    required this.profileId,
    this.mode = ProfileMode.standard,
    this.todayProvider = LocalDate.today,
    this.readOnly = false,
    this.guardiansRepository,
    this.dayEntriesRepository,
    this.observationsRepository,
    this.bbtUnit = BbtUnit.celsius,
  });

  final String profileId;
  final DayEntriesRepository? dayEntriesRepository;

  /// Source of this profile's BBT readings for the chart (Issue #245);
  /// falls back to `context.read<ObservationsRepository?>()` like
  /// [dayEntriesRepository] does for entries — null in a tree with no
  /// observations repository wired renders the chart's empty state rather
  /// than throwing.
  final ObservationsRepository? observationsRepository;

  /// Per-profile BBT display unit (Issue #457/#245): governs only the
  /// chart's caption text — every plotted value is already Celsius.
  final BbtUnit bbtUnit;

  /// The profile's care mode (issue #131): selects the headline-stat
  /// vocabulary below, same as [OverviewPanel].
  final ProfileMode mode;

  /// "Today" as the device-local civil date; injectable for tests.
  final LocalDate Function() todayProvider;

  /// Read-only regardless of guardian role — the app shell never sets
  /// this today (see the file doc comment: an archived profile stays on
  /// the old `ProfileDetailScreen`), but [_effectiveReadOnly] still
  /// honours it the way [OverviewPanel.readOnly] does, so a future caller
  /// can force this tab read-only without a guardian row to back it.
  final bool readOnly;

  /// Source of this profile's guardians for the viewer-role read-only
  /// check (same shape as [OverviewPanel.guardiansRepository]); null in
  /// local-only use.
  final ProfileGuardiansRepository? guardiansRepository;

  @override
  State<AnalysisTab> createState() => _AnalysisTabState();
}

class _AnalysisTabState extends State<AnalysisTab>
    with GuardianWatchMixin<AnalysisTab> {
  late final CyclePredictionService _service = context
      .read<CyclePredictionService>();
  late Stream<CyclePrediction> _predictions = _service.watch(
    widget.profileId,
    today: widget.todayProvider,
  );

  /// #543: re-subscribes after a stream error — `InlineError`'s Retry
  /// callback on the top-level `StreamBuilder`.
  void _retryPredictions() {
    setState(() {
      _predictions = _service.watch(
        widget.profileId,
        today: widget.todayProvider,
      );
    });
  }

  StreamSubscription<List<DayEntry>>? _entriesSub;
  AuthController? _auth;
  String? _currentUserId;
  List<ProfileGuardian> _guardians = const [];
  List<DayEntry> _entries = const [];

  /// Issue #245: this profile's live observations, refetched on every
  /// entries-stream tick — see [_watchEntries]'s doc for why that keeps
  /// this current without [ObservationsRepository] needing a `watch()` of
  /// its own.
  List<Observation> _observations = const [];

  CareModeCopy get _copy => careModeCopyFor(widget.mode);

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthController?>();
    if (auth != null) {
      _currentUserId = auth.currentUserId;
      auth.addListener(_onAuthChanged);
      _auth = auth;
    }
    _watchGuardians();
    _watchEntries();
  }

  // The listener is only ever registered while [_auth] is non-null and is
  // removed (with [_auth] cleared) in dispose, so a single mounted check is
  // the whole guard; kept minimal because this handler has no widget-test
  // trigger and the CRAP gate scores uncovered branches quadratically.
  void _onAuthChanged() {
    if (!mounted) return;
    setState(() => _currentUserId = _auth?.currentUserId);
  }

  void _watchGuardians() {
    watchGuardiansForProfile(
      widget.guardiansRepository,
      widget.profileId,
      (guardians) => setState(() => _guardians = guardians),
    );
  }

  void _watchEntries() {
    unawaited(_entriesSub?.cancel());
    _entries = const [];
    final repository =
        widget.dayEntriesRepository ?? context.read<DayEntriesRepository?>();
    if (repository == null) return;
    _entriesSub = repository.watchForProfile(widget.profileId).listen((
      entries,
    ) {
      if (!mounted) return;
      setState(() => _entries = entries);
      // Issue #245: [ObservationsRepository] has no `watch()` of its own
      // (Issue #240's read surface is one-shot reads only), but every
      // BBT/weight autosave also writes this same day's `DayEntry` in the
      // same atomic call (`saveDayEntryWithObservations`), so refetching
      // here on every entries tick keeps the BBT chart's data live without
      // adding a new repository method for this one chart.
      unawaited(_refetchObservations());
    });
  }

  Future<void> _refetchObservations() async {
    final repository = widget.observationsRepository ??
        context.read<ObservationsRepository?>();
    if (repository == null) return;
    final observations = await repository.listForProfile(widget.profileId);
    if (!mounted) return;
    setState(() => _observations = observations);
  }

  @override
  void didUpdateWidget(covariant AnalysisTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId) {
      _predictions = _service.watch(
        widget.profileId,
        today: widget.todayProvider,
      );
      _watchGuardians();
      _watchEntries();
      return;
    }
    // Issue #574: same profile, but `guardiansRepository`/`todayProvider`
    // changed underneath it — re-run just the watch that reads the changed
    // collaborator.
    if (oldWidget.guardiansRepository != widget.guardiansRepository) {
      _watchGuardians();
    }
    if (oldWidget.observationsRepository != widget.observationsRepository) {
      unawaited(_refetchObservations());
    }
    if (oldWidget.todayProvider != widget.todayProvider) {
      _predictions = _service.watch(
        widget.profileId,
        today: widget.todayProvider,
      );
    }
  }

  @override
  void dispose() {
    disposeGuardianWatch();
    unawaited(_entriesSub?.cancel());
    _entriesSub = null;
    _auth?.removeListener(_onAuthChanged);
    _auth = null;
    super.dispose();
  }

  /// Same effective read-only rule as [OverviewPanel]/`MonthCalendar`: the
  /// caller's accepted role is `viewer`, or the widget was told to be
  /// read-only outright. Fails open on an unknown role (no guardian rows
  /// yet, no signed-in operator, no matching row).
  bool get _effectiveReadOnly =>
      widget.readOnly ||
      acceptedGuardianFor(_guardians, _currentUserId)?.role.canLog == false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CyclePrediction>(
      stream: _predictions,
      builder: (context, snapshot) {
        return AsyncSnapshotView<CyclePrediction>(
          snapshot: snapshot,
          errorMessage: 'Could not load your cycle analysis.',
          onRetry: _retryPredictions,
          builder: (context, prediction) => ListView(
            padding: const EdgeInsets.all(LLSpace.space4),
            children: _sections(context, prediction),
          ),
        );
      },
    );
  }

  /// Section list — mounts headline statistics, phase insights (#236),
  /// symptom trends & cramp forecasts (#135/#229), and the cycle history list.
  List<Widget> _sections(BuildContext context, CyclePrediction prediction) {
    final episodes = deriveEpisodes(bleedDatesOf(_entries));
    final report = CycleInsightsCalculator.compute(
      entries: _entries,
      episodes: episodes,
      prediction: prediction is ActivePrediction ? prediction : null,
    );

    return [
      Text(
        'Analysis',
        key: const ValueKey('analysis-heading'),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: LLSpace.space3),
      switch (prediction) {
        ActivePrediction() => _statsCard(context, prediction),
        NotEnoughHistory() => _notEnoughCard(context),
        // Issue #233/#528: an in-effect continuous method, or a life-stage
        // mode the averaging model doesn't apply to, suppresses period
        // prediction with an explicit named state — the stats card has no
        // mean/spread to show, so this renders the shared suppressed card.
        PredictionsSuppressed() => PredictionsSuppressedCard(
          method: prediction.method,
          lifecycleMode: prediction.lifecycleMode,
        ),
        // Issue #225: per-profile toggle turning off predictions.
        PredictionsDisabled() => const PredictionsDisabledCard(),
      },
      const SizedBox(height: LLSpace.space4),
      CycleHistorySection(
        profileId: widget.profileId,
        todayProvider: widget.todayProvider,
        readOnly: _effectiveReadOnly,
        showStatistics: false,
        showDisclaimer: false,
        onCompareSelected: (cycleAStart, cycleBStart) =>
            Navigator.of(context).push(
              CycleComparisonScreen.route(
                profileId: widget.profileId,
                cycleAStart: cycleAStart,
                cycleBStart: cycleBStart,
                todayProvider: widget.todayProvider,
              ),
            ),
      ),
      if (prediction is ActivePrediction) ...[
        const SizedBox(height: 16),
        PhaseInsightsCard(
          prediction: prediction,
          today: widget.todayProvider(),
        ),
      ],
      const SizedBox(height: 16),
      SymptomTrendsSection(report: report),
      const SizedBox(height: 16),
      _bbtChartCard(context, episodes),
    ];
  }

  /// Issue #245: the BBT chart card — data shaping is
  /// [bbt.deriveBbtChartData] (pure, `lib/domain/insights/bbt_chart.dart`),
  /// reusing the exact same [episodes] this method already derived for
  /// [CycleInsightsCalculator] above, so the chart's cycle-day axis is the
  /// same cycle boundaries the rest of this tab shows. Renders in every
  /// care mode and regardless of [prediction]'s state (unlike the headline
  /// stats card) — a profile can have logged BBT with too little cycle
  /// history for a prediction yet, and the chart's own honest empty state
  /// (issue #245 AC3) already covers "no data" without needing the
  /// prediction gate above to also cover it.
  Widget _bbtChartCard(BuildContext context, List<Episode> episodes) {
    final theme = Theme.of(context);
    final data = bbt.deriveBbtChartData(
      episodes: episodes,
      observations: _observations,
    );
    return Card(
      key: const ValueKey('analysis-bbt-chart-card'),
      child: Padding(
        padding: const EdgeInsets.all(LLSpace.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'BBT by cycle day',
              key: const ValueKey('analysis-bbt-chart-title'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: LLSpace.space2),
            BbtChart(data: data, displayUnit: widget.bbtUnit),
          ],
        ),
      ),
    );
  }

  Widget _statsCard(BuildContext context, ActivePrediction prediction) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Card(
      key: const ValueKey('analysis-stats'),
      child: Padding(
        padding: const EdgeInsets.all(LLSpace.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cycle statistics',
              key: const ValueKey('analysis-stats-title'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: LLSpace.space2),
            ..._headlineStats(theme, l10n, prediction),
            ..._fertileWindowSection(theme, l10n, prediction),
            const SizedBox(height: LLSpace.space3),
            Text(
              kEstimateDisclaimer,
              key: const ValueKey('analysis-disclaimer'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  /// Issue #131/#223 follow-up: the three statistics render in every care
  /// mode — [CareModeCopy.showsTierCaption] is documented as scoping only
  /// the short tier caption (`irregular` elsewhere still renders cycle day
  /// / dates, so silencing every digit here was a wider suppression than
  /// the flag is meant to cover). Only the variability row's tier-name
  /// prefix is gated on it; the spread itself always renders, mirroring
  /// how [OverviewPanel]'s separate tier caption is the only thing
  /// `irregular` mode silences, never the estimate date next to it.
  List<Widget> _headlineStats(
    ThemeData theme,
    AppLocalizations l10n,
    ActivePrediction prediction,
  ) {
    return [
      _statRow(
        theme,
        'analysis-mean-cycle-length',
        'Average cycle length',
        formatDays(l10n, prediction.meanCycleLengthDays),
      ),
      _statRow(
        theme,
        'analysis-mean-period-length',
        'Average period length',
        formatDays(l10n, prediction.meanPeriodLengthDays),
      ),
      _statRow(
        theme,
        'analysis-variability',
        'Variability',
        _variabilityText(l10n, prediction),
      ),
    ];
  }

  String _variabilityText(AppLocalizations l10n, ActivePrediction prediction) {
    final spread = '±${prediction.spreadDays.round()} days';
    if (!_copy.showsTierCaption) return spread;
    return '${tierLabel(l10n, prediction.tier)} ($spread)';
  }

  /// Issue #143: the fertile-window row and its contraception-specific
  /// disclaimer, gated on [CareModeCopy.showsFertileWindow] the same way
  /// the calendar band is — empty (never rendered) for a mode that hides
  /// the estimate. Split out of [_statsCard] to keep that method's own
  /// branch count low (the quality gate's per-method CRAP rule).
  ///
  /// Issue #143 review: uses [currentFertileWindow] rather than
  /// [estimateFertileWindow] — the latter always describes the *next*
  /// cycle's window even once it has entirely passed, which read as a
  /// stale window shown as current; this instead walks
  /// [ActivePrediction.forecast] for the first window that has not yet
  /// passed, hiding the row entirely if none remain (defensive — see that
  /// function's own doc comment).
  List<Widget> _fertileWindowSection(
    ThemeData theme,
    AppLocalizations l10n,
    ActivePrediction prediction,
  ) {
    if (!_copy.showsFertileWindow) return const [];
    final fertile = currentFertileWindow(prediction);
    if (fertile == null) return const [];
    return [
      _statRow(
        theme,
        'analysis-fertile-window',
        _copy.fertileWindowLabel,
        _fertileWindowText(l10n, fertile),
      ),
      const SizedBox(height: LLSpace.space1),
      Text(
        kFertileWindowDisclaimer,
        key: const ValueKey('analysis-fertile-disclaimer'),
        style: theme.textTheme.bodySmall,
      ),
    ];
  }

  /// Same tier-caption rule as [_variabilityText]: the date range always
  /// renders, and [CareModeCopy.showsTierCaption] only adds the tier-name
  /// prefix — this estimate is never hidden behind a caption gate of its
  /// own, only the whole-row [CareModeCopy.showsFertileWindow] gate above.
  String _fertileWindowText(
    AppLocalizations l10n,
    FertileWindowEstimate fertile,
  ) {
    final range =
        '${_formatDate(fertile.windowStart)} – ${_formatDate(fertile.windowEnd)}';
    if (!_copy.showsTierCaption) return range;
    return '${tierLabel(l10n, fertile.tier)} ($range)';
  }

  // Issue #160: locale-derived long date (the `en` fallback renders
  // "August 16, 2026", the same shape the old kMonthNames concatenation gave).
  String _formatDate(LocalDate date) =>
      dates.formatMonthDayYear(DateTime(date.year, date.month, date.day));

  // Issue #143 review: the fertile-window row's value ("High confidence
  // (August 16, 2026 – August 22, 2026)") is far longer than the other
  // rows' plain "±N days" — the value is now wrapped in `Expanded` with
  // right-aligned, wrapping text instead of two bare `Text`s in a
  // `spaceBetween` row, so a long value wraps onto a second line rather
  // than overflowing the card horizontally.
  Widget _statRow(ThemeData theme, String key, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LLSpace.space1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          const SizedBox(width: LLSpace.space2),
          Expanded(
            child: Text(
              value,
              key: ValueKey(key),
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  /// Same posture as [OverviewPanel._notEnoughCard]: a loaded-but-empty
  /// result, not a loading state (issue #187), so it renders through
  /// [EmptyState] with the disclaimer alongside it as a plain [Text].
  Widget _notEnoughCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('analysis-not-enough'),
      child: Padding(
        padding: const EdgeInsets.all(LLSpace.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EmptyState(
              title: _copy.notEnoughTitle,
              body: _copy.notEnoughBody,
              titleStyle: theme.textTheme.headlineSmall,
              crossAxisAlignment: CrossAxisAlignment.start,
            ),
            const SizedBox(height: LLSpace.space2),
            Text(
              kEstimateDisclaimer,
              key: const ValueKey('analysis-not-enough-disclaimer'),
              style: theme.textTheme.bodySmall,
            ),
            // Issue #139: same three-cycle explainer as OverviewPanel.
            const HelpCardLink(
              cardId: 'why-no-estimate-yet',
              label: 'Why three cycles?',
            ),
          ],
        ),
      ),
    );
  }
}
