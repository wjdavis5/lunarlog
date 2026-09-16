/// Issue #257: the day sheet's custom-tag registry surfaces — the
/// read-only body's registry-aware chip resolution (a retired tag renders
/// by display name; a code not yet present in this device's registry copy
/// renders as raw text, never dropped), and the editable picker's
/// custom-tags section (offered registry entries as selectable chips
/// whose pick survives autosave — pre-#257, `validateTagCodes` rejected
/// any non-taxonomy code and that exact flow threw).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/logging/custom_tag_registry.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/tag_registry_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:provider/provider.dart';

import '../logging_test.dart' show ThrowingDayEntriesRepository;

const profileId = '01J8ZQ9K7MC2X3V4B5N6P7Q8R9';
final LocalDate kToday = LocalDate(2026, 8, 30);

CustomTag registryTag(
  String code,
  String displayName, {
  DateTime? hiddenAt,
}) =>
    CustomTag(
      id: '01J8ZQ9K7MC2X3V4B5N6P7Q${code.length.toString().padLeft(2, '0')}',
      profileId: profileId,
      code: code,
      displayName: displayName,
      category: 'custom',
      hiddenAt: hiddenAt,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
    );

class FakeTagRegistryRepository implements TagRegistryRepository {
  FakeTagRegistryRepository(this.rows);

  List<CustomTag> rows;
  int creates = 0;
  int retires = 0;

  @override
  Future<CustomTag> create({
    required String profileId,
    required String label,
  }) async {
    creates++;
    final created = registryTag(customTagCodeFromLabel(label)!, label.trim());
    rows = [...rows, created];
    return created;
  }

  @override
  Future<List<CustomTag>> listForProfile(String profileId) async => rows;

  @override
  Future<CustomTag> rename({required String tagId, required String label}) {
    throw UnimplementedError();
  }

  @override
  Future<void> retire(String tagId) async => retires++;

  @override
  Stream<List<CustomTag>> watchForProfile(String profileId) =>
      Stream.value(rows);
}

class _NoopObservations implements ObservationsRepository {
  @override
  Future<List<Observation>> listForProfile(String profileId) async =>
      const [];

  @override
  Future<List<Observation>> listForDayEntry(String dayEntryId) async =>
      const [];

  @override
  Future<List<Observation>> listForDayEntryWithLegacyAlias(
          String dayEntryId) async =>
      const [];

  @override
  Future<Observation> save(Observation observation) async => observation;

  @override
  Future<void> delete(String id) async {}
}

/// Records every [DayEntry] the sheet persists (the autosave-write
/// assertion); the parent supplies the rest of the no-throw behavior.
class _RecordingRepository extends ThrowingDayEntriesRepository {
  _RecordingRepository() : super(failSave: false);

  final List<DayEntry> saved = [];

  @override
  Future<DayEntry> save(DayEntry entry) async {
    final result = await super.save(entry);
    saved.add(result);
    return result;
  }
}

Future<void> pumpSheet(
  WidgetTester tester, {
  required TagRegistryRepository tagRegistry,
  required DayEntriesRepository repository,
  List<String> tags = const [],
  bool readOnly = false,
}) {
  return tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<TagRegistryRepository>.value(value: tagRegistry),
        Provider<ObservationsRepository>.value(value: _NoopObservations()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DaySheet(
            repository: repository,
            profileId: profileId,
            date: kToday,
            today: kToday,
            existing: tags.isEmpty
                ? null
                : DayEntry(
                    id: 'e1',
                    profileId: profileId,
                    localDate: kToday,
                    tz: 'America/Chicago',
                    flow: FlowLevel.none,
                    tags: tags,
                    updatedAt: DateTime.utc(2026, 8, 30),
                  ),
            readOnly: readOnly,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a retired custom tag renders by display name in the '
      'read-only body', (tester) async {
    // 'back_cracking' is deliberately NOT a taxonomy code (the issue's
    // own observed Clue value) so the registry is the only place the
    // display name can come from.
    await pumpSheet(
      tester,
      tagRegistry: FakeTagRegistryRepository([
        registryTag('back_cracking', 'Back cracking',
            hiddenAt: DateTime.utc(2026, 9, 2)),
      ]),
      repository: ThrowingDayEntriesRepository(),
      tags: ['back_cracking'],
      readOnly: true,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('read-only-tag-back_cracking')),
      findsOneWidget,
    );
    expect(find.text('Back cracking'), findsOneWidget,
        reason: 'retirement removes the picker chip, never the stored '
            "row's rendering (by display name where available)");
  });

  testWidgets('a code not in this device\'s registry copy renders as raw '
      'text, never dropped', (tester) async {
    await pumpSheet(
      tester,
      // The registry holds an unrelated entry: 'ghost_tag' has never
      // arrived on this device (a co-guardian's newer vocabulary).
      tagRegistry: FakeTagRegistryRepository([registryTag('other', 'Other')]),
      repository: ThrowingDayEntriesRepository(),
      tags: ['ghost_tag'],
      readOnly: true,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('read-only-tag-ghost_tag')),
      findsOneWidget,
      reason: '#237 (TM-1): unknown codes must never drop',
    );
    expect(find.text('ghost_tag'), findsOneWidget);
  });

  testWidgets('the picker offers live registry entries and a picked custom '
      'code survives autosave', (tester) async {
    final repository = _RecordingRepository();
    await pumpSheet(
      tester,
      tagRegistry: FakeTagRegistryRepository([
        registryTag('back_cracking', 'Back cracking'),
        registryTag('retired_one', 'Retired one',
            hiddenAt: DateTime.utc(2026, 9, 2)),
      ]),
      repository: repository,
    );
    await tester.pumpAndSettle();

    // The offered entry renders as a picker chip; the retired one never
    // does (retirement removed it from the picker). The custom section
    // renders after every curated category, so the chip can sit below
    // the fold of the scrollable sheet — ensureVisible first.
    final chip = find.widgetWithText(FilterChip, 'Back cracking');
    expect(chip, findsOneWidget);
    expect(find.text('Retired one'), findsNothing);
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();

    await tester.tap(chip);
    await tester.pump(kDaySheetAutosaveDelay);
    await tester.pumpAndSettle();

    expect(
      repository.saved,
      isNotEmpty,
      reason: 'pre-#257 this exact flow threw ArgumentError from '
          'validateTagCodes on autosave',
    );
    expect(repository.saved.last.tags, contains('back_cracking'));
    final l10n = AppLocalizations.of(
      tester.element(find.byType(DaySheet)),
    );
    expect(
      find.text(l10n.daySheetRetryHint),
      findsNothing,
      reason: 'the save succeeded — no failure copy may render',
    );
  });
}
