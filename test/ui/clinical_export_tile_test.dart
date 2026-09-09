/// Widget tests for the "Export clinical summary (FHIR)" tile (Issue
/// #157). Every collaborator is a fake (KTD6): the profiles/day-entries/
/// observations repositories and the FHIR export collaborator never touch
/// drift, `path_provider`, or `share_plus`. Fakes mirror
/// `test/ui/your_data_section_test.dart`'s own.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/ui/components/inline_error.dart';
import 'package:lunarlog/ui/settings/clinical_export_tile.dart';
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

DayEntry _entry(String id, String profileId) => DayEntry(
      id: id,
      profileId: profileId,
      localDate: LocalDate(2026, 4, 1),
      tz: 'UTC',
      flow: FlowLevel.medium,
      updatedAt: DateTime.utc(2026, 4, 1),
    );

class FakeProfilesRepository implements ProfilesRepository {
  FakeProfilesRepository([List<Profile> initial = const []])
      : _profiles = initial;

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

Future<void> _pump(
  WidgetTester tester, {
  required FakeProfilesRepository profiles,
  FakeDayEntriesRepository? dayEntries,
  FakeObservationsRepository? observations,
  FhirExportCollaborator? exportFhir,
}) async {
  addTearDown(profiles.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: MultiProvider(
        providers: [
          Provider<ProfilesRepository>.value(value: profiles),
          Provider<DayEntriesRepository>.value(
              value: dayEntries ?? FakeDayEntriesRepository()),
          Provider<ObservationsRepository>.value(
              value: observations ?? FakeObservationsRepository()),
        ],
        child: Scaffold(
          body: ClinicalExportTile(exportFhir: exportFhir),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('reachability', () {
    testWidgets('no profiles: the tile is absent', (tester) async {
      final profiles = FakeProfilesRepository(const []);
      await _pump(tester, profiles: profiles);
      expect(key('clinical-export-fhir'), findsNothing);
    });

    testWidgets(
        'no ProfilesRepository provided at all: the tile is absent, same '
        'as no profiles', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ClinicalExportTile())),
      );
      await tester.pumpAndSettle();
      expect(key('clinical-export-fhir'), findsNothing);
    });

    testWidgets('a profile with no entries: the tile renders disabled with '
        'a reason', (tester) async {
      final profiles = FakeProfilesRepository([_profile('p1')]);
      await _pump(tester, profiles: profiles);

      expect(key('clinical-export-fhir'), findsOneWidget);
      final tile = tester.widget<ListTile>(key('clinical-export-fhir'));
      expect(tile.enabled, isFalse);
      expect(
        find.text('Add at least one day entry to export a clinical '
            'summary.'),
        findsOneWidget,
      );
    });

    testWidgets('a profile with entries: the tile renders enabled',
        (tester) async {
      final profiles = FakeProfilesRepository([_profile('p1')]);
      final dayEntries = FakeDayEntriesRepository()
        ..entriesByProfile = {
          'p1': [_entry('e1', 'p1')],
        };
      await _pump(tester, profiles: profiles, dayEntries: dayEntries);

      expect(key('clinical-export-fhir'), findsOneWidget);
      final tile = tester.widget<ListTile>(key('clinical-export-fhir'));
      expect(tile.enabled, isTrue);
    });

    testWidgets('a profile arriving after first build makes the tile '
        'appear reactively', (tester) async {
      final profiles = FakeProfilesRepository(const []);
      await _pump(tester, profiles: profiles);
      expect(key('clinical-export-fhir'), findsNothing);

      profiles.setProfiles([_profile('p1')]);
      await tester.pumpAndSettle();
      expect(key('clinical-export-fhir'), findsOneWidget);
    });
  });

