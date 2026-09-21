/// Household-view row signals (issue #803): what a multi-profile guardian
/// scans for on the profile picker, derived per profile as a testable pure
/// layer over the services the app already watches.
///
/// Three signals per row, each status words and counts only — no note
/// body, no symptom label, ever (the issue's content-discretion constraint,
/// the same rule as the activity feed and notification payloads):
///
/// * **Timing** — "Period expected in 3 days" / "4 days late" from the
///   [CyclePredictionService] prediction the row's cycle status already
///   uses, with #853's framing respected: a profile whose effective
///   irregular framing is ON (`irregularFramingInEffect`) never reads
///   "late" — variation is expected, not overdue — so its overdue state
///   renders as the quiet factual "Last period N days ago" instead, and
///   its upcoming estimate renders nothing at all (a precise-looking
///   "expected in N days" is exactly the false precision the framing
///   exists to avoid — the same reasoning `CareModeCopy.showsFertileWindow`
///   applies).
/// * **Silence** — "Nothing logged for N days" from the profile's day
///   entries, shown only when the profile has history (a fresh profile is
///   not "silent") and suppressed while a timing signal shows (a late
///   count already implies nobody has logged; two lines saying it is
///   noise). The threshold comes from the profile's own device-local
///   reminder preferences — the daily log nudge's cadence
///   ([householdSilenceThresholdDays]) — falling back to a fixed default
///   when the profile never configured reminders, so the signal stays
///   computed from local data (the issue's offline constraint) and never
///   depends on the server-backed caregiver-alert row.
/// * **Changes** — "N changes since you last looked" from the activity
///   feed's unread count (issue #124): rows newer than the device-local
///   last-seen stamp, counted. A profile whose feed was never opened
///   carries no baseline, so it never reads "new" — the feed's own
///   `isActivityNew` discipline, reused unchanged.
///
/// The pure functions take exactly what the widget layer already holds
/// (a prediction, a feed snapshot, entry dates, a threshold) and return
/// copy or signal values; every stream subscription lives in
/// [HouseholdRowSignals] below. Null-provider tolerant throughout: a tree
/// without a repository renders no signal rather than a guessed one (the
/// picker's #241 null-gating discipline).
library;

import 'dart:async' show StreamSubscription, unawaited;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/activity/activity_feed.dart';
import 'package:lunarlog/domain/activity/activity_feed_snapshot.dart';
import 'package:lunarlog/domain/care_modes.dart' show irregularFramingInEffect;
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/notifications/reminder_config.dart';
import 'package:lunarlog/domain/notifications/reminder_config_store.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/activity_feed_repository.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/theme/tokens.dart';

/// How far ahead an unframed profile's upcoming estimate earns a
/// "Period expected in N days" timing line. Past this window the row's
/// plain "Cycle day N" status is the honest summary — an always-on
/// "expected in 23 days" is noise, not attention.
const int kHouseholdTimingWindowDays = 7;

/// The silence threshold for a profile whose reminder preferences carry no
/// explicit log-nudge cadence ([householdSilenceThresholdDays]'s
/// fallback): roughly the longest missed-entry window the caregiver-alert
/// preferences offer, so an unconfigured profile still surfaces the
/// "nobody has logged in days" case the household view exists to answer.
const int kHouseholdSilenceDefaultDays = 3;

/// The timing signal for one profile's household row, or null when the row
/// carries no timing fact: no estimate yet, mid-episode (the row already
/// reads "Period, day N"), or outside the upcoming window.
sealed class HouseholdTimingSignal {
  const HouseholdTimingSignal();

  /// Whole days the signal counts (its copy is built around one number).
  int get days;
}

/// The next estimate falls [days] days ahead, inside the window:
/// "Period expected in N days" (0 reads "expected today").
class HouseholdTimingExpected extends HouseholdTimingSignal {
  const HouseholdTimingExpected(this.days);

  @override
  final int days;
}

/// The open cycle is [days] past its un-rolled estimate — the resolver's
/// own vocabulary ("N days late"), never rendered for a framed profile.
class HouseholdTimingLate extends HouseholdTimingSignal {
  const HouseholdTimingLate(this.days);

  @override
  final int days;
}

/// The quiet, factual open-cycle line for a framed (#853) or
/// stale-history (#859) profile: "Last period N days ago" — informative
/// without the overdue framing, or without a day count a stale history
/// can no longer back.
class HouseholdTimingOpen extends HouseholdTimingSignal {
  const HouseholdTimingOpen(this.days);

  @override
  final int days;
}

