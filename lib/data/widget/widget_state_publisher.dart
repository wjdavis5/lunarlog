/// Keeps the home-screen widget's discreet payload current (issue #141).
///
/// Data-change signals only, never a timer: the publisher subscribes to the
/// streams the app already maintains — the profile list, the widget's
/// profile-selection setting, the selected profile's prediction stream
/// (which itself re-emits on day-entry writes, prediction changes, and the
/// service's civil-date rollover), and the selected profile's guardian rows
/// (role changes) — and rewrites the payload whenever any of them moves.
/// No scheduling of its own, no polling, no background refresh: the widget
/// is exactly as fresh as the app's own data signals make it, and the
/// native timeline rolls the day count forward between signals (see
/// `ll_widget_as_of` in `widget_cycle_state.dart`).
///
/// ## Profile resolution
///
/// The widget shows the profile pinned in `SettingsKeys.widgetProfileId`
/// when that profile is still live and non-archived; otherwise it falls
/// back to the app's active profile (`SettingsKeys.lastActiveProfile`
/// resolved the way `ProfileController` resolves it), then to the first
/// active profile. With no profiles at all the payload degrades to the
/// neutral no-data state and the quick-log intent is cleared, so a widget
/// left pointing at a deleted profile can never act.
///
/// ## Writes
///
/// Each emission derives the [WidgetCycleState] (the render plus the role
/// answer via `canQuickLogFor`), encodes it with
/// `WidgetCycleStatePayload.encode`, and writes through the [WidgetDataStore]
/// port. Payload writes serialize through a small drain queue so two
/// overlapping emissions can never interleave half a payload across the
/// boundary.
library;

// Named required parameters cannot be initializing formals; the private
// finals below are assigned through the constructor's initializer list
// (the same shape as `ReminderActionExecutor`).
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/widget/widget_cycle_state.dart';
import 'package:lunarlog/domain/widget/widget_data_store.dart';
import 'package:lunarlog/domain/widget/widget_profile_options.dart';

class WidgetStatePublisher {
  WidgetStatePublisher({
    required ProfilesRepository profiles,
    required SettingsStore settings,
    required Stream<CyclePrediction> Function(String profileId) predictionFor,
    required ProfileGuardiansRepository guardians,
    required WidgetDataStore store,
    required String? Function() currentUserId,
    LocalDate Function()? today,
  })  : _profiles = profiles,
        _settings = settings,
        _predictionFor = predictionFor,
        _guardians = guardians,
        _store = store,
        _currentUserId = currentUserId,
        _today = today ?? LocalDate.today;

  final ProfilesRepository _profiles;
  final SettingsStore _settings;
  final Stream<CyclePrediction> Function(String profileId) _predictionFor;
  final ProfileGuardiansRepository _guardians;
  final WidgetDataStore _store;
  final String? Function() _currentUserId;
  final LocalDate Function() _today;

  StreamSubscription<List<Profile>>? _profilesSub;
  StreamSubscription<String?>? _selectionSub;
  StreamSubscription<String?>? _activeProfileSub;
  StreamSubscription<CyclePrediction>? _predictionSub;
  StreamSubscription<List<ProfileGuardian>>? _guardiansSub;

  /// The profile id currently subscribed to (empty string when none).
  String _subscribedProfileId = '';

  /// The latest prediction emission per subscribed profile, and the latest
  /// guardian rows, so a selection/profile change can republish from the
  /// new inputs without waiting for their next emission.
  CyclePrediction? _lastPrediction;
  List<ProfileGuardian> _lastGuardians = const [];

  /// The profile list snapshot the selection resolves against.
  List<Profile> _profileSnapshot = const [];
  String? _pinnedId;
  String? _activeId;

  bool _disposed = false;

  /// The tail of the serialized payload-write queue; null when idle.
  Future<void>? _draining;

  /// Resolves once every queued write has finished — test seam.
  @visibleForTesting
  Future<void> get idle => _draining ?? Future<void>.value();

