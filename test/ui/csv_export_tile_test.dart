/// Widget tests for CsvExportTile (Issue #469).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/export/csv_export_writer.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/components/inline_error.dart';
import 'package:lunarlog/ui/settings/csv_export_tile.dart';
import 'package:provider/provider.dart';

Finder key(String value) => find.byKey(ValueKey(value));

Profile _profile(String id, {String displayName = 'Riley', DateTime? archivedAt}) =>
    Profile(
      id: id,
      displayName: displayName,
      isMinor: false,
      archivedAt: archivedAt,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

DayEntry _entry(String id, String profileId, {LocalDate? date}) => DayEntry(
      id: id,
      profileId: profileId,
      localDate: date ?? LocalDate(2026, 4, 1),
      tz: 'UTC',
      flow: FlowLevel.medium,
      updatedAt: DateTime.utc(2026, 4, 1),
    );

class FakeProfilesRepository implements ProfilesRepository {
  FakeProfilesRepository([List<Profile> initial = const []]) : _profiles = initial;

  List<Profile> _profiles;
  final _controller = StreamController<List<Profile>>.broadcast();

  void setProfiles(List<Profile> profiles) {
    _profiles = profiles;
    _controller.add(profiles);
  }

  @override
  Future<List<Profile>> list() async => _profiles;

  @override
  Stream<List<Profile>> watch() async* {
    yield _profiles;
    yield* _controller.stream;
  }

  void dispose() => unawaited(_controller.close());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDayEntriesRepository implements DayEntriesRepository {
  Map<String, List<DayEntry>> entriesByProfile = const {};

  @override
  Future<List<DayEntry>> listForProfile(String profileId) async =>
      entriesByProfile[profileId] ?? const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeObservationsRepository implements ObservationsRepository {
  Map<String, List<Observation>> observationsByProfile = const {};

  @override
  Future<List<Observation>> listForProfile(String profileId) async =>
      observationsByProfile[profileId] ?? const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsStore implements SettingsStore {
  final Map<String, String> _store = {};

  @override
  Future<String?> get(String key) async => _store[key];

  @override
  Future<void> set(String key, String value) async {
    _store[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCsvExportWriter implements CsvExportWriter {
  bool called = false;
  String? cycles;
  String? dailyLog;

  @override
  Future<void> exportAndShare({
    required String cyclesCsv,
    required String dailyLogCsv,
    required DateTime exportedAt,
  }) async {
    called = true;
    cycles = cyclesCsv;
    dailyLog = dailyLogCsv;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required FakeProfilesRepository profiles,
  FakeDayEntriesRepository? dayEntries,
  FakeObservationsRepository? observations,
  FakeSettingsStore? settingsStore,
  CsvExportCollaborator? exportCsv,
  CsvExportWriter? csvWriter,
}) async {
  addTearDown(profiles.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: MultiProvider(
        providers: [
          Provider<ProfilesRepository>.value(value: profiles),
          Provider<DayEntriesRepository>.value(
            value: dayEntries ?? FakeDayEntriesRepository(),
          ),
          Provider<ObservationsRepository>.value(
            value: observations ?? FakeObservationsRepository(),
          ),
          Provider<SettingsStore>.value(
            value: settingsStore ?? FakeSettingsStore(),
          ),
          if (csvWriter != null) Provider<CsvExportWriter>.value(value: csvWriter),
        ],
        child: Scaffold(
          body: CsvExportTile(exportCsv: exportCsv),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('reachability & subtitles', () {
    testWidgets('no profiles: tile is absent', (tester) async {
      final profiles = FakeProfilesRepository(const []);
      await _pump(tester, profiles: profiles);
      expect(key('csv-export-tile'), findsNothing);
    });

    testWidgets('no ProfilesRepository provided: tile is absent', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: CsvExportTile())),
      );
      await tester.pumpAndSettle();
      expect(key('csv-export-tile'), findsNothing);
    });

    testWidgets('single profile with no entries: tile renders disabled with prompt', (tester) async {
      final profiles = FakeProfilesRepository([_profile('p1', displayName: 'Riley')]);
      await _pump(tester, profiles: profiles);

      expect(key('csv-export-tile'), findsOneWidget);
      final tile = tester.widget<ListTile>(key('csv-export-tile'));
      expect(tile.enabled, isFalse);
      expect(
        find.text('Add at least one day entry to export CSV tables.'),
        findsOneWidget,
      );
    });

    testWidgets('single profile with entries: tile renders enabled with single-profile subtitle', (tester) async {
      final profiles = FakeProfilesRepository([_profile('p1', displayName: 'Riley')]);
      final dayEntries = FakeDayEntriesRepository()
        ..entriesByProfile = {
          'p1': [_entry('e1', 'p1')],
        };
      await _pump(tester, profiles: profiles, dayEntries: dayEntries);

      expect(key('csv-export-tile'), findsOneWidget);
      final tile = tester.widget<ListTile>(key('csv-export-tile'));
      expect(tile.enabled, isTrue);
      expect(
        find.text("Export Riley's cycle data as spreadsheet-compatible CSV files."),
        findsOneWidget,
      );
    });

    testWidgets('multiple profiles with entries: tile renders with multi-profile subtitle', (tester) async {
      final profiles = FakeProfilesRepository([
        _profile('p1', displayName: 'Riley'),
        _profile('p2', displayName: 'Alex'),
      ]);
      final dayEntries = FakeDayEntriesRepository()
        ..entriesByProfile = {
          'p1': [_entry('e1', 'p1')],
        };
      await _pump(tester, profiles: profiles, dayEntries: dayEntries);

      expect(key('csv-export-tile'), findsOneWidget);
      final tile = tester.widget<ListTile>(key('csv-export-tile'));
      expect(tile.enabled, isTrue);
      expect(
        find.text('Export your cycles and daily log as spreadsheet-compatible CSV files.'),
        findsOneWidget,
      );
    });

    testWidgets('profile arriving reactively makes tile appear', (tester) async {
      final profiles = FakeProfilesRepository(const []);
      await _pump(tester, profiles: profiles);
      expect(key('csv-export-tile'), findsNothing);

      profiles.setProfiles([_profile('p1')]);
      await tester.pumpAndSettle();
      expect(key('csv-export-tile'), findsOneWidget);
    });
  });

  group('export flow', () {
    testWidgets('single profile: tapping invokes export collaborator directly', (tester) async {
      String? capturedCycles;
      String? capturedDailyLog;

      final profiles = FakeProfilesRepository([_profile('p1', displayName: 'Riley')]);
      final dayEntries = FakeDayEntriesRepository()
        ..entriesByProfile = {
          'p1': [_entry('e1', 'p1', date: LocalDate(2026, 4, 1))],
        };

      await _pump(
        tester,
        profiles: profiles,
        dayEntries: dayEntries,
        exportCsv: ({required cyclesCsv, required dailyLogCsv, required exportedAt}) async {
          capturedCycles = cyclesCsv;
          capturedDailyLog = dailyLogCsv;
        },
      );

      await tester.tap(key('csv-export-tile'));
      await tester.pumpAndSettle();

      expect(capturedCycles, contains('cycle_number,start_date,end_date'));
      expect(capturedCycles, contains('1,2026-04-01'));
      expect(capturedDailyLog, contains('date,flow,pms,tags,pain_intensity,spotting,notes,bbt,weight'));
      expect(capturedDailyLog, contains('2026-04-01,medium,false,,,false,,,'));
    });

    testWidgets('single profile: uses CsvExportWriter when no collaborator injected', (tester) async {
      final profiles = FakeProfilesRepository([_profile('p1', displayName: 'Riley')]);
      final dayEntries = FakeDayEntriesRepository()
        ..entriesByProfile = {
          'p1': [_entry('e1', 'p1')],
        };
      final writer = FakeCsvExportWriter();

      await _pump(
        tester,
        profiles: profiles,
        dayEntries: dayEntries,
        csvWriter: writer,
      );

      await tester.tap(key('csv-export-tile'));
      await tester.pumpAndSettle();

      expect(writer.called, isTrue);
      expect(writer.cycles, contains('cycle_number'));
      expect(writer.dailyLog, contains('date,flow'));
    });

    testWidgets('multiple profiles: tapping displays dialog and exports chosen profile', (tester) async {
      String? capturedCycles;
      final profiles = FakeProfilesRepository([
        _profile('p1', displayName: 'Riley'),
        _profile('p2', displayName: 'Morgan'),
      ]);
      final dayEntries = FakeDayEntriesRepository()
        ..entriesByProfile = {
          'p1': [_entry('e1', 'p1', date: LocalDate(2026, 3, 1))],
          'p2': [_entry('e2', 'p2', date: LocalDate(2026, 4, 15))],
        };

      await _pump(
        tester,
        profiles: profiles,
        dayEntries: dayEntries,
        exportCsv: ({required cyclesCsv, required dailyLogCsv, required exportedAt}) async {
          capturedCycles = cyclesCsv;
        },
      );

      await tester.tap(key('csv-export-tile'));
      await tester.pumpAndSettle();

      // Dialog opens with options for both
      expect(find.text('Export CSV data for'), findsOneWidget);
      expect(key('csv-export-profile-p1'), findsOneWidget);
      expect(key('csv-export-profile-p2'), findsOneWidget);

      // Select Morgan
      await tester.tap(key('csv-export-profile-p2'));
      await tester.pumpAndSettle();

      expect(capturedCycles, contains('1,2026-04-15'));
      expect(capturedCycles, isNot(contains('2026-03-01')));
    });

    testWidgets('error displays inline error banner', (tester) async {
      final profiles = FakeProfilesRepository([_profile('p1', displayName: 'Riley')]);
      final dayEntries = FakeDayEntriesRepository()
        ..entriesByProfile = {
          'p1': [_entry('e1', 'p1')],
        };

      await _pump(
        tester,
        profiles: profiles,
        dayEntries: dayEntries,
        exportCsv: ({required cyclesCsv, required dailyLogCsv, required exportedAt}) async {
          throw Exception('Disk full');
        },
      );

      await tester.tap(key('csv-export-tile'));
      await tester.pumpAndSettle();

      expect(key('csv-export-error'), findsOneWidget);
      expect(find.byType(InlineError), findsOneWidget);
      expect(find.text(kCsvExportFailureCopy), findsOneWidget);
    });
  });
}
