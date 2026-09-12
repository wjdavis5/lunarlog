/// Device-local persistence for per-profile reminder configuration,
/// late-reminder snoozes, and (Issue #178) the cycle-statistic-change
/// detection state — four JSON-valued keys total.
///
/// Backed by the device-local [SettingsStore] — deliberately **not**
/// synced, per the posture decision recorded on `reminder_config.dart`'s
/// library doc. Device-local is the same call the cycle-omission list made.
///
/// Pure Dart (R14/R16): [SettingsStore] is a `lib/domain` interface.
library;

import 'dart:async';

import '../models/local_date.dart';
import '../repositories/settings_store.dart';
import 'reminder_config.dart';
import 'statistic_change.dart';

/// A key-value snapshot service over the reminder settings keys.
///
/// Each state family lives under one key (rather than one key per
/// profile) because [SettingsStore] offers no key enumeration: a single
/// JSON document makes `loadAll` — the planner's per-replan read — a
/// single `get`, and the `watch`-based [changes] stream a single
/// subscription. Writes are read-modify-write on those documents; the
/// store is single-operator local data, so no locking beyond that is
/// needed.
class ReminderConfigService {
  ReminderConfigService(this._settings);

  final SettingsStore _settings;

  StreamController<void>? _changesController;
  final List<StreamSubscription<Object?>> _changeSubscriptions = [];

  /// Emits (with no payload) after every [save] and every [snoozeLate],
  /// and again whenever the underlying settings key changes for any other
  /// reason. The reminder coordinator subscribes and replans — a settings
  /// edit takes effect at the next coordinator pass, the same way a care
  /// mode switch does (Issue #131's posture). Emissions are not coalesced
  /// here: a save touches both keys at most, and the coordinator's own
  /// replan debounce collapses any burst into one pass.
  ///
  /// Issue #541: the four `SettingsStore.watch` subscriptions behind this
  /// only exist between the stream's first listener and its last
  /// cancellation ([_onListen]/[_onCancel], mirroring
  /// `DriftActivityFeedRepository.watch`'s own onListen/onCancel shape)
  /// rather than for this service's entire lifetime, and [dispose] cancels
  /// them outright — a device reset
  /// (`resetDevice`, KTD16) closes and deletes the database, then a new
  /// [ReminderConfigService] is built over the reopened one; without this,
  /// the old subscriptions kept firing against the closed database with
  /// nothing left to cancel them, an unhandled root-zone async error, four
  /// more accumulating per reset.
  Stream<void> get changes =>
      (_changesController ??= StreamController<void>.broadcast(
        onListen: _onListen,
        onCancel: _onCancel,
      ))
          .stream;

  void _onListen() {
    void ping(_) => _changesController?.add(null);
    void onError(Object error, StackTrace stackTrace) {
      _changesController?.addError(error, stackTrace);
    }

    _changeSubscriptions.addAll([
      _settings
          .watch(SettingsKeys.reminderConfigs)
          .listen(ping, onError: onError),
      _settings
          .watch(SettingsKeys.reminderLateSnoozes)
          .listen(ping, onError: onError),
      // Issue #178: the coordinator's own baseline/signal writes also ride
      // the changes stream. The replan they trigger re-reads the baselines,
      // finds no *new* meaningful change, and writes nothing — so this
      // never loops beyond one debounced no-op pass.
      _settings
          .watch(SettingsKeys.reminderStatisticBaselines)
          .listen(ping, onError: onError),
      _settings
          .watch(SettingsKeys.reminderStatisticChangeSignals)
          .listen(ping, onError: onError),
    ]);
  }

  /// Cancels every subscription currently in [_changeSubscriptions].
  ///
  /// Snapshots-and-clears the list *synchronously* before awaiting any
  /// cancellation: this callback fires both automatically (the broadcast
  /// controller's own `onCancel`, when the last listener unsubscribes) and
  /// manually from [dispose]'s fallback, and those two calls can overlap —
  /// [dispose] calls this while a listener (the reminder coordinator) is
  /// still in the middle of tearing itself down, so its own unsubscription
  /// can trigger the automatic invocation before the manual one has
  /// finished. Without the synchronous clear, both invocations would read
  /// the same not-yet-cleared list and call `cancel()` a second time on
  /// subscriptions already mid-cancellation — on the Drift-backed watch
  /// streams behind [SettingsStore.watch], a redundant `cancel()` never
  /// settles, so this stream's teardown would never complete.
  Future<void> _onCancel() async {
    if (_changeSubscriptions.isEmpty) return;
    final subscriptions = List.of(_changeSubscriptions);
    _changeSubscriptions.clear();
    await Future.wait([for (final sub in subscriptions) sub.cancel()]);
  }

