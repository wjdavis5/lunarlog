/// Shell-level "Log today" quick action (issue #209 item 4a): a
/// [FloatingActionButton.extended] that opens the day sheet for
/// [todayProvider]'s date directly -- the same day-sheet entry point
/// [OverviewPanel]'s late resolver already opens ("Log it"), so every
/// "Log today" affordance in the app converges on the one
/// `DayEntriesRepository` write path.
///
/// Hidden entirely (renders nothing) for a `viewer`-role guardian
/// (`GuardianRole.canLog`) -- the same guardian-watch shape
/// [OverviewPanel]/`MonthCalendar` already use for their own
/// `_effectiveReadOnly`, duplicated here in miniature since neither widget
/// exposes it publicly and this button lives one layer up, in the shell
/// rather than either tab.
///
/// Issue #1489: the label reads "Edit today" once today has something
/// logged, and "Log today" until then. The button used to learn about
/// today's entry only when tapped; it now watches it through
/// [TodayLogWatchMixin] — the same watch, and the same
/// [TodayLog.hasContent] rule, the Today log card under the estimate uses —
/// so the label is right before the tap and changes as the entry does.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/logging/today_log.dart';
import 'package:lunarlog/domain/logging/tracking_preferences.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/measurement_unit.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/logging/today_log_watch.dart';
import 'package:lunarlog/ui/sharing/guardian_watch_mixin.dart';
import 'package:lunarlog/ui/theme/haptics.dart';
import 'package:provider/provider.dart';

class TodayLogFab extends StatefulWidget {
  const TodayLogFab({
    super.key,
    required this.profileId,
    this.mode = ProfileMode.standard,
    this.lifecycleMode,
    this.trackingPreferences,
    this.isMinor = false,
    this.todayProvider = LocalDate.today,
    this.timezoneProvider,
    this.guardiansRepository,
    this.bbtUnit = BbtUnit.celsius,
    this.weightUnit = WeightUnit.kg,
  });

  final String profileId;

  /// The profile's care mode (Issue #131): category headings and
  /// surfacing order in the day sheet this button opens.
  final ProfileMode mode;

  /// The profile's life-stage mode (Issue #188/#204), forwarded to
  /// [DaySheet] so Conceive mode surfaces Tests/Discharge first. Null means
  /// no life-stage context: the standard order, never a guess.
  final LifecycleMode? lifecycleMode;

  /// The profile's curated tracking categories (Issue #259), forwarded to
  /// [DaySheet]; null means never customized. Presentation only.
  final TrackingPreferences? trackingPreferences;

  /// Whether the profile subject is a minor (Issue #259): gates the
  /// minor-visibility defaults in [DaySheet]. Presentation only.
  final bool isMinor;

  /// "Today" as the device-local civil date; injectable for tests.
  final LocalDate Function() todayProvider;

  /// Provider for the resolved IANA time zone identifier (paired with
  /// #38); passed through to the day sheet.
  final String Function()? timezoneProvider;

  /// Source of this profile's guardians for the viewer-role check; null in
  /// local-only use (the button then fails open, matching
  /// `acceptedGuardianFor`'s own null-vs-empty discipline).
  final ProfileGuardiansRepository? guardiansRepository;

  /// Per-profile BBT/weight display units (Issue #457), forwarded to
  /// [DaySheet]. Presentation only.
  final BbtUnit bbtUnit;
  final WeightUnit weightUnit;

  @override
  State<TodayLogFab> createState() => _TodayLogFabState();
}

