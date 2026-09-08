/// Tests for the cycle-history service (issue #132): the combined
/// entries + omission stream, per-profile isolation, and one-shot reads.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late DriftProfilesRepository profiles;
  late DriftDayEntriesRepository dayEntries;
  late DriftSettingsStore settings;
  late CycleHistoryService service;

  setUp(() {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    profiles = DriftProfilesRepository(db.storage);
    dayEntries = DriftDayEntriesRepository(db.storage);
    settings = DriftSettingsStore(db.storage);
    service = CycleHistoryService(dayEntries, settings: settings);
  });

  Future<void> recordBleed(String profileId, LocalDate start) async {
    await dayEntries.save(
      DayEntry(
        id: '',
        profileId: profileId,
        localDate: start,
        tz: 'UTC',
        flow: FlowLevel.medium,
        tags: const [],
        note: null,
        updatedAt: DateTime.utc(2026, 1, 1),
        deletedAt: null,
      ),
    );
  }

  test('emits on entry writes and on omission changes', () async {
    final profile = await profiles.create(displayName: 'A', isMinor: false);
    final seen = <CycleHistoryView>[];
    final sub = service.watch(profile.id).listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(seen.last.items, isEmpty);

    await recordBleed(profile.id, LocalDate(2026, 1, 1));
    await recordBleed(profile.id, LocalDate(2026, 1, 29));
    await recordBleed(profile.id, LocalDate(2026, 2, 26));
    await pumpEventQueue();
    expect(seen.last.items, hasLength(3), reason: 'open + two completed');
    expect(seen.last.completedCycleCount, 2);

    final exclusions = CycleExclusionList(settings);
    await exclusions.omit(profile.id, LocalDate(2026, 1, 1));
    await pumpEventQueue();
    expect(
      seen.last.averagedCycleCount,
      1,
      reason: 'one of the two completed cycles is now omitted',
    );
    expect(
      seen.last.items
          .firstWhere((i) => i.start == LocalDate(2026, 1, 1))
          .omitted,
      isTrue,
    );
  });

  test('profiles are isolated', () async {
    final a = await profiles.create(displayName: 'A', isMinor: false);
    final b = await profiles.create(displayName: 'B', isMinor: true);
    await recordBleed(a.id, LocalDate(2026, 1, 1));
    await recordBleed(a.id, LocalDate(2026, 1, 29));
    await CycleExclusionList(settings).omit(a.id, LocalDate(2026, 1, 1));

    final viewA = await service.current(a.id);
    final viewB = await service.current(b.id);
    expect(viewA.completedCycleCount, 1);
    expect(
      viewA.averagedCycleCount,
      0,
      reason: 'the only completed cycle is omitted',
    );
    expect(viewB.items, isEmpty);
  });

  test('current() reflects the stored omission list', () async {
    final profile = await profiles.create(displayName: 'A', isMinor: false);
    await recordBleed(profile.id, LocalDate(2026, 1, 1));
    await recordBleed(profile.id, LocalDate(2026, 1, 29));
    await CycleExclusionList(settings).omit(profile.id, LocalDate(2026, 1, 29));

    final view = await service.current(profile.id);
    expect(
      view.items.first.omitted,
      isTrue,
      reason: 'the open cycle (start Jan 29) was skipped',
    );
  });
}