  /// Subscribes to the signals. Idempotent; call once.
  void start() {
    if (_profilesSub != null) return;
    _profilesSub = _profiles.watch().listen((profiles) {
      _profileSnapshot = profiles;
      _resolveAndSubscribe();
    });
    _selectionSub = _settings
        .watch(SettingsKeys.widgetProfileId)
        .listen((value) {
      _pinnedId = (value == null || value.isEmpty) ? null : value;
      _resolveAndSubscribe();
    });
    _activeProfileSub = _settings
        .watch(SettingsKeys.lastActiveProfile)
        .listen((value) {
      _activeId = (value == null || value.isEmpty) ? null : value;
      _resolveAndSubscribe();
    });
  }

  /// Resolves the target profile and (re)wires the per-profile
  /// subscriptions. Split from [start] (CRAP gate) so the three input
  /// listeners share one body.
  void _resolveAndSubscribe() {
    if (_disposed) return;
    final target = _resolveTargetProfileId();
    if (target == _subscribedProfileId) {
      // Same target, but a profile row itself may have changed (archive
      // state, deletion): republish from the latest inputs.
      unawaited(_republish());
      return;
    }
    unawaited(_predictionSub?.cancel());
    unawaited(_guardiansSub?.cancel());
    _predictionSub = null;
    _guardiansSub = null;
    _subscribedProfileId = target ?? '';
    _lastPrediction = null;
    _lastGuardians = const [];
    if (target == null) {
      unawaited(_republish());
      return;
    }
    _predictionSub = _predictionFor(target).listen((prediction) {
      _lastPrediction = prediction;
      unawaited(_republish());
    });
    _guardiansSub = _guardians.watchForProfile(target).listen((rows) {
      _lastGuardians = rows;
      unawaited(_republish());
    });
  }

  /// The pinned id when it resolves against the live list; else the app's
  /// active profile; else the first active profile; else null.
  String? _resolveTargetProfileId() {
    Profile? resolve(String? id) {
      if (id == null) return null;
      for (final profile in _profileSnapshot) {
        if (profile.id == id && profile.archivedAt == null) return profile;
      }
      return null;
    }

    final pinned = resolve(_pinnedId);
    if (pinned != null) return pinned.id;
    final active = resolve(_activeId) ?? _firstActive();
    return active?.id;
  }

  Profile? _firstActive() {
    for (final profile in _profileSnapshot) {
      if (profile.archivedAt == null) return profile;
    }
    return null;
  }

  /// Derives the state from the latest inputs and writes the payload.
  Future<void> _republish() async {
    if (_disposed) return;
    final profileId = _subscribedProfileId;
    final prediction = _lastPrediction;
    final state = prediction == null || profileId.isEmpty
        ? const WidgetCycleState(kind: WidgetCycleStateKind.noData)
        : WidgetCycleState.fromPrediction(
            prediction,
            canQuickLog: canQuickLogFor(
              guardians: _lastGuardians,
              currentUserId: _currentUserId(),
            ),
          );
    // No profile to act for: the quick-log intent is cleared so a widget
    // left pointing at a deleted profile can never act.
    final payload = WidgetCycleStatePayload.encode(
      state: state,
      profileId: profileId,
      asOf: _today(),
    );
    // Serialize: two overlapping emissions must never interleave half a
    // payload across the boundary.
    final previous = _draining ?? Future<void>.value();
    final run = previous.then((_) async {
      if (_disposed) return;
      await _store.savePayload(payload);
      await _store.refresh();
    });
    _draining = run;
    await run.whenComplete(() {
      if (identical(_draining, run)) _draining = null;
    });
  }

  /// Cancels every subscription. The store stays owned by the caller.
  Future<void> dispose() async {
    _disposed = true;
    await _profilesSub?.cancel();
    await _selectionSub?.cancel();
    await _activeProfileSub?.cancel();
    await _predictionSub?.cancel();
    await _guardiansSub?.cancel();
    _profilesSub = null;
    _selectionSub = null;
    _activeProfileSub = null;
    _predictionSub = null;
    _guardiansSub = null;
  }
}