/// Derives the timing signal from the prediction the row's cycle status
/// already consumed (one shared [CyclePredictionService] pipeline, #839),
/// plus the profile's *effective* irregular framing — resolve it through
/// [irregularFramingInEffect], not the stored tri-state.
HouseholdTimingSignal? householdTimingSignal({
  required CyclePrediction? prediction,
  required bool irregularFraming,
}) {
  switch (prediction) {
    case null:
    case NotEnoughHistory():
    case PredictionsSuppressed():
    case PredictionsDisabled():
      return null;
    case final ActivePrediction active:
      return _activeTiming(active, irregularFraming);
  }
}

HouseholdTimingSignal? _activeTiming(
  ActivePrediction active,
  bool irregularFraming,
) {
  if (active.duringEpisode) return null;
  final openDays = active.daysSinceLastEpisodeStart;
  if (openDays < 1) return null;
  // Issue #859: past the staleness threshold the day count is too old to
  // mean anything — the soft factual line either way, never "N days late".
  if (active.staleHistory) return HouseholdTimingOpen(openDays);
  final lateDays = active.daysLate;
  if (lateDays != null) {
    return irregularFraming
        ? HouseholdTimingOpen(openDays)
        : HouseholdTimingLate(lateDays);
  }
  if (active.unusuallyLongCycle) return HouseholdTimingOpen(openDays);
  // Issue #853: under the framing a precise "expected in N days" is the
  // false precision the framing exists to avoid — no upcoming line at all.
  if (irregularFraming) return null;
  final until = active.daysUntilNextPeriod;
  if (until >= 0 && until <= kHouseholdTimingWindowDays) {
    return HouseholdTimingExpected(until);
  }
  return null;
}

/// The localized copy for [signal] (the count is pluralized through the
/// shared ICU `daysCount` shape — never a bare "1 days").
String householdTimingCopy(
  HouseholdTimingSignal signal,
  AppLocalizations l10n,
) =>
    switch (signal) {
      HouseholdTimingExpected(:final days) when days == 0 =>
        l10n.householdTimingExpectedToday,
      HouseholdTimingExpected(:final days) =>
        l10n.householdTimingExpectedIn(days),
      HouseholdTimingLate(:final days) => l10n.householdTimingLate(days),
      HouseholdTimingOpen(:final days) => l10n.householdTimingLastLogged(days),
    };

/// The silence threshold in days for a profile whose device-local reminder
/// config carries the daily log nudge [log] (null when it has none): the
/// operator's own "how often should days get logged here" answer, mapped
/// to how long a quiet stretch must run before this row mentions it — two
/// days for a daily nudge, the cadence length for the slower ones, and
/// [kHouseholdSilenceDefaultDays] when the nudge is off or unconfigured.
int householdSilenceThresholdDays(ReminderTypeConfig? log) {
  if (log == null || !log.enabled) return kHouseholdSilenceDefaultDays;
  return switch (log.cadence) {
    ReminderCadence.daily => 2,
    ReminderCadence.weekly => 7,
    ReminderCadence.fortnightly => 14,
    ReminderCadence.monthly => 30,
  };
}

/// Whole civil days since [entries]' latest logged date, or null when the
/// profile has no live entries at all — a fresh profile is never "silent".
int? daysSinceLastLog(List<DayEntry> entries, LocalDate today) {
  LocalDate? latest;
  for (final entry in entries) {
    final date = entry.localDate;
    if (latest == null || date.isAfter(latest)) latest = date;
  }
  if (latest == null) return null;
  return today.difference(latest);
}

/// The silence line for the row, or null when it must not show: no
/// history ([daysSinceLastLog] null), a quieter stretch than
/// [thresholdDays], or a timing signal already on the row (the late/open
/// count already says nobody has logged — two lines saying it is noise).
String? householdSilenceLine({
  required int? daysSinceLastLog,
  required int thresholdDays,
  required bool timingSignalVisible,
  required AppLocalizations l10n,
}) {
  if (daysSinceLastLog == null) return null;
  if (timingSignalVisible) return null;
  if (daysSinceLastLog < thresholdDays) return null;
  return l10n.householdSilence(daysSinceLastLog);
}

/// The changes line for the row — [items] is the activity feed snapshot's
/// newest-first list and [lastSeen] its device-local baseline — or null
/// when it must not show. Null [lastSeen] (the feed was never opened on
/// this device) means no baseline exists to be "since", so it is never
/// new: the exact `isActivityNew` discipline, reused unchanged.
String? householdChangesLine({
  required DateTime? lastSeen,
  required List<ActivityItem> items,
  required AppLocalizations l10n,
}) {
  if (lastSeen == null) return null;
  var count = 0;
  for (final item in items) {
    if (isActivityNew(item, lastSeen)) count++;
  }
  if (count == 0) return null;
  return l10n.householdChanges(count);
}

