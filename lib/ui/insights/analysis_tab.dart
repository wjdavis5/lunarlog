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
///
/// Issue #852: the [CycleRecapCard] leads this tab when a cycle has
/// completed since the device last looked. The baseline lives in the
/// device-local [cycleRecapSettingKey] record (never synced, never health
/// data), so dismissing it once hides it for that cycle on this device. The
/// recap is in-app only by decision -- no notification is scheduled by this
/// tab or anything it mounts.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/episodes/episodes.dart';
import '../../domain/insights/bbt_chart.dart' as bbt;
import '../../domain/insights/cycle_insights_calculator.dart';
import '../../domain/insights/cycle_recap.dart';
import '../../domain/insights/symptom_trends.dart';
import '../../domain/models/day_entry.dart';
import '../../domain/models/measurement_unit.dart';
import '../../domain/models/observation.dart';
import '../../domain/repositories/day_entries_repository.dart';
import '../../domain/repositories/observations_repository.dart';
import '../../domain/repositories/profile_guardians_repository.dart';
import '../../domain/repositories/settings_store.dart';
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
import 'cycle_recap_card.dart';
import 'phase_insights_card.dart';
import 'symptom_trends_section.dart';

/// The pure insights derivation this tab memoises (issue #841) — production
/// always uses [CycleInsightsCalculator.compute]. Exposed as a widget
/// parameter only so a test can inject a counting wrapper and prove the
/// report is derived once per changed input rather than once per rebuild.
typedef CycleInsightsComputer = CycleInsightsReport Function({
  required List<DayEntry> entries,
  required List<Episode> episodes,
  ActivePrediction? prediction,
});

