/// Unit tests for [AndroidNotificationDenials] (issue #1425): the single
/// owner of the persisted Android refusal count that both the "Turn on
/// reminders" tap and push registration's launch-time ask feed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/notifications/android_notification_denials.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';

import '../../support/fake_settings_store.dart';

const _key = SettingsKeys.androidNotificationDeniedAttempts;

void main() {
  group('load', () {
    test('an absent count reads as zero', () async {
      expect(await AndroidNotificationDenials(FakeSettingsStore()).load(), 0);
    });

    test('an unparsable count reads as zero', () async {
      final store = FakeSettingsStore({_key: 'many'});
      expect(await AndroidNotificationDenials(store).load(), 0);
    });

    test('reads the count on record', () async {
      final store = FakeSettingsStore({_key: '2'});
      expect(await AndroidNotificationDenials(store).load(), 2);
    });

    test('goes back to the store every time -- a write another owner '
        'instance made over the same store is seen at once', () async {
      // The scheduler and the push token source each hold their own
      // instance over one store; neither may answer from a stale copy.
      final store = FakeSettingsStore();
      final scheduler = AndroidNotificationDenials(store);
      final push = AndroidNotificationDenials(store);

      expect(await scheduler.load(), 0);
      await push.record(false);

      expect(await scheduler.load(), 1);
      expect(await scheduler.record(false), 2,
          reason: 'and it adds to what the other instance recorded');
    });
  });

  group('record', () {
    test('a refusal adds one and persists it', () async {
      final store = FakeSettingsStore();
      final denials = AndroidNotificationDenials(store);

      expect(await denials.record(false), 1);
      expect(await store.get(_key), '1');
      expect(await denials.record(false), 2);
      expect(await store.get(_key), '2');
    });

    test('a grant clears the count', () async {
      final store = FakeSettingsStore({_key: '2'});

      expect(await AndroidNotificationDenials(store).record(true), 0);
      expect(await store.get(_key), '0');
    });

    test('an unresolved (null) answer is not a refusal -- the count is '
        'returned as it stood and nothing is written', () async {
      final store = FakeSettingsStore({_key: '1'});

      expect(await AndroidNotificationDenials(store).record(null), 1);
      expect(await store.get(_key), '1');

      final empty = FakeSettingsStore();
      expect(await AndroidNotificationDenials(empty).record(null), 0);
      expect(await empty.get(_key), isNull,
          reason: 'no answer, so no count to put on record');
    });

    test('a grant with nothing on record writes nothing', () async {
      final store = FakeSettingsStore();

      expect(await AndroidNotificationDenials(store).record(true), 0);
      expect(await store.get(_key), isNull);
    });
  });

  group('with no store attached', () {
    test('the count is carried in memory for the instance\'s lifetime',
        () async {
      final denials = AndroidNotificationDenials(null);

      expect(await denials.load(), 0);
      expect(await denials.record(false), 1);
      expect(await denials.load(), 1);
      expect(await denials.record(null), 1);
      expect(await denials.record(false), 2);
      expect(await denials.record(true), 0);
      expect(await denials.load(), 0);
    });
  });
}
