/// Widget tests for the "Export clinical summary (FHIR)" tile (Issue
/// #157). Every collaborator is a fake (KTD6): the profiles/day-entries/
/// observations repositories and the FHIR export collaborator never touch
/// drift, `path_provider`, or `share_plus`. Fakes mirror
/// `test/ui/your_data_section_test.dart`'s own.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/export/fhir_bundle_writer.dart';
import 'package:lunarlog/domain/export/fhir_bundle_writer.dart';
import 'package:lunarlog/domain/export/fhir_export_range.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/components/inline_error.dart';
import 'package:lunarlog/ui/settings/clinical_export_tile.dart';
import 'package:provider/provider.dart';

Finder key(String value) => find.byKey(ValueKey(value));

/// Confirms the export-range picker sheet (issue #459) with whatever
/// preset is already selected — the default, "last 6 cycles", for every
/// test that does not care which range it exports. The sheet opens
/// between the profile choice and the Bundle build (see
/// `ClinicalExportTile._export`), so every export-flow test must clear it
/// before a captured bundle appears.
Future<void> _confirmExportRange(WidgetTester tester) async {
  expect(key('export-range-confirm'), findsOneWidget);
  await tester.tap(key('export-range-confirm'));
  await tester.pumpAndSettle();
}

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

/// Minimal in-memory [SettingsStore] (Issue #612, LLA-067) — just enough to
/// back a real [CycleExclusionList] in its device-local mode (no
/// [CycleOverridesRepository]), so a widget test can seed a cycle-start
/// omission without a Drift store.
class FakeSettingsStore implements SettingsStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> get(String key) async => _values[key];

  @override
  Future<void> set(String key, String value) async => _values[key] = value;

  @override
  Stream<String?> watch(String key) => Stream.value(_values[key]);
}

