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

  group('changes lifecycle (issue #541)', () {
    test(
        'listening subscribes to all four settings keys; cancelling the '
        'last listener unsubscribes from all four', () async {
      final sub = service.changes.listen((_) {});
      await pumpEventQueue();

      expect(store.hasListeners(SettingsKeys.reminderConfigs), isTrue);
      expect(store.hasListeners(SettingsKeys.reminderLateSnoozes), isTrue);
      expect(
          store.hasListeners(SettingsKeys.reminderStatisticBaselines), isTrue);
      expect(store.hasListeners(SettingsKeys.reminderStatisticChangeSignals),
          isTrue);

      await sub.cancel();
      await pumpEventQueue();

      expect(store.hasListeners(SettingsKeys.reminderConfigs), isFalse);
      expect(store.hasListeners(SettingsKeys.reminderLateSnoozes), isFalse);
      expect(store.hasListeners(SettingsKeys.reminderStatisticBaselines),
          isFalse);
      expect(store.hasListeners(SettingsKeys.reminderStatisticChangeSignals),
          isFalse);
    });

    test('dispose cancels every underlying watch subscription', () async {
      final sub = service.changes.listen((_) {});
      await pumpEventQueue();
      expect(store.hasListeners(SettingsKeys.reminderConfigs), isTrue);

      await service.dispose();

      expect(store.hasListeners(SettingsKeys.reminderConfigs), isFalse);
      expect(store.hasListeners(SettingsKeys.reminderLateSnoozes), isFalse);
      expect(
          store.hasListeners(SettingsKeys.reminderStatisticBaselines), isFalse);
      expect(store.hasListeners(SettingsKeys.reminderStatisticChangeSignals),
          isFalse);
      await sub.cancel();
    });

    test('dispose is safe to call with no listener ever attached', () async {
      await service.dispose();
    });

    test('dispose is idempotent', () async {
      final sub = service.changes.listen((_) {});
      await pumpEventQueue();
      await service.dispose();
      await service.dispose();
      await sub.cancel();
    });

    test(
        'a write after dispose reaches no stale listener (simulating a '
        'device reset reopening onto a fresh service, issue #541)',
        () async {
      final events = <void>[];
      final sub = service.changes.listen(events.add);
      await pumpEventQueue();
      final seeded = events.length;

      await service.dispose();
      // A write on the (still-open, from the fake's perspective) settings
      // key after dispose must never reach the disposed service's stream.
      await store.set(SettingsKeys.reminderConfigs, '{"p1":{}}');
      await pumpEventQueue();

      expect(events.length, seeded,
          reason: 'dispose already cancelled the subscription feeding this '
              'stream, so this write is never observed');
      await sub.cancel();
    });

    test('listening again after a full cancel resubscribes (broadcast '
        'controller is reused across listen/cancel cycles until dispose)',
        () async {
      final firstSub = service.changes.listen((_) {});
      await pumpEventQueue();
      await firstSub.cancel();
      await pumpEventQueue();
      expect(store.hasListeners(SettingsKeys.reminderConfigs), isFalse);

      var emissions = 0;
      final secondSub = service.changes.listen((_) => emissions++);
      await pumpEventQueue();
      expect(store.hasListeners(SettingsKeys.reminderConfigs), isTrue);

      await service.save('p1', ReminderConfig.standard);
      await pumpEventQueue();
      expect(emissions, greaterThan(0));
      await secondSub.cancel();
    });
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
