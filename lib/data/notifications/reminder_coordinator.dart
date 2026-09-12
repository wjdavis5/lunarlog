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
///
/// Issue #178: each replan also runs the cycle-statistic-change detection
/// pass (see [_detectStatisticChanges]) — the prediction emissions this
/// class already consumes are the change signal the statistic-change
/// reminder fires on.
///
/// Issue #183: each active profile's birth-control state (the raw
/// `profile_modes` columns, via [birthControlStateFor]) is watched the
/// same way the predictions are — a recorded-method change lands as a row
/// emission and takes effect at the next debounced replan, so the plan
/// re-routes onto the new method's cadence (or drops it) with no stale
/// reminder left armed for the old method (`rescheduleAll` cancels every
/// pending notification before re-arming the fresh plan).
library;

// Named required parameters cannot be initializing formals; the private
// finals below are assigned through the constructor's initializer list.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lunarlog/data/notifications/notification_scheduler.dart'
    show LocalTimeZoneProvider, defaultLocalTimeZoneProvider;
import 'package:lunarlog/domain/birth_control.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/notifications/reminder_config.dart';
import 'package:lunarlog/domain/notifications/reminder_config_store.dart';
import 'package:lunarlog/domain/notifications/reminder_payload.dart';
import 'package:lunarlog/domain/notifications/reminder_presets.dart';
import 'package:lunarlog/domain/notifications/reminder_scheduler.dart';
import 'package:lunarlog/domain/notifications/scheduling.dart';
import 'package:lunarlog/domain/notifications/statistic_change.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/util/timezone.dart' show isValidIanaTimeZone;
import 'package:timezone/timezone.dart' as tz;

typedef ActiveProfilesStream = Stream<List<Profile>>;
typedef PredictionStream = Stream<CyclePrediction> Function(String profileId);

/// The per-profile birth-control state stream (Issue #183): the raw
/// `profile_modes` birth-control columns for [profileId], or null when no
/// row exists. The production source is the drift row watcher
/// (`LunarLogStorage.watchProfileMode`); the reminder seam deliberately
/// reads the raw strings and lets the planner resolve them through
/// `birthControlMethodInEffectOn`, so coordinator and planner share one
/// interpretation of the row.
typedef BirthControlStateStream = Stream<BirthControlState?> Function(
    String profileId);

class ReminderCoordinator with WidgetsBindingObserver {
  ReminderCoordinator({
    required ReminderScheduler scheduler,
    required NotificationAvailabilitySink permissionState,
    required ActiveProfilesStream activeProfiles,
    required PredictionStream predictionFor,
    ReminderConfigService? localSettings,
    BirthControlStateStream? birthControlStateFor,
    LocalDate Function()? today,
    LocalTimeZoneProvider? localTimeZoneProvider,
    this.replanDebounce = const Duration(milliseconds: 250),
  })  : _scheduler = scheduler,
        _permissionState = permissionState,
        _activeProfiles = activeProfiles,
        _predictionFor = predictionFor,
        _localSettings = localSettings,
        _birthControlStateFor = birthControlStateFor,
        today = today ?? LocalDate.today,
        _localTimeZoneProvider =
            localTimeZoneProvider ?? defaultLocalTimeZoneProvider {
    WidgetsBinding.instance.addObserver(this);
  }

  final ReminderScheduler _scheduler;
  final NotificationAvailabilitySink _permissionState;
  final ActiveProfilesStream _activeProfiles;
  final PredictionStream _predictionFor;
  final LocalTimeZoneProvider _localTimeZoneProvider;

  /// Issue #183: the per-profile birth-control row watcher. Null keeps the
  /// pre-#183 shape (no birth-control reminders are planned); when
  /// present, each active profile gets a subscription like its prediction
  /// one, and a row emission schedules a replan so a recorded-method
  /// change re-routes the adherence reminder at the next pass.
  final BirthControlStateStream? _birthControlStateFor;

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
  final Map<String, StreamSubscription<BirthControlState?>> _birthControlSubs =
      {};
  final Map<String, ActivePrediction> _latest = {};

