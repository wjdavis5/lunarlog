/// Overview panel (U6, R11/R13/R17): the prediction summary for one
/// profile, rendered from the U3 [CyclePredictionService] stream so it
/// refreshes as entries are logged (F4 in-app half).
///
/// Issue #132 adds the two surfaces below the estimate card: the
/// three-option late resolver (R6) replacing the old single-line banner,
/// and the cycle-history section (R4/R5) with omit-from-average,
/// statistics, and confidence framing. Wording is date-based only today —
/// no fertility vocabulary in any state until #143 lands — and every
/// estimate sits next to the fixed non-medical disclaimer (R17). No drift
/// types cross into this file.
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
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunarlog/app_lifecycle.dart'
    show RequestNotificationPermissionCallback;
import 'package:lunarlog/data/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/care_modes.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/components/empty_state.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart' show kMonthNames;
import 'package:lunarlog/ui/overview/cycle_history_section.dart';
import 'package:lunarlog/ui/overview/late_resolver.dart';
import 'package:lunarlog/ui/overview/notification_permission_state.dart';
import 'package:provider/provider.dart';

const String kEstimateDisclaimer = 'Estimates only — not medical advice.';

String _formatDate(LocalDate date) =>
    '${kMonthNames[date.month - 1]} ${date.day}, ${date.year}';

/// Issue #213: `high` confidence keeps the single exact-date estimate
/// (unchanged from before this issue); any other tier renders the range
/// `estimatedRangeStart`–`estimatedRangeEnd` instead of one exact date,
/// per the issue's own display rule — except when that range is
/// degenerate (a spread that rounds to zero days, e.g. a perfectly steady
/// history that has not yet filled the 6-cycle average window): showing
/// "June 18, 2026 – June 18, 2026" would be a redundant, confusing range
/// for a single date, so that case falls back to the plain date instead.
String _estimateDateText(ActivePrediction prediction) {
  if (prediction.tier == CycleConfidence.high) {
    return _formatDate(prediction.estimatedNextStart);
  }
  final rangeStart = prediction.estimatedRangeStart;
  final rangeEnd = prediction.estimatedRangeEnd;
  if (rangeStart == rangeEnd) {
    return _formatDate(prediction.estimatedNextStart);
  }
  return '${_formatDate(rangeStart)} – ${_formatDate(rangeEnd)}';
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
  });

  final String profileId;

  /// The profile's care mode (Issue #131): selects the vocabulary below.
  /// Presentation only — it never changes what any guardian role may read
  /// or write ([_effectiveReadOnly] consults roles alone).
  final ProfileMode mode;

  /// "Today" as the device-local civil date; injectable for tests.
  final LocalDate Function() todayProvider;

  /// Archived-profile read-only (U5): the resolver shows no actions and
  /// the history list shows no omit toggles.
  final bool readOnly;

  /// Provider for the resolved IANA time zone identifier (paired with
  /// #38); passed to the day sheet the resolver's "log it" opens.
  final String Function()? timezoneProvider;

  /// Source of this profile's guardians for the viewer-role read-only
  /// check (same shape as [MonthCalendar.guardiansRepository]); null in
  /// local-only use.
  final ProfileGuardiansRepository? guardiansRepository;

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
            CycleHistorySection(
              profileId: widget.profileId,
              todayProvider: widget.todayProvider,
              readOnly: _effectiveReadOnly,
            ),
            if (availability == NotificationAvailability.denied)
              const _ReminderHint(),
          ],
        );
      },
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

  Widget _activeCard(BuildContext context, ActivePrediction prediction) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('overview-active'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              key: const ValueKey('overview-phase'),
              prediction.duringEpisode
                  ? 'Period'
                  : 'Cycle day ${prediction.cycleDay}',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text(
              '${_copy.nextEstimateLabel} ${_estimateDateText(prediction)}',
              key: const ValueKey('overview-next-period'),
              style: theme.textTheme.titleMedium,
            ),
            // Issue #213: below `high` confidence (`learning` included —
            // #213 item 5), the estimate above is already a range rather
            // than one exact date; this caption names why (no numbers,
            // matching the rest of R11's no-partial-numbers framing).
            // Issue #131 cheap fix: routed through CareModeCopy so
            // `irregular` care mode — which already replaces the late
            // banner with its own quiet, non-numeric framing — can silence
            // this caption rather than showing it twice over.
            if (_copy.showsTierCaption &&
                prediction.tier != CycleConfidence.high) ...[
              const SizedBox(height: 4),
              Text(
                '${prediction.tier.label} — ${prediction.tier.summary}',
                key: const ValueKey('overview-tier-caption'),
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 4),
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
            const SizedBox(height: 12),
            Text(
              kEstimateDisclaimer,
              key: const ValueKey('overview-disclaimer'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
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
    final messenger = ScaffoldMessenger.of(context);
    await _exclusions.omit(widget.profileId, prediction.lastEpisodeStart);
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text('This cycle is excluded from future averages.'),
      ),
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
            'This cycle is unusually long',
            key: const ValueKey('overview-long-cycle-title'),
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'It has run well past a typical cycle for this profile. You can '
            'exclude it from future averages, or turn off predictions if '
            'long cycles are common for this profile.',
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
                  child: const Text('Exclude this cycle'),
                ),
                // TODO(#225): wire this up once profile-level "turn
                // predictions off" exists. Until then it stays a disabled,
                // honestly-labeled button rather than a live one that only
                // ever shows a "coming soon" snackbar — a button that always
                // just defers reads as broken, not as a placeholder.
                const OutlinedButton(
                  key: ValueKey('long-cycle-predictions-off'),
                  onPressed: null,
                  child: Text('Turn off predictions (coming soon)'),
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
            ),
            const SizedBox(height: 8),
            Text(
              kEstimateDisclaimer,
              key: const ValueKey('overview-not-enough-disclaimer'),
              style: theme.textTheme.bodySmall,
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
    final request = context.read<RequestNotificationPermissionCallback?>();
    return Padding(
      key: const ValueKey('reminder-hint'),
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(
            Icons.notifications_off,
            size: 18,
            color: theme.colorScheme.tertiary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Reminders unavailable — notifications are off',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
          ),
          if (request != null)
            TextButton(
              key: const ValueKey('reminder-hint-action'),
              onPressed: _requesting ? null : () => _onTap(request),
              child: const Text('Turn on reminders'),
            ),
        ],
      ),
    );
  }
}
