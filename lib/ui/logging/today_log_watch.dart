/// The live "what is logged today" subscription (issue #1489) shared by the
/// Today log card (`OverviewPanel`) and the floating button's label
/// (`TodayLogFab`).
///
/// Both need the same answer before any tap and both need it to change the
/// moment the entry does (the day sheet autosaves, a sync arrives, Undo on
/// the quick log). One mixin owns the subscription so the two cannot drift:
/// the card and the button read the same [TodayLog], through the same
/// [TodayLog.hasContent].
///
/// "Today" also changes with no entry written at all: at midnight, and
/// while the app sits in the background overnight. A log read for
/// yesterday must not go on being shown as today's, so the watch reads
/// again when the app comes back to the foreground and whenever the
/// caller's own day-change signal fires — see
/// [TodayLogWatchMixin.watchTodayLog].
///
/// And the day's log changes with no entry written: spotting and readings
/// are observations, and the reminder's "Spotting" action, the health
/// import and a sync pull write them on their own. So the watch also
/// follows today's entry's observations where the repository offers a
/// stream of them.
///
/// Reads, never writes. The entries read is the repository's existing
/// windowed watch; the observations read is its existing one-day read, the
/// one the day sheet itself opens with.
///
/// [watchCustomTagsSafely] is the card's other live read, the profile's
/// own tag names, kept here so both of the card's streams fail the same
/// quiet way.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lunarlog/domain/logging/custom_tag_registry.dart';
import 'package:lunarlog/domain/logging/today_log.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/tag_registry_repository.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show Sentry;

/// Records a failed read behind the today watch (a type-only breadcrumb and
/// a Sentry capture, as `watchGuardiansForProfileSafely` does) and drops
/// it. The reader keeps whatever it last knew: a broken read must not take
/// the Today screen down, and the estimate card above already says so when
/// the entries stream itself is failing.
void _recordTodayLogFailure(String what, Object error, StackTrace stackTrace) {
  defaultBreadcrumbLog.record(
    'todayLogWatch',
    '$what failed: ${error.runtimeType}',
  );
  unawaited(Sentry.captureException(error, stackTrace: stackTrace));
}

/// [repository]'s custom-tag registry for [profileId] — the names the Today
/// log card shows a profile's own tags by — with a stream error recorded
/// and dropped rather than forwarded, so a listener needs no `onError` of
/// its own and a failed read leaves the names it last had.
Stream<List<CustomTag>> watchCustomTagsSafely(
  TagRegistryRepository repository,
  String profileId,
) =>
    repository.watchForProfile(profileId).handleError(
          (Object error, StackTrace stackTrace) => _recordTodayLogFailure(
            'tagRegistry.watchForProfile',
            error,
            stackTrace,
          ),
        );

/// The live entry dated [date] among [entries], or null.
DayEntry? _liveEntryOn(List<DayEntry> entries, LocalDate date) {
  for (final entry in entries) {
    if (entry.localDate == date && entry.deletedAt == null) return entry;
  }
  return null;
}

/// Calls back when the app returns to the foreground. A plain observer
/// rather than an `AppLifecycleListener`, which asserts on the order of the
/// states it is told about; this only ever asks "are we back?".
class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this._onResumed);

  final VoidCallback _onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onResumed();
  }
}

/// What one [TodayLogWatchMixin.watchTodayLog] call was given, kept for the
/// reads that follow it.
class _TodayLogWatch {
  const _TodayLogWatch(this.observations, this.todayProvider, this.onLog);

  final ObservationsRepository? observations;
  final LocalDate Function() todayProvider;
  final void Function(TodayLog? log) onLog;
}

