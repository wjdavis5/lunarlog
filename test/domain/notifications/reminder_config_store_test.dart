/// Unit tests for the device-local reminder configuration store (Issue
/// #136): per-profile save/load round-trips, the late snooze, and the
/// `changes` stream the coordinator replans on.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/notifications/reminder_config.dart';
import 'package:lunarlog/domain/notifications/reminder_config_store.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';

import '../../support/fake_settings_store.dart';

void main() {
  late FakeSettingsStore store;
  late ReminderConfigService service;

  setUp(() {
    store = FakeSettingsStore();
    service = ReminderConfigService(store);
  });

  tearDown(() => store.close());

  test('an empty store loads nothing', () async {
    expect(await service.loadAll(), isEmpty);
    expect(await service.load('p1'), isNull);
    expect(await service.loadLateSnoozes(), isEmpty);
  });

  test('save then load round-trips per profile', () async {
    const p1 = ReminderConfig(
      late: ReminderTypeConfig(enabled: false, timeOfDayMinutes: 10 * 60),
    );
    final p2 = ReminderConfig.standard.copyWith(
      log: ReminderTypeConfig(enabled: true, timeOfDayMinutes: 20 * 60),
    );
    await service.save('p1', p1);
    await service.save('p2', p2);

    expect(await service.load('p1'), p1);
    expect(await service.load('p2'), p2);
    expect((await service.loadAll()).keys, {'p1', 'p2'});
  });

  test('saving one profile preserves the others', () async {
    await service.save('p1', ReminderConfig.standard);
    final p2 = ReminderConfig.standard.copyWith(
      pms: ReminderTypeConfig(enabled: true, leadDays: 5, timeOfDayMinutes: 0),
    );
    await service.save('p2', p2);

    expect(await service.load('p1'), ReminderConfig.standard);
    expect(await service.load('p2'), p2);
  });

  test('snoozeLate stores today + days, and preserves other profiles',
      () async {
    final today = LocalDate(2026, 9, 3);
    await service.snoozeLate('p1', days: 3, today: today);
    await service.snoozeLate('p2', days: 1, today: today);

    expect(await service.loadLateSnoozes(), {
      'p1': LocalDate(2026, 9, 6),
      'p2': LocalDate(2026, 9, 4),
    });
  });

  test('snoozeLate is idempotent for the same today', () async {
    final today = LocalDate(2026, 9, 3);
    await service.snoozeLate('p1', days: 3, today: today);
    await service.snoozeLate('p1', days: 3, today: today);
    expect(await service.loadLateSnoozes(), {'p1': LocalDate(2026, 9, 6)});
  });

  test('changes emits after a save and after a snooze', () async {
    var emissions = 0;
    final sub = service.changes.listen((_) => emissions++);
    addTearDown(sub.cancel);

    // Let the seeded watch values land first (two watches, one emission
    // each) so the count below measures only the writes.
    await pumpEventQueue();
    final seeded = emissions;

    await service.save('p1', ReminderConfig.standard);
    await pumpEventQueue();
    expect(emissions, greaterThan(seeded));

    final afterSave = emissions;
    await service.snoozeLate(
      'p1',
      days: 3,
      today: LocalDate(2026, 9, 3),
    );
    await pumpEventQueue();
    expect(emissions, greaterThan(afterSave));
  });

  test('the stored document is the settings key the docs promise', () async {
    await service.save('p1', ReminderConfig.standard);
    expect(
      await store.get(SettingsKeys.reminderConfigs),
      isNotNull,
    );
    await service.snoozeLate('p1', days: 3, today: LocalDate(2026, 9, 3));
    expect(
      await store.get(SettingsKeys.reminderLateSnoozes),
      isNotNull,
    );
  });
}