  /// Tears down [changes]'s subscriptions and closes its controller. Called
  /// from `_AppState.dispose()` (issue #541) — the coordinator that
  /// subscribes to [changes] is disposed first, so this stream typically
  /// has no listener left by the time this runs, meaning [_onCancel] has
  /// already fired; this is the fallback for the case where it hasn't
  /// (e.g. no coordinator was ever built).
  ///
  /// [_changesController]'s own `close()` is deliberately not awaited: a
  /// broadcast controller with no remaining listeners has nothing left for
  /// `close()` to deliver, and the returned future's completion is bound to
  /// the zone the controller was created in (`initState`'s) — awaiting it
  /// from a caller that has since hopped zones (a widget test's `runAsync`,
  /// escaping the fake-time zone to let the drift cancellations above
  /// settle) can leave that future's completion queued in the original
  /// zone's microtask queue indefinitely. Firing `close()` and moving on is
  /// enough: every subscription is already cancelled by [_onCancel] above,
  /// and nothing downstream depends on the controller having *finished*
  /// closing, only on it no longer being reused (`_changesController` is
  /// nulled immediately below).
  Future<void> dispose() async {
    await _onCancel();
    unawaited(_changesController?.close());
    _changesController = null;
  }

  /// Every stored per-profile config, keyed by profile id. Profiles with
  /// no stored config are simply absent — callers fall back to the
  /// profile's care-mode preset defaults ([ReminderConfig.fromPreset]).
  Future<Map<String, ReminderConfig>> loadAll() async =>
      decodeReminderConfigs(await _settings.get(SettingsKeys.reminderConfigs));

  /// One profile's stored config, or null when it has none.
  Future<ReminderConfig?> load(String profileId) async =>
      (await loadAll())[profileId];

  /// Writes [config] for [profileId], preserving every other profile's
  /// stored config in the same document.
  Future<void> save(String profileId, ReminderConfig config) async {
    final configs = Map.of(await loadAll());
    configs[profileId] = config;
    await _settings.set(
      SettingsKeys.reminderConfigs,
      encodeReminderConfigs(configs),
    );
  }

  /// Every live late-reminder snooze, keyed by profile id: the last date
  /// the profile's "Not yet" action snoozed from — late reminders stay
  /// suppressed through that date.
  Future<Map<String, LocalDate>> loadLateSnoozes() async =>
      decodeLateSnoozes(
          await _settings.get(SettingsKeys.reminderLateSnoozes));

  /// Suppresses [profileId]'s late reminders for the next [days] days
  /// (Issue #136: the notification's "Not yet" action snoozes by three).
  /// Idempotent per action tap: the snooze end is recomputed from [today]
  /// each time, so a double-tap lands on the same end date.
  Future<void> snoozeLate(
    String profileId, {
    required int days,
    required LocalDate today,
  }) async {
    final snoozes = Map.of(await loadLateSnoozes());
    snoozes[profileId] = today.addDays(days);
    await _settings.set(
      SettingsKeys.reminderLateSnoozes,
      encodeLateSnoozes(snoozes),
    );
  }

  /// Every stored per-profile statistic baseline (Issue #178), keyed by
  /// profile id: the last displayed-statistic snapshot the reminder
  /// coordinator observed for the profile.
  Future<Map<String, CycleStatisticSnapshot>> loadStatisticBaselines() async =>
      decodeStatisticBaselines(
          await _settings.get(SettingsKeys.reminderStatisticBaselines));

  /// Writes the whole baseline map (Issue #178). The coordinator is the
  /// only writer; it stores only when the map actually changed, so this
  /// never ping-pongs the [changes] stream.
  Future<void> saveStatisticBaselines(
          Map<String, CycleStatisticSnapshot> baselines) =>
      _settings.set(
        SettingsKeys.reminderStatisticBaselines,
        encodeStatisticBaselines(baselines),
      );

  /// Every live statistic-change signal (Issue #178), keyed by profile id:
  /// the date a meaningful displayed-statistic change was last observed.
  Future<Map<String, LocalDate>> loadStatisticChangeSignals() async =>
      decodeStatisticChangeSignals(await _settings
          .get(SettingsKeys.reminderStatisticChangeSignals));

  /// Records that a meaningful statistic change was observed for
  /// [profileId] on [today] (Issue #178). The signal date survives restarts
  /// so the same-day reminder replans after a relaunch; the planner drops
  /// it once the date passes, and the next change overwrites it.
  Future<void> recordStatisticChange(
    String profileId, {
    required LocalDate today,
  }) async {
    final signals = Map.of(await loadStatisticChangeSignals());
    signals[profileId] = today;
    await _settings.set(
      SettingsKeys.reminderStatisticChangeSignals,
      encodeStatisticChangeSignals(signals),
    );
  }
}
