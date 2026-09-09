/// Device-local persistence for per-profile reminder configuration and
/// late-reminder snoozes (Issue #136).
///
/// Backed by the device-local [SettingsStore] (two JSON-valued keys, one
/// for configs and one for snoozes) — deliberately **not** synced, per the
/// posture decision recorded on `reminder_config.dart`'s library doc.
/// Device-local is the same call the cycle-omission list made.
///
/// Pure Dart (R14/R16): [SettingsStore] is a `lib/domain` interface.
library;

import 'dart:async';

import '../models/local_date.dart';
import '../repositories/settings_store.dart';
import 'reminder_config.dart';

/// A key-value snapshot service over the two reminder settings keys.
///
/// The whole per-profile map lives under one key (rather than one key per
/// profile) because [SettingsStore] offers no key enumeration: a single
/// JSON document makes `loadAll` — the planner's per-replan read — a
/// single `get`, and the `watch`-based [changes] stream a single
/// subscription. Writes are read-modify-write on that document; the store
/// is single-operator local data, so no locking beyond that is needed.
class ReminderConfigService {
  ReminderConfigService(this._settings);

  final SettingsStore _settings;

  /// Emits (with no payload) after every [save] and every [snoozeLate],
  /// and again whenever the underlying settings key changes for any other
  /// reason. The reminder coordinator subscribes and replans — a settings
  /// edit takes effect at the next coordinator pass, the same way a care
  /// mode switch does (Issue #131's posture). Emissions are not coalesced
  /// here: a save touches both keys at most, and the coordinator's own
  /// replan debounce collapses any burst into one pass.
  late final Stream<void> changes = () {
    final controller = StreamController<void>.broadcast();
    void ping(_) => controller.add(null);
    _settings.watch(SettingsKeys.reminderConfigs).listen(ping);
    _settings.watch(SettingsKeys.reminderLateSnoozes).listen(ping);
    return controller.stream;
  }();

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
}
