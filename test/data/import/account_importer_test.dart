/// Tests for `lib/data/import/account_importer.dart` (Issue #140):
/// [DriftAccountImporter.apply]'s transactional guarantee, and
/// [AccountImportCoordinator.buildPlan]/`apply` end to end against a real
/// in-memory Drift store (mirrors `test/data/profile_guardians_repository_test.dart`'s
/// setup) — including the full export -> import round trip and a same-date
/// collision merge.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' hide Profile;
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart' as dbtables show FlowLevel;
import 'package:lunarlog/data/import/account_importer.dart';
import 'package:lunarlog/data/repositories/drift_cycle_overrides_repository.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_profile_guardians_repository.dart';
import 'package:lunarlog/data/repositories/drift_tag_registry_repository.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/export/account_export.dart';
import 'package:lunarlog/domain/import/account_import.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/measurement_unit.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart'
    show GuardiansForProfile;

List<int> _bytes(Map<String, Object?> document) => utf8.encode(jsonEncode(document));

AccountImportDocument _parse(Map<String, Object?> document) {
  final result = parseAccountImport(_bytes(document));
  return (result as AccountImportParsed).document;
}

Map<String, Object?> _document({List<Map<String, Object?>> profiles = const []}) => {
      'schemaVersion': kAccountExportSchemaVersion,
      'exportedAt': '2026-01-03T00:00:00.000Z',
      'app': {'name': 'lunarlog', 'version': '1.0.0+1'},
      'profiles': profiles,
    };

Map<String, Object?> _rawProfile(
  String id, {
  List<Map<String, Object?>> dayEntries = const [],
  List<Map<String, Object?>> observations = const [],
  List<Map<String, Object?>> cycleOverrides = const [],
  List<Map<String, Object?>> customTags = const [],
}) =>
    {
      'id': id,
      'displayName': 'Riley',
      'isMinor': true,
      'mode': 'standard',
      'sortOrder': 0,
      'archivedAt': null,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-01-01T00:00:00.000Z',
      'dayEntries': dayEntries,
      'observations': observations,
      'cycleOverrides': cycleOverrides,
      'customTags': customTags,
    };

/// A `profiles[].customTags[]` element (Issue #824).
Map<String, Object?> _rawCustomTag(
  String id,
  String code,
  String displayName, {
  String category = 'custom',
  bool intensityEnabled = false,
  String? hiddenAt,
  int? sortOrder,
}) =>
    {
      'id': id,
      'code': code,
      'displayName': displayName,
      'category': category,
      'intensityEnabled': intensityEnabled,
      'hiddenAt': hiddenAt,
      'sortOrder': sortOrder,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-01-01T00:00:00.000Z',
    };

/// A `profiles[].cycleOverrides[]` element (Issue #140 review, LLA-084).
Map<String, Object?> _rawCycleOverride(
  String id,
  String cycleStartDate, {
  bool excludedFromAverage = false,
  bool manualStart = false,
  String? noteId,
}) =>
    {
      'id': id,
      'cycleStartDate': cycleStartDate,
      'excludedFromAverage': excludedFromAverage,
      'manualStart': manualStart,
      'noteId': noteId,
    };

Map<String, Object?> _rawDayEntry(
  String id,
  String localDate, {
  String flow = 'medium',
  List<String> tags = const [],
}) =>
    {
      'id': id,
      'localDate': localDate,
      'tz': 'UTC',
      'flow': flow,
      'tags': tags,
      'note': null,
      'source': 'manual',
      'sourceId': null,
      'importId': null,
      'updatedAt': '2026-01-02T00:00:00.000Z',
    };

Map<String, Object?> _rawObservation(String id, String localDate) => {
      'id': id,
      'dayEntryId': 'de-$id',
      'localDate': localDate,
      'observedAt': null,
      'tz': 'UTC',
      'category': 'pain',
      'code': 'cramps',
      'valueNum': null,
      'valueText': null,
      'unit': null,
      'intensity': null,
      'excluded': false,
      'source': 'manual',
      'sourceId': null,
      'importId': null,
      'raw': null,
      'updatedAt': '2026-01-02T00:00:00.000Z',
    };

