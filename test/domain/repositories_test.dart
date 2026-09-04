import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/data/db/ulid.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late ProfilesRepository profiles;
  late DayEntriesRepository dayEntries;
  late SettingsStore settings;

  setUp(() {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    profiles = DriftProfilesRepository(db.storage);
    dayEntries = DriftDayEntriesRepository(db.storage);
    settings = DriftSettingsStore(db.storage);
  });

  DayEntry entryFor(String profileId, LocalDate date,
      {FlowLevel flow = FlowLevel.medium,
      List<String> tags = const [],
      String? note}) {
    return DayEntry(
      id: '',
      profileId: profileId,
      localDate: date,
      tz: 'America/Chicago',
      flow: flow,
      tags: tags,
      note: note,
      updatedAt: DateTime.utc(2026, 1, 1),
      deletedAt: null,
    );
  }

  group('profiles repository contract', () {
    test('create returns a domain model with a storage-assigned ULID', () async {
      final profile = await profiles.create(
          displayName: 'Luna', isMinor: true, sortOrder: 2);
      expect(profile, isA<Profile>());
      expect(isValidUlid(profile.id), isTrue);
      expect(profile.displayName, 'Luna');
      expect(profile.isMinor, isTrue);
      expect(profile.sortOrder, 2);
      expect(profile.archivedAt, isNull);
      expect(profile.deletedAt, isNull);
      expect(profile.createdAt, isNotNull);
      expect(profile.updatedAt, isNotNull);
    });

    test('list and watch return the created profile; watch is reactive',
        () async {
      final created = await profiles.create(displayName: 'A', isMinor: false);
      expect((await profiles.list()).map((p) => p.id), [created.id]);

      final seen = <List<Profile>>[];
      final sub = profiles.watch().listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(seen.last.single.id, created.id);

      await profiles.create(displayName: 'B', isMinor: true);
      await pumpEventQueue();
      expect(seen.last.map((p) => p.displayName), ['A', 'B']);
    });

    test('update persists edited fields', () async {
      final created = await profiles.create(displayName: 'Old', isMinor: false);
      final updated = await profiles
          .update(created.copyWith(displayName: 'New', sortOrder: 7));
      expect(updated.id, created.id);
      expect(updated.displayName, 'New');
      expect(updated.sortOrder, 7);

      final reread = await profiles.findById(created.id);
      expect(reread!.displayName, 'New');
    });

    test('archive sets archivedAt; unarchive clears it', () async {
      final created = await profiles.create(displayName: 'A', isMinor: false);
      await profiles.setArchived(created.id, true);
      final archived = await profiles.findById(created.id);
      expect(archived!.archivedAt, isNotNull);

      await profiles.setArchived(created.id, false);
      final live = await profiles.findById(created.id);
      expect(live!.archivedAt, isNull);
      expect((await profiles.list()).map((p) => p.id), [created.id],
          reason: 'archived profiles stay in the live list; UI filters');
    });

    test('delete tombstones: gone from list/watch/findById', () async {
      final created = await profiles.create(displayName: 'A', isMinor: false);
      await profiles.delete(created.id);
      expect(await profiles.list(), isEmpty);
      expect(await profiles.findById(created.id), isNull);
      expect(await profiles.watch().first, isEmpty);
    });

    test('findById reads null for a tombstoned id', () async {
      final created = await profiles.create(displayName: 'A', isMinor: false);
      await profiles.delete(created.id);
      expect(await profiles.findById(created.id), isNull);
      expect(await db.storage.getProfiles(includeTombstones: true),
          hasLength(1),
          reason: 'the tombstone is still held for sync');
    });

    test('setArchived throws for an unknown id and for a tombstoned id',
        () async {
      await expectLater(
        profiles.setArchived('01JPROFILEUNKNOWN000000000', true),
        throwsStateError,
      );

      final created = await profiles.create(displayName: 'A', isMinor: false);
      await profiles.delete(created.id);
      await expectLater(
        profiles.setArchived(created.id, true),
        throwsStateError,
      );
    });

    test('mapping round-trip: domain equality after write-then-read', () async {
      final created = await profiles.create(displayName: 'Eq', isMinor: true);
      final reread = await profiles.findById(created.id);
      expect(reread, created);
      expect(reread, isNot(equals(created.copyWith(displayName: 'Other'))));
    });
  });

  group('day entries repository contract', () {
    test('save returns a domain model; find round-trips every field', () async {
      final profile = await profiles.create(displayName: 'P', isMinor: false);
      final saved = await dayEntries.save(entryFor(
        profile.id,
        LocalDate(2026, 5, 10),
        flow: FlowLevel.heavy,
        tags: const ['cramps', 'sleep_trouble'],
        note: 'rough day',
      ));
      expect(saved, isA<DayEntry>());
      expect(isValidUlid(saved.id), isTrue);
      expect(saved.profileId, profile.id);
      expect(saved.localDate, LocalDate(2026, 5, 10));
      expect(saved.tz, 'America/Chicago');
      expect(saved.flow, FlowLevel.heavy);
      expect(saved.tags, ['cramps', 'sleep_trouble']);
      expect(saved.note, 'rough day');
      expect(saved.deletedAt, isNull);

      final found =
          await dayEntries.find(profile.id, LocalDate(2026, 5, 10));
      expect(found, saved);
      expect(
          await dayEntries.find(profile.id, LocalDate(2026, 5, 11)), isNull);
    });

    test('find is scoped to one profile and ignores tombstoned rows',
        () async {
      final a = await profiles.create(displayName: 'A', isMinor: false);
      final b = await profiles.create(displayName: 'B', isMinor: true);
      final forB =
          await dayEntries.save(entryFor(b.id, LocalDate(2026, 5, 10)));

      expect(await dayEntries.find(a.id, LocalDate(2026, 5, 10)), isNull,
          reason: 'another profile entry for the same date must not answer');
      expect((await dayEntries.find(b.id, LocalDate(2026, 5, 10)))!.id,
          forB.id);

      await dayEntries.delete(b.id, LocalDate(2026, 5, 10));
      expect(await dayEntries.find(b.id, LocalDate(2026, 5, 10)), isNull,
          reason: 'a date whose only row is a tombstone reads as null');
      expect(
          await db.storage
              .getDayEntries(profileId: b.id, includeTombstones: true),
          hasLength(1),
          reason: 'the tombstone is still held for sync');
    });

    test('re-saving the same date updates in place (same row id)', () async {
      final profile = await profiles.create(displayName: 'P', isMinor: false);
      final first =
          await dayEntries.save(entryFor(profile.id, LocalDate(2026, 5, 10)));
      final second = await dayEntries.save(entryFor(profile.id,
          LocalDate(2026, 5, 10),
          flow: FlowLevel.light, note: 'easier'));
      expect(second.id, first.id);
      expect(second.flow, FlowLevel.light);
      expect((await dayEntries.listForProfile(profile.id)), hasLength(1));
    });

    test('listForProfile orders by civil date', () async {
      final profile = await profiles.create(displayName: 'P', isMinor: false);
      for (final date in [LocalDate(2026, 5, 3), LocalDate(2026, 5, 1), LocalDate(2026, 4, 28)]) {
        await dayEntries.save(entryFor(profile.id, date));
      }
      expect(
        (await dayEntries.listForProfile(profile.id)).map((e) => e.localDate),
        [LocalDate(2026, 4, 28), LocalDate(2026, 5, 1), LocalDate(2026, 5, 3)],
      );
    });

    test('all five flow levels round-trip through storage', () async {
      final profile = await profiles.create(displayName: 'P', isMinor: false);
      for (final flow in FlowLevel.values) {
        final saved = await dayEntries.save(
            entryFor(profile.id, LocalDate(2026, 7, 1).addDays(flow.index),
                flow: flow));
        expect(saved.flow, flow);
        expect(
            (await dayEntries.find(profile.id, saved.localDate))!.flow, flow);
      }
    });

    test('unknown tag codes are rejected at the repository boundary',
        () async {
      final profile = await profiles.create(displayName: 'P', isMinor: false);
      await expectLater(
        dayEntries.save(entryFor(profile.id, LocalDate(2026, 5, 10),
            tags: const ['cramps', 'not-a-tag'])),
        throwsArgumentError,
      );
    });

    test('delete tombstones the date and it disappears from reads and streams',
        () async {
      final profile = await profiles.create(displayName: 'P', isMinor: false);
      await dayEntries
          .save(entryFor(profile.id, LocalDate(2026, 5, 10)));

      final seen = <List<DayEntry>>[];
      final sub = dayEntries.watchForProfile(profile.id).listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(seen.last, hasLength(1));

      await dayEntries.delete(profile.id, LocalDate(2026, 5, 10));
      await pumpEventQueue();
      expect(seen.last, isEmpty, reason: 'tombstoned rows are excluded');
      expect(
          await dayEntries.find(profile.id, LocalDate(2026, 5, 10)), isNull);
      expect(await dayEntries.listForProfile(profile.id), isEmpty);
    });

    test('re-creating a deleted date yields a fresh row id', () async {
      final profile = await profiles.create(displayName: 'P', isMinor: false);
      final first =
          await dayEntries.save(entryFor(profile.id, LocalDate(2026, 5, 10)));
      await dayEntries.delete(profile.id, LocalDate(2026, 5, 10));
      final second =
          await dayEntries.save(entryFor(profile.id, LocalDate(2026, 5, 10)));
      expect(second.id, isNot(first.id));
      expect(
          (await dayEntries.listForProfile(profile.id)).single.id, second.id);
    });
  });

  group('R3: per-profile isolation through the repositories', () {
    test('reads, writes and streams never co-mingle profiles', () async {
      final a = await profiles.create(displayName: 'A', isMinor: true);
      final b = await profiles.create(displayName: 'B', isMinor: false);
      await dayEntries.save(entryFor(a.id, LocalDate(2026, 4, 1)));
      await dayEntries.save(entryFor(a.id, LocalDate(2026, 4, 2)));

      final seenForA = <List<DayEntry>>[];
      final sub = dayEntries.watchForProfile(a.id).listen(seenForA.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();

      // Mutating B must never leak into A's stream...
      await dayEntries.save(entryFor(b.id, LocalDate(2026, 4, 3)));
      await pumpEventQueue();
      for (final emission in seenForA) {
        expect(emission, everyElement(isA<DayEntry>()));
        expect(emission.map((e) => e.profileId).toSet(), {a.id});
      }
      expect(seenForA.last, hasLength(2));

      // ...and B's own stream only ever holds B's entries.
      final seenForB = await dayEntries.watchForProfile(b.id).first;
      expect(seenForB.map((e) => e.profileId).toSet(), {b.id});
      expect(seenForB.map((e) => e.localDate), [LocalDate(2026, 4, 3)]);
    });

    test('entries for an unknown profile are rejected (foreign key)', () async {
      await expectLater(
        dayEntries.save(entryFor(
            'noprofileulid00000000000000', LocalDate(2026, 4, 1))),
        throwsA(anything),
      );
    });
  });

  group('settings store contract', () {
    test('get/set/watch round-trip; missing keys read as null', () async {
      expect(await settings.get(SettingsKeys.lastActiveProfile), isNull);

      await settings.set(SettingsKeys.lastActiveProfile, 'profileulid000000000000000000');
      expect(await settings.get(SettingsKeys.lastActiveProfile),
          'profileulid000000000000000000');

      final seen = <String?>[];
      final sub =
          settings.watch(SettingsKeys.relockEnabled).listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(seen.last, isNull);

      await settings.set(SettingsKeys.relockEnabled, 'true');
      await pumpEventQueue();
      expect(seen.last, 'true');
    });

    test('settled key names are stable', () {
      expect(SettingsKeys.lastActiveProfile, 'last_active_profile');
      expect(SettingsKeys.relockEnabled, 'relock_enabled');
      expect(SettingsKeys.webModalAcknowledged, 'web_modal_acknowledged');
    });
  });
}
