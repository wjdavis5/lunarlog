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

import 'package:flutter/foundation.dart' show listEquals;
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
import 'package:lunarlog/domain/care_modes.dart' show irregularFramingInEffect;
import 'package:lunarlog/domain/notifications/reminder_presets.dart';
import 'package:lunarlog/domain/notifications/reminder_scheduler.dart';
import 'package:lunarlog/domain/notifications/scheduling.dart';
import 'package:lunarlog/domain/notifications/statistic_change.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/util/timezone.dart' show isValidIanaTimeZone;
import 'package:timezone/timezone.dart' as tz;

/// The per-profile birth-control state stream (Issue #183): the raw
/// `profile_modes` birth-control columns for [profileId], or null when no
/// row exists. The production source is the drift row watcher
/// (`LunarLogStorage.watchProfileMode`); the reminder seam deliberately
/// reads the raw strings and lets the planner resolve them through
/// `birthControlMethodInEffectOn`, so coordinator and planner share one
/// interpretation of the row.
typedef BirthControlStateStream = Stream<BirthControlState?> Function(
    String profileId);

/// Answers whether the current viewer is the *subject* of [profileId]
/// (Issue #850, D-6) — the per-viewer guardian lens resolved over that
/// profile's guardian rows plus the signed-in user id. Null keeps the
/// pre-#850 all-subject default: every active profile counts as the
/// viewer's own, so its mode preset arms locally. The production wiring in
/// `lib/composition/app_dependencies.dart` builds it from `guardianLensFor`.
///
/// A profile the source reports as *not* subject is planned with
/// [ReminderPreset.none]: a guardian's device never arms a local reminder
/// for someone else's record — the server caregiver alerts (issue #5)
/// cover that case. The source is read fresh at every replan, so a sign-in
/// (or a membership row that arrives late) is reflected at the next pass.
typedef SubjectProfileSource = Future<bool> Function(String profileId);

class ReminderCoordinator with WidgetsBindingObserver {
  ReminderCoordinator({
    required ReminderScheduler scheduler,
    required NotificationAvailabilitySink permissionState,
    required ActiveProfilesStream activeProfiles,
    required PredictionStream predictionFor,
    ReminderConfigService? localSettings,
    BirthControlStateStream? birthControlStateFor,
    SubjectProfileSource? isSubjectFor,
    LocalDate Function()? today,
    LocalTimeZoneProvider? localTimeZoneProvider,
    this.replanDebounce = const Duration(milliseconds: 250),
  })  : _scheduler = scheduler,
        _permissionState = permissionState,
        _activeProfiles = activeProfiles,
        _predictionFor = predictionFor,
        _localSettings = localSettings,
        _birthControlStateFor = birthControlStateFor,
        _isSubjectFor = isSubjectFor,
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

  /// Issue #850, D-6: the per-viewer lens source. Null keeps the pre-#850
  /// all-subject default (every active profile arms its mode preset), so
  /// every existing harness that passes no source behaves exactly as
  /// before. When present, a profile the source reports as *not* the
  /// viewer's subject is planned with [ReminderPreset.none].
  final SubjectProfileSource? _isSubjectFor;

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

  /// The reminder plan last applied to [_scheduler] via `rescheduleAll`
  /// (Issue #840). When a newly-computed plan is element-wise unchanged from
  /// this snapshot, `rescheduleAll` is skipped entirely — avoiding ~61
  /// sequential platform-channel calls on every prediction emission or
  /// autosave. Reset to null on permission denial or timezone change so the
  /// next eligible pass unconditionally re-arms the scheduler.
  List<PlannedReminder>? _lastAppliedPlan;

  /// Each active profile's last-observed birth-control state (Issue #183),
  /// carried into every replan for [planReminders]'s
  /// `birthControlModes`. Null rows (no mode row yet) leave no entry.
  final Map<String, BirthControlState> _birthControlStates = {};

