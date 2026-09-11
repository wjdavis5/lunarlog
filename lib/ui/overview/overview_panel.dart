/// Overview panel (U6, R11/R13/R17): the prediction summary for one
/// profile, rendered from the U3 [CyclePredictionService] stream so it
/// refreshes as entries are logged (F4 in-app half).
///
/// Issue #132 adds the two surfaces below the estimate card: the
/// three-option late resolver (R6) replacing the old single-line banner,
/// and the cycle-history section (R4/R5) with omit-from-average,
/// statistics, and confidence framing. Wording is date-based only here —
/// #143's fertile-window/ovulation estimate renders on the Analysis tab
/// (`AnalysisTab`) and the forward calendar (`month_calendar.dart`)
/// instead, never on this panel — and every estimate sits next to the
/// fixed non-medical disclaimer (R17). No drift types cross into this
/// file.
///
/// Issue #131: the profile's care mode selects the vocabulary
/// (`careModeCopyFor`) — status labels, estimate framing, and the
/// empty/insufficient-history copy. `irregular` additionally silences the
/// late resolver, replacing it with a quiet status line; the disclaimer
/// stays next to every estimate in every mode, without exception.
///
/// Issue #221/A2-11/A2-12: the old dead-end "predictions paused" card is
/// gone — an open cycle past sixty days stays an active, rolled-forward
/// estimate (at `irregular` confidence) with its own "this cycle is
/// unusually long" prompt instead, so this panel never renders a state
/// with no date and no way forward.
///
/// Issue #314: [CycleHistorySection] no longer mounts here -- once #223
/// gave the Analysis tab (`insights/analysis_tab.dart`) its own mount of
/// the same section, this panel's copy rendered a second time and ran a
/// second, redundant `CycleHistoryService.watch` subscription per profile.
/// This panel keeps the late resolver and the long-cycle prompt's "Exclude
/// this cycle" (both use [CycleExclusionList] directly, never the
/// section's own widget state) and, in their place, a "See cycle history"
/// link that switches to Insights through the #313 tab-switch seam
/// ([AppShellScope]) -- hidden entirely when no shell is mounted above
/// this panel (`ProfileDetailScreen`'s archived read-only view, and any
/// test tree that pumps this panel directly).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunarlog/app_lifecycle.dart'
    show RequestNotificationPermissionCallback;
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/care_modes.dart';
import 'package:lunarlog/domain/logging/quick_log.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/pms.dart' show PmsEstimate;
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/util/timezone.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/components/app_shell_scope.dart';
import 'package:lunarlog/ui/components/empty_state.dart';
import 'package:lunarlog/ui/components/today_card.dart';
import 'package:lunarlog/ui/help/help_card_view.dart';
import 'package:lunarlog/ui/l10n/dates.dart' as dates;
import 'package:lunarlog/ui/l10n/tiers.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/overview/estimate_copy.dart';
import 'package:lunarlog/ui/overview/late_resolver.dart';
import 'package:lunarlog/ui/overview/notification_permission_state.dart';
import 'package:provider/provider.dart';

// Issue #316 review: re-exported (not just imported) so
// `month_calendar.dart`'s existing `import '...overview_panel.dart' show
// kEstimateDisclaimer` keeps resolving unchanged -- see
// `estimate_copy.dart`'s doc comment for why the constant itself moved out
// of this file (it broke a mutual import with `today_card.dart`).
export 'package:lunarlog/ui/overview/estimate_copy.dart'
    show kEstimateDisclaimer, kFertileWindowDisclaimer;