/// Five ~28-day period starts, the last gap widened to 56 days (Issue #612,
/// LLA-067's own repro numbers: "28, 28, 28, 56") — three completed cycles
/// long enough on their own to clear [kMinCompletedValidCycles] once the
/// outlier is excluded from averages, mirroring
/// `test/domain/export/fhir_bundle_test.dart`'s `_cycleHistory` shape.
List<DayEntry> _cycleHistoryWithOutlier(String profileId) {
  final starts = [
    LocalDate(2026, 1, 1),
    LocalDate(2026, 1, 29),
    LocalDate(2026, 2, 26),
    LocalDate(2026, 3, 26),
    LocalDate(2026, 5, 21), // 56 days after 2026-03-26
  ];
  var n = 0;
  return [
    for (final start in starts)
      for (var day = 0; day < 3; day++)
        DayEntry(
          id: 'outlier-e${n++}',
          profileId: profileId,
          localDate: start.addDays(day),
          tz: 'UTC',
          flow: FlowLevel.medium,
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
  ];
}

/// Five single-day episode starts, 40 days apart (issue #459): the newest
/// ([starts.last]) is the open cycle; the other four are completed cycles,
/// newest-first once read back through `deriveCycleHistoryFromEntries`. A
/// range narrowed to fewer than four completed cycles necessarily excludes
/// [starts.first] — the fixture [_manyCyclesRangeTest] below uses to prove
/// a picker preset actually narrows the exported document.
List<LocalDate> _manyCycleStarts() => [
      for (var i = 0; i < 5; i++) LocalDate(2025, 1, 1).addDays(i * 40),
    ];

List<DayEntry> _manyCyclesEntries(String profileId, List<LocalDate> starts) => [
      for (var i = 0; i < starts.length; i++)
        _entry('many-e$i', profileId, date: starts[i]),
    ];

Future<void> _pump(
  WidgetTester tester, {
  required FakeProfilesRepository profiles,
  FakeDayEntriesRepository? dayEntries,
  FakeObservationsRepository? observations,
  FhirExportCollaborator? exportFhir,
  CycleExclusionList? cycleExclusions,
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
          // The tree-provided FHIR writer the tile reads before falling back
          // to the injected collaborator (mirrors `lib/app.dart`).
          Provider<FhirBundleWriter>.value(value: const PlatformFhirBundleWriter()),
          // Issue #612, LLA-067: same seam `lib/app.dart` wires
          // (`Provider<CycleExclusionList>.value`). Only provided when a
          // test actually needs it — the "no collaborator at all" fail-open
          // path is exercised by every other test in this file leaving it
          // unset.
          if (cycleExclusions != null)
            Provider<CycleExclusionList>.value(value: cycleExclusions),
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

      // No chooser dialog for a single live profile — the range picker
      // opens directly (#459).
      expect(find.byType(SimpleDialog), findsNothing);
      await _confirmExportRange(tester);

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

      // The range picker opens after the profile choice (#459).
      await _confirmExportRange(tester);

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
      await _confirmExportRange(tester);

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
      await _confirmExportRange(tester);

      expect(key('clinical-export-fhir-error'), findsOneWidget);
      expect(
        tester.widget<InlineError>(key('clinical-export-fhir-error')).message,
        kClinicalExportFailureCopy,
      );
    });

    testWidgets(
        'a cycle the operator explicitly excluded from averages is honored '
        'in the exported cycle-length statistic — not silently recomputed '
        'over every logged cycle (Issue #612, LLA-067)', (tester) async {
      Map<String, Object?>? capturedBundle;
      final profiles = FakeProfilesRepository([_profile('p1')]);
      final dayEntries = FakeDayEntriesRepository()
        ..entriesByProfile = {'p1': _cycleHistoryWithOutlier('p1')};
      final settings = FakeSettingsStore();
      // The 56-day outlier cycle starts 2026-03-26 (see
      // `_cycleHistoryWithOutlier`'s own doc comment: three 28-day cycles
      // then one widened to 56) — omitting it leaves three 28-day cycles,
      // exactly clearing kMinCompletedValidCycles.
      await settings.set(
        omittedCyclesSettingKey('p1'),
        encodeOmittedCycles({LocalDate(2026, 3, 26)}),
      );
      final exclusions = CycleExclusionList(settings);

      await _pump(
        tester,
        profiles: profiles,
        dayEntries: dayEntries,
        cycleExclusions: exclusions,
        exportFhir: ({required bundle, required exportedAt}) async {
          capturedBundle = bundle;
        },
      );

      await tester.tap(key('clinical-export-fhir'));
      await tester.pumpAndSettle();
      await _confirmExportRange(tester);

      expect(capturedBundle, isNotNull);
      final entries = (capturedBundle!['entry'] as List).cast<Map>();
      final lengthObs = entries
          .map((e) => e['resource'] as Map)
          .firstWhere((r) => r.containsKey('valueQuantity'));
      expect(
        (lengthObs['valueQuantity'] as Map)['value'],
        28,
        reason: 'the excluded 56-day cycle must not pull the exported mean '
            'up to 35 — the same average the history list/overview panel '
            'would show for this profile once that cycle is omitted',
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

  group('entry-existence reactivity (issue #642, LLA-010)', () {
    testWidgets(
        'entry existence is its own bounded stream, independent of the '
        'profiles stream ticking, and the tile stays reactive across an '
        'IndexedStack tab switch', (tester) async {
      final profiles = FakeProfilesRepository([_profile('p1', displayName: 'Riley')]);
      final dayEntries = FakeDayEntriesRepository();
      final activeIndex = ValueNotifier<int>(0);
      addTearDown(profiles.dispose);
      addTearDown(activeIndex.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              Provider<ProfilesRepository>.value(value: profiles),
              Provider<DayEntriesRepository>.value(value: dayEntries),
              Provider<ObservationsRepository>.value(value: FakeObservationsRepository()),
              Provider<FhirBundleWriter>.value(value: const PlatformFhirBundleWriter()),
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
                    ClinicalExportTile(),
                    SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
          tester.widget<ListTile>(key('clinical-export-fhir')).enabled, isFalse);

      // Switch away and back through the IndexedStack — the tile's State
      // stays mounted the whole time.
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
      expect(
          tester.widget<ListTile>(key('clinical-export-fhir')).enabled, isTrue);

      // One -> zero, the same way.
      dayEntries.setHasEntries('p1', false);
      await tester.pump();
      expect(
          tester.widget<ListTile>(key('clinical-export-fhir')).enabled, isFalse);
    });
  });

  group('date-range selection (issue #459)', () {
    testWidgets(
        'the default preset ("last 6 cycles") is pre-selected when the '
        'picker opens', (tester) async {
      final profiles = FakeProfilesRepository([_profile('p1')]);
      final dayEntries = FakeDayEntriesRepository()
        ..entriesByProfile = {
          'p1': [_entry('e1', 'p1')],
        };
      await _pump(tester, profiles: profiles, dayEntries: dayEntries);

      await tester.tap(key('clinical-export-fhir'));
      await tester.pumpAndSettle();

      // Reads/writes through the ancestor `RadioGroup`, not its own
      // `groupValue` (removed with the pre-3.32 `RadioListTile` API).
      final group = tester.widget<RadioGroup<FhirExportRangePreset>>(
        find.byType(RadioGroup<FhirExportRangePreset>),
      );
      expect(group.groupValue, FhirExportRangePreset.last6Cycles);
    });

    testWidgets('cancelling the picker exports nothing', (tester) async {
      var calls = 0;
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
          calls++;
        },
      );

      await tester.tap(key('clinical-export-fhir'));
      await tester.pumpAndSettle();
      await tester.tap(key('export-range-cancel'));
      await tester.pumpAndSettle();

      expect(calls, 0);
      expect(key('clinical-export-fhir-error'), findsNothing);
    });

    testWidgets(
        'choosing a narrower preset excludes entries outside it, while the '
        'default preset ("last 6 cycles") includes every entry in this '
        'fixture — the builder receives exactly the entries the chosen '
        'range selects', (tester) async {
      Map<String, Object?>? capturedBundle;
      final starts = _manyCycleStarts();
      final profiles = FakeProfilesRepository([_profile('p1')]);
      final dayEntries = FakeDayEntriesRepository()
        ..entriesByProfile = {'p1': _manyCyclesEntries('p1', starts)};

      // Flow Observations are the only resources in this fixture (no tags,
      // no `observations` rows) carrying `valueCodeableConcept` — the
      // cycle-statistic Observations use `valueQuantity`/`valueDateTime`
      // instead (see `_flowObservation` vs. `_cycleLengthObservation`/
      // `_lastMenstrualPeriodObservation` in `fhir_bundle.dart`), so this
      // is an unambiguous filter.
      List<String> flowDatesOf(Map<String, Object?> bundle) {
        final entries = (bundle['entry'] as List).cast<Map>();
        return [
          for (final e in entries)
            if ((e['resource'] as Map).containsKey('valueCodeableConcept'))
              (e['resource'] as Map)['effectiveDateTime'] as String,
        ];
      }

      await _pump(
        tester,
        profiles: profiles,
        dayEntries: dayEntries,
        exportFhir: ({required bundle, required exportedAt}) async {
          capturedBundle = bundle;
        },
      );

      // Default ("last 6 cycles"): only 4 completed cycles exist in this
      // fixture, fewer than 6, so the range has no lower bound and every
      // entry is exported — including the oldest.
      await tester.tap(key('clinical-export-fhir'));
      await tester.pumpAndSettle();
      await _confirmExportRange(tester);
      expect(flowDatesOf(capturedBundle!), contains(starts.first.iso));

      // "Last 3 cycles": narrower than the whole fixture — the oldest
      // completed cycle (starts.first) falls outside the window and must
      // not appear, while the open cycle and the 3 most recent completed
      // ones still do.
      capturedBundle = null;
      await tester.tap(key('clinical-export-fhir'));
      await tester.pumpAndSettle();
      await tester.tap(key('export-range-preset-last3Cycles'));
      await tester.pumpAndSettle();
      await _confirmExportRange(tester);

      final dates = flowDatesOf(capturedBundle!);
      expect(dates, isNot(contains(starts.first.iso)),
          reason: 'the oldest cycle falls outside "last 3 cycles"');
      expect(dates, contains(starts.last.iso),
          reason: 'the open (newest) cycle is always included');
    });

    testWidgets('the "Everything" preset always includes the oldest entry',
        (tester) async {
      Map<String, Object?>? capturedBundle;
      final starts = _manyCycleStarts();
      final profiles = FakeProfilesRepository([_profile('p1')]);
      final dayEntries = FakeDayEntriesRepository()
        ..entriesByProfile = {'p1': _manyCyclesEntries('p1', starts)};

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
      await tester.tap(key('export-range-preset-everything'));
      await tester.pumpAndSettle();
      await _confirmExportRange(tester);

      final entries = (capturedBundle!['entry'] as List).cast<Map>();
      final dates = [
        for (final e in entries)
          if ((e['resource'] as Map)['effectiveDateTime'] != null)
            (e['resource'] as Map)['effectiveDateTime'] as String,
      ];
      expect(dates, contains(starts.first.iso));
    });
  });
}
