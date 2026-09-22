/// Widget tests for CsvExportTile (Issue #469).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/export/csv_export_writer.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/measurement_unit.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/components/inline_error.dart';
import 'package:lunarlog/ui/settings/csv_export_tile.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';

Finder key(String value) => find.byKey(ValueKey(value));

/// Confirms the export-range picker sheet (Issue #115 G3) with whatever
/// preset is already selected — the default, "last 6 cycles", for every test
/// that does not care which range it exports. CSV now opens the same sheet
/// the FHIR/PDF clinical tiles use, so every export-flow test must clear it
/// before a captured export appears.
Future<void> _confirmExportRange(WidgetTester tester) async {
  expect(key('export-range-confirm'), findsOneWidget);
  await tester.tap(key('export-range-confirm'));
  await tester.pumpAndSettle();
}

/// Five single-day episode starts, 40 days apart: the newest is the open
/// cycle; the other four are completed. Fewer than six completed cycles, so
/// the picker's default ("last 6 cycles") has no lower bound and exports
/// every row — a narrower preset necessarily excludes the oldest start.
List<LocalDate> _manyCycleStarts() => [
      for (var i = 0; i < 5; i++) LocalDate(2025, 1, 1).addDays(i * 40),
    ];

List<DayEntry> _manyCyclesEntries(String profileId, List<LocalDate> starts) => [
      for (var i = 0; i < starts.length; i++)
        _entry('many-e$i', profileId, date: starts[i]),
    ];