/// The three signal lines for one household row, subscribed to the same
/// streams the surfaces they summarize already use: the profile's
/// prediction pipeline (timing), its activity feed (changes), and its day
/// entries (silence), plus a one-shot reminder-config read re-run on the
/// config store's change stream (threshold).
///
/// Every repository is optional: a null one silences exactly that signal
/// (an unconfigured tree renders a bare row, never a guessed line — the
/// #241 null-gating discipline). Nothing here spins: each line appears
/// when its stream's first emission lands and stays absent before that.
class HouseholdRowSignals extends StatefulWidget {
  const HouseholdRowSignals({
    super.key,
    required this.profile,
    this.predictionService,
    this.feedRepository,
    this.dayEntriesRepository,
    this.reminderConfigs,
    this.todayProvider = LocalDate.today,
  });

  final Profile profile;

  /// Null in an unconfigured tree (or a bare test harness): no timing
  /// line renders — never a guessed state for a stream nobody watched.
  final CyclePredictionService? predictionService;
  final ActivityFeedRepository? feedRepository;
  final DayEntriesRepository? dayEntriesRepository;
  final ReminderConfigService? reminderConfigs;

  /// "Today" as the device-local civil date; injectable for tests.
  final LocalDate Function() todayProvider;

  @override
  State<HouseholdRowSignals> createState() => _HouseholdRowSignalsState();
}

class _HouseholdRowSignalsState extends State<HouseholdRowSignals> {
  StreamSubscription<void>? _configChanges;
  int _thresholdDays = kHouseholdSilenceDefaultDays;
  Stream<CyclePrediction>? _predictions;

  @override
  void initState() {
    super.initState();
    _predictions = _watchPredictions();
    unawaited(_loadThreshold());
    _configChanges = widget.reminderConfigs?.changes.listen(
      (_) => unawaited(_loadThreshold()),
    );
  }

  @override
  void didUpdateWidget(HouseholdRowSignals oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id ||
        oldWidget.predictionService != widget.predictionService) {
      _predictions = _watchPredictions();
    }
  }

  Stream<CyclePrediction>? _watchPredictions() =>
      widget.predictionService?.watch(widget.profile.id,
          today: widget.todayProvider);

  /// Device-local per-profile reminder config read; the [changes] stream
  /// re-runs it after any settings edit, the same way the reminder
  /// coordinator replans.
  Future<void> _loadThreshold() async {
    final config = await widget.reminderConfigs?.load(widget.profile.id);
    if (!mounted) return;
    setState(() => _thresholdDays = householdSilenceThresholdDays(config?.log));
  }

  @override
  void dispose() {
    unawaited(_configChanges?.cancel());
    _configChanges = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final predictions = _predictions;
    final feedRepository = widget.feedRepository;
    final dayEntriesRepository = widget.dayEntriesRepository;
    if (predictions == null || feedRepository == null ||
        dayEntriesRepository == null) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<CyclePrediction>(
      stream: predictions,
      builder: (context, predictionSnapshot) =>
          StreamBuilder<ActivityFeedSnapshot>(
            stream: feedRepository.watch(widget.profile.id),
            builder: (context, feedSnapshot) => StreamBuilder<List<DayEntry>>(
              stream: dayEntriesRepository.watchForProfile(widget.profile.id),
              builder: (context, entriesSnapshot) => _lines(
                context,
                prediction: predictionSnapshot.data,
                feed: feedSnapshot.data,
                entries: entriesSnapshot.data ?? const [],
              ),
            ),
          ),
    );
  }

  Widget _lines(
    BuildContext context, {
    required CyclePrediction? prediction,
    required ActivityFeedSnapshot? feed,
    required List<DayEntry> entries,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final style = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final framing = irregularFramingInEffect(
      mode: widget.profile.mode,
      stored: widget.profile.irregularFraming,
      tier: prediction is ActivePrediction ? prediction.tier : null,
    );
    final timing = householdTimingSignal(
      prediction: prediction,
      irregularFraming: framing,
    );
    final silence = householdSilenceLine(
      daysSinceLastLog: daysSinceLastLog(entries, widget.todayProvider()),
      thresholdDays: _thresholdDays,
      timingSignalVisible: timing != null,
      l10n: l10n,
    );
    final changes = householdChangesLine(
      lastSeen: feed?.lastSeen,
      items: feed?.items ?? const [],
      l10n: l10n,
    );
    final lines = <(String, String)>[
      if (timing != null)
        (
          'household-timing-${widget.profile.id}',
          householdTimingCopy(timing, l10n),
        ),
      if (silence != null) ('household-silence-${widget.profile.id}', silence),
      if (changes != null) ('household-changes-${widget.profile.id}', changes),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (key, text) in lines) ...[
          Text(key: ValueKey(key), text, style: style),
          const SizedBox(height: LLSpace.space1),
        ],
      ],
    );
  }
}