// Issue #140 review round 2, item 1: fixture ids must be syntactically
// valid ULIDs now that parseAccountImport enforces the format. Plain
// zero-padded digits are valid Crockford base32 characters, so these are
// cheap, distinct, and still readable at a glance.
const String _e1 = '00000000000000000000000011';
const String _o1 = '00000000000000000000000021';
const String _fileP1 = '00000000000000000000000031';
const String _co1 = '00000000000000000000000041';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late LunarLogStorage storage;
  late DriftProfilesRepository profiles;
  late DriftDayEntriesRepository entries;
  late DriftObservationsRepository observations;
  late DriftCycleOverridesRepository cycleOverrides;
  late DriftTagRegistryRepository tagRegistry;

  setUp(() {
    db = LunarLogDatabase(NativeDatabase.memory());
    storage = LunarLogStorage(db);
    profiles = DriftProfilesRepository(storage);
    entries = DriftDayEntriesRepository(storage);
    observations = DriftObservationsRepository(storage);
    cycleOverrides = DriftCycleOverridesRepository(storage);
    tagRegistry = DriftTagRegistryRepository(storage);
  });

  tearDown(() => db.close());

  DriftAccountImportCoordinator coordinator({
    GuardiansForProfile? guardiansForProfile,
    String? currentUserId,
  }) =>
      DriftAccountImportCoordinator(
        profilesRepository: profiles,
        dayEntriesRepository: entries,
        observationsRepository: observations,
        storage: storage,
        cycleOverridesRepository: cycleOverrides,
        tagRegistryRepository: tagRegistry,
        guardiansForProfile: guardiansForProfile,
        currentUserId: currentUserId,
      );

  group('DriftAccountImporter.apply — transactional rollback', () {
    test('an unexpected write failure partway through leaves the store '
        'exactly as it was before apply ran', () async {
      // Hand-crafted plan (bypassing the pure planner's own bound checks,
      // which would never let this reach apply) — the second profile's
      // entry carries a note over `kMaxNoteLength`, so
      // `LunarLogStorage.upsertDayEntry` throws partway through the one
      // transaction `apply` wraps everything in.
      final plan = ImportPlan(profiles: [
        ProfilePlan(
          fileProfileId: 'p1',
          displayName: 'Good Profile',
          outcome: ProfileImportOutcome.created,
          entries: [
            DayEntryPlan(
              outcome: DayEntryImportOutcome.add,
              localDate: _date('2026-01-05'),
              tz: 'UTC',
              flow: FlowLevel.light,
              tags: [],
              note: null,
              source: 'file_import',
              sourceId: 'e1',
              importId: null,
            ),
          ],
        ),
        ProfilePlan(
          fileProfileId: 'p2',
          displayName: 'Bad Profile',
          outcome: ProfileImportOutcome.created,
          entries: [
            DayEntryPlan(
              outcome: DayEntryImportOutcome.add,
              localDate: _date('2026-01-06'),
              tz: 'UTC',
              flow: FlowLevel.light,
              tags: const [],
              note: 'x' * 3000, // over kMaxNoteLength
              source: 'file_import',
              sourceId: 'e2',
              importId: null,
            ),
          ],
        ),
      ]);

      await expectLater(
        DriftAccountImporter(storage).apply(plan),
        throwsA(isA<ArgumentError>()),
      );

      // The first profile's write happened before the failure — but the
      // whole transaction must still roll back, so nothing survives.
      expect(await profiles.list(), isEmpty);
      expect(await storage.getDayEntries(profileId: 'p1'), isEmpty);
    });
  });

  group('AccountImportCoordinator — create, no existing data', () {
    test('buildPlan + apply creates the profile and writes its entries/'
        'observations with file-import provenance', () async {
      final document = _parse(_document(profiles: [
        _rawProfile(_fileP1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05', flow: 'medium', tags: ['cramps']),
        ], observations: [
          _rawObservation(_o1, '2026-01-05'),
        ]),
      ]));

      final plan = await coordinator().buildPlan(document);
      final summary = await coordinator().apply(plan);

      expect(summary.profilesCreated, 1);
      expect(summary.entriesAdded, 1);
      expect(summary.observationsAdded, 1);

      final created = (await profiles.list()).single;
      expect(created.displayName, 'Riley');
      // Issue #140 review, item 2: the file's own profile id is reused,
      // not re-minted — see `_resolveProfileId`'s doc comment.
      expect(created.id, _fileP1);
      final createdEntries = await entries.listForProfile(created.id);
      expect(createdEntries.single.flow, FlowLevel.medium);
      expect(createdEntries.single.tags, ['cramps']);
      expect(createdEntries.single.source, DayEntrySource.fileImport);
      expect(createdEntries.single.sourceId, _e1);

      final createdObservations = await observations.listForProfile(created.id);
      expect(createdObservations, hasLength(1));
      // observations_source_check has no `file_import` value (Issue #140
      // Assumptions) — the label stays manual. Issue #140 review, item 6:
      // sourceId is left null, not the file's original observation id —
      // see `_applyObservation`'s doc comment for why.
      expect(createdObservations.single.source, ObservationSource.manual);
      expect(createdObservations.single.sourceId, isNull);
    });

    test('issue #255: a created profile takes the file display-unit '
        'preferences; an absent key falls back to the metric default',
        () async {
      final document = _parse(_document(profiles: [
        {..._rawProfile(_fileP1), 'bbtUnit': 'fahrenheit', 'weightUnit': 'lb'},
      ]));
      final plan = await coordinator().buildPlan(document);
      await coordinator().apply(plan);

      final created = (await profiles.list()).single;
      expect(created.bbtUnit, BbtUnit.fahrenheit);
      expect(created.weightUnit, WeightUnit.lb);

      // Re-importing the same file must plan as *matched* and keep the
      // stored preference untouched (mode's contract).
      final plan2 = await coordinator().buildPlan(document);
      await coordinator().apply(plan2);
      final second = (await profiles.list()).single;
      expect(second.id, _fileP1);
      expect(second.bbtUnit, BbtUnit.fahrenheit);
      expect(second.weightUnit, WeightUnit.lb);
    });

    test('issue #255: a pre-v8 export (no unit keys) creates a profile '
        'with the metric defaults', () async {
      final rawDoc = _document(profiles: [_rawProfile(_fileP1)])
        ..['schemaVersion'] = 7;
      final plan = await coordinator().buildPlan(_parse(rawDoc));
      await coordinator().apply(plan);
      final created = (await profiles.list()).single;
      expect(created.bbtUnit, BbtUnit.celsius);
      expect(created.weightUnit, WeightUnit.kg);
    });

    test('re-importing the same file plans the profile as matched, not '
        'created (Issue #140 review, item 2), and APPLYING that second plan '
        'is idempotent — the entry merges in place, no duplicate rows '
        '(Issue #140 review round 2, item 7)', () async {
      final document = _parse(_document(profiles: [
        _rawProfile(_fileP1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05', tags: ['cramps']),
        ], observations: [
          _rawObservation(_o1, '2026-01-05'),
        ]),
      ]));

      final firstPlan = await coordinator().buildPlan(document);
      await coordinator().apply(firstPlan);

      final secondPlan = await coordinator().buildPlan(document);
      expect(secondPlan.summary.profilesMatched, 1);
      expect(secondPlan.summary.profilesCreated, 0);
      expect(secondPlan.profiles.single.entries.single.outcome,
          DayEntryImportOutcome.merge);
      expect(secondPlan.profiles.single.observations.single.outcome,
          ObservationImportOutcome.skip);

      final secondSummary = await coordinator().apply(secondPlan);
      expect(secondSummary.entriesMerged, 1);
      expect(secondSummary.entriesAdded, 0);
      expect(secondSummary.observationsSkipped, 1);
      expect(secondSummary.observationsAdded, 0);

      final all = await profiles.list();
      expect(all, hasLength(1), reason: 'no duplicate profile was created');
      expect(all.single.id, _fileP1);
      expect(await entries.listForProfile(_fileP1), hasLength(1),
          reason: 'no duplicate day entry row was created');
      expect(await observations.listForProfile(_fileP1), hasLength(1),
          reason: 'no duplicate observation row was created');
    });
  });

  group('AccountImportCoordinator — matched profile', () {
    test('a collision merges into the existing row rather than creating a '
        'second one', () async {
      final existingProfile = await profiles.create(displayName: 'Riley', isMinor: true);
      await storage.upsertDayEntry(
        profileId: existingProfile.id,
        localDate: '2026-01-05',
        tz: 'UTC',
        flow: dbtables.FlowLevel.light,
        tags: const ['bloating'],
      );

      final document = _parse(_document(profiles: [
        _rawProfile(existingProfile.id, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05', flow: 'heavy', tags: ['cramps']),
        ]),
      ]));

      final plan = await coordinator().buildPlan(document);
      final summary = await coordinator().apply(plan);

      expect(summary.profilesMatched, 1);
      expect(summary.profilesCreated, 0);
      expect(summary.entriesMerged, 1);
      expect(summary.entriesAdded, 0);

      final all = await profiles.list();
      expect(all, hasLength(1), reason: 'no second profile is created');
      final merged = (await entries.listForProfile(existingProfile.id)).single;
      expect(merged.flow, FlowLevel.heavy);
      expect(merged.tags, ['bloating', 'cramps']);
    });

    test('an archived matched profile is skipped: no entries are written '
        'to it', () async {
      final existingProfile = await profiles.create(displayName: 'Riley', isMinor: true);
      await profiles.setArchived(existingProfile.id, true);

      final document = _parse(_document(profiles: [
        _rawProfile(existingProfile.id, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05'),
        ]),
      ]));

      final plan = await coordinator().buildPlan(document);
      expect(plan.summary.skippedProfiles, hasLength(1));

      final summary = await coordinator().apply(plan);
      expect(summary.entriesAdded, 0);
      expect(summary.entriesMerged, 0);
      expect(await entries.listForProfile(existingProfile.id), isEmpty);
    });

    test('a viewer-role guardian cannot import into the matched profile',
        () async {
      final existingProfile = await profiles.create(displayName: 'Shared', isMinor: false);
      await storage.applyRemoteRows([
        RemoteProfileGuardianRow(
          id: 'g1',
          profileId: existingProfile.id,
          userId: 'viewer-user',
          role: 'viewer',
          status: 'accepted',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ]);
      final guardians = DriftProfileGuardiansRepository(storage);

      final document = _parse(_document(profiles: [
        _rawProfile(existingProfile.id, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05'),
        ]),
      ]));

      final plan = await coordinator(
        guardiansForProfile: guardians.getForProfile,
        currentUserId: 'viewer-user',
      ).buildPlan(document);

      expect(plan.profiles.single.outcome, ProfileImportOutcome.skipped);
    });
  });

  group('AccountImportCoordinator — portable state (Issue #140 review, '
      'LLA-084)', () {
    test('a created profile writes its subject metadata and profileMode',
        () async {
      final document = _parse(_document(profiles: [
        {
          ..._rawProfile(_fileP1),
          'birthYear': 2012,
          'relationship': 'daughter',
          'lastPeriodStart': '2026-08-01',
          'typicalCycleLengthDays': 28,
          'typicalPeriodLengthDays': 5,
          'profileMode': {
            'mode': 'conceive',
            'birthControlMethod': 'pill',
            'birthControlStartedOn': '2026-06-01',
          },
        },
      ]));

      final plan = await coordinator().buildPlan(document);
      await coordinator().apply(plan);

      final created = (await profiles.list()).single;
      expect(created.birthYear, 2012);
      expect(created.relationship?.toDb(), 'daughter');
      expect(created.lastPeriodStart?.iso, '2026-08-01');
      expect(created.typicalCycleLengthDays, 28);
      expect(created.typicalPeriodLengthDays, 5);

      final mode = await storage.getProfileMode(created.id);
      expect(mode, isNotNull);
      expect(mode!.mode, 'conceive');
      expect(mode.birthControlMethod, 'pill');
      expect(mode.birthControlStartedOn, '2026-06-01');
    });

    test('a MATCHED profile keeps its own stored subject metadata and '
        'profileMode — the file\'s values are never applied over them',
        () async {
      final existingProfile = await profiles.create(
        displayName: 'Riley',
        isMinor: true,
        birthYear: 2010,
      );
      await storage.upsertProfileMode(
        profileId: existingProfile.id,
        mode: 'tracking',
      );

      final document = _parse(_document(profiles: [
        {
          ..._rawProfile(existingProfile.id),
          'birthYear': 1999,
          'profileMode': {'mode': 'conceive'},
        },
      ]));

      final plan = await coordinator().buildPlan(document);
      await coordinator().apply(plan);

      final matched = (await profiles.list()).single;
      expect(matched.birthYear, 2010,
          reason: 'the file\'s birthYear is never applied to a matched '
              'profile');
      final mode = await storage.getProfileMode(existingProfile.id);
      expect(mode!.mode, 'tracking',
          reason: 'the file\'s profileMode is never applied to a matched '
              'profile');
    });

    test('a created profile writes its trackingPreferences document '
        '(Issue #648)', () async {
      final document = _parse(_document(profiles: [
        {
          ..._rawProfile(_fileP1),
          'trackingPreferences': {
            'mood': {'enabled': false, 'sort_order': 2},
          },
        },
      ]));

      final plan = await coordinator().buildPlan(document);
      await coordinator().apply(plan);

      final created = (await profiles.list()).single;
      expect(created.trackingPreferences, isNotNull);
      expect(created.trackingPreferences!.entries['mood']?.enabled, isFalse);
      expect(created.trackingPreferences!.entries['mood']?.sortOrder, 2);
    });

    test('a MATCHED profile keeps its own stored trackingPreferences — the '
        "file's document is never applied over it (Issue #648, same "
        'create-only treatment as profileMode)', () async {
      final existingProfile = await profiles.create(displayName: 'Riley', isMinor: true);
      await storage.upsertProfile(
        id: existingProfile.id,
        displayName: existingProfile.displayName,
        isMinor: existingProfile.isMinor,
        trackingPreferences: '{"mood":{"enabled":true,"sort_order":0}}',
      );

      final document = _parse(_document(profiles: [
        {
          ..._rawProfile(existingProfile.id),
          'trackingPreferences': {
            'mood': {'enabled': false, 'sort_order': 9},
          },
        },
      ]));

      final plan = await coordinator().buildPlan(document);
      await coordinator().apply(plan);

      final matched = (await profiles.list()).single;
      expect(matched.trackingPreferences!.entries['mood']?.enabled, isTrue,
          reason:
              "the file's trackingPreferences is never applied to a matched "
              'profile');
    });

    test('cycleOverrides are additive for both a created and a matched '
        'profile, and a colliding file id under the SAME profile is never '
        'reused (mirrors the LLA-086 observation-id-conflict fix)',
        () async {
      final existingProfile = await profiles.create(displayName: 'Riley', isMinor: true);
      final localOverride = await storage.upsertCycleOverride(
        profileId: existingProfile.id,
        cycleStartDate: '2026-01-01',
        excludedFromAverage: true,
      );
      // The file's own cycle override id already belongs to a DIFFERENT
      // local row (a different cycleStartDate) under the SAME profile —
      // reusing it would move localOverride onto the file's date instead
      // of adding a genuinely new row.
      final document = _parse(_document(profiles: [
        _rawProfile(existingProfile.id, cycleOverrides: [
          _rawCycleOverride(localOverride.id, '2026-03-01',
              excludedFromAverage: true),
          _rawCycleOverride(_co1, '2026-01-01'), // collides by date -> skip
        ]),
      ]));

      final plan = await coordinator().buildPlan(document);
      final overridePlans = plan.profiles.single.cycleOverrides;
      expect(overridePlans[0].outcome, CycleOverrideImportOutcome.add);
      expect(overridePlans[1].outcome, CycleOverrideImportOutcome.skip);

      await coordinator().apply(plan);

      final all = await cycleOverrides.listForProfile(existingProfile.id);
      expect(all, hasLength(2),
          reason: 'the file row landed as a genuinely new row, not a move '
              'of the existing one');
      final untouched = all.singleWhere((o) => o.id == localOverride.id);
      expect(untouched.cycleStartDate, '2026-01-01',
          reason: 'the existing override is never silently moved despite '
              'the file row sharing its raw id');
      final added = all.singleWhere((o) => o.id != localOverride.id);
      expect(added.cycleStartDate, '2026-03-01');
    });

    test('customTags are additive for both a created and a matched profile, '
        'and a colliding file id is safely re-minted', () async {
      final existingProfile =
          await profiles.create(displayName: 'Riley', isMinor: true);
      final localTag = await storage.upsertProfileTagRegistryEntry(
        profileId: existingProfile.id,
        code: 'cramps_mild',
        displayName: 'Mild Cramps',
        category: 'custom',
        updatedAt: DateTime.utc(2026, 1, 1),
      );

      final document = _parse(_document(profiles: [
        _rawProfile(existingProfile.id, customTags: [
          _rawCustomTag(localTag.id, 'herbal_tea', 'Herbal Tea'),
          _rawCustomTag(
              '00000000000000000000000099', 'cramps_mild', 'Duplicate Cramps'),
        ]),
      ]));

      final plan = await coordinator().buildPlan(document);
      final tagPlans = plan.profiles.single.customTags;
      expect(tagPlans[0].outcome, CustomTagImportOutcome.add);
      expect(tagPlans[1].outcome, CustomTagImportOutcome.skip);

      await coordinator().apply(plan);

      final all = await tagRegistry.listForProfile(existingProfile.id);
      expect(all, hasLength(2));
      final untouched = all.singleWhere((t) => t.id == localTag.id);
      expect(untouched.code, 'cramps_mild');
      expect(untouched.displayName, 'Mild Cramps');
      final added = all.singleWhere((t) => t.id != localTag.id);
      expect(added.code, 'herbal_tea');
      expect(added.displayName, 'Herbal Tea');
    });
  });

  group('AccountImportCoordinator — stale merge detection (Issue #140 '
      'review, LLA-085)', () {
    test('a concurrent edit landing after buildPlan aborts apply entirely, '
        'writing nothing from the whole plan — not just the stale entry',
        () async {
      final existingProfile =
          await profiles.create(displayName: 'Riley', isMinor: true);
      await storage.upsertDayEntry(
        profileId: existingProfile.id,
        localDate: '2026-01-05',
        tz: 'UTC',
        flow: dbtables.FlowLevel.light,
        note: 'noteA',
      );

      final document = _parse(_document(profiles: [
        // A second, brand-new profile in the SAME plan -- proves a stale
        // merge aborts the whole transaction, not just its own profile.
        // A distinct entry id: ids must be unique across the WHOLE
        // document, not just within one profile.
        _rawProfile(_fileP1, dayEntries: [
          _rawDayEntry('00000000000000000000000099', '2026-02-01'),
        ]),
        _rawProfile(existingProfile.id, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05', flow: 'heavy'),
        ]),
      ]));

      final plan = await coordinator().buildPlan(document);
      final mergePlan = plan.profiles
          .singleWhere((p) => p.fileProfileId == existingProfile.id)
          .entries
          .single;
      expect(mergePlan.outcome, DayEntryImportOutcome.merge);
      expect(mergePlan.existingUpdatedAt, isNotNull);

      // A "concurrent sync" lands on the SAME row after buildPlan already
      // read it -- note changes to noteC, with a fresh updated_at, exactly
      // the LLA-085 repro ("remote sync changes it to C while dialog
      // open").
      await storage.upsertDayEntry(
        profileId: existingProfile.id,
        localDate: '2026-01-05',
        tz: 'UTC',
        flow: dbtables.FlowLevel.light,
        note: 'noteC',
      );

      await expectLater(
        coordinator().apply(plan),
        throwsA(isA<StaleImportPlanException>()),
      );

      // The concurrent edit survives untouched -- the stale plan's merged
      // value (which would have reverted to noteA under a fresh timestamp)
      // was never applied.
      final stillStored =
          (await entries.listForProfile(existingProfile.id)).single;
      expect(stillStored.note, 'noteC');
      expect(stillStored.flow, FlowLevel.light);

      // The whole transaction rolled back -- the OTHER, unrelated profile
      // in the same plan was never created either.
      expect(await profiles.list(), hasLength(1));
    });

    test('a merge whose target is unchanged since buildPlan applies '
        'normally', () async {
      final existingProfile =
          await profiles.create(displayName: 'Riley', isMinor: true);
      await storage.upsertDayEntry(
        profileId: existingProfile.id,
        localDate: '2026-01-05',
        tz: 'UTC',
        flow: dbtables.FlowLevel.light,
      );

      final document = _parse(_document(profiles: [
        _rawProfile(existingProfile.id, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05', flow: 'heavy'),
        ]),
      ]));

      final plan = await coordinator().buildPlan(document);
      final summary = await coordinator().apply(plan);
      expect(summary.entriesMerged, 1);
      final merged = (await entries.listForProfile(existingProfile.id)).single;
      expect(merged.flow, FlowLevel.heavy);
    });
  });

  group('AccountImportCoordinator — dedup by provenance triple (Issue #140 '
      'review, item 5)', () {
    test('import, delete the day, re-import: the original row id is '
        'revived, no duplicate', () async {
      final existingProfile =
          await profiles.create(displayName: 'Riley', isMinor: true);
      final document = _parse(_document(profiles: [
        _rawProfile(existingProfile.id, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05', flow: 'heavy'),
        ]),
      ]));

      final firstPlan = await coordinator().buildPlan(document);
      await coordinator().apply(firstPlan);
      final firstEntries = await entries.listForProfile(existingProfile.id);
      final originalId = firstEntries.single.id;
      expect(firstEntries.single.source, DayEntrySource.fileImport);
      expect(firstEntries.single.sourceId, _e1);

      // Delete the day: the live row is tombstoned, not removed.
      await entries.delete(existingProfile.id, firstEntries.single.localDate);
      expect(await entries.listForProfile(existingProfile.id), isEmpty);

      // Re-importing the same file plans an "add" again (no live row at
      // that date any more) — the importer must find the tombstoned row
      // by (profileId, source, sourceId) and revive it, not insert a
      // second row under a fresh id.
      final secondPlan = await coordinator().buildPlan(document);
      expect(secondPlan.profiles.single.entries.single.outcome,
          DayEntryImportOutcome.add);
      await coordinator().apply(secondPlan);

      final revived = await entries.listForProfile(existingProfile.id);
      expect(revived, hasLength(1), reason: 'no duplicate row was created');
      expect(revived.single.id, originalId,
          reason: 'the original tombstoned row was revived, not replaced');
      expect(revived.single.flow, FlowLevel.heavy);
      // Issue #140 review round 2, item 7: the revived row is a genuine
      // local write, not a no-op — dirty (so sync actually pushes it) with
      // localRev bumped past the tombstone's own. `storage.getDayEntries`
      // (unlike `entries.listForProfile`, which returns the domain model)
      // returns the drift row directly, which carries `dirty`/`localRev`.
      final allRows = await storage.getDayEntries(
          profileId: existingProfile.id, includeTombstones: true);
      final revivedRow = allRows.singleWhere((r) => r.id == originalId);
      expect(revivedRow.dirty, isTrue);
      expect(revivedRow.localRev, greaterThan(1));

      // Full-fidelity read (including tombstones) confirms there is still
      // exactly one row for this (profile, source, sourceId) — revival,
      // not a second insert.
      final allDayEntries =
          await storage.getDayEntries(profileId: existingProfile.id, includeTombstones: true);
      expect(allDayEntries, hasLength(1));
    });
  });

  group('AccountImportCoordinator — row id reuse (Issue #140 review round '
      '2, item 3)', () {
    test('import on a fresh store: the entry and observation row ids equal '
        "the file's own ids", () async {
      final document = _parse(_document(profiles: [
        _rawProfile(_fileP1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05'),
        ], observations: [
          _rawObservation(_o1, '2026-01-05'),
        ]),
      ]));

      final plan = await coordinator().buildPlan(document);
      await coordinator().apply(plan);

      final createdEntries = await entries.listForProfile(_fileP1);
      expect(createdEntries.single.id, _e1,
          reason: 'no local collision existed, so the file\'s own id is '
              'reused for the new row instead of a freshly generated one');

      final createdObservations = await observations.listForProfile(_fileP1);
      expect(createdObservations.single.id, _o1);
    });

    test('import onto a date with a live manual row: merges into the '
        "existing row id, not the file's id", () async {
      final existingProfile =
          await profiles.create(displayName: 'Riley', isMinor: true);
      final manualRow = await storage.upsertDayEntry(
        profileId: existingProfile.id,
        localDate: '2026-01-05',
        tz: 'UTC',
        flow: dbtables.FlowLevel.light,
      );

      final document = _parse(_document(profiles: [
        _rawProfile(existingProfile.id, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05', flow: 'heavy'),
        ]),
      ]));

      final plan = await coordinator().buildPlan(document);
      expect(plan.profiles.single.entries.single.outcome,
          DayEntryImportOutcome.merge);
      await coordinator().apply(plan);

      final merged = (await entries.listForProfile(existingProfile.id)).single;
      expect(merged.id, manualRow.id,
          reason: 'a merge always targets the existing live row by '
              '(profileId, localDate) — the file\'s own id is never '
              'adopted for a merge');
      expect(merged.id, isNot(_e1));
      expect(merged.flow, FlowLevel.heavy);
    });
  });

  group(
      'AccountImportCoordinator — observation id conflict (Issue #140 '
      'review, LLA-086)', () {
    test(
        'a stored observation whose code changed since backup shares no '
        'semantic key with the file row despite sharing its id — planImport '
        'calls it "add", but the id is not reused: the existing row is '
        'never silently overwritten', () async {
      final existingProfile =
          await profiles.create(displayName: 'Riley', isMinor: true);
      await storage.upsertDayEntry(
        id: 'de1',
        profileId: existingProfile.id,
        localDate: '2026-01-05',
        tz: 'UTC',
        flow: dbtables.FlowLevel.light,
      );
      // The file's own observation id, X, already belongs to a LIVE local
      // observation — but with a different code, so it shares no semantic
      // (date, category, code) key with the file's row.
      final existingObs = await storage.upsertObservation(
        id: _o1,
        dayEntryId: 'de1',
        profileId: existingProfile.id,
        localDate: '2026-01-05',
        tz: 'UTC',
        category: 'mood',
        code: 'happy',
      );

      final document = _parse(_document(profiles: [
        _rawProfile(existingProfile.id, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05'),
        ], observations: [
          {..._rawObservation(_o1, '2026-01-05'), 'category': 'mood', 'code': 'sad'},
        ]),
      ]));

      final plan = await coordinator().buildPlan(document);
      expect(plan.profiles.single.observations.single.outcome,
          ObservationImportOutcome.add,
          reason: 'no existing row at (date, mood, sad) — planImport\'s '
              'semantic dedup alone sees this as a fresh add');

      await coordinator().apply(plan);

      final all = await observations.listForProfile(existingProfile.id);
      expect(all, hasLength(2),
          reason: 'the file row landed as a genuinely new row, not an '
              'overwrite of the existing one');

      final untouched = all.singleWhere((o) => o.id == _o1);
      expect(untouched.category, 'mood');
      expect(untouched.code, 'happy',
          reason: 'the existing observation X is never silently '
              'overwritten despite the file row sharing its raw id');

      final added = all.singleWhere((o) => o.id != _o1);
      expect(added.category, 'mood');
      expect(added.code, 'sad');
      expect(added.id, isNot(_o1),
          reason: 'the colliding file id is never reused — a fresh id is '
              'minted instead');
      // Sanity: the file id really was a syntactically valid ULID (the
      // conflict, not the format, is what routes this to a fresh id).
      expect(existingObs.id, _o1);
    });

    test('the same colliding id under a DIFFERENT profile still gets a '
        'fresh id, not the file\'s own', () async {
      final profileA = await profiles.create(displayName: 'A', isMinor: true);
      final profileB = await profiles.create(displayName: 'B', isMinor: true);
      await storage.upsertDayEntry(
        id: 'de-a',
        profileId: profileA.id,
        localDate: '2026-01-05',
        tz: 'UTC',
        flow: dbtables.FlowLevel.light,
      );
      await storage.upsertObservation(
        id: _o1,
        dayEntryId: 'de-a',
        profileId: profileA.id,
        localDate: '2026-01-05',
        tz: 'UTC',
        category: 'mood',
        code: 'happy',
      );

      final document = _parse(_document(profiles: [
        _rawProfile(profileB.id, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05'),
        ], observations: [
          _rawObservation(_o1, '2026-01-05'),
        ]),
      ]));

      final plan = await coordinator().buildPlan(document);
      await coordinator().apply(plan);

      final profileAObs = await observations.listForProfile(profileA.id);
      expect(profileAObs.single.id, _o1);
      expect(profileAObs.single.category, 'mood',
          reason: 'profile A\'s own observation is untouched by profile '
              'B\'s import');

      final profileBObs = await observations.listForProfile(profileB.id);
      expect(profileBObs, hasLength(1));
      expect(profileBObs.single.id, isNot(_o1),
          reason: 'an id already claimed by ANOTHER profile\'s row is '
              'never reused either');
    });
  });

  group('AccountImportCoordinator — tombstoned profile revival (Issue #140 '
      'review round 2, item 6)', () {
    test('re-importing a file after its profile was deleted un-deletes it, '
        "keeps its own stored metadata (not the file's), and reports it as "
        'restored', () async {
      final existingProfile =
          await profiles.create(displayName: 'Riley', isMinor: true);
      await profiles.delete(existingProfile.id);
      expect(await profiles.findById(existingProfile.id), isNull);

      final document = _parse(_document(profiles: [
        {
          ..._rawProfile(existingProfile.id, dayEntries: [
            _rawDayEntry(_e1, '2026-01-05'),
          ]),
          // Deliberately different from what's actually stored
          // (isMinor: true) — proves the revival keeps the STORED
          // metadata, never the file's copy of it.
          'isMinor': false,
        },
      ]));

      final plan = await coordinator().buildPlan(document);
      final profilePlan = plan.profiles.single;
      expect(profilePlan.outcome, ProfileImportOutcome.matched);
      expect(profilePlan.restoredFromTombstone, isTrue);
      expect(plan.summary.profilesRestored, 1);
      expect(plan.summary.profilesCreated, 0);

      final summary = await coordinator().apply(plan);
      expect(summary.profilesRestored, 1);

      final revived = await profiles.findById(existingProfile.id);
      expect(revived, isNotNull);
      expect(revived!.isMinor, isTrue,
          reason: 'the stored value survives; the file\'s isMinor: false '
              'is never applied');

      final revivedEntries = await entries.listForProfile(existingProfile.id);
      expect(revivedEntries, hasLength(1),
          reason: "the file's day entry attaches to the un-deleted profile");
    });

    test('a viewer-role guardian blocks revival too, same as it would '
        'block a live matched profile', () async {
      final existingProfile =
          await profiles.create(displayName: 'Shared', isMinor: false);
      await storage.applyRemoteRows([
        RemoteProfileGuardianRow(
          id: 'g2',
          profileId: existingProfile.id,
          userId: 'viewer-user',
          role: 'viewer',
          status: 'accepted',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ]);
      final guardians = DriftProfileGuardiansRepository(storage);
      await profiles.delete(existingProfile.id);

      final document = _parse(_document(profiles: [
        _rawProfile(existingProfile.id, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05'),
        ]),
      ]));

      final plan = await coordinator(
        guardiansForProfile: guardians.getForProfile,
        currentUserId: 'viewer-user',
      ).buildPlan(document);

      expect(plan.profiles.single.outcome, ProfileImportOutcome.skipped);
    });
  });

  group('round trip — export then import into an empty store', () {
    test('produces the same set of profiles, entries, and observations, '
        'preserving the source profile id (Issue #140 review, item 2) and '
        'stamping file-import provenance on new entries', () async {
      final sourceProfile =
          await profiles.create(displayName: 'Riley', isMinor: true);
      await storage.upsertDayEntry(
        profileId: sourceProfile.id,
        localDate: '2026-01-05',
        tz: 'UTC',
        flow: dbtables.FlowLevel.heavy,
        tags: const ['cramps', 'bloating'],
        note: 'felt awful',
      );
      await storage.upsertDayEntry(
        profileId: sourceProfile.id,
        localDate: '2026-01-06',
        tz: 'UTC',
        flow: dbtables.FlowLevel.light,
      );
      final sourceEntries = await entries.listForProfile(sourceProfile.id);
      final entryId = sourceEntries.firstWhere((e) => e.localDate.iso == '2026-01-05').id;
      await storage.upsertObservation(
        dayEntryId: entryId,
        profileId: sourceProfile.id,
        localDate: '2026-01-05',
        tz: 'UTC',
        category: 'pain',
        code: 'cramps',
        intensity: 3,
      );
      await storage.upsertProfileTagRegistryEntry(
        profileId: sourceProfile.id,
        code: 'cramps_severe',
        displayName: 'Severe Cramps',
        category: 'custom',
        updatedAt: DateTime.utc(2026, 1, 1),
      );

      final exportDocument = buildAccountExport(
        profiles: [sourceProfile],
        entriesByProfile: {sourceProfile.id: sourceEntries},
        observationsByProfile: {
          sourceProfile.id: await observations.listForProfile(sourceProfile.id),
        },
        customTagsByProfile: {
          sourceProfile.id: await tagRegistry.listForProfile(sourceProfile.id),
        },
        exportedAt: DateTime.utc(2026, 1, 10),
        appVersion: '1.0.0+1',
      );

      // A fresh, empty store — the target device that never had this data.
      final targetDb = LunarLogDatabase(NativeDatabase.memory());
      addTearDown(() => targetDb.close());
      final targetStorage = LunarLogStorage(targetDb);
      final targetProfiles = DriftProfilesRepository(targetStorage);
      final targetEntries = DriftDayEntriesRepository(targetStorage);
      final targetObservations = DriftObservationsRepository(targetStorage);
      final targetTagRegistry = DriftTagRegistryRepository(targetStorage);
      final targetCoordinator = DriftAccountImportCoordinator(
        profilesRepository: targetProfiles,
        dayEntriesRepository: targetEntries,
        observationsRepository: targetObservations,
        storage: targetStorage,
        tagRegistryRepository: targetTagRegistry,
      );

      final parsed = parseAccountImport(_bytes(exportDocument));
      expect(parsed, isA<AccountImportParsed>());
      final document = (parsed as AccountImportParsed).document;

      final plan = await targetCoordinator.buildPlan(document);
      final summary = await targetCoordinator.apply(plan);

      expect(summary.profilesCreated, 1);
      expect(summary.entriesAdded, 2);
      expect(summary.observationsAdded, 1);
      expect(summary.customTagsAdded, 1);

      final restoredProfile = (await targetProfiles.list()).single;
      expect(restoredProfile.displayName, sourceProfile.displayName);
      expect(restoredProfile.id, sourceProfile.id,
          reason: 'a created profile reuses the file\'s own id (item 2)');

      final restoredEntries = await targetEntries.listForProfile(restoredProfile.id);
      expect(restoredEntries, hasLength(2));
      final restoredHeavy =
          restoredEntries.firstWhere((e) => e.localDate.iso == '2026-01-05');
      expect(restoredHeavy.flow, FlowLevel.heavy);
      // An "add" (no local collision) carries the file's tags verbatim,
      // unlike a merge (which unions and sorts — see the "matched profile"
      // group above).
      expect(restoredHeavy.tags, ['cramps', 'bloating']);
      expect(restoredHeavy.note, 'felt awful');

      final restoredObservations =
          await targetObservations.listForProfile(restoredProfile.id);
      expect(restoredObservations, hasLength(1));
      expect(restoredObservations.single.category, 'pain');
      expect(restoredObservations.single.code, 'cramps');
      expect(restoredObservations.single.intensity, 3);

      final restoredTags =
          await targetTagRegistry.listForProfile(restoredProfile.id);
      expect(restoredTags, hasLength(1));
      expect(restoredTags.single.code, 'cramps_severe');
      expect(restoredTags.single.displayName, 'Severe Cramps');
    });
  });
}

LocalDate _date(String iso) => LocalDate.fromIso(iso);
