/// Drift-backed [SettingsStore] over U2's app_settings table.
library;

import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';

class DriftSettingsStore implements SettingsStore {
  DriftSettingsStore(this._storage);

  final LunarLogStorage _storage;

  @override
  Future<String?> get(String key) => _storage.getSetting(key);

  @override
  Future<void> set(String key, String value) =>
      _storage.setSetting(key: key, value: value);

  @override
  Stream<String?> watch(String key) => _storage.watchSetting(key);
}