  group('profile selection (#157 review fix)', () {
    Map<String, Object?>? patientOf(Map<String, Object?> bundle) {
      final entries = (bundle['entry'] as List).cast<Map>();
      final patient = entries
          .map((e) => e['resource'] as Map)
          .firstWhere((r) => r['resourceType'] == 'Patient');
      return patient.cast<String, Object?>();
    }

    testWidgets(
        'an archived profile is excluded: a single live profile still '
        'counts as "exactly one" and the archived one is never exported',
        (tester) async {
      Map<String, Object?>? capturedBundle;
      final profiles = FakeProfilesRepository([
        _profile('p1', displayName: 'Riley'),
        _profile('p2',
            displayName: 'Old Profile', archivedAt: DateTime.utc(2026, 2, 1)),
      ]);
      final dayEntries = FakeDayEntriesRepository()
        ..entriesByProfile = {
          'p1': [_entry('e1', 'p1')],
        };
      await _pump(
        tester,
        profiles: profiles,
        dayEntries: dayEntries,
        exportFhir: ({required bundle, required exportedAt}) async {
          capturedBundle = bundle;
        },
      );

      expect(
        find.text("Export Riley's clinical summary."),
        findsOneWidget,
        reason: 'the archived profile must not count toward "several"',
      );

      await tester.tap(key('clinical-export-fhir'));
      await tester.pumpAndSettle();

      // No chooser dialog for a single live profile.
      expect(find.byType(SimpleDialog), findsNothing);
      expect(capturedBundle, isNotNull);
      expect((patientOf(capturedBundle!)!['name'] as List).single,
          {'text': 'Riley'});
    });

    testWidgets('a single live profile: the subtitle names it', (tester) async {
      final profiles = FakeProfilesRepository([_profile('p1', displayName: 'Riley')]);
      final dayEntries = FakeDayEntriesRepository()
        ..entriesByProfile = {
          'p1': [_entry('e1', 'p1')],
        };
      await _pump(tester, profiles: profiles, dayEntries: dayEntries);

      expect(find.text("Export Riley's clinical summary."), findsOneWidget);
    });

    testWidgets(
        'several live profiles: tapping shows a chooser, and picking one '
        'exports that profile',
        (tester) async {
      Map<String, Object?>? capturedBundle;
      final profiles = FakeProfilesRepository([
        _profile('p1', displayName: 'Riley'),
        _profile('p2', displayName: 'Jamie'),
      ]);
      final dayEntries = FakeDayEntriesRepository()
        ..entriesByProfile = {
          'p1': [_entry('e1', 'p1')],
        };
      await _pump(
        tester,
        profiles: profiles,
        dayEntries: dayEntries,
        exportFhir: ({required bundle, required exportedAt}) async {
          capturedBundle = bundle;
        },
      );

      // Generic subtitle, no single name, since the tile can't yet know
      // which profile will be chosen.
      expect(find.text("Export Riley's clinical summary."), findsNothing);
      expect(find.text("Export Jamie's clinical summary."), findsNothing);

      await tester.tap(key('clinical-export-fhir'));
      await tester.pumpAndSettle();

      expect(find.byType(SimpleDialog), findsOneWidget);
      expect(find.text('Riley'), findsOneWidget);
      expect(find.text('Jamie'), findsOneWidget);

      await tester.tap(key('clinical-export-fhir-profile-p2'));
      await tester.pumpAndSettle();

      expect(capturedBundle, isNotNull);
      expect((patientOf(capturedBundle!)!['name'] as List).single,
          {'text': 'Jamie'});
    });
  });

  group('export', () {
    testWidgets('tapping the enabled tile builds a Bundle and hands it to '
        'the export collaborator', (tester) async {
      Map<String, Object?>? capturedBundle;
      final profiles = FakeProfilesRepository([_profile('p1')]);
      final dayEntries = FakeDayEntriesRepository()
        ..entriesByProfile = {
          'p1': [_entry('e1', 'p1')],
        };
      await _pump(
        tester,
        profiles: profiles,
        dayEntries: dayEntries,
        exportFhir: ({required bundle, required exportedAt}) async {
          capturedBundle = bundle;
        },
      );

      await tester.tap(key('clinical-export-fhir'));
      await tester.pumpAndSettle();

      expect(capturedBundle, isNotNull);
      expect(capturedBundle!['resourceType'], 'Bundle');
      expect(capturedBundle!['type'], 'document');
      expect(key('clinical-export-fhir-error'), findsNothing);
    });

    testWidgets('a failed export surfaces copy, not an exception',
        (tester) async {
      final profiles = FakeProfilesRepository([_profile('p1')]);
      final dayEntries = FakeDayEntriesRepository()
        ..entriesByProfile = {
          'p1': [_entry('e1', 'p1')],
        };
      await _pump(
        tester,
        profiles: profiles,
        dayEntries: dayEntries,
        exportFhir: ({required bundle, required exportedAt}) async {
          throw StateError('disk full');
        },
      );

      await tester.tap(key('clinical-export-fhir'));
      await tester.pumpAndSettle();

      expect(key('clinical-export-fhir-error'), findsOneWidget);
      expect(
        tester.widget<InlineError>(key('clinical-export-fhir-error')).message,
        kClinicalExportFailureCopy,
      );
    });

    testWidgets('tapping a disabled tile (no entries) does nothing',
        (tester) async {
      var calls = 0;
      final profiles = FakeProfilesRepository([_profile('p1')]);
      await _pump(
        tester,
        profiles: profiles,
        exportFhir: ({required bundle, required exportedAt}) async {
          calls++;
        },
      );

      await tester.tap(key('clinical-export-fhir'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(calls, 0);
    });
  });
}
