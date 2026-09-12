/// Tests for `lib/data/import/clue_importer.dart` (Issue #199) against a
/// real in-memory Drift store (mirrors
/// `test/data/import/account_importer_test.dart`'s setup):
/// * the `unknown_type_and_option.json` fixture imports end to end — an
///   unmapped `type` (hot_flashes) and an unmapped `option`
///   (mystery_symptom) are stored, never dropped, with `raw` carrying the
///   full original datapoint;
/// * re-importing the same bytes is a no-op via the checksum-derived
///   `source`/`source_id` (no new rows, nothing rewritten);
/// * `period` levels land on the day entry's `flow` (highest wins);
/// * a manually logged day keeps its flow/tags/note against an import;
/// * unknown tag codes and observation options write fine at the storage
///   layer, while `validateTagCodes` stays the UI-only validator.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' hide Profile;
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart' as dbtables show FlowLevel;
import 'package:lunarlog/data/import/clue_importer.dart';
import 'package:lunarlog/domain/import/clue/clue_export_parser.dart';
import 'package:lunarlog/domain/import/clue/clue_import_run.dart';
import 'package:lunarlog/domain/tags.dart';

List<int> _fixtureBytes(String name) =>
    File('test/fixtures/clue/$name').readAsBytesSync();

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late LunarLogStorage storage;
  late ClueImporter importer;

  setUp(() {
    db = LunarLogDatabase(NativeDatabase.memory());
    storage = LunarLogStorage(db);
    importer = ClueImporter(storage);
  });

  tearDown(() => db.close());

  Future<String> profileId() async {
    final profile = await storage.upsertProfile(
      id: '01K1TESTPROFILE000000000001',
      displayName: 'Riley',
      isMinor: false,
    );
    return profile.id;
  }

  Future<ClueImportSummary> runFixture(String pid, String name) {
    final bytes = _fixtureBytes(name);
    return importer.run(
      profileId: pid,
      tz: 'UTC',
      parseResult: parseClueDatapoints(bytes),
      fileChecksum: clueFileChecksum(bytes),
    );
  }

  group('ClueImporter.run — escape hatch end to end', () {
    test('fixture with unmapped type and option: stored, never dropped',
        () async {
      final pid = await profileId();
      final summary = await runFixture(pid, 'unknown_type_and_option.json');

      expect(summary.unmappedTypeCount, 1);
      expect(summary.unmappedTypes, ['hot_flashes']);
      expect(summary.unmappedValueCount, 4);
      expect(summary.rowsSkipped, 0);
      expect(summary.daysWritten, 7);
      expect(summary.observationsWritten, 8);

      final observations = await storage.getObservationsForProfile(pid);
      expect(observations.length, 8);

      // The unmapped option rides `code` verbatim (pass-through, #240).
      final mystery =
          observations.where((o) => o.code == 'mystery_symptom');
      expect(mystery.length, 1);
      expect(mystery.single.category, 'pain');
      expect(mystery.single.raw, isNull);

      // The unmapped types ride `raw` with the full original datapoint:
      // hot_flashes (unknown type) and period/extreme (unknown value).
      final unmapped =
          observations.where((o) => o.category == 'unmapped');
      expect(unmapped.length, 2);
      final hotFlashes =
          unmapped.where((o) => o.code == 'hot_flashes');
      expect(hotFlashes.length, 1);
      final raw =
          jsonDecode(hotFlashes.single.raw!) as Map<String, Object?>;
      expect(raw['date'], '2026-04-01');
      expect(raw['type'], 'hot_flashes');
      expect((raw['value'] as Map)['option'], 'moderate');

      // Every written row carries the import provenance.
      for (final o in observations) {
        expect(o.source, 'clue_import');
        expect(o.sourceId, startsWith('clue:'));
      }
      final days = await storage.getDayEntries(profileId: pid);
      expect(days.length, 7);
      for (final day in days) {
        expect(day.source, 'clue_import');
        expect(day.sourceId, startsWith('clue:'));
      }
    });

    test('re-importing the same file is a no-op', () async {
      final pid = await profileId();
      final first = await runFixture(pid, 'unknown_type_and_option.json');
      expect(first.isNoop, isFalse);

      final second = await runFixture(pid, 'unknown_type_and_option.json');
      expect(second.isNoop, isTrue);
      expect(second.daysWritten, 0);
      expect(second.observationsWritten, 0);
      expect(second.daysUnchanged, 7);
      expect(second.observationsUnchanged, 8);

      expect(
        (await storage.getDayEntries(profileId: pid)).length,
        7,
      );
      expect(
        (await storage.getObservationsForProfile(pid)).length,
        8,
      );
    });

    test('a different file does not collapse onto the first', () async {
      final pid = await profileId();
      await runFixture(pid, 'unknown_type_and_option.json');
      final other = await runFixture(pid, 'mapping_table.json');
      expect(other.isNoop, isFalse);
      expect(other.daysWritten, greaterThan(0));
    });

    test('period levels land on flow, highest wins per day', () async {
      final pid = await profileId();
      final bytes = utf8.encode(jsonEncode([
        {'date': '2026-05-01', 'type': 'period', 'value': {'option': 'light'}},
        {'date': '2026-05-02', 'type': 'period', 'value': {'option': 'heavy'}},
        {
          'date': '2026-05-02',
          'type': 'period',
          'value': {'option': 'medium'}
        },
        {'date': '2026-05-03', 'type': 'period', 'value': {'option': 'none'}},
      ]));
      final summary = await importer.run(
        profileId: pid,
        tz: 'UTC',
        parseResult: parseClueDatapoints(bytes),
        fileChecksum: clueFileChecksum(bytes),
      );
      expect(summary.rowsSkipped, 0);
      final days = await storage.getDayEntries(profileId: pid);
      final byDate = {for (final d in days) d.localDate: d};
      expect(byDate['2026-05-01']!.flow, dbtables.FlowLevel.light);
      // Same-day duplicate: heavy beats medium.
      expect(byDate['2026-05-02']!.flow, dbtables.FlowLevel.heavy);
      // An explicit "not bleeding" assertion is kept, never read as unlogged.
      expect(byDate['2026-05-03']!.flow, dbtables.FlowLevel.notBleeding);
    });

    test('a manually logged day is never downgraded by an import', () async {
      final pid = await profileId();
      await storage.upsertDayEntry(
        profileId: pid,
        localDate: '2026-06-01',
        tz: 'UTC',
        flow: dbtables.FlowLevel.heavy,
        tags: const ['cramps'],
        note: 'kept',
      );
      final bytes = utf8.encode(jsonEncode([
        {'date': '2026-06-01', 'type': 'period', 'value': {'option': 'light'}},
      ]));
      await importer.run(
        profileId: pid,
        tz: 'UTC',
        parseResult: parseClueDatapoints(bytes),
        fileChecksum: clueFileChecksum(bytes),
      );
      final day =
          await storage.getDayEntry(profileId: pid, localDate: '2026-06-01');
      expect(day!.flow, dbtables.FlowLevel.heavy);
      expect(day.tags, ['cramps']);
      expect(day.note, 'kept');
      // The day still belongs to the manual row, not the import.
      expect(day.source, 'manual');
    });

    test('an unlogged manual date gains the imported flow', () async {
      final pid = await profileId();
      await storage.upsertDayEntry(
        profileId: pid,
        localDate: '2026-06-02',
        tz: 'UTC',
        flow: dbtables.FlowLevel.none,
        note: 'kept',
      );
      final bytes = utf8.encode(jsonEncode([
        {'date': '2026-06-02', 'type': 'period', 'value': {'option': 'medium'}},
      ]));
      await importer.run(
        profileId: pid,
        tz: 'UTC',
        parseResult: parseClueDatapoints(bytes),
        fileChecksum: clueFileChecksum(bytes),
      );
      final day =
          await storage.getDayEntry(profileId: pid, localDate: '2026-06-02');
      expect(day!.flow, dbtables.FlowLevel.medium);
      expect(day.note, 'kept');
    });

    test('numeric datapoints land on bbt with unit and exclusion', () async {      final pid = await profileId();
      final bytes = utf8.encode(jsonEncode([
        {
          'date': '2026-07-01',
          'type': 'bbt',
          'value': {'celsius': 36.6, 'excluded': true}
        },
      ]));
      await importer.run(
        profileId: pid,
        tz: 'UTC',
        parseResult: parseClueDatapoints(bytes),
        fileChecksum: clueFileChecksum(bytes),
      );
      final observations = await storage.getObservationsForProfile(pid);
      expect(observations.length, 1);
      expect(observations.single.category, 'bbt');
      expect(observations.single.valueNum, 36.6);
      expect(observations.single.unit, 'celsius');
      expect(observations.single.excluded, isTrue);
    });

    test('deleting a day then re-importing revives it', () async {
      final pid = await profileId();
      await runFixture(pid, 'unknown_type_and_option.json');
      await storage.softDeleteDayEntry(
        profileId: pid,
        localDate: '2026-04-01',
      );
      final second = await runFixture(pid, 'unknown_type_and_option.json');
      expect(second.isNoop, isFalse);
      expect(second.daysWritten, 1);
      expect(second.daysUnchanged, 6);
      final day =
          await storage.getDayEntry(profileId: pid, localDate: '2026-04-01');
      expect(day, isNotNull);
      expect(day!.deletedAt, isNull);
    });

    test('an oversized datapoint is skipped and counted, never silent',
        () async {
      final pid = await profileId();
      final bytes = utf8.encode(jsonEncode([
        {
          // A type string so long the datapoint fits `raw` neither whole
          // nor reduced to its identifying subset: unkeepable, so skipped
          // and counted rather than dropped silently.
          'date': '2026-09-01',
          'type': 't' * 9000,
          'value': {'text': 'x' * 9000}
        },
        {
          'date': '2026-09-02',
          'type': 'pain',
          'value': {'option': 'headache'}
        },
      ]));
      final summary = await importer.run(
        profileId: pid,
        tz: 'UTC',
        parseResult: parseClueDatapoints(bytes),
        fileChecksum: clueFileChecksum(bytes),
      );
      // The giant row cannot fit `raw` even reduced; the small row lands.
      expect(summary.rowsSkipped, 1);
      expect(summary.skippedDetails.length, 1);
      expect(summary.observationsWritten, 1);
      expect(summary.notesDetected, isTrue);
      final observations = await storage.getObservationsForProfile(pid);
      expect(observations.length, 1);
      expect(observations.single.code, 'headache');
    });
  });

  group('write path accepts the unknown (AC7 layers)', () {
    test('storage accepts unknown tag codes and observation options',
        () async {
      final pid = await profileId();
      final day = await storage.upsertDayEntry(
        profileId: pid,
        localDate: '2026-08-01',
        tz: 'UTC',
        flow: dbtables.FlowLevel.none,
        tags: const ['mystery_symptom', 'cramps'],
      );
      expect(day.tags, contains('mystery_symptom'));
      final observation = await storage.upsertObservation(
        dayEntryId: day.id,
        profileId: pid,
        localDate: '2026-08-01',
        tz: 'UTC',
        category: 'hot_flashes',
        code: 'moderate',
        raw: '{"date":"2026-08-01","type":"hot_flashes"}',
      );
      expect(observation.code, 'moderate');
      expect(observation.raw, contains('hot_flashes'));
    });

    test('validateTagCodes stays the UI-only validator (never the write path)',
        () async {
      expect(() => validateTagCodes(['cramps']), returnsNormally);
      expect(
        () => validateTagCodes(['mystery_symptom']),
        throwsArgumentError,
      );
    });
  });
}
