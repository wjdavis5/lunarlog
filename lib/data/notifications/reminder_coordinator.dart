/// Reminder coordinator (KTD7, R12): wires prediction streams to the
/// scheduler. Replans on every profile/prediction change (i.e. at every
/// write) and on app resume ("at every app open"); archived profiles drop
/// out because only active profiles are planned. Permission denial skips
/// scheduling and surfaces the U6 overview hint.
///
/// Issue #131 (KTD10): each active profile's care mode contributes a
/// [ReminderPreset] to every replan, so switching a profile's mode takes
/// effect at the next coordinator pass — never retroactively rewriting
/// saved entries or already-delivered reminders.
library;

// Named required parameters cannot be initializing formals; the private
// finals below are assigned through the constructor's initializer list.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lunarlog/data/notifications/notification_scheduler.dart';
import 'package:lunarlog/data/notifications/reminder_payload.dart';
import 'package:lunarlog/data/notifications/scheduling.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/notifications/reminder_config.dart';
import 'package:lunarlog/domain/notifications/reminder_config_store.dart';
import 'package:lunarlog/domain/notifications/reminder_presets.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

typedef ActiveProfilesStream = Stream<List<Profile>>;
typedef PredictionStream = Stream<CyclePrediction> Function(String profileId);

class ReminderCoordinator with WidgetsBindingObserver {
  ReminderCoordinator({
    required ReminderScheduler scheduler,
    required NotificationAvailabilitySink permissionState,
    required ActiveProfilesStream activeProfiles,
    required PredictionStream predictionFor,
    ReminderConfigService? localSettings,
    LocalDate Function()? today,
    this.replanDebounce = const Duration(milliseconds: 250),
  })  : _scheduler = scheduler,
        _permissionState = permissionState,
        _activeProfiles = activeProfiles,
        _predictionFor = predictionFor,
        _localSettings = localSettings,
        today = today ?? LocalDate.today {
    WidgetsBinding.instance.addObserver(this);
  }

  final ReminderScheduler _scheduler;
  final NotificationAvailabilitySink _permissionState;
  final ActiveProfilesStream _activeProfiles;
  final PredictionStream _predictionFor;

  /// Per-profile local reminder configuration and late snoozes (Issue
  /// #136, R10/R11). Null keeps the pre-#136 shape: every profile plans
  /// from its care-mode preset defaults with no snoozes. When present,
  /// every replan re-reads the stored configs and snoozes (a cheap,
  /// always-current device-local read), and the service's `changes`
  /// stream triggers a replan — so a settings edit takes effect at the
  /// next coordinator pass exactly like a care-mode switch does.
  final ReminderConfigService? _localSettings;
  StreamSubscription<void>? _localSettingsSub;
  final LocalDate Function() today;

  @visibleForTesting
  final Duration replanDebounce;

  // Availability as last published through [_setAvailability] — by [start],
  // and again by the resume re-probe. [replan] reads this rather than the
  // sink, which is a write-only `lib/domain` contract.
  //
  // Eagerly initialized, never `late`. `didChangeAppLifecycleState`'s
  // `_started` guard means nothing should reach [replan] before [start]
  // resolves, so this is defence in depth rather than the only thing
  // holding that window: a `late` field would turn any future path that did
  // reach it into a LateInitializationError thrown from an unawaited timer.
  // `available` matches the value the composition root seeds the sink with.
  NotificationAvailability _availability = NotificationAvailability.available;

  StreamSubscription<List<Profile>>? _profilesSub;
  final Map<String, StreamSubscription<CyclePrediction>> _predictionSubs = {};
  final Map<String, ActivePrediction> _latest = {};

  /// Each active profile's care mode (Issue #131), carried from the active-
  /// profiles stream into every replan as a [ReminderPreset]. Refreshed by
  /// the same `_onProfilesChanged` emission that schedules the replan, so a
  /// mode switch is applied at the next coordinator pass.
  final Map<String, ProfileMode> _modes = {};
  Timer? _replanTimer;
  int _permissionProbeGeneration = 0;
  bool _started = false;
  bool _disposed = false;

  Future<void> start({
    void Function(ReminderLaunch launch)? onLaunchFromNotification,
  }) async {
    final generation = ++_permissionProbeGeneration;
    final availability =
        await _scheduler.initialize(onLaunchFromNotification: (launch) {
      onLaunchFromNotification?.call(launch);
      // A tap that lands while the app is backgrounded re-locks the gate;
      // the payload is consumed by the home gate after the next unlock.
      // An action-button tap (Issue #136) rides the same callback and is
      // executed after the gate by the ReminderActionExecutor.
    });
    if (_disposed) return;
    if (generation == _permissionProbeGeneration) {
      _setAvailability(availability);
    }
    _profilesSub = _activeProfiles.listen(_onProfilesChanged);
    // Issue #136: a reminder-settings edit (or a "Not yet" snooze) replans
    // at the next debounced pass.
    _localSettingsSub = _localSettings?.changes.listen((_) {
      _scheduleReplan();
    });
    _started = true;
  }