Profile _profile(
  String id, {
  String displayName = 'Riley',
  DateTime? archivedAt,
  BbtUnit bbtUnit = BbtUnit.celsius,
  WeightUnit weightUnit = WeightUnit.kg,
  bool isMinor = false,
}) =>
    Profile(
      id: id,
      displayName: displayName,
      isMinor: isMinor,
      archivedAt: archivedAt,
      bbtUnit: bbtUnit,
      weightUnit: weightUnit,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

DayEntry _entry(
  String id,
  String profileId, {
  LocalDate? date,
  String? note,
  bool notePrivate = false,
}) =>
    DayEntry(
      id: id,
      profileId: profileId,
      localDate: date ?? LocalDate(2026, 4, 1),
      tz: 'UTC',
      flow: FlowLevel.medium,
      note: note,
      notePrivate: notePrivate,
      updatedAt: DateTime.utc(2026, 4, 1),
    );

ProfileGuardian _guardian(
  String userId, {
  bool isSubject = false,
  GuardianStatus status = GuardianStatus.accepted,
}) =>
    ProfileGuardian(
      id: 'g-$userId',
      profileId: 'p1',
      userId: userId,
      role: GuardianRole.caregiver,
      status: status,
      isSubject: isSubject,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

class FakeProfileGuardiansRepository implements ProfileGuardiansRepository {
  FakeProfileGuardiansRepository(this._byProfile);

  final Map<String, List<ProfileGuardian>> _byProfile;

  @override
  Future<List<ProfileGuardian>> getForProfile(String profileId) async =>
      _byProfile[profileId] ?? const [];

  @override
  Stream<List<ProfileGuardian>> watchForProfile(String profileId) =>
      Stream.value(_byProfile[profileId] ?? const []);
}

/// A signed-in [AuthController] whose [AuthController.currentUserId] is
/// [userId], so the tile resolves a real viewer.
AuthController _signedInAs(String userId) {
  final service = FakeAuthService()
    ..emit(AuthSessionState.signedIn, user: AuthUser(id: userId));
  addTearDown(service.dispose);
  final controller = AuthController(authService: service);
  addTearDown(controller.dispose);
  return controller;
}

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
  final Map<String, StreamController<bool>> _hasEntriesControllers = {};

  @override
  Future<List<DayEntry>> listForProfile(String profileId) async =>
      entriesByProfile[profileId] ?? const [];

  @override
  Future<bool> hasAnyEntries(String profileId) async =>
      (entriesByProfile[profileId] ?? const []).isNotEmpty;

  /// Reactive counterpart of [hasAnyEntries] (issue #642, LLA-010),
  /// independently controllable via [setHasEntries] so a test can push a
  /// change without a real write path — the same bounded, per-profile
  /// existence stream `EntryExistenceWatchMixin` observes.
  @override
  Stream<bool> watchHasAnyEntries(String profileId) async* {
    yield (entriesByProfile[profileId] ?? const []).isNotEmpty;
    yield* _controllerFor(profileId).stream;
  }

  /// Pushes a new existence value for [profileId] — LLA-010's own seam:
  /// changes entry existence with no corresponding `profiles` stream tick,
  /// the exact case the pre-#642 tile derived `hasEntries` from and so
  /// missed.
  void setHasEntries(String profileId, bool value) {
    entriesByProfile = {
      ...entriesByProfile,
      profileId: value ? [_entry('e-$profileId', profileId)] : const [],
    };
    _controllerFor(profileId).add(value);
  }

  StreamController<bool> _controllerFor(String profileId) =>
      _hasEntriesControllers.putIfAbsent(
          profileId, () => StreamController<bool>.broadcast());

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
  CycleExclusionList? cycleExclusions,
  CsvExportCollaborator? exportCsv,
  CsvExportWriter? csvWriter,
  ProfileGuardiansRepository? guardians,
  AuthController? auth,
}) async {
  addTearDown(profiles.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MultiProvider(
        providers: [
          Provider<ProfilesRepository>.value(value: profiles),
          Provider<DayEntriesRepository>.value(
            value: dayEntries ?? FakeDayEntriesRepository(),
          ),
          Provider<ObservationsRepository>.value(
            value: observations ?? FakeObservationsRepository(),
          ),
          // Issue #115 G3: the same seam `lib/app.dart` wires
          // (`Provider<CycleExclusionList>.value`), replacing the tile's
          // former divergent `SettingsStore` read. Only provided when a test
          // needs it — every other test exercises the fail-open path.
          if (cycleExclusions != null)
            Provider<CycleExclusionList>.value(value: cycleExclusions),
          if (guardians != null)
            Provider<ProfileGuardiansRepository>.value(value: guardians),
          if (auth != null)
            ChangeNotifierProvider<AuthController>.value(value: auth),
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
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: CsvExportTile()),
        ),
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

    testWidgets(
        'entry existence is its own bounded stream, independent of the '
        'profiles stream ticking, and the tile stays reactive across an '
        'IndexedStack tab switch (issue #642, LLA-010)', (tester) async {
      final profiles = FakeProfilesRepository([_profile('p1', displayName: 'Riley')]);
      final dayEntries = FakeDayEntriesRepository();
      final activeIndex = ValueNotifier<int>(0);
      addTearDown(profiles.dispose);
      addTearDown(activeIndex.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiProvider(
            providers: [
              Provider<ProfilesRepository>.value(value: profiles),
              Provider<DayEntriesRepository>.value(value: dayEntries),
              Provider<ObservationsRepository>.value(value: FakeObservationsRepository()),
            ],
            child: Scaffold(
              // A real IndexedStack, mirroring the app shell's own retained
              // tabs (`lib/ui/components/app_shell.dart`): every child stays
              // mounted regardless of which index is showing.
              body: ValueListenableBuilder<int>(
                valueListenable: activeIndex,
                builder: (context, index, _) => IndexedStack(
                  index: index,
                  children: const [
                    CsvExportTile(),
                    SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(key('csv-export-tile')).enabled, isFalse);

      // Switch away and back through the IndexedStack — CsvExportTile's
      // State stays mounted the whole time (never rebuilt from scratch).
      activeIndex.value = 1;
      await tester.pump();
      activeIndex.value = 0;
      await tester.pump();

      // Zero -> one, with no `profiles` stream re-emission at all — only
      // the bounded per-profile existence stream. The pre-#642 tile
      // derived `hasEntries` solely from a `profiles` tick and would have
      // stayed disabled here.
      dayEntries.setHasEntries('p1', true);
      await tester.pump();
      expect(tester.widget<ListTile>(key('csv-export-tile')).enabled, isTrue);

      // One -> zero, the same way.
      dayEntries.setHasEntries('p1', false);
      await tester.pump();
      expect(tester.widget<ListTile>(key('csv-export-tile')).enabled, isFalse);
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
      await _confirmExportRange(tester);

      expect(capturedCycles, contains('cycle_number,start_date,end_date'));
      expect(capturedCycles, contains('1,2026-04-01'));
      expect(capturedDailyLog,
          contains('date,flow,pms,tags,pain_intensity,spotting,notes,bbt,bbt_unit,weight,weight_unit'));
      expect(capturedDailyLog, contains('2026-04-01,medium,false,,,false,,,,,'));
    });

    testWidgets(
        "the profile's own display-unit preference reaches the CSV builder "
        '(Issue #612, LLA-093): a pound-display profile normalizes a '
        'kilogram-logged weight row into pounds', (tester) async {
      String? capturedDailyLog;

      final profiles = FakeProfilesRepository([
        _profile('p1', displayName: 'Riley', weightUnit: WeightUnit.lb),
      ]);
      final dayEntries = FakeDayEntriesRepository()
        ..entriesByProfile = {
          'p1': [_entry('e1', 'p1', date: LocalDate(2026, 4, 1))],
        };
      final observations = FakeObservationsRepository()
        ..observationsByProfile = {
          'p1': [
            Observation(
              id: 'o1',
              dayEntryId: 'e1',
              profileId: 'p1',
              localDate: LocalDate(2026, 4, 1),
              tz: 'UTC',
              category: ObservationCategory.weight,
              valueNum: 61.0, // ~134.5 lb
              unit: 'kg',
              updatedAt: DateTime.utc(2026, 4, 1),
            ),
          ],
        };

      await _pump(
        tester,
        profiles: profiles,
        dayEntries: dayEntries,
        observations: observations,
        exportCsv: ({required cyclesCsv, required dailyLogCsv, required exportedAt}) async {
          capturedDailyLog = dailyLogCsv;
        },
      );

      await tester.tap(key('csv-export-tile'));
      await tester.pumpAndSettle();
      await _confirmExportRange(tester);

      final lines = capturedDailyLog!.split('\r\n');
      final fields = lines[1].split(',');
      // bbt, bbt_unit, weight, weight_unit are the last four columns.
      expect(double.parse(fields[9]), closeTo(134.5, 0.1));
      expect(fields[10], 'lb');
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
      await _confirmExportRange(tester);

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
      await _confirmExportRange(tester);

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
      await _confirmExportRange(tester);

      expect(key('csv-export-error'), findsOneWidget);
      expect(find.byType(InlineError), findsOneWidget);
      expect(find.text(AppLocalizationsEn().settingsCsvExportFailure),
            findsOneWidget);
    });
  });

  group('guardian lens & minor gate (Issue #115 G4)', () {
    const privateNote = 'PRIVATE-NOTE-MARKER-9f3a';

    FakeDayEntriesRepository entriesFor(String profileId, {String? note}) =>
        FakeDayEntriesRepository()
          ..entriesByProfile = {
            profileId: [
              _entry('e1', profileId, note: note, notePrivate: note != null),
            ],
          };

    testWidgets(
        'guardian lens: a private note never reaches the CSV builder',
        (tester) async {
      String? capturedDailyLog;
      final profiles =
          FakeProfilesRepository([_profile('p1', displayName: 'Riley')]);
      final guardians = FakeProfileGuardiansRepository({
        'p1': [
          _guardian('subject-user', isSubject: true),
          _guardian('helper-user'),
        ],
      });

      await _pump(
        tester,
        profiles: profiles,
        dayEntries: entriesFor('p1', note: privateNote),
        guardians: guardians,
        auth: _signedInAs('helper-user'),
        exportCsv: ({required cyclesCsv, required dailyLogCsv, required exportedAt}) async {
          capturedDailyLog = dailyLogCsv;
        },
      );

      await tester.tap(key('csv-export-tile'));
      await tester.pumpAndSettle();
      await _confirmExportRange(tester);

      expect(capturedDailyLog, isNotNull);
      expect(capturedDailyLog, isNot(contains(privateNote)));
    });

    testWidgets('subject lens: the same private note is exported in full',
        (tester) async {
      String? capturedDailyLog;
      final profiles =
          FakeProfilesRepository([_profile('p1', displayName: 'Riley')]);
      final guardians = FakeProfileGuardiansRepository({
        'p1': [
          _guardian('subject-user', isSubject: true),
          _guardian('helper-user'),
        ],
      });

      await _pump(
        tester,
        profiles: profiles,
        dayEntries: entriesFor('p1', note: privateNote),
        guardians: guardians,
        auth: _signedInAs('subject-user'),
        exportCsv: ({required cyclesCsv, required dailyLogCsv, required exportedAt}) async {
          capturedDailyLog = dailyLogCsv;
        },
      );

      await tester.tap(key('csv-export-tile'));
      await tester.pumpAndSettle();
      await _confirmExportRange(tester);

      expect(capturedDailyLog, contains(privateNote));
    });

    testWidgets(
        'minor gate: a non-member operator is refused with the not-available '
        'copy and the writer is never called', (tester) async {
      var called = false;
      final profiles = FakeProfilesRepository(
          [_profile('p1', displayName: 'Riley', isMinor: true)]);
      final guardians = FakeProfileGuardiansRepository({
        'p1': [_guardian('parent-user')],
      });

      await _pump(
        tester,
        profiles: profiles,
        dayEntries: entriesFor('p1'),
        guardians: guardians,
        auth: _signedInAs('intruder-user'),
        exportCsv: ({required cyclesCsv, required dailyLogCsv, required exportedAt}) async {
          called = true;
        },
      );

      await tester.tap(key('csv-export-tile'));
      await tester.pumpAndSettle();

      expect(called, isFalse);
      expect(
        find.text(
          "Export is not available for a minor's profile without guardian access.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('minor gate: an accepted guardian may export', (tester) async {
      var called = false;
      final profiles = FakeProfilesRepository(
          [_profile('p1', displayName: 'Riley', isMinor: true)]);
      final guardians = FakeProfileGuardiansRepository({
        'p1': [_guardian('parent-user')],
      });

      await _pump(
        tester,
        profiles: profiles,
        dayEntries: entriesFor('p1'),
        guardians: guardians,
        auth: _signedInAs('parent-user'),
        exportCsv: ({required cyclesCsv, required dailyLogCsv, required exportedAt}) async {
          called = true;
        },
      );

      await tester.tap(key('csv-export-tile'));
      await tester.pumpAndSettle();
      await _confirmExportRange(tester);

      expect(called, isTrue);
      expect(
        find.text(
          "Export is not available for a minor's profile without guardian access.",
        ),
        findsNothing,
      );
    });
  });

  group('date range & shared exclusions (Issue #115 G3)', () {
    testWidgets('the range picker is shown exactly once per export, and a '
        'cancelled picker exports nothing', (tester) async {
      var calls = 0;
      final profiles =
          FakeProfilesRepository([_profile('p1', displayName: 'Riley')]);
      final dayEntries = FakeDayEntriesRepository()
        ..entriesByProfile = {
          'p1': [_entry('e1', 'p1', date: LocalDate(2026, 4, 1))],
        };

      await _pump(
        tester,
        profiles: profiles,
        dayEntries: dayEntries,
        exportCsv: ({required cyclesCsv, required dailyLogCsv, required exportedAt}) async {
          calls++;
        },
      );

      await tester.tap(key('csv-export-tile'));
      await tester.pumpAndSettle();

      // Exactly one sheet, and nothing exported until it is confirmed.
      expect(key('export-range-confirm'), findsOneWidget);
      expect(calls, 0);

      await tester.tap(key('export-range-cancel'));
      await tester.pumpAndSettle();
      expect(key('export-range-confirm'), findsNothing);
      expect(calls, 0);
      // Cancelling is not a failure: no error banner.
      expect(key('csv-export-error'), findsNothing);

      await tester.tap(key('csv-export-tile'));
      await tester.pumpAndSettle();
      await _confirmExportRange(tester);
      expect(calls, 1);
      expect(key('export-range-confirm'), findsNothing,
          reason: 'the picker is shown once per export, not left open');
    });

    testWidgets('a window trims cycles.csv and daily_log.csv to the same '
        'boundary; the "everything" preset stays whole-history',
        (tester) async {
      String? cycles;
      String? dailyLog;
      final starts = _manyCycleStarts();
      final profiles =
          FakeProfilesRepository([_profile('p1', displayName: 'Riley')]);
      final dayEntries = FakeDayEntriesRepository()
        ..entriesByProfile = {'p1': _manyCyclesEntries('p1', starts)};

      await _pump(
        tester,
        profiles: profiles,
        dayEntries: dayEntries,
        exportCsv: ({required cyclesCsv, required dailyLogCsv, required exportedAt}) async {
          cycles = cyclesCsv;
          dailyLog = dailyLogCsv;
        },
      );

      // Default ("last 6 cycles"): only four completed cycles exist, fewer
      // than six, so every row is exported.
      await tester.tap(key('csv-export-tile'));
      await tester.pumpAndSettle();
      await _confirmExportRange(tester);
      expect(cycles, contains(starts.first.iso));
      expect(dailyLog, contains(starts.first.iso));

      // "Last 3 cycles": the oldest start falls outside and must leave BOTH
      // files, while the newest (open) start stays in both.
      cycles = null;
      dailyLog = null;
      await tester.tap(key('csv-export-tile'));
      await tester.pumpAndSettle();
      await tester.tap(key('export-range-preset-last3Cycles'));
      await tester.pumpAndSettle();
      await _confirmExportRange(tester);
      expect(cycles, isNot(contains(starts.first.iso)));
      expect(dailyLog, isNot(contains(starts.first.iso)),
          reason: 'both files trim to the same boundary');
      expect(cycles, contains(starts.last.iso));
      expect(dailyLog, contains(starts.last.iso));

      // The explicit "everything" preset restores the whole-history default.
      cycles = null;
      dailyLog = null;
      await tester.tap(key('csv-export-tile'));
      await tester.pumpAndSettle();
      await tester.tap(key('export-range-preset-everything'));
      await tester.pumpAndSettle();
      await _confirmExportRange(tester);
      expect(cycles, contains(starts.first.iso));
      expect(dailyLog, contains(starts.first.iso));
    });

    testWidgets('an omitted cycle is marked in cycles.csv through the shared '
        'CycleExclusionList (Issue #115 G3 — no SettingsStore read)',
        (tester) async {
      String? cycles;
      final starts = _manyCycleStarts();
      final profiles =
          FakeProfilesRepository([_profile('p1', displayName: 'Riley')]);
      final dayEntries = FakeDayEntriesRepository()
        ..entriesByProfile = {'p1': _manyCyclesEntries('p1', starts)};
      final settings = FakeSettingsStore();
      await settings.set(
        omittedCyclesSettingKey('p1'),
        encodeOmittedCycles({starts[2]}),
      );
      final exclusions = CycleExclusionList(settings);

      await _pump(
        tester,
        profiles: profiles,
        dayEntries: dayEntries,
        cycleExclusions: exclusions,
        exportCsv: ({required cyclesCsv, required dailyLogCsv, required exportedAt}) async {
          cycles = cyclesCsv;
        },
      );

      await tester.tap(key('csv-export-tile'));
      await tester.pumpAndSettle();
      await _confirmExportRange(tester);

      final row = cycles!
          .split('\r\n')
          .firstWhere((line) => line.contains(starts[2].iso));
      expect(row.endsWith(',true'), isTrue,
          reason: 'the shared list must mark the excluded cycle, got: $row');
    });
  });
}
