part of 'storage.dart';

// The device-local key-value settings, extracted out of `LunarLogStorage`
// into their own class (issue #551 problem 1, part 1 step 3), following
// `SyncCursorStorage`'s template extraction (step 2).
//
// `AppSettingsStorage` implements `AppSettingsStore` over the same drift
// database and shares the one `StorageClock`, so a setting's `updated_at`
// stamp comes from the same clock every other local write uses. The column
// is kept for uniform change tracking only — the table is not part of the
// sync model (open design question), so there is no dirty flag and no
// remote-apply half here. `LunarLogStorage` keeps implementing the role by
// delegating every member to its own `AppSettingsStorage` (the
// `LunarLogStorageAppSettings` mixin below), so every existing consumer and
// test compiles and behaves exactly as before.

/// The device-local `app_settings` key-value store, extracted verbatim from
/// `LunarLogStorage` (issue #551 part 1 step 3). Constructed with the same
/// drift database and the same [StorageClock] the storage uses; every
/// member is a pure move.
class AppSettingsStorage implements AppSettingsStore {
  AppSettingsStorage(this.db, this._clock);

  final LunarLogDatabase db;
  final StorageClock _clock;

  @override
  Future<String?> getSetting(String key) async {
    final row = await (db.select(db.appSettings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  @override
  Stream<String?> watchSetting(String key) {
    final query = db.select(db.appSettings)..where((t) => t.key.equals(key));
    return query.watchSingleOrNull().map((row) => row?.value);
  }

  /// Device-local key-value state. Not part of the sync model (open design
  /// question); `updated_at` kept for uniform change tracking.
  @override
  Future<void> setSetting({
    required String key,
    required String value,
    DateTime? updatedAt,
  }) async {
    await db.transaction(() async {
      final now = (updatedAt ?? _clock.now()).toUtc();
      final existing = await (db.select(db.appSettings)
            ..where((t) => t.key.equals(key)))
          .getSingleOrNull();
      await db.into(db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: key,
              value: value,
              updatedAt:
                  existing == null ? now : _notBefore(now, existing.updatedAt),
            ),
          );
    });
  }
}

/// Delegation shim (issue #551 part 1 step 3): `LunarLogStorage` keeps
/// implementing [AppSettingsStore] by forwarding each member to the
/// extracted [AppSettingsStorage] it owns. Every existing consumer and test
/// therefore keeps compiling against the same `LunarLogStorage` surface.
mixin LunarLogStorageAppSettings implements AppSettingsStore {
  AppSettingsStore get appSettings;

  @override
  Future<String?> getSetting(String key) => appSettings.getSetting(key);

  @override
  Stream<String?> watchSetting(String key) => appSettings.watchSetting(key);

  @override
  Future<void> setSetting({
    required String key,
    required String value,
    DateTime? updatedAt,
  }) =>
      appSettings.setSetting(key: key, value: value, updatedAt: updatedAt);
}