  /// Each active profile's last-observed birth-control state (Issue #183),
  /// carried into every replan for [planReminders]'s
  /// `birthControlModes`. Null rows (no mode row yet) leave no entry.
  final Map<String, BirthControlState> _birthControlStates = {};

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
    _syncBirthControlSubs(activeIds);
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

  /// Keeps the per-profile birth-control row subscriptions (Issue #183) in
  /// step with the active set: an archived profile's subscription is
  /// cancelled and its cached state dropped so its adherence reminders
  /// stop at the next replan; each still-active profile without one gets a
  /// subscription. Extracted from [_onProfilesChanged] for the same
  /// complexity reason as every other seam hook there.
  void _syncBirthControlSubs(Set<String> activeIds) {
    _birthControlSubs.removeWhere((id, sub) {
      if (activeIds.contains(id)) return false;
      unawaited(sub.cancel());
      _birthControlStates.remove(id);
      return true;
    });
    final birthControlStateFor = _birthControlStateFor;
    if (birthControlStateFor == null) return;
    for (final id in activeIds) {
      _birthControlSubs.putIfAbsent(
        id,
        () => birthControlStateFor(id).listen((state) {
          if (state == null) {
            _birthControlStates.remove(id);
          } else {
            _birthControlStates[id] = state;
          }
          _scheduleReplan();
        }),
      );
    }
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
    Map<String, LocalDate> statisticSignals = const {};
    final localSettings = _localSettings;
    if (localSettings != null) {
      configs = await localSettings.loadAll();
      lateSnoozes = await localSettings.loadLateSnoozes();
      statisticSignals = await _detectStatisticChanges(localSettings);
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
        statisticChangeSignals: statisticSignals,
        // Issue #183: the birth-control row watcher's last-observed
        // state. An empty map (no watcher wired, or no rows yet) plans
        // no adherence reminders.
        birthControlModes: Map.of(_birthControlStates),
      ),
    );
  }

  /// The `cycleStatisticChange` detection pass (Issue #178): compares each
  /// live prediction's displayed-statistic snapshot against the stored
  /// per-profile baseline, records a same-day signal on a meaningful
  /// change, and re-baselines every observed profile — the prediction
  /// stream itself is the change signal, no polling timer. Baselines live
  /// in the device-local store, so a change that lands while the app is
  /// closed (an overnight sync, a back-dated log) still fires on the first
  /// post-open replan, and the stored signal date makes the same-day
  /// reminder survive a restart before it has fired.
  ///
  /// Detection runs regardless of the kind's toggle: the signal is data
  /// about the statistics, and the planner gates on the config — so
  /// enabling the kind mid-day still fires a change observed earlier that
  /// day. Baselines are persisted only when the map actually changed,
  /// which keeps this pass from ping-ponging the settings `changes`
  /// stream into an endless replan loop.
  Future<Map<String, LocalDate>> _detectStatisticChanges(
    ReminderConfigService localSettings,
  ) async {
    final today = this.today();
    final storedSignals = await localSettings.loadStatisticChangeSignals();
    final signals = Map.of(storedSignals);
    final nextBaselines = Map.of(await localSettings.loadStatisticBaselines());
    var baselinesChanged = false;
    for (final entry in _latest.entries) {
      final snapshot = CycleStatisticSnapshot.fromPrediction(entry.value);
      final baseline = nextBaselines[entry.key];
      if (baseline != null &&
          isMeaningfulStatisticChange(baseline, snapshot) &&
          storedSignals[entry.key] != today) {
        signals[entry.key] = today;
        await localSettings.recordStatisticChange(entry.key, today: today);
      }
      if (baseline != snapshot) {
        nextBaselines[entry.key] = snapshot;
        baselinesChanged = true;
      }
    }
    if (baselinesChanged) {
      await localSettings.saveStatisticBaselines(nextBaselines);
    }
    return signals;
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

    // Issue #169: re-resolve device timezone on resume instead of once at init.
    try {
      final tzName = await _localTimeZoneProvider();
      if (tz.local.name != tzName && isValidIanaTimeZone(tzName)) {
        final loc = tz.getLocation(tzName);
        tz.setLocalLocation(loc);
      }
    } catch (_) {}

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
    for (final sub in _birthControlSubs.values) {
      await sub.cancel();
    }
    _birthControlSubs.clear();
  }
}