/// Mixed into a [State] that shows something about today's log. The mixing
/// state owns its own field and `setState` call; this only owns the
/// subscription, as `GuardianWatchMixin` does for guardians.
mixin TodayLogWatchMixin<T extends StatefulWidget> on State<T> {
  StreamSubscription<List<DayEntry>>? _todayLogSub;
  StreamSubscription<Object?>? _todayLogDaySub;
  _ResumeObserver? _todayLogResume;

  /// The subscription to today's entry's own observations, and the entry it
  /// is for. An observation can be written with no day-entry write beside
  /// it, so the entries subscription alone never hears of one. Held only
  /// while today has an entry and the repository offers the stream
  /// ([DayEntryObservationsWatchRepository]).
  StreamSubscription<Object?>? _todayLogObservationsSub;
  String? _todayLogObservedEntryId;

  /// The entries the subscription last emitted, and the day the last read
  /// picked out of them. Kept so a change of day can be answered from what
  /// is already in hand: the window is open-ended, so an entry for the new
  /// day is in it if one exists.
  List<DayEntry>? _todayLogWindow;
  LocalDate? _todayLogDate;

  /// Bumped by every (re)subscription and every read, so a slow
  /// observations read can tell it has been overtaken and drop its answer.
  int _todayLogTick = 0;

  /// (Re)subscribes to [profileId]'s log for today, cancelling any earlier
  /// subscription first.
  ///
  /// Calls [onLog] with null at once (nothing is known yet, and a profile
  /// switch must never keep showing the previous profile's day), then with
  /// a [TodayLog] on every change, guarded by [mounted]. A null [entries]
  /// resets and subscribes to nothing; a null [observations] yields logs
  /// with no observations.
  ///
  /// [todayProvider] is called here for the window and again on every read
  /// to pick the day, so the first write after midnight is read against the
  /// new day. The subscribed window is open-ended and starts the day
  /// before, which is what lets that write arrive at all.
  ///
  /// A new day with nothing written yet is the other case, and the common
  /// one: the app is opened the next morning with yesterday's log still in
  /// hand. Two things make the watch read again when [todayProvider] no
  /// longer answers the day it last read for: the app returning to the
  /// foreground, and any event on [dayTicks]. [dayTicks] is the caller's
  /// own signal that the day may have changed — in the app, the estimate
  /// stream, which the prediction service re-runs at the date rollover —
  /// and only its timing is used, never its values. Its errors are its own
  /// consumer's to report and are ignored here.
  ///
  /// The estimate stream only speaks when the estimate changes, so with the
  /// app left open across midnight a profile that has no estimate to move
  /// (too little history, estimates turned off) is not re-read until the
  /// next write or the next return to the foreground. The watch
  /// deliberately starts no timer of its own: the app keeps one date ticker
  /// per profile, paused in the background (#839), and this does not add
  /// to them.
  ///
  /// An observation written on its own is the third case: the reminder's
  /// "Spotting" action, the health import and a sync pull all write a
  /// spotting or temperature row with no day-entry write beside it, so the
  /// entries stream says nothing. When [observations] offers a stream per
  /// day entry ([DayEntryObservationsWatchRepository]) the watch follows
  /// today's entry's and reads again on each of its emissions. It takes
  /// that stream once the entry is known, and lets go of it when today's
  /// entry becomes a different one or there is none. A repository with no
  /// such stream is read once per entries emission, as before.
  void watchTodayLog({
    required DayEntriesRepository? entries,
    required ObservationsRepository? observations,
    required String profileId,
    required LocalDate Function() todayProvider,
    required void Function(TodayLog? log) onLog,
    Stream<Object?>? dayTicks,
  }) {
    _cancelTodayLogWatch();
    onLog(null);
    if (entries == null) return;
    final watch = _TodayLogWatch(observations, todayProvider, onLog);

    _todayLogSub = entries
        .watchForProfile(profileId, from: todayProvider().addDays(-1))
        .listen(
          (window) => unawaited(_readTodayLog(watch, window)),
          onError: (Object error, StackTrace stackTrace) =>
              _recordTodayLogFailure('watchForProfile', error, stackTrace),
        );
    _todayLogDaySub = dayTicks?.listen(
      (_) => _readIfDayChanged(watch),
      onError: (Object _, StackTrace _) {},
    );
    final resume =
        _todayLogResume = _ResumeObserver(() => _readIfDayChanged(watch));
    WidgetsBinding.instance.addObserver(resume);
  }

  /// Reads again from the window in hand if "today" is no longer the day
  /// the last read was for.
  void _readIfDayChanged(_TodayLogWatch watch) {
    final window = _todayLogWindow;
    if (window == null || watch.todayProvider() == _todayLogDate) return;
    unawaited(_readTodayLog(watch, window));
  }

  /// Reads again from the window in hand: an observation of today's entry
  /// changed, with no entries emission to say so.
  void _readAgain(_TodayLogWatch watch) {
    final window = _todayLogWindow;
    if (window == null) return;
    unawaited(_readTodayLog(watch, window));
  }

  Future<void> _readTodayLog(
    _TodayLogWatch watch,
    List<DayEntry> window,
  ) async {
    final tick = ++_todayLogTick;
    final date = watch.todayProvider();
    _todayLogWindow = window;
    _todayLogDate = date;
    final entry = _liveEntryOn(window, date);
    _followObservationsOf(watch, entry);
    final attached = await _observationsOf(entry, watch.observations);
    if (!mounted || tick != _todayLogTick) return;
    watch.onLog(TodayLog(entry: entry, observations: attached));
  }

  /// Keeps the observations subscription on today's [entry]: nothing to do
  /// while it is the same entry, otherwise the old one is dropped and, if
  /// there is an entry and a stream to follow, the new one taken. Each
  /// emission is one re-read ([_readAgain]); a read it overtakes is dropped
  /// by the same tick that guards the entries path.
  void _followObservationsOf(_TodayLogWatch watch, DayEntry? entry) {
    final entryId = entry?.id;
    if (entryId == _todayLogObservedEntryId) return;
    unawaited(_todayLogObservationsSub?.cancel());
    _todayLogObservationsSub = null;
    _todayLogObservedEntryId = entryId;
    final observations = watch.observations;
    if (entryId == null ||
        observations is! DayEntryObservationsWatchRepository) {
      return;
    }
    _todayLogObservationsSub = observations.watchForDayEntry(entryId).listen(
      (_) => _readAgain(watch),
      onError: (Object error, StackTrace stackTrace) =>
          _recordTodayLogFailure('watchForDayEntry', error, stackTrace),
    );
  }

  /// The observations attached to [entry]. A failed read is recorded and
  /// answered with none, so the log still says what the entry itself holds.
  Future<List<Observation>> _observationsOf(
    DayEntry? entry,
    ObservationsRepository? observations,
  ) async {
    if (entry == null || observations == null) return const [];
    try {
      return await observations.listForDayEntryWithLegacyAlias(entry.id);
    } catch (error, stackTrace) {
      _recordTodayLogFailure('listForDayEntry', error, stackTrace);
      return const [];
    }
  }

  /// Lets go of everything [watchTodayLog] took. Nothing here is awaited: a
  /// `dispose` that waits on a cancel never finishes under a test's fake
  /// clock.
  void _cancelTodayLogWatch() {
    unawaited(_todayLogSub?.cancel());
    _todayLogSub = null;
    unawaited(_todayLogDaySub?.cancel());
    _todayLogDaySub = null;
    unawaited(_todayLogObservationsSub?.cancel());
    _todayLogObservationsSub = null;
    _todayLogObservedEntryId = null;
    final resume = _todayLogResume;
    if (resume != null) WidgetsBinding.instance.removeObserver(resume);
    _todayLogResume = null;
    _todayLogWindow = null;
    _todayLogDate = null;
    _todayLogTick++;
  }

  /// Cancels the watch, if any. Call from the mixing state's own
  /// `dispose()`.
  void disposeTodayLogWatch() => _cancelTodayLogWatch();
}
