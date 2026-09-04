/// Reminder coordinator (KTD7, R12): wires prediction streams to the
/// scheduler. Replans on every profile/prediction change (i.e. at every
/// write) and on app resume ("at every app open"); archived profiles drop
/// out because only active profiles are planned. Permission denial skips
/// scheduling and surfaces the U6 overview hint.
library;

// Named required parameters cannot be initializing formals; the private
// finals below are assigned through the constructor's initializer list.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lunarlog/data/notifications/notification_scheduler.dart';
import 'package:lunarlog/data/notifications/scheduling.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

typedef ActiveProfilesStream = Stream<List<Profile>>;
typedef PredictionStream = Stream<CyclePrediction> Function(String profileId);

class ReminderCoordinator with WidgetsBindingObserver {
  ReminderCoordinator({
    required ReminderScheduler scheduler,
    required NotificationAvailabilitySink permissionState,
    required ActiveProfilesStream activeProfiles,
    required PredictionStream predictionFor,
    LocalDate Function()? today,
    this.replanDebounce = const Duration(milliseconds: 250),
  })  : _scheduler = scheduler,
        _permissionState = permissionState,
        _activeProfiles = activeProfiles,
        _predictionFor = predictionFor,
        today = today ?? LocalDate.today {
    WidgetsBinding.instance.addObserver(this);
  }

  final ReminderScheduler _scheduler;
  final NotificationAvailabilitySink _permissionState;
  final ActiveProfilesStream _activeProfiles;
  final PredictionStream _predictionFor;
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
  Timer? _replanTimer;
  int _permissionProbeGeneration = 0;
  bool _started = false;
  bool _disposed = false;

  Future<void> start({
    void Function(String profileId)? onLaunchFromNotification,
  }) async {
    final generation = ++_permissionProbeGeneration;
    final availability =
        await _scheduler.initialize(onLaunchFromNotification: (id) {
      onLaunchFromNotification?.call(id);
      // A tap that lands while the app is backgrounded re-locks the gate;
      // the payload is consumed by the home gate after the next unlock.
    });
    if (_disposed) return;
    if (generation == _permissionProbeGeneration) {
      _setAvailability(availability);
    }
    _profilesSub = _activeProfiles.listen(_onProfilesChanged);
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
          return true;
        });
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
    await _scheduler.rescheduleAll(
      planReminders(today: today(), predictions: Map.of(_latest)),
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

  Future<void> dispose() async {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _replanTimer?.cancel();
    await _profilesSub?.cancel();
    for (final sub in _predictionSubs.values) {
      await sub.cancel();
    }
    _predictionSubs.clear();
  }
}
