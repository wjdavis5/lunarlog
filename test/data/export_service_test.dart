/// U1 (R13): the export service builds CSV, PDF, and JSON for the selected
/// profile through the share sheet over a real seeded database, and deletes
/// its temp files on completion, cancellation, AND failure.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/export/export_service.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/domain/models/day_entry.dart' as domain;
import 'package:lunarlog/domain/models/flow_level.dart' as domain;
import 'package:lunarlog/domain/models/local_date.dart' as domain;
import 'package:share_plus/share_plus.dart';

Future<String> _seed(LunarLogDatabase db) async {
  final profiles = DriftProfilesRepository(db.storage);
  final entries = DriftDayEntriesRepository(db.storage);
  final profile =
      await profiles.create(displayName: 'Alex', isMinor: false);
  Future<void> save(
    String date,
    String tz,
    domain.FlowLevel flow, {
    List<String> tags = const [],
    String? note,
  }) =>
      entries.save(domain.DayEntry(
        id: '',
        profileId: profile.id,
        localDate: domain.LocalDate.fromIso(date),
        tz: tz,
        flow: flow,
        tags: tags,
        note: note,
        updatedAt: DateTime.utc(2026, 9, 1),
      ));
  await save('2026-07-01', 'America/New_York', domain.FlowLevel.medium,
      tags: ['cramps'], note: 'first note');
  await save('2026-07-29', 'Europe/Berlin', domain.FlowLevel.light,
      tags: ['headache']);
  await entries.delete(profile.id, domain.LocalDate.fromIso('2026-07-29'));
  return profile.id;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('ExportService', () {
    test('shares CSV, PDF, and JSON matching the seeded profile', () async {
      final db = LunarLogDatabase(NativeDatabase.memory());
      final profileId = await _seed(db);
      final staging =
          await Directory.systemTemp.createTemp('lunarlog-export-test');
      final shared = <XFile>[];
      final service = ExportService(
        profiles: DriftProfilesRepository(db.storage),
        dayEntries: DriftDayEntriesRepository(db.storage),
        tempDirectory: () async => staging,
        shareFiles: (files, {subject}) async => shared.addAll(files),
        clock: () => DateTime.utc(2026, 9, 4, 12),
      );
      try {
        await service.exportProfile(profileId);

        expect(shared.length, 3);
        final byExt = {
          for (final file in shared)
            file.path.split('.').last: await File(file.path).exists(),
        };
        // Files are deleted right after the share returns.
        expect(byExt.values, everyElement(isFalse));

        final csv = shared.firstWhere((f) => f.path.endsWith('.csv'));
        expect(csv.path, contains('lunarlog-export-2026-09-04'));
        // Re-read before deletion: share a second time through a recorder
        // that keeps the bytes instead.
        String? csvText;
        Map<String, Object?>? envelope;
        final capture = ExportService(
          profiles: DriftProfilesRepository(db.storage),
          dayEntries: DriftDayEntriesRepository(db.storage),
          tempDirectory: () async => staging,
          shareFiles: (files, {subject}) async {
            for (final file in files) {
              if (file.path.endsWith('.csv')) {
                csvText = await File(file.path).readAsString();
              }
              if (file.path.endsWith('.json')) {
                envelope = jsonDecode(
                  await File(file.path).readAsString(),
                ) as Map<String, Object?>;
              }
            }
          },
          clock: () => DateTime.utc(2026, 9, 4, 12),
        );
        await capture.exportProfile(profileId);
        final rows =
            const LineSplitter().convert(csvText ?? '').toList();
        expect(rows.first, 'date,timezone,flow,tags,note');
        // The tombstoned 2026-07-29 entry is excluded: one live row remains.
        expect(rows.length, 2);
        expect(rows[1], contains('2026-07-01'));
        expect(rows[1], contains('America/New_York'));
        expect(rows[1], contains('first note'));
        expect(csvText, isNot(contains('2026-07-29')));
        final entries = envelope!['entries'] as List<Object?>;
        expect(entries.length, 1);
        expect(
          (envelope!['profile'] as Map<String, Object?>)['display_name'],
          'Alex',
        );
      } finally {
        await db.close();
        await staging.delete(recursive: true);
      }
    });

    test('a failing share still deletes the temp files', () async {
      final db = LunarLogDatabase(NativeDatabase.memory());
      final profileId = await _seed(db);
      final staging =
          await Directory.systemTemp.createTemp('lunarlog-export-test');
      final service = ExportService(
        profiles: DriftProfilesRepository(db.storage),
        dayEntries: DriftDayEntriesRepository(db.storage),
        tempDirectory: () async => staging,
        shareFiles: (files, {subject}) async =>
            throw Exception('sheet dismissed'),
      );
      try {
        await expectLater(
          service.exportProfile(profileId),
          throwsA(const ExportError.shareFailed()),
        );
        expect(await staging.list().toList(), isEmpty,
            reason: 'no orphaned temp files after a share failure');
      } finally {
        await db.close();
        await staging.delete(recursive: true);
      }
    });

    test('unknown profile shares nothing', () async {
      final db = LunarLogDatabase(NativeDatabase.memory());
      var shared = false;
      final service = ExportService(
        profiles: DriftProfilesRepository(db.storage),
        dayEntries: DriftDayEntriesRepository(db.storage),
        tempDirectory: () async => Directory.systemTemp,
        shareFiles: (files, {subject}) async => shared = true,
      );
      try {
        await expectLater(
          service.exportProfile('01J0000000000000000000000Z'),
          throwsA(const ExportError.noProfile()),
        );
        expect(shared, isFalse);
      } finally {
        await db.close();
      }
    });
  });
}