  /// Each active profile's care mode (Issue #131), carried from the active-
  /// profiles stream into every replan as a [ReminderPreset]. Refreshed by
  /// the same `_onProfilesChanged` emission that schedules the replan, so a
  /// mode switch is applied at the next coordinator pass.
  final Map<String, ProfileMode> _modes = {};

  /// Each active profile's stored irregular-framing tri-state (Issue #853),
  /// resolved against the live prediction's tier at replan time by
  /// [irregularFramingInEffect] — the teen default (framing ON until
  /// `CycleConfidence.high`) therefore applies to reminder planning too,
  /// not just rendered copy.
  final Map<String, bool?> _irregularFraming = {};
  Timer? _replanTimer;
  int _permissionProbeGeneration = 0;

  /// Stamped on every [replan] entry (Issue #634, LLA-097): whichever pass
  /// last incremented this is the only one still allowed to apply its
  /// plan. A pass whose own reads (stored config, snoozes, statistic
  /// baselines) take long enough for a fresher pass to start and finish
  /// first sees a mismatch at its own pre-scheduler-call check and returns
  /// without ever reaching the scheduler — the same generation-guard shape
  /// [_permissionProbeGeneration] already uses for the resume/permission
  /// probe (also the root cause behind #655's flaky test: two passes
  /// racing to decide the coordinator's next scheduler call).
  int _replanGeneration = 0;

  /// The most recently started [replan] call — tracked so [dispose] can
  /// drain it (Issue #634, LLA-097) rather than returning while a
  /// pre-teardown pass (and whatever it has already queued onto
  /// [_schedulerQueue]) is still in flight.
  Future<void>? _activeReplan;