/// Issue #213: `high` confidence keeps the single exact-date estimate
/// (unchanged from before this issue); any other tier renders the range
/// `estimatedRangeStart`–`estimatedRangeEnd` instead of one exact date,
/// per the issue's own display rule — except when that range is
/// degenerate (a spread that rounds to zero days, e.g. a perfectly steady
/// history that has not yet filled the 6-cycle average window): showing
/// "June 18, 2026 – June 18, 2026" would be a redundant, confusing range
/// for a single date, so that case falls back to the plain date instead.
/// Issue #160: month names are locale-derived via `lib/ui/l10n/dates.dart`,
/// replacing the old `kMonthNames` list this file used to re-import.
String _estimateDateText(ActivePrediction prediction, String locale) {
  String format(LocalDate date) => dates.formatMonthDayYear(
        DateTime(date.year, date.month, date.day),
        locale: locale,
      );
  if (prediction.tier == CycleConfidence.high) {
    return format(prediction.estimatedNextStart);
  }
  final rangeStart = prediction.estimatedRangeStart;
  final rangeEnd = prediction.estimatedRangeEnd;
  if (rangeStart == rangeEnd) {
    return format(prediction.estimatedNextStart);
  }
  return '${format(rangeStart)} – ${format(rangeEnd)}';
}

class OverviewPanel extends StatefulWidget {
  const OverviewPanel({
    super.key,
    required this.profileId,
    this.mode = ProfileMode.standard,
    this.todayProvider = LocalDate.today,
    this.readOnly = false,
    this.timezoneProvider,
    this.guardiansRepository,
    this.trailingChildren = const [],
  });

  final String profileId;

  /// The profile's care mode (Issue #131): selects the vocabulary below.
  /// Presentation only — it never changes what any guardian role may read
  /// or write ([_effectiveReadOnly] consults roles alone).
  final ProfileMode mode;

  /// "Today" as the device-local civil date; injectable for tests.
  final LocalDate Function() todayProvider;

  /// Archived-profile read-only (U5): the resolver shows no actions.
  /// (Issue #314: this panel itself never mounts the history list any
  /// more -- see the file doc comment. `ProfileDetailScreen`'s archived
  /// view, the only caller that still sets this, mounts its own read-only
  /// `CycleHistorySection` separately, below this panel, since it has no
  /// shell above it for this panel's "See cycle history" link to reach.)
  final bool readOnly;

  /// Provider for the resolved IANA time zone identifier (paired with
  /// #38); passed to the day sheet the resolver's "log it" opens.
  final String Function()? timezoneProvider;

  /// Source of this profile's guardians for the viewer-role read-only
  /// check (same shape as [MonthCalendar.guardiansRepository]); null in
  /// local-only use.
  final ProfileGuardiansRepository? guardiansRepository;

  /// Issue #314 review item 3: extra widgets appended below this panel's
  /// own content, inside the same [ListView] -- one scroll region rather
  /// than a caller stacking a second scrollable underneath. `
  /// ProfileDetailScreen`'s archived view uses this to place its read-only
  /// [CycleHistorySection] here instead of in its own `Expanded`
  /// `SingleChildScrollView` half.
  final List<Widget> trailingChildren;

  @override
  State<OverviewPanel> createState() => _OverviewPanelState();
}

class _OverviewPanelState extends State<OverviewPanel> {
  late CyclePredictionService _service;
  late Stream<CyclePrediction> _predictions;
  // Captured once (matches _resolverFor/cycle_history_section.dart's
  // pattern) rather than re-reading context.read inside a button callback.
  late final CycleExclusionList _exclusions = context
      .read<CycleExclusionList>();
  StreamSubscription<List<ProfileGuardian>>? _guardiansSub;
  AuthController? _auth;
  String? _currentUserId;
  List<ProfileGuardian> _guardians = const [];

  /// The mode's vocabulary (Issue #131), resolved once per build.
  CareModeCopy get _copy => careModeCopyFor(widget.mode);

  @override
  void initState() {
    super.initState();
    _service = context.read<CyclePredictionService>();
    _predictions = _service.watch(
      widget.profileId,
      today: widget.todayProvider,
    );
    final auth = context.read<AuthController?>();
    if (auth != null) {
      _currentUserId = auth.currentUserId;
      auth.addListener(_onAuthChanged);
      _auth = auth;
    }
    _watchGuardians();
  }

