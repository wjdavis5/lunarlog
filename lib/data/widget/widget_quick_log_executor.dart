/// Executes the home-screen widget's quick-log tap (issue #141): a
/// "period started today" write for the widget's profile, through the same
/// repositories and the same quick-log rule every other write uses — never
/// a second, weaker write path.
///
/// ## The gate (the issue's non-negotiable constraint)
///
/// A widget tap happens on the home screen, while the app may be locked.
/// The write must only ever land **after the device-credential gate is
/// satisfied**, so this executor follows issue #136's `ReminderActionExecutor`
/// exactly: while the gate is locked the intent is latched (single slot —
/// a fresher tap replaces an older one, never duplicates it), and the gate's
/// unlock listener executes it. If the gate relocks while an intent waits
/// its turn on the drain queue, it re-latches rather than writing behind
/// the lock. Nothing writes in the widget itself and no headless callback
/// engine is registered — the tap only opens the app carrying the URI.
///
/// ## Idempotency
///
/// Two layers, identical to the reminder executor's: executions serialize
/// through one drain queue (a double tap observes its own first write), and
/// the write itself is an upsert keyed by (profileId, civil date) through
/// `DayEntriesRepository.save`, with `quickLogFlowLevel` never downgrading
/// a flow the operator already recorded.
///
/// ## Role re-verification
///
/// The `can_quick_log` flag that crossed the widget boundary is render-only.
/// Before any write this executor asks the injected `canQuickLogNow`
/// closure — which resolves the operator's accepted role against freshly
/// read guardian rows — and drops the intent when the answer is false (a
/// known `viewer`). A stale container value can therefore never widen who
/// can write. The target profile is also re-resolved live: an intent for a
/// since-archived or deleted profile is dropped, never silently rerouted.
///
/// ## Acknowledgement (issue #1016)
///
/// Every materialized write is emitted on [WidgetQuickLogExecutor.outcomes]
/// so the app shell can land the operator on the logged profile's Today tab
/// and show the same snackbar + Undo the in-app Today card shows — the
/// widget path is no longer the one silent write in the app. Drops stay
/// deliberately silent (see the stream's doc comment for the one line of
/// #1016's expected behavior that is explicitly out of scope).
library;

// Named required parameters cannot be initializing formals; the private
// finals below are assigned through the constructor's initializer list
// (the same shape as `ReminderActionExecutor`).
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lunarlog/domain/logging/quick_log.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/widget/widget_quick_log_intent.dart';
import 'package:lunarlog/domain/util/timezone.dart';

/// A materialized widget quick-log write (issue #1016): everything the app
/// shell needs to acknowledge the write the way the in-app Today button
/// does — jump to the logged profile's Today tab and offer the same Undo.
class WidgetQuickLogOutcome {
  const WidgetQuickLogOutcome({
    required this.profileId,
    required this.previousEntry,
    required this.date,
  });

  /// The profile the write landed on: the widget intent's target,
  /// re-resolved live at write time (never rerouted).
  final String profileId;

  /// The day's entry as it stood immediately before the write — the exact
  /// state the shared [undoQuickLog] helper restores. Null when the tap is
  /// what created the day (the Undo is then a tombstone through the
  /// repository's own delete path).
  final DayEntry? previousEntry;

  /// The civil date the write landed on (the executor's injected "today").
  final LocalDate date;
}

/// Executes (or latches) the widget's quick-log intent. Constructed by the
/// app shell with plain gate closures — this module never names
/// `GateController` (the same discipline as `buildReminderActionExecutor`).
class WidgetQuickLogExecutor {
  WidgetQuickLogExecutor({
    required DayEntriesRepository dayEntries,
    required ProfilesRepository profiles,
    required Future<bool> Function(String profileId) canQuickLogNow,
    bool Function()? isUnlocked,
    void Function(void Function() callback)? addUnlockListener,
    void Function(void Function() callback)? removeUnlockListener,
    LocalDate Function()? today,
    String Function()? timezoneProvider,
  })  : _dayEntries = dayEntries,
        _profiles = profiles,
        _canQuickLogNow = canQuickLogNow,
        _isUnlocked = isUnlocked,
        _today = today ?? LocalDate.today,
        _timezone = timezoneProvider ?? resolveCurrentTimeZoneSync {
    if (addUnlockListener != null) {
      addUnlockListener(_onGateChanged);
      _removeUnlockListener = removeUnlockListener;
    }
  }

  final DayEntriesRepository _dayEntries;
  final ProfilesRepository _profiles;
  final Future<bool> Function(String profileId) _canQuickLogNow;
  final bool Function()? _isUnlocked;
  final LocalDate Function() _today;
  final String Function() _timezone;
  void Function(void Function() callback)? _removeUnlockListener;

  /// The latched intent waiting for the gate to open; null when nothing is
  /// pending. Exposed for tests and diagnostics only.
  @visibleForTesting
  bool get hasPending => _pending != null;
  String? _pending;

