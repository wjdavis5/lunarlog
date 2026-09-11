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
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/repositories/profile_guardians_repository.dart';
import '../../domain/care_modes.dart';
import '../../domain/models/local_date.dart';
import '../../domain/models/profile_guardian.dart';
import '../../domain/models/profile_mode.dart';
import '../../domain/prediction/fertile_window.dart';
import '../../domain/prediction/prediction.dart';
import '../../domain/prediction/prediction_service.dart';
import '../account/auth_controller.dart';
import '../components/empty_state.dart';
import '../help/help_card_view.dart';
import 'package:lunarlog/ui/l10n/dates.dart' as dates;
import '../overview/cycle_history_section.dart';
import '../overview/overview_panel.dart'
    show kEstimateDisclaimer, kFertileWindowDisclaimer;

class AnalysisTab extends StatefulWidget {
  const AnalysisTab({
    super.key,
    required this.profileId,
    this.mode = ProfileMode.standard,
    this.todayProvider = LocalDate.today,
    this.readOnly = false,
    this.guardiansRepository,
  });

  final String profileId;

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

class _AnalysisTabState extends State<AnalysisTab> {
  late final CyclePredictionService _service =
      context.read<CyclePredictionService>();
  late Stream<CyclePrediction> _predictions = _service.watch(
    widget.profileId,
    today: widget.todayProvider,
  );

  StreamSubscription<List<ProfileGuardian>>? _guardiansSub;
  AuthController? _auth;
  String? _currentUserId;
  List<ProfileGuardian> _guardians = const [];

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
  }

  // The listener is only ever registered while [_auth] is non-null and is
  // removed (with [_auth] cleared) in dispose, so a single mounted check is
  // the whole guard; kept minimal because this handler has no widget-test
  // trigger and the CRAP gate scores uncovered branches quadratically.
  void _onAuthChanged() {
    if (!mounted) return;
    setState(() => _currentUserId = _auth?.currentUserId);
  }

  /// Same shape as [OverviewPanel._watchGuardians]: resubscribes on every
  /// call (profile switch included) and resets to an empty list first so
  /// a still-arriving subscription for the old profile can never be
  /// mistaken for the new one's guardians.
  void _watchGuardians() {
    _guardiansSub?.cancel();
    _guardians = const [];
    final repository = widget.guardiansRepository;
    if (repository == null) return;
    _guardiansSub = repository.watchForProfile(widget.profileId).listen((
      guardians,
    ) {
      if (!mounted) return;
      setState(() => _guardians = guardians);
    });
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
    }
  }

  @override
  void dispose() {
    _guardiansSub?.cancel();
    _guardiansSub = null;
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
        final prediction = snapshot.data;
        if (prediction == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: _sections(context, prediction),
        );
      },
    );
  }

  /// Section list — the seam #135 (statistics/trends) mounts an additional
  /// entry into once that issue lands. #135 mounts here.
  List<Widget> _sections(BuildContext context, CyclePrediction prediction) {
    return [
      Text(
        'Analysis',
        key: const ValueKey('analysis-heading'),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      switch (prediction) {
        ActivePrediction() => _statsCard(context, prediction),
        NotEnoughHistory() => _notEnoughCard(context),
      },
      const SizedBox(height: 16),
      CycleHistorySection(
        profileId: widget.profileId,
        todayProvider: widget.todayProvider,
        readOnly: _effectiveReadOnly,
        showStatistics: false,
        showDisclaimer: false,
      ),
    ];
  }

  Widget _statsCard(BuildContext context, ActivePrediction prediction) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('analysis-stats'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cycle statistics',
              key: const ValueKey('analysis-stats-title'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ..._headlineStats(theme, prediction),
            ..._fertileWindowSection(theme, prediction),
            const SizedBox(height: 12),
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
  List<Widget> _headlineStats(ThemeData theme, ActivePrediction prediction) {
    return [
      _statRow(
        theme,
        'analysis-mean-cycle-length',
        'Average cycle length',
        formatDays(prediction.meanCycleLengthDays),
      ),
      _statRow(
        theme,
        'analysis-mean-period-length',
        'Average period length',
        formatDays(prediction.meanPeriodLengthDays),
      ),
      _statRow(
        theme,
        'analysis-variability',
        'Variability',
        _variabilityText(prediction),
      ),
    ];
  }

  String _variabilityText(ActivePrediction prediction) {
    final spread = '±${prediction.spreadDays.round()} days';
    if (!_copy.showsTierCaption) return spread;
    return '${prediction.tier.label} ($spread)';
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
        _fertileWindowText(fertile),
      ),
      const SizedBox(height: 4),
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
  String _fertileWindowText(FertileWindowEstimate fertile) {
    final range =
        '${_formatDate(fertile.windowStart)} – ${_formatDate(fertile.windowEnd)}';
    if (!_copy.showsTierCaption) return range;
    return '${fertile.tier.label} ($range)';
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
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          const SizedBox(width: 8),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EmptyState(
              title: _copy.notEnoughTitle,
              body: _copy.notEnoughBody,
              titleStyle: theme.textTheme.headlineSmall,
              crossAxisAlignment: CrossAxisAlignment.start,
            ),
            const SizedBox(height: 8),
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
