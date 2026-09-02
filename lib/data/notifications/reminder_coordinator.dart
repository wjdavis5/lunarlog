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
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/ui/overview/notification_availability.dart';

/// Observable permission state consumed by the overview hint (U6 seam).
class NotificationPermissionState extends ChangeNotifier {
  NotificationPermissionState(this.value);

  NotificationAvailability value;

  void update(NotificationAvailability next) {
    if (value == next) return;
    value = next;
    notifyListeners();
  }
}

typedef ActiveProfilesStream = Stream<List<Profile>>;
typedef PredictionStream = Stream<CyclePrediction> Function(String profileId);

class ReminderCoordinator with WidgetsBindingObserver {
  ReminderCoordinator({
    required ReminderScheduler scheduler,
    required NotificationPermissionState permissionState,
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
  final NotificationPermissionState _permissionState;
  final ActiveProfilesStream _activeProfiles;
  final PredictionStream _predictionFor;
  final LocalDate Function() today;

  @visibleForTesting
  final Duration replanDebounce;

  StreamSubscription<List<Profile>>? _profilesSub;
  final Map<String, StreamSubscription<CyclePrediction>> _predictionSubs = {};
  final Map<String, ActivePrediction> _latest = {};
  Timer? _replanTimer;
  bool _disposed = false;

  Future<void> start({
    void Function(String profileId)? onLaunchFromNotification,
  }) async {
    final availability =
        await _scheduler.initialize(onLaunchFromNotification: (id) {
      onLaunchFromNotification?.call(id);
      // A tap that lands while the app is backgrounded re-locks the gate;
      // the payload is consumed by the home gate after the next unlock.
    });
    if (_disposed) return;
    _permissionState.update(availability);
    _profilesSub = _activeProfiles.listen(_onProfilesChanged);
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

  @visibleForTesting
  Future<void> replan() async {
    if (_disposed) return;
    if (_permissionState.value == NotificationAvailability.denied) {
      await _scheduler.cancelAll();
      return;
    }
    await _scheduler.rescheduleAll(
      planReminders(today: today(), predictions: Map.of(_latest)),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // "At every app open": a new day may have arrived without any write.
      _scheduleReplan();
    }
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
