/// Widget tests for ClinicalPdfExportTile (Issue #154).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/logging/custom_tag_registry.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/tag_registry_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/settings/clinical_pdf_export_tile.dart';
import 'package:provider/provider.dart';

Finder key(String value) => find.byKey(ValueKey(value));

Profile _profile(String id, {String displayName = 'Riley'}) => Profile(
  id: id,
  displayName: displayName,
  isMinor: false,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

List<DayEntry> _cycleEntries(String profileId) => [
  for (var cycle = 0; cycle < 8; cycle++)
    for (var day = 0; day < 2; day++)
      DayEntry(
        id: 'e$cycle-$day',
        profileId: profileId,
        localDate: LocalDate(2025, 1, 1).addDays(cycle * 28 + day),
        tz: 'UTC',
        flow: FlowLevel.medium,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
];

class FakeProfilesRepository implements ProfilesRepository {
  FakeProfilesRepository(this._profiles);

  final List<Profile> _profiles;
  final _controller = StreamController<List<Profile>>.broadcast();

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
  Stream<bool> watchHasAnyEntries(String profileId) async* {
    yield (entriesByProfile[profileId] ?? const []).isNotEmpty;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeObservationsRepository implements ObservationsRepository {
  @override
  Future<List<Observation>> listForProfile(String profileId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTagRegistryRepository implements TagRegistryRepository {
  Map<String, List<CustomTag>> tagsByProfile = const {};

  @override
  Future<List<CustomTag>> listForProfile(String profileId) async =>
      tagsByProfile[profileId] ?? const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester, {
  required FakeProfilesRepository profiles,
  FakeDayEntriesRepository? dayEntries,
  FakeTagRegistryRepository? tagRegistry,
  ClinicalPdfExportCollaborator? exportPdf,
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
            value: FakeObservationsRepository(),
          ),
          Provider<TagRegistryRepository?>.value(
            value: tagRegistry,
          ),
        ],
        child: Scaffold(body: ClinicalPdfExportTile(exportPdf: exportPdf)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no profiles: tile is absent', (tester) async {
    await _pump(tester, profiles: FakeProfilesRepository(const []));
    expect(key('clinical-pdf-export'), findsNothing);
  });

  testWidgets('no ProfilesRepository: tile is absent', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ClinicalPdfExportTile()),
      ),
    );
    await tester.pumpAndSettle();
    expect(key('clinical-pdf-export'), findsNothing);
  });

  testWidgets('single profile with no entries: disabled with prompt',
      (tester) async {
    await _pump(
      tester,
      profiles: FakeProfilesRepository([_profile('p1')]),
    );
    expect(key('clinical-pdf-export'), findsOneWidget);
    final tile = tester.widget<ListTile>(key('clinical-pdf-export'));
    expect(tile.enabled, isFalse);
    expect(
      find.text('Add at least one day entry to export a PDF clinical summary.'),
      findsOneWidget,
    );
  });

  testWidgets('single profile with entries: enabled with named subtitle',
      (tester) async {
    final dayEntries = FakeDayEntriesRepository()
      ..entriesByProfile = {'p1': _cycleEntries('p1')};
    await _pump(
      tester,
      profiles: FakeProfilesRepository([_profile('p1')]),
      dayEntries: dayEntries,
    );
    final tile = tester.widget<ListTile>(key('clinical-pdf-export'));
    expect(tile.enabled, isTrue);
    expect(
      find.text("Export Riley's clinical summary as a PDF."),
      findsOneWidget,
    );
  });

  testWidgets('multiple profiles: a chooser runs before the range picker',
      (tester) async {
    final dayEntries = FakeDayEntriesRepository()
      ..entriesByProfile = {
        'p1': _cycleEntries('p1'),
        'p2': _cycleEntries('p2'),
      };
    await _pump(
      tester,
      profiles: FakeProfilesRepository([
        _profile('p1', displayName: 'Riley'),
        _profile('p2', displayName: 'Alex'),
      ]),
      dayEntries: dayEntries,
    );
    await tester.tap(key('clinical-pdf-export'));
    await tester.pumpAndSettle();
    expect(find.text('Export clinical summary for'), findsOneWidget);
    await tester.tap(key('clinical-pdf-export-profile-p2'));
    await tester.pumpAndSettle();
    expect(key('export-range-confirm'), findsOneWidget);
  });

  testWidgets('export flow opens the shared range picker and shares PDF bytes',
      (tester) async {
    final dayEntries = FakeDayEntriesRepository()
      ..entriesByProfile = {'p1': _cycleEntries('p1')};
    Uint8List? capturedBytes;
    DateTime? capturedAt;
    await _pump(
      tester,
      profiles: FakeProfilesRepository([_profile('p1')]),
      dayEntries: dayEntries,
      exportPdf: ({required pdfBytes, required exportedAt}) async {
        capturedBytes = pdfBytes;
        capturedAt = exportedAt;
      },
    );

    await tester.tap(key('clinical-pdf-export'));
    await tester.pumpAndSettle();
    expect(key('export-range-confirm'), findsOneWidget);
    await tester.tap(key('export-range-confirm'));
    await tester.pumpAndSettle();

    expect(capturedBytes, isNotNull);
    expect(latin1.decode(capturedBytes!).startsWith('%PDF-1.4'), isTrue);
    expect(capturedAt, isNotNull);
  });

  testWidgets('a cancelled range picker does not export', (tester) async {
    final dayEntries = FakeDayEntriesRepository()
      ..entriesByProfile = {'p1': _cycleEntries('p1')};
    var called = false;
    await _pump(
      tester,
      profiles: FakeProfilesRepository([_profile('p1')]),
      dayEntries: dayEntries,
      exportPdf: ({required pdfBytes, required exportedAt}) async {
        called = true;
      },
    );

    await tester.tap(key('clinical-pdf-export'));
    await tester.pumpAndSettle();
    await tester.tap(key('export-range-cancel'));
    await tester.pumpAndSettle();
    expect(called, isFalse);
  });

  testWidgets('a failure renders the inline error copy', (tester) async {
    final dayEntries = FakeDayEntriesRepository()
      ..entriesByProfile = {'p1': _cycleEntries('p1')};
    await _pump(
      tester,
      profiles: FakeProfilesRepository([_profile('p1')]),
      dayEntries: dayEntries,
      exportPdf: ({required pdfBytes, required exportedAt}) async {
        throw StateError('share sheet unavailable');
      },
    );

    await tester.tap(key('clinical-pdf-export'));
    await tester.pumpAndSettle();
    await tester.tap(key('export-range-confirm'));
    await tester.pumpAndSettle();
    expect(key('clinical-pdf-export-error'), findsOneWidget);
    expect(find.text(kClinicalPdfExportFailureCopy), findsOneWidget);
  });

  testWidgets(
      'export passes custom tags from TagRegistryRepository to PDF document (Issue #834)',
      (tester) async {
    final entries = _cycleEntries('p1');
    entries[2] = DayEntry(
      id: entries[2].id,
      profileId: 'p1',
      localDate: entries[2].localDate,
      tz: 'UTC',
      flow: entries[2].flow,
      tags: const ['acupuncture'],
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final dayEntries = FakeDayEntriesRepository()
      ..entriesByProfile = {'p1': entries};
    final tagRegistry = FakeTagRegistryRepository()
      ..tagsByProfile = {
        'p1': [
          CustomTag(
            id: 'ct1',
            profileId: 'p1',
            code: 'acupuncture',
            displayName: 'Acupuncture',
            category: 'custom',
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      };
    Uint8List? capturedBytes;
    await _pump(
      tester,
      profiles: FakeProfilesRepository([_profile('p1')]),
      dayEntries: dayEntries,
      tagRegistry: tagRegistry,
      exportPdf: ({required pdfBytes, required exportedAt}) async {
        capturedBytes = pdfBytes;
      },
    );

    await tester.tap(key('clinical-pdf-export'));
    await tester.pumpAndSettle();
    await tester.tap(key('export-range-confirm'));
    await tester.pumpAndSettle();

    expect(capturedBytes, isNotNull);
    final pdfText = latin1.decode(capturedBytes!);
    expect(pdfText, contains('Acupuncture'));
  });
}
