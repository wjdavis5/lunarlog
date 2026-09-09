import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/data/db/ulid.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/logging/tracking_preferences.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late ProfilesRepository profiles;
  late DayEntriesRepository dayEntries;
  late ObservationsRepository observations;
  late SettingsStore settings;

  setUp(() {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    profiles = DriftProfilesRepository(db.storage);
    dayEntries = DriftDayEntriesRepository(db.storage);
    observations = DriftObservationsRepository(db.storage);
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

    test('tracking preferences round-trip through the domain model '
        '(Issue #259)', () async {
      final created = await profiles.create(displayName: 'A', isMinor: true);
      expect(created.trackingPreferences, isNull,
          reason: 'a new profile starts never-customized');

      final doc = TrackingPreferences({
        'mood': TrackingCategoryPreference(enabled: false, sortOrder: 0),
        'pain': TrackingCategoryPreference(enabled: true, sortOrder: 1),
      });
      await profiles.update(created.copyWith(trackingPreferences: doc));
      final reread = await profiles.findById(created.id);
      expect(reread!.trackingPreferences, doc,
          reason: 'update() must carry the document through the full-row '
              'overwrite, never silently null it');
    });

    test('setTrackingPreferences writes and clears without touching any '
        'other metadata (Issue #259)', () async {
      final created = await profiles.create(
          displayName: 'A', isMinor: true, sortOrder: 4);
      final updated = await profiles.setTrackingPreferences(
          created.id,
          TrackingPreferences({
            'sex_life': TrackingCategoryPreference(enabled: true, sortOrder: 0),
          }));
      expect(updated, isNotNull);
      expect(updated!.trackingPreferences,
          TrackingPreferences({
            'sex_life': TrackingCategoryPreference(enabled: true, sortOrder: 0),
          }));
      expect(updated.displayName, 'A');
      expect(updated.sortOrder, 4);
      expect(updated.updatedAt.isAfter(created.updatedAt), isTrue);

      expect((await profiles.setTrackingPreferences(created.id, null))!
          .trackingPreferences, isNull);
      expect(await profiles.setTrackingPreferences('01JPROFILEUNKNOWN000000000', null),
          isNull,
          reason: 'unknown id: nothing to curate');
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

    test(
        'every non-deprecated flow level round-trips through storage '
        '(Issue #247 adds notBleeding/superHeavy)', () async {
      final profile = await profiles.create(displayName: 'P', isMinor: false);
      // ignore: deprecated_member_use_from_same_package
      for (final flow in FlowLevel.values.where((f) => f != FlowLevel.spotting)) {
        final saved = await dayEntries.save(
            entryFor(profile.id, LocalDate(2026, 7, 1).addDays(flow.index),
                flow: flow));
        expect(saved.flow, flow);
        expect(
            (await dayEntries.find(profile.id, saved.localDate))!.flow, flow);
      }
    });

    test(
        'a stored deprecated spotting row reads back as notBleeding, never '
        'spotting itself (Issue #247 alias, mappers.dart flowToDomain)',
        () async {
      final profile = await profiles.create(displayName: 'P', isMinor: false);
      final saved = await dayEntries.save(entryFor(
          profile.id, LocalDate(2026, 7, 20),
          // ignore: deprecated_member_use_from_same_package
          flow: FlowLevel.spotting));
      expect(saved.flow, FlowLevel.notBleeding);
      expect((await dayEntries.find(profile.id, saved.localDate))!.flow,
          FlowLevel.notBleeding);
    });

    group(
        'legacy spotting flow -> synthesised observation alias (review '
        'follow-up, PR #335, issue #247)', () {
      test(
          'spottingAliasId is a valid ULID and matches the server backfill\'s '
          'own md5 formula for a fixture id', () {
        const dayEntryId = '01J0000000000000000000FIX1';
        final id = spottingAliasId(dayEntryId);
        expect(isValidUlid(id), isTrue);
        // Mirrors 20260908200000_flow_model.sql's
        // `substr(upper(md5(day_entry_id || ':flow:spotting')), 1, 26)`
        // exactly -- computed independently here (not via spottingAliasId
        // itself) so this test cannot pass merely because both sides share
        // a bug.
        final expected = md5
            .convert(utf8.encode('$dayEntryId:flow:spotting'))
            .toString()
            .toUpperCase()
            .substring(0, 26);
        expect(id, expected);
        expect(id.length, 26);
      });

      test(
          'spottingAliasId is deterministic and namespaced apart from a '
          'plain tag-backfill id for the same day entry + "spotting" text',
          () {
        const dayEntryId = '01J0000000000000000000FIX2';
        final flowAliasId = spottingAliasId(dayEntryId);
        expect(spottingAliasId(dayEntryId), flowAliasId,
            reason: 'deterministic: two calls never disagree');
        final tagBackfillId = md5
            .convert(utf8.encode('$dayEntryId:spotting'))
            .toString()
            .toUpperCase()
            .substring(0, 26);
        expect(flowAliasId, isNot(tagBackfillId),
            reason: 'the ":flow:" namespace segment keeps this keyspace '
                'disjoint from the tag backfill\'s own md5(id || \':\' || '
                'tag) formula for a literal "spotting" tag');
      });

      test(
          'listForProfile synthesises a spotting observation for a live '
          'legacy flow = spotting day entry, with a valid-ULID alias id',
          () async {
        final profile = await profiles.create(displayName: 'P', isMinor: false);
        final saved = await dayEntries.save(entryFor(
            profile.id, LocalDate(2026, 7, 21),
            // ignore: deprecated_member_use_from_same_package
            flow: FlowLevel.spotting));

        final obs = await observations.listForProfile(profile.id);
        final spotting = obs.where((o) => o.category == 'spotting').toList();
        expect(spotting, hasLength(1));
        expect(spotting.single.dayEntryId, saved.id);
        expect(spotting.single.id, spottingAliasId(saved.id));
        expect(isValidUlid(spotting.single.id), isTrue);
      });

      test(
          'listForProfile does not duplicate the synthesised alias once a '
          'real spotting observation is persisted for the same day entry',
          () async {
        final profile = await profiles.create(displayName: 'P', isMinor: false);
        final saved = await dayEntries.save(entryFor(
            profile.id, LocalDate(2026, 7, 22),
            // ignore: deprecated_member_use_from_same_package
            flow: FlowLevel.spotting));

        await observations.save(Observation(
          id: '',
          dayEntryId: saved.id,
          profileId: profile.id,
          localDate: saved.localDate,
          tz: saved.tz,
          category: 'spotting',
          code: 'spotting',
          updatedAt: DateTime.utc(2026, 7, 22),
        ));

        final obs = await observations.listForProfile(profile.id);
        final spotting = obs.where((o) => o.category == 'spotting').toList();
        expect(spotting, hasLength(1),
            reason: 'a real persisted spotting observation suppresses the '
                'synthesised alias for the same day entry, never both');
        expect(isValidUlid(spotting.single.id), isTrue);
      });

      test(
          'listForProfile never synthesises an alias for a day entry whose '
          'flow was never spotting', () async {
        final profile = await profiles.create(displayName: 'P', isMinor: false);
        await dayEntries.save(entryFor(
            profile.id, LocalDate(2026, 7, 23),
            flow: FlowLevel.notBleeding));

        final obs = await observations.listForProfile(profile.id);
        expect(obs.where((o) => o.category == 'spotting'), isEmpty);
      });
    });

    test(
        'unknown tag codes are preserved, not rejected, at the repository '
        'boundary (#237)', () async {
      // A code outside kTagTaxonomy must not make the entry permanently
      // unsavable (a peer device's newer taxonomy, an import, or — as here —
      // a code this build simply predates). validateTagCodes stays available
      // for a caller that wants strict validation of newly-chosen codes
      // (DaySheet), but the repository write path itself must not gate on
      // taxonomy membership.
      final profile = await profiles.create(displayName: 'P', isMinor: false);
      final saved = await dayEntries.save(entryFor(
          profile.id, LocalDate(2026, 5, 10),
          tags: const ['cramps', 'not-a-tag']));
      expect(saved.tags, unorderedEquals(['cramps', 'not-a-tag']));

      final found = await dayEntries.find(profile.id, LocalDate(2026, 5, 10));
      expect(found!.tags, unorderedEquals(['cramps', 'not-a-tag']),
          reason: 'the unknown code survives the save round-trip unchanged');

      // Saving again (the DaySheet Save-retry scenario #237 reports) must
      // keep succeeding — the entry is never permanently unsavable.
      final resaved = await dayEntries.save(entryFor(
          profile.id, LocalDate(2026, 5, 10),
          tags: const ['cramps', 'not-a-tag'], note: 'still saves'));
      expect(resaved.note, 'still saves');
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

  group('watchForProfile from/to threading (issue #197)', () {
    test('from/to narrow the domain stream to an inclusive date range',
        () async {
      final profile = await profiles.create(displayName: 'A', isMinor: false);
      await dayEntries.save(entryFor(profile.id, LocalDate(2026, 5, 31)));
      await dayEntries.save(entryFor(profile.id, LocalDate(2026, 6, 1)));
      await dayEntries.save(entryFor(profile.id, LocalDate(2026, 6, 15)));
      await dayEntries.save(entryFor(profile.id, LocalDate(2026, 6, 30)));
      await dayEntries.save(entryFor(profile.id, LocalDate(2026, 7, 1)));

      final windowed = await dayEntries
          .watchForProfile(
            profile.id,
            from: LocalDate(2026, 6, 1),
            to: LocalDate(2026, 6, 30),
          )
          .first;
      expect(windowed.map((e) => e.localDate), [
        LocalDate(2026, 6, 1),
        LocalDate(2026, 6, 15),
        LocalDate(2026, 6, 30),
      ], reason: 'the boundary dates themselves must be included');
    });

    test('omitting from/to still reads full history, unchanged', () async {
      final profile = await profiles.create(displayName: 'A', isMinor: false);
      await dayEntries.save(entryFor(profile.id, LocalDate(2020, 1, 1)));
      await dayEntries.save(entryFor(profile.id, LocalDate(2026, 4, 1)));

      final full = await dayEntries.watchForProfile(profile.id).first;
      expect(full, hasLength(2));
    });

    test('a range never leaks another profile\'s entries', () async {
      final a = await profiles.create(displayName: 'A', isMinor: true);
      final b = await profiles.create(displayName: 'B', isMinor: false);
      await dayEntries.save(entryFor(a.id, LocalDate(2026, 6, 15)));
      await dayEntries.save(entryFor(b.id, LocalDate(2026, 6, 15)));

      final aWindowed = await dayEntries
          .watchForProfile(
            a.id,
            from: LocalDate(2026, 6, 1),
            to: LocalDate(2026, 6, 30),
          )
          .first;
      expect(aWindowed.map((e) => e.profileId).toSet(), {a.id});
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
