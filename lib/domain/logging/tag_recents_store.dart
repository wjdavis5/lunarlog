/// Device-local persistence for [TagRecents] (Issue #234), mirroring
/// `reminder_config_store.dart`'s [SettingsStore]-backed shape: one JSON
/// document under [SettingsKeys.tagRecents] holding every profile's list,
/// read-modify-write on each [recordUse].
///
/// Pure Dart (R14/R16): [SettingsStore] is a `lib/domain` interface.
library;

import '../repositories/settings_store.dart';
import 'tag_recents.dart';

/// A key-value snapshot service over the `tag_recents` settings key.
class TagRecentsStore {
  TagRecentsStore(this._settings);

  final SettingsStore _settings;

  /// Every stored per-profile recents list, keyed by profile id. Profiles
  /// with no stored list are simply absent — callers treat that as "no
  /// recents yet" (an empty Recent row).
  Future<Map<String, List<String>>> loadAll() async =>
      decodeTagRecents(await _settings.get(SettingsKeys.tagRecents));

  /// [profileId]'s stored recents (most-recent-first), or an empty list
  /// when it has none.
  Future<List<String>> load(String profileId) async =>
      (await loadAll())[profileId] ?? const [];

  /// Records that [code] was just picked for [profileId] — moves it to the
  /// front of that profile's list, de-duplicated and capped
  /// ([kTagRecentsCap]), preserving every other profile's stored list in
  /// the same document.
  Future<void> recordUse(String profileId, String code) async {
    final recents = Map.of(await loadAll());
    recents[profileId] = withRecordedTagUse(recents[profileId] ?? const [], code);
    await _settings.set(SettingsKeys.tagRecents, encodeTagRecents(recents));
  }
}
