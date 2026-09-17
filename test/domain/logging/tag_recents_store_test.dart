/// Unit tests for the device-local per-profile recents store (Issue #234):
/// save/load round-trips and cross-profile isolation, mirroring
/// `reminder_config_store_test.dart`'s shape.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/logging/tag_recents_store.dart';

import '../../support/fake_settings_store.dart';

void main() {
  late FakeSettingsStore store;
  late TagRecentsStore recents;

  setUp(() {
    store = FakeSettingsStore();
    recents = TagRecentsStore(store);
  });

  tearDown(() => store.close());

  test('an empty store loads nothing', () async {
    expect(await recents.loadAll(), isEmpty);
    expect(await recents.load('p1'), isEmpty);
  });

  test('recordUse seeds a profile with no prior recents', () async {
    await recents.recordUse('p1', 'cramps');
    expect(await recents.load('p1'), ['cramps']);
  });

  test('recordUse moves an existing code to the front', () async {
    await recents.recordUse('p1', 'cramps');
    await recents.recordUse('p1', 'headache');
    await recents.recordUse('p1', 'cramps');
    expect(await recents.load('p1'), ['cramps', 'headache']);
  });

  test('recordUse for one profile preserves every other profile\'s list',
      () async {
    await recents.recordUse('p1', 'cramps');
    await recents.recordUse('p2', 'sad');
    await recents.recordUse('p1', 'headache');

    expect(await recents.load('p1'), ['headache', 'cramps']);
    expect(await recents.load('p2'), ['sad']);
    expect((await recents.loadAll()).keys, {'p1', 'p2'});
  });
}