  void _onProfilesChanged(List<Profile> profiles) {
    if (_disposed) return;
    final activeIds = profiles.map((p) => p.id).toSet();
    // Archiving drops a profile's reminders: cancel its prediction stream
    // and forget its plan.
    _predictionSubs
        .removeWhere((id, sub) {
          if (activeIds.contains(id)) return false;
          unawaited(sub.cancel());
          _latest.remove(id);
          _modes.remove(id);
          return true;
        });
    for (final profile in profiles) {
      // Mode is carried on the same stream the replan rides: a mode switch
      // (any profile write) lands here and the scheduled replan below
      // re-filters every reminder through the new preset (Issue #131).
      _modes[profile.id] = profile.mode;
    }
    _modes.removeWhere((id, _) => !activeIds.contains(id));
    for (final id in activeIds) {
      _predictionSubs.putIfAbsent(
        id,
        () => _predictionFor(id).listen((prediction) {
          if (prediction is ActivePrediction) {
            _latest[id] = prediction;
          } else {
            _latest.remove(id);
          }
          _scheduleReplan();
        }),
      );
    }
    _scheduleReplan();
  }

  void _scheduleReplan() {
    if (_disposed) return;
    _replanTimer?.cancel();
    _replanTimer = Timer(replanDebounce, () => unawaited(replan()));
  }

  /// The only writer of availability: keeps the local mirror [replan]
  /// reads in step with the sink the UI renders. The sink is write-only
  /// (it is a `lib/domain` contract), so the mirror is how the coordinator
  /// reads back a value it published — including the resume re-check.
  void _setAvailability(NotificationAvailability next) {
    _availability = next;
    _permissionState.update(next);
  }

  @visibleForTesting
  Future<void> replan() async {
    if (_disposed) return;
    if (_availability == NotificationAvailability.denied) {
      await _scheduler.cancelAll();
      return;
    }
    // Issue #136: the stored per-profile configs and late snoozes are
    // re-read on every replan rather than mirrored in memory — a settings
    // edit (or a "Not yet" tap) is then live at the very next pass with
    // no cache to invalidate, and a profile with nothing stored still
    // plans from its care-mode preset defaults via planReminders.
    Map<String, ReminderConfig> configs = const {};
    Map<String, LocalDate> lateSnoozes = const {};
    final localSettings = _localSettings;
    if (localSettings != null) {
      configs = await localSettings.loadAll();
      lateSnoozes = await localSettings.loadLateSnoozes();
    }
    await _scheduler.rescheduleAll(
      planReminders(
        today: today(),
        predictions: Map.of(_latest),
        presets: {
          for (final entry in _modes.entries)
            entry.key: reminderPresetFor(entry.value),
        },
        configs: configs,
        lateSnoozes: lateSnoozes,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_started && state == AppLifecycleState.resumed) {
      final generation = ++_permissionProbeGeneration;
      unawaited(_refreshPermissionAndReplan(generation));
    }
  }

  Future<void> _refreshPermissionAndReplan(int generation) async {
    final availability = await _scheduler.checkAvailability();
    if (_disposed || generation != _permissionProbeGeneration) return;
    _setAvailability(availability);
    // "At every app open": permissions or the civil day may have changed.
    _scheduleReplan();
  }

  /// Issue #168: the overview hint's "Turn on reminders" tap. Same
  /// generation-guarded shape as [start] and [_refreshPermissionAndReplan]
  /// so a resume racing this request can't let a stale answer win, and
  /// republishes through the same [_setAvailability] seam so the hint
  /// reacts immediately rather than waiting for the next app resume.
  Future<void> requestPermission() async {
    if (_disposed || !_started) return;
    final generation = ++_permissionProbeGeneration;
    // In practice, the OS permission dialog this awaits is itself a real
    // app-lifecycle event (backgrounded, then resumed) even though
    // `app.dart` wraps this call in the gate's system-UI window to stop it
    // from re-locking. That resume still reaches
    // `didChangeAppLifecycleState`, which bumps `_permissionProbeGeneration`
    // again and races its own `_refreshPermissionAndReplan` probe to
    // completion first -- so by the time `_scheduler.requestPermission()`
    // resolves here, the guard below usually finds a stale generation and
    // discards this result rather than applying it. That is intentional,
    // not a bug to tighten: the resume's probe is the fresher of the two,
    // and letting this one win instead would occasionally overwrite it
    // with an answer read a moment earlier.
    final availability = await _scheduler.requestPermission();
    if (_disposed || generation != _permissionProbeGeneration) return;
    _setAvailability(availability);
    _scheduleReplan();
  }

  Future<void> dispose() async {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _replanTimer?.cancel();
    await _profilesSub?.cancel();
    await _localSettingsSub?.cancel();
    _localSettingsSub = null;
    for (final sub in _predictionSubs.values) {
      await sub.cancel();
    }
    _predictionSubs.clear();
  }
}