class AnalysisTab extends StatefulWidget {
  const AnalysisTab({
    super.key,
    required this.profileId,
    this.mode = ProfileMode.standard,
    this.irregularFraming,
    this.todayProvider = LocalDate.today,
    this.readOnly = false,
    this.guardiansRepository,
    this.dayEntriesRepository,
    this.observationsRepository,
    this.insightsCalculator,
    this.settingsStore,
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

  /// Issue #853: the profile's stored irregular-framing tri-state (null =
  /// engine default), resolved against the live prediction's tier by
  /// [_copyFor] — same rule as [OverviewPanel.irregularFraming].
  final bool? irregularFraming;

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

  /// Test seam (issue #841): the pure insights derivation this tab caches.
  /// Null selects [CycleInsightsCalculator.compute] in production.
  final CycleInsightsComputer? insightsCalculator;

  /// Source of this tab's device-local recap baseline (issue #852). Null
  /// falls back to `context.read<SettingsStore?>()`; when neither is
  /// present the recap simply never renders (there would be no way to
  /// remember a dismissal, so showing it would risk repeating the moment).
  final SettingsStore? settingsStore;

  @override
  State<AnalysisTab> createState() => _AnalysisTabState();
}

class _AnalysisTabState extends State<AnalysisTab>
    with GuardianWatchMixin<AnalysisTab> {
  late final CyclePredictionService _service = context
      .read<CyclePredictionService>();
  StreamSubscription<CyclePrediction>? _predictionSub;

  /// The latest prediction snapshot, driven by [_predictionSub] rather than
  /// a `StreamBuilder` (issue #841): the derived report is computed in that
  /// listener, so it must run once per *emission*, not on every build.
  AsyncSnapshot<CyclePrediction> _predictionSnapshot =
      const AsyncSnapshot<CyclePrediction>.nothing();
  CyclePrediction? _prediction;

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

  /// Monotonic token for the entries-tick coalescing (issue #841): a tick
  /// snapshots it before the observations read and applies its result only
  /// if it is still the newest, so a slow read can never clobber a newer
  /// tick's state (or a different profile's, since [_watchEntries] bumps it
  /// on reset).
  int _entriesTick = 0;

  /// Memoised insight derivation (issue #841). [_report] and [_episodes]
  /// are recomputed only when [_reportEntries]/[_reportPrediction] (and
  /// [_episodeEntries]) are not `identical` to the current inputs — the
  /// `identical` guard is deliberate: an unchanged prediction is already
  /// dropped upstream (#940's `.distinct(identical)`), and the two-setState
  /// path is what would otherwise recompute the same list twice.
  List<DayEntry>? _reportEntries;
  CyclePrediction? _reportPrediction;
  CycleInsightsReport _report = CycleInsightsReport.empty;
  List<DayEntry>? _episodeEntries;
  List<Episode> _episodes = const [];

  /// Issue #852: the device-local recap baseline and the derived recap.
  /// [_recapStateLoaded] gates baseline establishment until the stored
  /// record has actually been read, so the first stream emission can never
  /// write a baseline that the load then overwrites.
  SettingsStore? _settingsStore;
  CycleRecapState _recapState = CycleRecapState.empty;
  bool _recapStateLoaded = false;
  bool _entriesLoaded = false;
  CycleRecap? _recap;
  List<DayEntry>? _recapEntries;
  CyclePrediction? _recapPrediction;
  CycleInsightsReport? _recapReport;
  CycleRecapState? _recapStateUsed;

  /// Issue #853: the composed copy — mode composed with the effective
  /// irregular framing (stored tri-state resolved against [prediction]'s
  /// tier; a null tier — not-enough-history/suppressed/disabled — keeps a
  /// teen's framing ON). Same rule as [OverviewPanel._copyFor]. Replaces
  /// the pre-#853 single-axis getter: every copy read here flows through
  /// the composition, never the raw mode axis.
  CareModeCopy _copyFor(CyclePrediction prediction) => careModeCopyFor(
        widget.mode,
        irregularFraming: irregularFramingInEffect(
          mode: widget.mode,
          stored: widget.irregularFraming,
          tier: prediction is ActivePrediction ? prediction.tier : null,
        ),
      );

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthController?>();
    if (auth != null) {
      _currentUserId = auth.currentUserId;
      auth.addListener(_onAuthChanged);
      _auth = auth;
    }
    _settingsStore = widget.settingsStore ?? context.read<SettingsStore?>();
    _subscribePredictions();
    _watchGuardians();
    _watchEntries();
    unawaited(_loadRecapState());
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

  /// (Re)subscribes [_predictionSub]. Replacing the old `StreamBuilder`
  /// (issue #841) is what lets [_onPrediction] do the report computation
  /// once per emission instead of once per build; the snapshot is still fed
  /// to the same [AsyncSnapshotView] so loading/error/retry are unchanged.
  void _subscribePredictions() {
    unawaited(_predictionSub?.cancel());
    _predictionSub = _service
        .watch(widget.profileId, today: widget.todayProvider)
        .listen(_onPrediction, onError: _onPredictionError);
  }

  void _onPrediction(CyclePrediction prediction) {
    if (!mounted) return;
    setState(() {
      _prediction = prediction;
      _predictionSnapshot = AsyncSnapshot<CyclePrediction>.withData(
        ConnectionState.active,
        prediction,
      );
      _recomputeInsights();
      _recomputeRecap();
    });
  }

  void _onPredictionError(Object error, StackTrace stackTrace) {
    if (!mounted) return;
    setState(() {
      _predictionSnapshot = AsyncSnapshot<CyclePrediction>.withError(
        ConnectionState.active,
        error,
        stackTrace,
      );
    });
  }

  /// #543: re-subscribes after a stream error — `InlineError`'s Retry
  /// callback on the top-level [AsyncSnapshotView].
  void _retryPredictions() {
    setState(() {
      _predictionSnapshot = const AsyncSnapshot<CyclePrediction>.nothing();
    });
    _subscribePredictions();
  }

  void _watchEntries() {
    unawaited(_entriesSub?.cancel());
    _entries = const [];
    _observations = const [];
    _entriesTick++;
    // A profile switch must never render the previous profile's derived
    // report or BBT chart; clearing the memo keys forces a fresh
    // derivation on the next emission.
    _reportEntries = null;
    _reportPrediction = null;
    _report = CycleInsightsReport.empty;
    _episodeEntries = null;
    _episodes = const [];
    // Same reasoning for the recap (issue #852): never render the previous
    // profile's recap while the new one's entries stream warms up.
    _entriesLoaded = false;
    _recap = null;
    _recapEntries = null;
    _recapPrediction = null;
    _recapReport = null;
    _recapStateUsed = null;
    final repository =
        widget.dayEntriesRepository ?? context.read<DayEntriesRepository?>();
    if (repository == null) return;
    _entriesSub = repository.watchForProfile(widget.profileId).listen(
      _onEntries,
    );
  }

  void _onEntries(List<DayEntry> entries) {
    if (!mounted) return;
    unawaited(_applyEntriesTick(entries));
  }

  /// Issue #841: the entries tick coalesces both reads into **one**
  /// `setState` once the observations read lands — previously `_entries`
  /// was set immediately and `_observations` in a later turn, so every
  /// write rebuilt the tab twice and recomputed the report at least three
  /// times.
  Future<void> _applyEntriesTick(List<DayEntry> entries) async {
    final token = ++_entriesTick;
    final observations = await _readObservations();
    if (!mounted || token != _entriesTick) return;
    setState(() {
      _entries = entries;
      _entriesLoaded = true;
      if (observations != null) _observations = observations;
      _recomputeInsights();
      _recomputeRecap();
    });
  }

  /// The observations read stays profile-wide (issue #841 deliberately did
  /// **not** window it): the BBT chart's value-range caption and its
  /// `maxCycleDay` are computed over every episode-derived series, so a
  /// date-bounded read would change what the chart renders. Null when no
  /// repository is in scope (the tick then applies entries alone).
  Future<List<Observation>?> _readObservations() async {
    final repository = widget.observationsRepository ??
        context.read<ObservationsRepository?>();
    if (repository == null) return null;
    return repository.listForProfile(widget.profileId);
  }

  /// Re-reads observations when the injected seam itself changes
  /// (`didUpdateWidget`), without disturbing the entries tick.
  Future<void> _refreshObservations() async {
    final observations = await _readObservations();
    if (!mounted || observations == null) return;
    setState(() => _observations = observations);
  }

  void _recomputeInsights() {
    if (identical(_reportEntries, _entries) &&
        identical(_reportPrediction, _prediction)) {
      return;
    }
    _reportEntries = _entries;
    _reportPrediction = _prediction;
    final prediction = _prediction;
    final computer =
        widget.insightsCalculator ?? CycleInsightsCalculator.compute;
    _report = computer(
      entries: _entries,
      episodes: _episodesFor(_entries),
      prediction: prediction is ActivePrediction ? prediction : null,
    );
  }

  List<Episode> _episodesFor(List<DayEntry> entries) {
    if (identical(_episodeEntries, entries)) return _episodes;
    _episodeEntries = entries;
    _episodes = deriveEpisodes(bleedDatesOf(entries));
    return _episodes;
  }

  /// Reads this profile's stored recap baseline (issue #852). Until this
  /// completes, [_maybeEstablishBaseline] refuses to write — otherwise the
  /// first entries emission could baseline before the load, and the load
  /// would then overwrite it.
  Future<void> _loadRecapState() async {
    final store = _settingsStore;
    if (store == null) return;
    final raw = await store.get(cycleRecapSettingKey(widget.profileId));
    if (!mounted) return;
    setState(() {
      _recapState = decodeCycleRecapState(raw);
      _recapStateLoaded = true;
      _recomputeRecap();
    });
  }

  /// Memoised recap derivation, mirroring [_recomputeInsights]'s identity
  /// guard: the same pure [deriveCycleRecap] runs only when the entries,
  /// prediction, report, or stored baseline actually changed.
  void _recomputeRecap() {
    if (identical(_recapEntries, _entries) &&
        identical(_recapPrediction, _prediction) &&
        identical(_recapReport, _report) &&
        identical(_recapStateUsed, _recapState)) {
      return;
    }
    _recapEntries = _entries;
    _recapPrediction = _prediction;
    _recapReport = _report;
    _recapStateUsed = _recapState;
    _recap = deriveCycleRecap(
      entries: _entries,
      prediction: _prediction,
      report: _report,
      today: widget.todayProvider(),
      previousSnapshot: _recapState.snapshot,
    );
    _maybeEstablishBaseline();
  }

  /// One-time baseline (issue #852): on the first observation of a profile
  /// with a stored-but-unrecorded state, remember the cycle that has
  /// already closed without showing a recap for it, so only cycles that
  /// complete *after* this device started watching are ever surfaced.
  void _maybeEstablishBaseline() {
    final store = _settingsStore;
    if (!_recapStateLoaded ||
        store == null ||
        _recapState.recorded ||
        !_entriesLoaded) {
      return;
    }
    final recap = _recap;
    final next = CycleRecapState(
      recorded: true,
      seenCycleIso: recap?.cycleStart.iso,
      snapshot: recap?.currentSnapshot,
    );
    _recapState = next;
    _recapStateUsed = next;
    unawaited(
      store.set(
        cycleRecapSettingKey(widget.profileId),
        encodeCycleRecapState(next),
      ),
    );
    // Recompute once with the new baseline so a snapshot can never be
    // compared against itself on the next emission.
    _recomputeRecap();
  }

  /// Persists the dismissal for [recap]'s cycle and hides the card.
  void _dismissRecap(CycleRecap recap) {
    final next = CycleRecapState(
      recorded: true,
      seenCycleIso: recap.cycleStart.iso,
      snapshot: recap.currentSnapshot,
    );
    setState(() {
      _recapState = next;
      _recapStateUsed = next;
    });
    final store = _settingsStore;
    if (store == null) return;
    unawaited(
      store.set(
        cycleRecapSettingKey(widget.profileId),
        encodeCycleRecapState(next),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant AnalysisTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId) {
      _recapState = CycleRecapState.empty;
      _recapStateLoaded = false;
      _subscribePredictions();
      _watchGuardians();
      _watchEntries();
      unawaited(_loadRecapState());
      return;
    }
    // Issue #574: same profile, but `guardiansRepository`/`todayProvider`
    // changed underneath it — re-run just the watch that reads the changed
    // collaborator.
    if (oldWidget.guardiansRepository != widget.guardiansRepository) {
      _watchGuardians();
    }
    if (oldWidget.observationsRepository != widget.observationsRepository) {
      unawaited(_refreshObservations());
    }
    if (oldWidget.todayProvider != widget.todayProvider) {
      _subscribePredictions();
    }
  }

  @override
  void dispose() {
    disposeGuardianWatch();
    unawaited(_predictionSub?.cancel());
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
    return AsyncSnapshotView<CyclePrediction>(
      snapshot: _predictionSnapshot,
      errorMessage: 'Could not load your cycle analysis.',
      onRetry: _retryPredictions,
      builder: (context, prediction) => ListView(
        padding: const EdgeInsets.all(LLSpace.space4),
        children: _sections(context, prediction),
      ),
    );
  }

  /// Section list — mounts headline statistics, phase insights (#236),
  /// symptom trends & cramp forecasts (#135/#229), and the cycle history list.
  ///
  /// Issue #841: [report] and [episodes] are read from the memoised state
  /// [_recomputeInsights] maintains, never recomputed here — a build must
  /// not re-derive them.
  List<Widget> _sections(BuildContext context, CyclePrediction prediction) {
    final episodes = _episodes;
    final report = _report;

    return [
      Text(
        'Analysis',
        key: const ValueKey('analysis-heading'),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: LLSpace.space3),
      // Issue #852: the cycle-end recap leads the tab — a moment worth
      // returning for, shown once per completed cycle and dismissible
      // without covering a single log affordance.
      ..._recapSection(context),
      switch (prediction) {
        ActivePrediction() => _statsCard(context, prediction),
        NotEnoughHistory() => _notEnoughCard(context, prediction),
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
        // Issue #816: hand the history header the engine's own tally so its
        // "N of 3 completed cycles" line can never disagree with the empty
        // state above it. Null in every other prediction state.
        notEnough: prediction is NotEnoughHistory ? prediction : null,
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

  /// The recap section (issue #852) or nothing at all — split out of
  /// [_sections] to keep that method's own branch count low (the quality
  /// gate's per-method CRAP rule).
  List<Widget> _recapSection(BuildContext context) {
    final recap = _recap;
    if (recap == null ||
        !_recapState.recorded ||
        _recapState.seenCycleIso == recap.cycleStart.iso) {
      return const [];
    }
    return [_recapCard(context, recap), const SizedBox(height: LLSpace.space3)];
  }

  Widget _recapCard(BuildContext context, CycleRecap recap) {
    final prediction = _prediction;
    return CycleRecapCard(
      recap: recap,
      // Issue #853: the recap's suppression follows the composed irregular
      // framing, not the raw mode axis, so a migrated legacy `irregular`
      // profile and a teen whose cycles are still settling both keep the
      // false-precision language off.
      irregularFraming: irregularFramingInEffect(
        mode: widget.mode,
        stored: widget.irregularFraming,
        tier: prediction is ActivePrediction ? prediction.tier : null,
      ),
      onDismiss: () => _dismissRecap(recap),
      onCompare: recap.previousCycleStart == null
          ? null
          : () => Navigator.of(context).push(
                CycleComparisonScreen.route(
                  profileId: widget.profileId,
                  cycleAStart: recap.previousCycleStart!,
                  cycleBStart: recap.cycleStart,
                  todayProvider: widget.todayProvider,
                ),
              ),
    );
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
            ..._headlineStats(context, theme, l10n, prediction, _copyFor(prediction)),
            ..._fertileWindowSection(context, theme, l10n, prediction, _copyFor(prediction)),
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
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
    ActivePrediction prediction,
    CareModeCopy copy,
  ) {
    return [
      _statRow(
        context,
        theme,
        'analysis-mean-cycle-length',
        'Average cycle length',
        formatDays(l10n, prediction.meanCycleLengthDays),
      ),
      _statRow(
        context,
        theme,
        'analysis-mean-period-length',
        'Average period length',
        formatDays(l10n, prediction.meanPeriodLengthDays),
      ),
      _statRow(
        context,
        theme,
        'analysis-variability',
        'Variability',
        _variabilityText(l10n, prediction, copy),
      ),
    ];
  }

  String _variabilityText(
    AppLocalizations l10n,
    ActivePrediction prediction,
    CareModeCopy copy,
  ) {
    final spread = '±${prediction.spreadDays.round()} days';
    if (!copy.showsTierCaption) return spread;
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
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
    ActivePrediction prediction,
    CareModeCopy copy,
  ) {
    if (!copy.showsFertileWindow) return const [];
    final fertile = currentFertileWindow(prediction);
    if (fertile == null) return const [];
    return [
      _statRow(
        context,
        theme,
        'analysis-fertile-window',
        copy.fertileWindowLabel,
        _fertileWindowText(l10n, fertile, copy),
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
    CareModeCopy copy,
  ) {
    final range =
        '${_formatDate(fertile.windowStart)} – ${_formatDate(fertile.windowEnd)}';
    if (!copy.showsTierCaption) return range;
    return '${tierLabel(l10n, fertile.tier)} ($range)';
  }

  // Issue #160: locale-derived long date (the `en` fallback renders
  // "August 16, 2026", the same shape the old kMonthNames concatenation gave).
  String _formatDate(LocalDate date) =>
      dates.formatLocalDateMonthDayYear(date);

  // Issue #143 review / Issue #836: the fertile-window row's value ("High confidence
  // (August 16, 2026 – August 22, 2026)") and large Dynamic Type scales cause
  // horizontal overflow or mid-word breaks if forced into a side-by-side Row.
  // When text scale is large (> 1.2) or constraints are narrow (< 320), the
  // row stacks vertically so label and value have full width to wrap naturally.
  // In side-by-side mode, Flexible on the label prevents horizontal overflow.
  Widget _statRow(
    BuildContext context,
    ThemeData theme,
    String key,
    String label,
    String value,
  ) {
    // Issue #813: the value is the content, so it carries the weight and a
    // tabular-figure ramp (numbers line up column-wise); the label is a
    // quiet caption. They used to share one `bodyMedium` style, giving a
    // number and its caption equal visual weight.
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final isLargeText =
            textScaler.scale(1) > 1.2 || constraints.maxWidth < 320;

        if (isLargeText) {
          return Padding(
            padding: const EdgeInsets.only(bottom: LLSpace.space2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: labelStyle),
                const SizedBox(height: LLSpace.space1),
                Text(value, key: ValueKey(key), style: valueStyle),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: LLSpace.space1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(label, style: labelStyle),
              ),
              const SizedBox(width: LLSpace.space2),
              Expanded(
                child: Text(
                  value,
                  key: ValueKey(key),
                  textAlign: TextAlign.end,
                  style: valueStyle,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Same posture as [OverviewPanel._notEnoughCard]: a loaded-but-empty
  /// result, not a loading state (issue #187), so it renders through
  /// [EmptyState] with the disclaimer alongside it as a plain [Text].
  /// Issue #816: the body comes from [prediction]'s live tally (the same
  /// "N of 3 completed cycles" the history header below shows), never a
  /// vague "a few cycles".
  Widget _notEnoughCard(BuildContext context, NotEnoughHistory prediction) {
    final theme = Theme.of(context);
    final copy = _copyFor(prediction);
    return Card(
      key: const ValueKey('analysis-not-enough'),
      child: Padding(
        padding: const EdgeInsets.all(LLSpace.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EmptyState(
              title: copy.notEnoughTitle,
              body: copy.notEnoughBody(
                prediction.usableCycleCount,
                kMinCompletedValidCycles,
              ),
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
            // Issue #816: the label names the unit the threshold counts.
            const HelpCardLink(
              cardId: 'why-no-estimate-yet',
              label: 'Why three completed cycles?',
            ),
          ],
        ),
      ),
    );
  }
}
