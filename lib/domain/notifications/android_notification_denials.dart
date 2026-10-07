/// The single owner of the Android "refused notification asks" count
/// ([SettingsKeys.androidNotificationDeniedAttempts], issue #168).
///
/// Two things ask Android for `POST_NOTIFICATIONS`: the "Turn on
/// reminders" tap (`FlutterLocalNotificationsScheduler.requestPermission`)
/// and, on a push-configured build, push registration's in-context ask
/// (`FirebasePushTokenSource`, via
/// `PushRegistrationCoordinator.ensurePermissionAndRegister`). Android
/// shows its dialog twice in total, whoever asked, so both must feed one
/// count — a refusal either of them did not record leaves the "Turn on
/// reminders" hint re-asking into silence instead of opening settings
/// (issue #1425). Every read and write of the key goes through this
/// class; nothing else touches it.
///
/// Pure Dart over the [SettingsStore] contract, so the transitions are
/// unit-tested directly rather than riding inside either plugin-bound
/// caller (both are excluded from the coverage gate).
library;

import 'package:lunarlog/domain/repositories/settings_store.dart';

class AndroidNotificationDenials {
  /// [store] is the device-local settings store. `null` (a test or widget
  /// tree with no store wired) keeps the count in memory for this
  /// instance's lifetime only.
  AndroidNotificationDenials(SettingsStore? store) : _store = store;

  final SettingsStore? _store;

  /// The count when no store is attached. With a store this is never read:
  /// every [load] goes back to the persisted value, so two callers sharing
  /// one store can never drift apart on a stale copy.
  int _unpersisted = 0;

  /// The refusals on record. Absent or unparsable reads as zero.
  Future<int> load() async {
    final store = _store;
    if (store == null) return _unpersisted;
    final raw = await store.get(SettingsKeys.androidNotificationDeniedAttempts);
    return int.tryParse(raw ?? '') ?? 0;
  }

  /// Records the OS's answer to one ask and returns the resulting count: a
  /// grant clears it, a refusal adds one, and `null` — the OS never
  /// actually resolved the request — leaves it alone, because an answer
  /// that was never given is not a refusal.
  Future<int> record(bool? granted) async {
    final previous = await load();
    final next = switch (granted) {
      true => 0,
      false => previous + 1,
      null => previous,
    };
    if (next == previous) return next;
    _unpersisted = next;
    await _store?.set(
      SettingsKeys.androidNotificationDeniedAttempts,
      '$next',
    );
    return next;
  }
}