  /// Every materialized write, emitted once its save has landed (issue
  /// #1016): the app shell subscribes next to the launch stream and
  /// acknowledges the write the way the in-app Today button does. The
  /// broadcast controller means a period with no subscriber drops events
  /// instead of buffering them — the shell subscribes synchronously in the
  /// same method that constructs this executor, before any intent can
  /// arrive, so a write can never outrun its own acknowledgement.
  final StreamController<WidgetQuickLogOutcome> _outcomes =
      StreamController<WidgetQuickLogOutcome>.broadcast();

  /// The stream of [WidgetQuickLogOutcome]s, one per materialized write.
  ///
  /// Deliberately silent on every non-write resolution — a role-drop, a
  /// since-archived profile, a relatch behind a relocked gate, a failed
  /// save, and a day the quick-log rule could not upgrade all stay quiet.
  /// Issue #1016 asked for a one-line "Already logged for today." on those
  /// paths; that surfaced-drop line is explicitly out of scope for this
  /// change (tracked as the issue's dropped line), so #141's silence on
  /// non-writes is the shipped posture for them.
  Stream<WidgetQuickLogOutcome> get outcomes => _outcomes.stream;

  /// Set by [dispose]: a write queued behind an earlier one must never
  /// land after this executor is torn down (its repositories may close).
  bool _disposed = false;

  /// The tail of the serialized execution queue; null when idle.
  Future<void>? _draining;

  /// Resolves once every enqueued execution has finished — test seam.
  @visibleForTesting
  Future<void> get idle => _draining ?? Future<void>.value();

  bool get _unlocked => _isUnlocked?.call() ?? true;

  /// Entry point from the widget-launch URI: only a quick-log intent does
  /// anything; the plain open intent (and anything else) is ignored.
  void handle(Uri? uri) {
    if (uri == null) return;
    final intent = parseWidgetQuickLogUri(uri);
    if (intent == null) return;
    if (!_unlocked) {
      // Locked now: latch. The gate listener executes it on unlock. A
      // second tap while still locked replaces the pending intent —
      // freshest-intent semantics, never a duplicate write.
      _pending = intent.profileId;
      return;
    }
    _enqueue(intent.profileId);
  }

  void _onGateChanged() {
    final pending = _pending;
    if (pending == null || !_unlocked) return;
    _pending = null;
    _enqueue(pending);
  }

  /// Serializes [profileId] onto the drain queue: two taps (or a tap
  /// racing the unlock event) run one after the other, never interleaved,
  /// so the second run's checks see the first run's write.
  void _enqueue(String profileId) {
    final previous = _draining ?? Future<void>.value();
    final run = previous.then((_) => _execute(profileId));
    _draining = run;
    unawaited(run.whenComplete(() {
      if (identical(_draining, run)) _draining = null;
    }));
  }

  Future<void> _execute(String profileId) async {
    if (_disposed) return;
    if (!_unlocked) {
      // The gate relocked while this intent waited its turn: relatch
      // instead of writing behind the lock. A fresher tap that latched in
      // the meantime already wins — never overwrite it with this older one.
      _pending ??= profileId;
      return;
    }
    try {
      // Role re-check against live rows, at write time: the widget
      // container's flag is render-only (see the library doc).
      if (!await _canQuickLogNow(profileId)) return;
      // The profile must still be live and non-archived: an intent for a
      // since-archived profile is dropped, never rerouted.
      final profile = await _profiles.findById(profileId);
      if (profile == null || profile.archivedAt != null) return;
      // Inside the try: a write landing after dispose() closed the stream
      // surfaces through the same best-effort catch below rather than
      // crashing an unawaited future.
      _outcomes.add(await _logStartedToday(profileId));
    } catch (error) {
      // Best effort by design: the tap has no UI of its own to surface a
      // failure into, and a failed write must never crash an unawaited
      // future. Logged by type only (details could carry profile or
      // database specifics), matching the reminder executor's posture.
      debugPrint('lunarlog widget: quick-log failed (${error.runtimeType})');
    }
  }

  /// "Period started today": upserts today's entry with the quick-log flow
  /// rule — the identical write the overview's "Period started today" card
  /// and the reminder action use, including never downgrading a flow the
  /// operator already recorded. Returns the outcome the shell acknowledges
  /// the write with, carrying the pre-write entry for the shared Undo.
  Future<WidgetQuickLogOutcome> _logStartedToday(String profileId) async {
    final date = _today();
    final tzName = _timezone();
    final previous = await _dayEntries.find(profileId, date);
    final flow = quickLogFlowLevel(previous?.flow);
    final entry = previous?.copyWith(flow: flow, tz: tzName) ??
        DayEntry(
          id: '',
          profileId: profileId,
          localDate: date,
          tz: tzName,
          flow: flow,
          updatedAt: DateTime.now().toUtc(),
        );
    await _dayEntries.save(entry);
    return WidgetQuickLogOutcome(
      profileId: profileId,
      previousEntry: previous,
      date: date,
    );
  }

  /// Detaches the gate listener and stops executing. Call when the owning
  /// widget tears down; a queued-but-not-started write finds itself
  /// disposed at its turn and never lands. Also closes the outcome stream
  /// (the shell cancels its subscription first, in its own dispose).
  void dispose() {
    _disposed = true;
    _removeUnlockListener?.call(_onGateChanged);
    _removeUnlockListener = null;
    _pending = null;
    unawaited(_outcomes.close());
  }
}