  void _onAuthChanged() {
    final auth = _auth;
    if (auth == null || !mounted) return;
    setState(() => _currentUserId = auth.currentUserId);
  }

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
  void didUpdateWidget(covariant OverviewPanel oldWidget) {
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

  /// Same effective read-only rule as [MonthCalendar]: archived, or the
  /// caller's accepted role is `viewer`. Fails open on an unknown role
  /// (no guardian rows yet, no signed-in operator, no matching row).
  bool get _effectiveReadOnly =>
      widget.readOnly ||
      acceptedGuardianFor(_guardians, _currentUserId)?.role.canLog == false;

  /// The resolver's "log it" (R6): the ordinary day sheet on today's
  /// date — the same logging surface the calendar opens.
  Future<void> _logItToday() async {
    final repository = context.read<DayEntriesRepository>();
    final today = widget.todayProvider();
    final existing = await repository.find(widget.profileId, today);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      routeSettings: const RouteSettings(name: kRouteDaySheetScreen),
      builder: (_) => DaySheet(
        repository: repository,
        profileId: widget.profileId,
        date: today,
        existing: existing,
        today: today,
        mode: widget.mode,
        readOnly: _effectiveReadOnly,
        timezoneProvider: widget.timezoneProvider,
        currentUserId: _currentUserId,
        guardians: _guardians,
      ),
    );
  }

  /// [TodayCard]'s primary "Period started today" action (issue #209 item
  /// 4c): an upsert through the same [DayEntriesRepository] the day sheet
  /// uses — not a second write path. [quickLogFlowLevel] keeps a second
  /// tap (or a day already logged heavier than the quick-log default, via
  /// the full day sheet) from ever downgrading an existing flow level, and
  /// the upsert-by-(profileId, date) identity keeps a second tap from ever
  /// creating a second entry.
  ///
  /// Issue #316 review: `tz` is now recomputed from [widget.timezoneProvider]
  /// the same way [DaySheet._save] does, rather than silently keeping a
  /// pre-existing entry's stale zone; the old `now` bump on the existing-entry
  /// branch was dead code -- the drift repository's `save` never reads
  /// [DayEntry.updatedAt] back out, it is storage-assigned -- so it is gone
  /// rather than carried along for no effect.
  ///
  /// Deliberately has no `try`/`catch` of its own: a throwing [save] must
  /// propagate to [TodayCard], which is what actually surfaces the failure
  /// (an [InlineError] with Retry) rather than this method swallowing it.
  ///
  /// Issue #316 review item 5 (undo + disclosure): a successful write shows
  /// a confirmation snackbar with an Undo action that restores exactly
  /// what was there before -- the previous [DayEntry] if today already had
  /// one, or a tombstone (through the repository's own delete path, so sync
  /// dirty-marking still applies) if this tap created it.
  Future<void> _logPeriodStartedToday() async {
    final repository = context.read<DayEntriesRepository>();
    final today = widget.todayProvider();
    final previous = await repository.find(widget.profileId, today);
    if (!mounted) return;
    final flow = quickLogFlowLevel(previous?.flow);
    final tz = (widget.timezoneProvider ?? resolveCurrentTimeZone)();
    final entry = previous?.copyWith(flow: flow, tz: tz) ??
        DayEntry(
          id: '',
          profileId: widget.profileId,
          localDate: today,
          tz: tz,
          flow: flow,
          updatedAt: DateTime.now().toUtc(),
        );
    final messenger = ScaffoldMessenger.of(context);
    await repository.save(entry);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    messenger.showSnackBar(SnackBar(
      content: Text(
        l10n.overviewLoggedSnackbar,
        key: const ValueKey('today-card-logged-snackbar'),
      ),
      action: SnackBarAction(
        label: l10n.overviewUndo,
        onPressed: () => _undoLogToday(previous, today),
      ),
    ));
  }

  /// Restores exactly what [_logPeriodStartedToday] overwrote: the prior
  /// [DayEntry] (flow/tags/note preserved) if today already had one, or a
  /// tombstone if the quick-log tap is what created it. Goes through
  /// [DayEntriesRepository] either way -- never a bespoke undo path -- so
  /// sync dirty-marking applies exactly as it would to any other edit.
  Future<void> _undoLogToday(DayEntry? previous, LocalDate today) async {
    final repository = context.read<DayEntriesRepository>();
    if (previous == null) {
      await repository.delete(widget.profileId, today);
    } else {
      await repository.save(previous);
    }
  }

