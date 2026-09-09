/// Executes a reminder notification's action-button tap (Issue #136):
/// "Started"/"Spotting" log the corresponding entry for the civil date at
/// tap time; "Not yet" writes nothing and snoozes the late reminders by
/// three days.
///
/// KTD4: an action **writes only after the device gate is unlocked, never
/// while locked**. When a tap arrives while the gate is locked (the app
/// was backgrounded, so backgrounding re-locked it), the intent is latched
/// here and executed on the next unlock — the same after-the-gate shape
/// the plain-tap payload seam uses (`GateController.pendingLaunchProfileId`
/// → `ProfileHomeGate`).
///
/// Idempotency (the issue's own acceptance criterion): a double-tapped
/// action leaves exactly one entry. Two layers guarantee it — executions
/// are serialized through a single drain queue (so the second run observes
/// the first's result), and every write is itself idempotent: the day
/// entry is an upsert keyed by (profileId, civil date), the spotting
/// observation is only written when the day has none yet, and the snooze
/// end is recomputed from the same `today`.
///
/// This file is deliberately the *only* new mover on the local reminder
/// path — the caregiver alert stack (the outbox,
/// `reminder_window_publisher.dart`, `reminder_coordinator.dart`'s
/// server-driven side) is untouched; the snooze reaches the planner by
/// writing through `ReminderConfigService`, whose `changes` stream the
/// coordinator already replans on.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lunarlog/data/notifications/reminder_payload.dart';
import 'package:lunarlog/domain/logging/quick_log.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/notifications/reminder_config.dart'
    show kNotYetSnoozeDays;
import 'package:lunarlog/domain/notifications/reminder_config_store.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/util/timezone.dart';

// Named required parameters cannot be initializing formals; the private
// finals below are assigned through the constructor's initializer list.
// ignore_for_file: prefer_initializing_formals

/// A latched, not-yet-executed action tap. Single-slot: a second tap of
/// the same action while the gate is still locked replaces (never
/// duplicates) the pending intent.
class _PendingAction {
  const _PendingAction(this.profileId, this.actionId);

  final String profileId;
  final String actionId;
}

class ReminderActionExecutor {
  ReminderActionExecutor({
    required DayEntriesRepository dayEntries,
    ObservationsRepository? observations,
    required ReminderConfigService configService,
    bool Function()? isUnlocked,
    void Function(void Function() callback)? addUnlockListener,
    void Function(void Function() callback)? removeUnlockListener,
    LocalDate Function()? today,
    String Function()? timezoneProvider,
  })  : _dayEntries = dayEntries,
        _observations = observations,
        _configService = configService,
        _isUnlocked = isUnlocked,
        _today = today ?? LocalDate.today,
        _timezone = timezoneProvider ?? resolveCurrentTimeZone {
    if (addUnlockListener != null) {
      addUnlockListener(_onGateChanged);
      _removeUnlockListener = removeUnlockListener;
    }
  }

  final DayEntriesRepository _dayEntries;
  final ObservationsRepository? _observations;
  final ReminderConfigService _configService;
  final bool Function()? _isUnlocked;
  final LocalDate Function() _today;
  final String Function() _timezone;
  void Function(void Function() callback)? _removeUnlockListener;

  /// The latched tap waiting for the gate to open (KTD4); null when
  /// nothing is pending. Exposed for tests and diagnostics only.
  @visibleForTesting
  bool get hasPending => _pending != null;
  _PendingAction? _pending;

  /// The tail of the serialized execution queue; null when idle.
  Future<void>? _draining;

  /// Resolves once every enqueued execution has finished — test and
  /// diagnostics seams; production never awaits this.
  @visibleForTesting
  Future<void> get idle => _draining ?? Future<void>.value();

  bool get _unlocked => _isUnlocked?.call() ?? true;

  /// Entry point from the notification-tap callback: handles action taps
  /// only. A plain tap (no action id) is not an action — it routes to the
  /// profile's overview through the pre-existing launch-payload seam and
  /// is ignored here.
  void handleAction(ReminderLaunch launch) {
    if (!launch.isAction) return;
    final pending = _PendingAction(launch.profileId, launch.actionId!);
    if (!_unlocked) {
      // Locked now: latch. The gate listener executes it on unlock.
      _pending = pending;
      return;
    }
    _enqueue(pending);
  }

  void _onGateChanged() {
    final pending = _pending;
    if (pending == null || !_unlocked) return;
    _pending = null;
    _enqueue(pending);
  }

  /// Serializes [pending] onto the drain queue: two taps (or a tap racing
  /// the unlock event) run one after the other, never interleaved, so the
  /// second run's dedupe checks see the first run's writes.
  void _enqueue(_PendingAction pending) {
    final previous = _draining ?? Future<void>.value();
    final run = previous.then((_) => _execute(pending));
    _draining = run;
    run.whenComplete(() {
      if (identical(_draining, run)) _draining = null;
    });
  }

  Future<void> _execute(_PendingAction pending) async {
    try {
      switch (pending.actionId) {
        case kReminderActionStarted:
          await _logStarted(pending.profileId);
        case kReminderActionSpotting:
          await _logSpotting(pending.profileId);
        case kReminderActionNotYet:
          await _configService.snoozeLate(
            pending.profileId,
            days: kNotYetSnoozeDays,
            today: _today(),
          );
        default:
          // decodeReminderLaunch only admits known action ids; unreachable
          // today, kept so a future action id that skips the decoder's
          // allow-list still cannot write anything.
          break;
      }
    } catch (error) {
      // Best effort by design: an action tap has no UI to surface a
      // failure into, and a failed write must never crash an unawaited
      // future. Logged by type only (the details could carry profile or
      // database specifics), matching the scheduler's posture.
      debugPrint('lunarlog reminders: action "${pending.actionId}" '
          'failed (${error.runtimeType})');
    }
  }

  /// "Started": upserts today's entry with the quick-log flow rule — the
  /// same rule the overview's "Period started today" card uses, including
  /// never downgrading a flow the operator already recorded.
  Future<void> _logStarted(String profileId) async {
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
  }

  /// "Spotting": the Issue #247 model — spotting is its own
  /// `observations` category row, never a flow level. Ensures the day has
  /// an entry (a fresh one carries the explicit not-bleeding assertion,
  /// exactly what the day sheet's own spotting-without-flow resolution
  /// writes), then attaches the spotting observation unless the day
  /// already has one.
  Future<void> _logSpotting(String profileId) async {
    final observations = _observations;
    final date = _today();
    final tzName = _timezone();
    final existing = await _dayEntries.find(profileId, date);
    final entry = existing ??
        await _dayEntries.save(DayEntry(
          id: '',
          profileId: profileId,
          localDate: date,
          tz: tzName,
          flow: FlowLevel.notBleeding,
          updatedAt: DateTime.now().toUtc(),
        ));
    if (observations == null) return;
    final dayObservations = await observations.listForDayEntry(entry.id);
    if (dayObservations.any((o) => o.category == 'spotting')) return;
    await observations.save(Observation(
      id: '',
      dayEntryId: entry.id,
      profileId: profileId,
      localDate: date,
      tz: tzName,
      category: 'spotting',
      code: 'spotting',
      updatedAt: DateTime.now().toUtc(),
    ));
  }

  /// Detaches the gate listener. Call when the owning widget tears down.
  void dispose() {
    _removeUnlockListener?.call(_onGateChanged);
    _removeUnlockListener = null;
    _pending = null;
  }
}
