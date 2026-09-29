/// Unit tests for the extracted [AppSettingsStorage] (issue #551 problem 1,
/// part 1 step 3): the device-local `app_settings` key-value store,
/// exercised directly against a real drift database (SQL behaviour, not a
/// fake), plus the delegation shim proving `LunarLogStorage` forwards to it
/// unchanged.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late AppSettingsStorage store;
  late LunarLogStorage storage;
  late DateTime now;

  final t0 = DateTime.utc(2026, 1, 15, 8);

  setUp(() {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    now = t0;
    // The production wiring: the storage and the extracted store share one
    // clock, so a setting's `updated_at` stamp comes from the same clock
    // every other local write uses.
    final clock = StorageClock(clock: () => now);
    storage = LunarLogStorage(db, clock: () => now);
    store = AppSettingsStorage(db, clock);
  });

  /// The stored `updated_at` of [key], read straight from the table.
  Future<DateTime?> storedUpdatedAt(String key) async {
    final rows = await db.select(db.appSettings).get();
    return rows.where((r) => r.key == key).map((r) => r.updatedAt).single;
  }

  group('get/set', () {
    test('getSetting returns null before anything is written', () async {
      expect(await store.getSetting('k'), isNull);
    });

    test('setSetting round-trips and overwrites', () async {
      await store.setSetting(key: 'k', value: 'v');
      expect(await store.getSetting('k'), 'v');

      await store.setSetting(key: 'k', value: 'v2');
      expect(await store.getSetting('k'), 'v2');
    });

    test('keys are independent', () async {
      await store.setSetting(key: 'a', value: '1');
      await store.setSetting(key: 'b', value: '2');
      expect(await store.getSetting('a'), '1');
      expect(await store.getSetting('b'), '2');
    });

    test('watchSetting emits the current value', () async {
      await store.setSetting(key: 'k', value: 'v');
      expect(await store.watchSetting('k').first, 'v');
      expect(await store.watchSetting('missing').first, isNull);
    });

    test('a setting write without updatedAt stamps the shared clock',
        () async {
      now = t0;
      await store.setSetting(key: 'k', value: 'v');
      expect(await storedUpdatedAt('k'), t0);

      now = t0.add(const Duration(hours: 1));
      await store.setSetting(key: 'k', value: 'v2');
      expect(await storedUpdatedAt('k'), t0.add(const Duration(hours: 1)));
    });

    test(
        'an explicit older updatedAt never regresses the stored stamp '
        '(_notBefore)', () async {
      await store.setSetting(
          key: 'k', value: 'v', updatedAt: t0.add(const Duration(days: 1)));
      await store.setSetting(
          key: 'k', value: 'v2', updatedAt: t0); // older on purpose

      expect(await storedUpdatedAt('k'), t0.add(const Duration(days: 1)));
      // The value itself still overwrites — only the stamp is clamped.
      expect(await store.getSetting('k'), 'v2');
    });
  });

  group('delegation shim', () {
    test('LunarLogStorage forwards the settings members', () async {
      await storage.setSetting(key: 'k', value: 'v');
      expect(await storage.getSetting('k'), 'v');
      expect(await store.getSetting('k'), 'v');
      expect(await storage.watchSetting('k').first, 'v');

      await store.setSetting(key: 'k', value: 'via-store');
      expect(await storage.getSetting('k'), 'via-store');
    });

    test(
        'the storage delegates to the SAME store instance it constructed '
        '(one shared clock)', () async {
      now = t0.add(const Duration(minutes: 5));
      await storage.setSetting(key: 'k', value: 'v');
      // The class's own clock is the one the extracted store holds.
      expect(await storedUpdatedAt('k'), t0.add(const Duration(minutes: 5)));
    });
  });
}