  /// Serializes every call into [_scheduler] (Issue #634, LLA-097): two
  /// replans that overlap (a fast profile edit racing a debounced resume)
  /// queue their `rescheduleAll`/`cancelAll` calls one after another
  /// instead of ever letting two such calls run concurrently against the
  /// plugin, which could otherwise let an older pass's write land after a
  /// newer one's and leave a stale reminder pending.
  Future<void> _schedulerQueue = Future<void>.value();
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
          _irregularFraming.remove(id);
          return true;
        });
    _syncBirthControlSubs(activeIds);
    for (final profile in profiles) {
      // Mode is carried on the same stream the replan rides: a mode switch
      // (any profile write) lands here and the scheduled replan below
      // re-filters every reminder through the new preset (Issue #131).
      _modes[profile.id] = profile.mode;
      // Issue #853: the framing flag rides the same stream for the same
      // reason — the compose happens per replan (with the live tier), not
      // here, so the teen default follows the engine as it changes.
      _irregularFraming[profile.id] = profile.irregularFraming;
    }
    _modes.removeWhere((id, _) => !activeIds.contains(id));
    _irregularFraming.removeWhere((id, _) => !activeIds.contains(id));
    for (final id in activeIds) {
      _predictionSubs.putIfAbsent(
        id,
        () => _predictionFor(id).listen((prediction) {
          final previous = _latest[id];
          // Issue #840: skip replanning when the prediction stream re-emits
          // the identical memo-cached prediction instance (the common
          // day-sheet entries write / autosave path).
          if (identical(prediction, previous)) return;
          if (prediction is ActivePrediction) {
            _latest[id] = prediction;
          } else {
            if (previous == null) return;
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
          final previous = _birthControlStates[id];
          if (state == previous) return;
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

  /// Serializes one call into [_scheduler] behind whatever is already
  /// queued (Issue #634, LLA-097). Errors are swallowed only on the
  /// queue's own continuation chain, never on the future handed back to
  /// [action]'s caller, so a failed pass cannot wedge every later one.
  ///
  /// Rechecks [_disposed] at the moment this queued action actually gets
  /// its turn — not just when it was enqueued — so an action that was
  /// already queued behind another when [dispose] ran still can never
  /// touch the scheduler once torn down: this is the single choke point
  /// every caller (the "denied" branch and the main plan both) funnels
  /// through, so neither needs its own extra disposed check right before
  /// enqueueing.
  Future<void> _runOnSchedulerQueue(Future<void> Function() action) {
    final result = _schedulerQueue.then((_) {
      if (_disposed) return Future<void>.value();
      return action();
    });
    _schedulerQueue = result.catchError((Object _) {});
    return result;
  }

  /// The only writer of availability: keeps the local mirror [replan]
  /// reads in step with the sink the UI renders. The sink is write-only
  /// (it is a `lib/domain` contract), so the mirror is how the coordinator
  /// reads back a value it published — including the resume re-check.
  void _setAvailability(NotificationAvailability next) {
    _availability = next;
    _permissionState.update(next);
  }

  /// Public replan entry point. Every call (whether from the debounce
  /// timer or a direct test call) is tracked in [_activeReplan] so
  /// [dispose] can drain it (Issue #634, LLA-097) — the tracking wrapper
  /// is kept separate from [_runReplan] so the generation/staleness logic
  /// below stays its own small method.
  @visibleForTesting
  Future<void> replan() {
    final result = _runReplan();
    _activeReplan = result;
    return result;
  }

  bool _isSuperseded(int generation) =>
      _disposed || generation != _replanGeneration;

  Future<void> _runReplan() async {
    if (_disposed) return;
    // Issue #634, LLA-097: stamps this pass so a superseded one (a newer
    // replan already started before this one finished its own reads)
    // never applies its now-stale plan — see the checks below, each
    // placed right before the point this pass would otherwise reach the
    // scheduler.
    final generation = ++_replanGeneration;
    if (_availability == NotificationAvailability.denied) {
      _lastAppliedPlan = null;
      await _runOnSchedulerQueue(_scheduler.cancelAll);
      return;
    }
    final (:configs, :lateSnoozes, :statisticSignals) =
        await _loadReplanSettings(_localSettings);
    final subjectProfileIds = await _resolveSubjectProfileIds();
    if (_isSuperseded(generation)) return;
    final plan = _buildPlan(
      configs: configs,
      lateSnoozes: lateSnoozes,
      statisticSignals: statisticSignals,
      subjectProfileIds: subjectProfileIds,
    );
    // Issue #840: skip rescheduleAll when the computed reminder plan is
    // element-wise unchanged from the last applied one. Each rescheduleAll
    // cancels all pending notifications and reschedules up to 60 reminders
    // (~61 sequential platform calls). Returning early when the plan hasn't
    // changed avoids redundant platform-channel churn on the UI event loop.
    if (listEquals(plan, _lastAppliedPlan)) return;
    if (_isSuperseded(generation)) return;
    await _runOnSchedulerQueue(() => _scheduler.rescheduleAll(plan));
    if (_isSuperseded(generation)) return;
    _lastAppliedPlan = plan;
  }

  Future<
      ({
        Map<String, ReminderConfig> configs,
        Map<String, LocalDate> lateSnoozes,
        Map<String, LocalDate> statisticSignals,
      })> _loadReplanSettings(ReminderConfigService? localSettings) async {
    if (localSettings == null) {
      return (
        configs: const <String, ReminderConfig>{},
        lateSnoozes: const <String, LocalDate>{},
        statisticSignals: const <String, LocalDate>{},
      );
    }
    return (
      configs: await localSettings.loadAll(),
      lateSnoozes: await localSettings.loadLateSnoozes(),
      statisticSignals: await _detectStatisticChanges(localSettings),
    );
  }

  List<PlannedReminder> _buildPlan({
    required Map<String, ReminderConfig> configs,
    required Map<String, LocalDate> lateSnoozes,
    required Map<String, LocalDate> statisticSignals,
    required Set<String>? subjectProfileIds,
  }) {
    return planReminders(
      today: today(),
      predictions: Map.of(_latest),
      presets: {
        // Issue #850, D-6: the preset is gated on the per-viewer lens — a
        // profile the viewer is not the subject of plans nothing locally.
        // Issue #853: for a subject profile the preset composes mode + the
        // effective irregular framing (the stored tri-state resolved against
        // the live tier from the prediction the coordinator already holds) —
        // framing ON means no "late" nags, whatever the mode.
        for (final entry in _modes.entries)
          entry.key: _presetForProfile(
            entry.key,
            entry.value,
            subjectProfileIds,
          ),
      },
      configs: configs,
      lateSnoozes: lateSnoozes,
      statisticChangeSignals: statisticSignals,
      // Issue #183: the birth-control row watcher's last-observed
      // state. An empty map (no watcher wired, or no rows yet) plans
      // no adherence reminders.
      birthControlModes: Map.of(_birthControlStates),
      // Issue #634, LLA-098: `_modes` is pruned to exactly the currently
      // active profile ids in `_onProfilesChanged`, so it is this
      // coordinator's own authoritative active set — a stored config row
      // or birth-control state left over for an archived/removed profile
      // (neither is deleted just because the profile leaves the active
      // stream) can then never plan a reminder.
      activeProfileIds: _modes.keys.toSet(),
    );
  }

  /// Resolves which currently active profiles the signed-in viewer is the
  /// subject of (Issue #850, D-6). Null when no [SubjectProfileSource] is
  /// wired — the pre-#850 all-subject default — so [_buildPlan] skips the
  /// lens gate entirely. The id set is snapshotted (`toList`) before
  /// awaiting, so a profiles emission that lands between reads cannot mutate
  /// the active set under iteration.
  ///
  /// A failed read fails open to "subject", matching `guardianLensFor`'s
  /// own posture: a not-yet-synced membership briefly keeps the subject
  /// preset rather than permanently silencing the operator's reminders.
  Future<Set<String>?> _resolveSubjectProfileIds() async {
    final isSubjectFor = _isSubjectFor;
    if (isSubjectFor == null) return null;
    final subjectIds = <String>{};
    for (final id in _modes.keys.toList()) {
      try {
        if (await isSubjectFor(id)) subjectIds.add(id);
      } catch (_) {
        subjectIds.add(id);
      }
    }
    return subjectIds;
  }

  /// The preset for one active profile, gated on the per-viewer lens
  /// (Issue #850, D-6): a profile the signed-in viewer is not the subject
  /// of plans nothing locally, whatever its mode. A null
  /// [subjectProfileIds] is the pre-#850 all-subject default.
  ///
  /// For a subject profile the preset composes mode + the effective
  /// irregular framing (Issue #853): the stored tri-state resolved against
  /// the live tier from the prediction the coordinator already holds —
  /// framing ON means no "late" nags, whatever the mode. Only an
  /// [ActivePrediction] carries a tier; every other prediction state
  /// (not-enough-history/suppressed/disabled) reads null, which
  /// [irregularFramingInEffect] resolves to a teen's framing ON — the early
  /// months are exactly when the "late" nag would be wrong.
  ReminderPreset _presetForProfile(
    String profileId,
    ProfileMode mode,
    Set<String>? subjectProfileIds,
  ) {
    if (subjectProfileIds != null && !subjectProfileIds.contains(profileId)) {
      return ReminderPreset.none;
    }
    return reminderPresetFor(
      mode,
      irregularFraming: irregularFramingInEffect(
        mode: mode,
        stored: _irregularFraming[profileId],
        tier: switch (_latest[profileId]) {
          final ActivePrediction p => p.tier,
          _ => null,
        },
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

    // "At every app open": permission or the civil day may have changed.
    // Scheduled immediately — before the timezone re-resolution below —
    // so a slow platform-channel timezone lookup can never delay the
    // permission-driven replan/cancellation this resume exists to run.
    // (Issue #655: this ordering used to be reversed, with the replan
    // gated behind the `await` on `_localTimeZoneProvider()` below; that
    // unrelated platform-channel round trip is genuinely variable-latency
    // in a headless test run, which is what made the "resume notices
    // revoked permission and cancels reminders" test flaky on CI — the
    // fixed-iteration `pumpEventQueue()` sometimes settled before that
    // await resolved. Decoupling it removes the dependency entirely
    // rather than papering over it with more pumps or a longer timeout.)
    _scheduleReplan();
    unawaited(_refreshTimeZone(generation));
  }

  /// Issue #169: re-resolve device timezone on resume instead of once at
  /// init. Split out of [_refreshPermissionAndReplan] (Issue #655) so a
  /// slow or hanging platform-channel timezone lookup can never delay the
  /// permission-driven replan there — but a zone that actually turns out
  /// to have changed still schedules its own replan below, so a real
  /// travel case is never left stuck on the stale zone: the caller's own
  /// unconditional replan may have already fired (and computed every fire
  /// time from the old zone) before this slower probe resolves, especially
  /// on a cold-start resume where the platform channel can plausibly
  /// outlast [replanDebounce]. Calling [_scheduleReplan] again here either
  /// coalesces into that not-yet-fired pass (still debounced) or — if it
  /// already fired — schedules a correcting one; the generation stamp in
  /// [_runReplan] means a slower, now-stale pass can never overwrite a
  /// fresher one's plan regardless of which order they actually resolve
  /// in. Skipped while denied: a denied replan only calls `cancelAll`,
  /// which has no time-zone dependency, so re-triggering it here would
  /// just be a second redundant `cancelAll` (exactly the double-call the
  /// first version of this fix introduced and the coordinator test below
  /// catches). Guarded on the same generation as the caller so a stale
  /// resume's late-arriving answer can never overwrite `tz.local` after a
  /// fresher probe already ran.
  Future<void> _refreshTimeZone(int generation) async {
    try {
      final tzName = await _localTimeZoneProvider();
      if (_disposed || generation != _permissionProbeGeneration) return;
      if (tz.local.name != tzName && isValidIanaTimeZone(tzName)) {
        tz.setLocalLocation(tz.getLocation(tzName));
        _lastAppliedPlan = null;
        if (_availability != NotificationAvailability.denied) {
          _scheduleReplan();
        }
      }
    } catch (_) {}
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
    // Issue #634, LLA-097 (revised after PR #668's review round 2): this
    // deliberately does NOT await [_activeReplan] or [_schedulerQueue].
    // An earlier version of this method did, reasoning that it would
    // "drain" whatever was in flight before returning — but an `await`
    // here has no bound: a genuinely hung platform call (the scheduler's
    // own plugin channel) would hang `dispose()` itself forever, and in
    // practice it hung a *passing* scenario too — a widget test's
    // `State.dispose()` runs inside `flutter_test`'s fake-async zone,
    // where an already-resolved-in-principle Future can still sit
    // unresolved until something pumps that zone again, which nothing in
    // `LunarLogApp hands its coordinator teardown to onTeardown` did
    // before handing the returned Future to `tester.runAsync`. A hung
    // platform call must never be able to block app teardown either way.
    //
    // LLA-097's actual guarantee — no reschedule/cancel reaches the
    // scheduler once disposed, and no stale generation's plan is ever
    // applied — is enforced structurally instead, independent of whether
    // anyone waits for it: [_runReplan] rechecks [_disposed] and its own
    // generation before ever deciding to touch the scheduler, and
    // [_runOnSchedulerQueue] rechecks [_disposed] again immediately
    // before actually invoking the scheduler, right as a queued action
    // gets its turn. Whatever was already in flight is left to finish
    // (and self-invalidate) or fail on its own; there is no caller left
    // to hand a late failure to, so it is swallowed here rather than
    // becoming an unhandled zone error.
    unawaited(_activeReplan?.catchError((_) {}));
  }
}