class _TodayLogFabState extends State<TodayLogFab>
    with GuardianWatchMixin<TodayLogFab>, TodayLogWatchMixin<TodayLogFab> {
  AuthController? _auth;
  String? _currentUserId;
  List<ProfileGuardian> _guardians = const [];

  /// Issue #1489: what is logged for today, kept live. Null until the first
  /// read lands (and on a tree with no entries repository), which reads as
  /// "Log today".
  TodayLog? _todayLog;

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
    _watchTodayLog();
  }

  /// Issue #1489: (re)subscribes [_todayLog] to this profile's log for
  /// today. `todayProvider` is read through the widget on every read, never
  /// cached, as every other read of it here is.
  ///
  /// The estimate stream is the day-change signal, as it is for the Today
  /// log card: the prediction service re-runs it at the date rollover. With
  /// the shell's own `todayProvider` this is the pipeline the Today tab
  /// already listens to (#839); a tree with no prediction service simply
  /// has no such signal, and the label still follows every write and every
  /// return to the foreground.
  void _watchTodayLog() {
    watchTodayLog(
      entries: context.read<DayEntriesRepository?>(),
      observations: context.read<ObservationsRepository?>(),
      profileId: widget.profileId,
      todayProvider: () => widget.todayProvider(),
      onLog: (log) => setState(() => _todayLog = log),
      dayTicks: context
          .read<CyclePredictionService?>()
          ?.watch(widget.profileId, today: widget.todayProvider),
    );
  }

  void _onAuthChanged() {
    final auth = _auth;
    if (auth == null || !mounted) return;
    setState(() => _currentUserId = auth.currentUserId);
  }

  void _watchGuardians() {
    watchGuardiansForProfile(widget.guardiansRepository, widget.profileId,
        (guardians) => setState(() => _guardians = guardians));
  }

  @override
  void didUpdateWidget(covariant TodayLogFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Issue #574: `guardiansRepository` also needs a fresh subscription on
    // its own — `todayProvider` needs none, since every read of it
    // (`widget.todayProvider()`) already happens at use time, never cached.
    if (oldWidget.profileId != widget.profileId ||
        oldWidget.guardiansRepository != widget.guardiansRepository) {
      _watchGuardians();
    }
    // Issue #1489: another profile, or another "today", is another day's
    // log. Unlike the tap, the label is held between emissions, so a
    // changed `todayProvider` does need a fresh read here.
    if (oldWidget.profileId != widget.profileId ||
        oldWidget.todayProvider != widget.todayProvider) {
      _watchTodayLog();
    }
  }

  @override
  void dispose() {
    disposeGuardianWatch();
    disposeTodayLogWatch();
    _auth?.removeListener(_onAuthChanged);
    super.dispose();
  }

  /// Fails open on an unknown role (R14/R16's rule, same as
  /// [OverviewPanel]/`MonthCalendar`): a null guardian match is never
  /// treated as read-only.
  bool get _canLog =>
      acceptedGuardianFor(_guardians, _currentUserId)?.role.canLog != false;

  Future<void> _openTodaySheet() async {
    LLHaptics.action();
    final repository = context.read<DayEntriesRepository>();
    final today = widget.todayProvider();
    final existing = await repository.find(widget.profileId, today);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      routeSettings: const RouteSettings(name: kRouteDaySheetScreen),
      builder: (_) => DaySheet(
        repository: repository,
        profileId: widget.profileId,
        date: today,
        existing: existing,
        today: today,
        mode: widget.mode,
        lifecycleMode: widget.lifecycleMode,
        trackingPreferences: widget.trackingPreferences,
        isMinor: widget.isMinor,
        timezoneProvider: widget.timezoneProvider,
        currentUserId: _currentUserId,
        guardians: _guardians,
        bbtUnit: widget.bbtUnit,
        weightUnit: widget.weightUnit,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_canLog) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return FloatingActionButton.extended(
      key: const ValueKey('today-log-fab'),
      onPressed: _openTodaySheet,
      icon: const Icon(Icons.edit_calendar_outlined),
      // Issue #1489: "Edit today" once today has something logged.
      label: Text(
        _todayLog?.hasContent ?? false
            ? l10n.todayLogFabEdit
            : l10n.householdLogToday,
      ),
    );
  }
}