  @override
  Widget build(BuildContext context) {
    final availability = context.watch<NotificationPermissionState>().value;
    return StreamBuilder<CyclePrediction>(
      stream: _predictions,
      builder: (context, snapshot) {
        final prediction = snapshot.data;
        if (prediction == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            switch (prediction) {
              ActivePrediction() => _activeCard(context, prediction),
              NotEnoughHistory() => _notEnoughCard(context),
            },
            _seeHistoryLink(context),
            if (availability == NotificationAvailability.denied)
              const _ReminderHint(),
            ...widget.trailingChildren,
          ],
        );
      },
    );
  }

  /// Issue #314: replaces the [CycleHistorySection] this panel used to
  /// mount directly -- the history list now lives exclusively on Insights
  /// ([AnalysisTab]), so this is a link there instead of a second copy of
  /// the section. [AppShellScope.maybeOf] is null in
  /// `ProfileDetailScreen`'s archived read-only view (no shell mounted
  /// above it) and in any test tree that pumps this panel on its own; in
  /// both cases there is nowhere for the link to switch to, so it renders
  /// nothing rather than a dead button.
  Widget _seeHistoryLink(BuildContext context) {
    final scope = AppShellScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: const ValueKey('overview-see-history-link'),
          onPressed: () => scope.select(AppTab.insights),
          child: Text(AppLocalizations.of(context).overviewSeeHistory),
        ),
      ),
    );
  }

  Widget _resolverFor(ActivePrediction prediction) => LateResolver(
    profileId: widget.profileId,
    prediction: prediction,
    exclusions: _exclusions,
    settings: context.read<SettingsStore>(),
    onLogIt: _logItToday,
    todayProvider: widget.todayProvider,
    readOnly: _effectiveReadOnly,
  );

  /// Issue #131: `irregular` silences the late resolver — the error-styled
  /// banner with log-it/skip/remind actions never renders in that mode.
  /// The quiet status line that replaces it carries the disclaimer
  /// underneath, exactly as the banner did. Issue #221/A2-12: this is also
  /// what renders for an unusually-long-open cycle now (folded into
  /// [ActivePrediction] — there is no separate paused state to gate here
  /// any more).
  Widget _lateSectionFor(ActivePrediction prediction, ThemeData theme) {
    if (_copy.silencesLateBanner) {
      return Padding(
        key: const ValueKey('overview-irregular-overdue'),
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _copy.overdueStatusLabel,
              key: const ValueKey('overview-irregular-overdue-line'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
          ],
        ),
      );
    }
    return _resolverFor(prediction);
  }

  /// Issue #209: the wheel/estimate/disclaimer/quick-log surface now lives
  /// in [TodayCard], mounted at the top of this card instead of the old
  /// standalone phase headline + next-period-estimate + disclaimer `Text`s
  /// — moved there rather than duplicated, so each still renders exactly
  /// once (the wheel's centre label replaces the old plain-text phase
  /// headline). The tier caption, late resolver/status line, and
  /// long-cycle prompt are unchanged.
  Widget _activeCard(BuildContext context, ActivePrediction prediction) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('overview-active'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TodayCard(
              cycleDay: prediction.cycleDay,
              duringEpisode: prediction.duringEpisode,
              cycleLengthDays: prediction.meanCycleLengthDays.round(),
              periodLengthDays: prediction.meanPeriodLengthDays.round(),
              estimateText:
                  '${_copy.nextEstimateLabel} ${_estimateDateText(prediction, dates.calendarLocale(context))}',
              tier: prediction.tier,
              showConfidenceChip: _copy.showsTierCaption,
              canLog: !_effectiveReadOnly,
              onLogToday: _logPeriodStartedToday,
            ),
            const SizedBox(height: 12),
            // Issue #213: below `high` confidence (`learning` included —
            // #213 item 5), the estimate above is already a range rather
            // than one exact date; this caption names why (no numbers,
            // matching the rest of R11's no-partial-numbers framing).
            // Issue #131 cheap fix: routed through CareModeCopy so
            // `irregular` care mode — which already replaces the late
            // banner with its own quiet, non-numeric framing — can silence
            // this caption rather than showing it twice over.
            // Issue #218: the label/summary route through AppLocalizations
            // (via the shared tier-vocabulary mapper) so the new
            // `provisional` tier renders localized copy, not a hardcoded
            // literal.
            if (_copy.showsTierCaption &&
                prediction.tier != CycleConfidence.high) ...[
              Text(
                '${tierLabel(AppLocalizations.of(context), prediction.tier)}'
                ' — ${tierSummary(AppLocalizations.of(context), prediction.tier)}',
                key: const ValueKey('overview-tier-caption'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
            ],
            // Issue #220: the predicted PMS phase — only when the profile
            // has the 3+ logged PMS intervals the hard minimum requires
            // (below that `pms` is null and nothing renders, never a
            // noisy partial band). The band carries the period estimate's
            // own tier, and — R17, "the disclaimer stays next to every
            // estimate in every mode, without exception" — its own
            // disclaimer line.
            if (prediction.pms != null) ...[
              _pmsSection(context, prediction.pms!, theme),
              const SizedBox(height: 8),
            ],
            if (prediction.isLate || prediction.unusuallyLongCycle)
              _lateSectionFor(prediction, theme)
            else
              Text(
                prediction.untilNextPeriodLabel,
                key: const ValueKey('overview-days-until'),
                style: theme.textTheme.bodyLarge,
              ),
            if (prediction.unusuallyLongCycle) ...[
              const SizedBox(height: 8),
              _longCycleSection(context, prediction, theme),
            ],
          ],
        ),
      ),
    );
  }

  /// Issue #220: the predicted PMS phase line — band range, the 6-cycle
  /// averages behind it, the shared tier vocabulary (the period estimate's
  /// own tier, so no second confidence system), and the fixed
  /// non-medical disclaimer. Rendered only when
  /// `ActivePrediction.pms` is non-null.
  Widget _pmsSection(BuildContext context, PmsEstimate pms, ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    String format(LocalDate date) => dates.formatMonthDayYear(
          DateTime(date.year, date.month, date.day),
          locale: dates.calendarLocale(context),
        );
    final range =
        '${format(pms.predictedStart)} – ${format(pms.predictedEnd)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          key: const ValueKey('overview-pms-band'),
          l10n.overviewPmsBandLabel(range),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 2),
        Text(
          key: const ValueKey('overview-pms-averages'),
          l10n.overviewPmsDaysBeforePeriod(
            pms.meanOnsetDaysBeforeNextPeriod.round(),
            pms.meanLengthDays.round(),
          ),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 2),
        Text(
          key: const ValueKey('overview-pms-tier'),
          tierLabel(l10n, pms.tier),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          kEstimateDisclaimer,
          key: const ValueKey('overview-pms-disclaimer'),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  /// The long-cycle prompt's "Exclude this cycle" action. Persisting the
  /// omission is fire-and-forget from the UI's point of view (same as the
  /// history list's own omit toggle), but unlike that toggle this button
  /// has no other visible state change once pressed — the prompt itself
  /// keeps showing (the cycle is still open) so without this confirmation
  /// the button would read as dead. A brief snackbar echoes that the write
  /// completed instead of adding persistent state to this already-shared
  /// widget state.
  Future<void> _excludeLongCycle(
    BuildContext context,
    ActivePrediction prediction,
  ) async {
    // Captured before the await (both the messenger and the localized
    // copy): nothing touches [context] past the `mounted` check below.
    final messenger = ScaffoldMessenger.of(context);
    final copy = AppLocalizations.of(context).overviewExcludedSnackbar;
    await _exclusions.omit(widget.profileId, prediction.lastEpisodeStart);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(copy)),
    );
  }

  /// Issue #221/A2-12: replaces the old dead-end "predictions paused" card.
  /// Rendered whenever [ActivePrediction.unusuallyLongCycle] is set,
  /// regardless of care mode or [ActivePrediction.isLate] (an unusually
  /// long mean cycle length can push the open cycle past
  /// [kMaxOpenCycleDays] before the grace window on the estimate itself has
  /// elapsed) — a low-confidence rolled estimate is still shown above, and
  /// this offers the two ways out the issue names: exclude the cycle from
  /// future averages (issue #132's existing exclusion list — the same
  /// action as the late resolver's "Skip this cycle"), or turn predictions
  /// off for the profile entirely (issue #225, not yet built — the button
  /// stands in as a discoverable placeholder rather than silently omitting
  /// the option).
  Widget _longCycleSection(
    BuildContext context,
    ActivePrediction prediction,
    ThemeData theme,
  ) {
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const ValueKey('overview-long-cycle-prompt'),
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.overviewLongCycleTitle,
            key: const ValueKey('overview-long-cycle-title'),
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.overviewLongCycleBody,
            key: const ValueKey('overview-long-cycle-body'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          if (!_effectiveReadOnly) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton(
                  key: const ValueKey('long-cycle-exclude'),
                  onPressed: () => _excludeLongCycle(context, prediction),
                  child: Text(l10n.overviewLongCycleExclude),
                ),
                // TODO(#225): wire this up once profile-level "turn
                // predictions off" exists. Until then it stays a disabled,
                // honestly-labeled button rather than a live one that only
                // ever shows a "coming soon" snackbar — a button that always
                // just defers reads as broken, not as a placeholder.
                OutlinedButton(
                  key: const ValueKey('long-cycle-predictions-off'),
                  onPressed: null,
                  child: Text(l10n.overviewLongCyclePredictionsOff),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Issue #187: the not-enough-history state is a loaded-but-empty result
  /// (no cycle history yet), not a loading state, so it renders through
  /// [EmptyState] instead of a bespoke card. Care-mode copy routing (#131)
  /// is unchanged — [_copy.notEnoughTitle]/[_copy.notEnoughBody] still
  /// choose the words; the explainer content itself is #139's, so this
  /// issue only changes the presentation, never the copy. The disclaimer
  /// stays a plain [Text] alongside it (R17: next to every estimate,
  /// without exception) rather than folded into the component itself.
  /// Issue #308: `titleStyle`/`crossAxisAlignment` regain this card's old
  /// `headlineSmall`, left-aligned heading now that [EmptyState] otherwise
  /// defaults to a centred `titleMedium`.
  Widget _notEnoughCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('overview-not-enough'),
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
              key: const ValueKey('overview-not-enough-disclaimer'),
              style: theme.textTheme.bodySmall,
            ),
            // Issue #139: the "not enough history yet" state links to the
            // bundled card explaining the three-cycle requirement.
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

/// Issue #168: was a passive line ("Reminders unavailable — notifications
/// are off"); now an actionable "Turn on reminders" affordance. Tapping it
/// always runs the same [RequestNotificationPermissionCallback] — whether
/// that re-requests the OS permission or opens the platform's
/// notification-settings screen instead (once Android has permanently
/// denied it) is a decision the scheduler makes, not this widget (see
/// `nextNotificationPermissionAction`). Absent that seam (no reminder
/// coordinator ever started), the hint falls back to the old passive line.
class _ReminderHint extends StatefulWidget {
  const _ReminderHint();

  @override
  State<_ReminderHint> createState() => _ReminderHintState();
}

class _ReminderHintState extends State<_ReminderHint> {
  bool _requesting = false;

  Future<void> _onTap(RequestNotificationPermissionCallback request) async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      await request();
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final request = context.read<RequestNotificationPermissionCallback?>();
    return Padding(
      key: const ValueKey('reminder-hint'),
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          // Issue #162 (B-24): the hint reads as de-emphasised copy, so it
          // uses `onSurfaceVariant` (the M3 text role for that job) for both
          // the icon and the text at the same value -- `tertiary` is not
          // contrast-guaranteed against `surface` in a fromSeed palette.
          Icon(
            Icons.notifications_off,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.overviewReminderHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (request != null)
            TextButton(
              key: const ValueKey('reminder-hint-action'),
              onPressed: _requesting ? null : () => _onTap(request),
              child: Text(l10n.overviewTurnOnReminders),
            ),
        ],
      ),
    );
  }
}
