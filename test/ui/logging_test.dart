/// Widget tests for U5: month calendar, day sheet logging (flow/tags/note),
/// backfill, future-date lock, edit-without-duplicate, delete via tombstone,
/// symptom-only markers, save-failure retention, and archived read-only view.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/tags.dart';
import 'package:lunarlog/domain/util/timezone.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_detail_screen.dart';
import 'package:provider/provider.dart';

/// Fixed "today" so month defaults and future locks are deterministic.
final LocalDate kToday = LocalDate(2026, 8, 30);

class Harness {
  Harness(this.db, this.profile, this.entries);

  final LunarLogDatabase db;
  final Profile profile;
  final DriftDayEntriesRepository entries;
}

DayEntry entryFor(
  String profileId,
  LocalDate date, {
  FlowLevel flow = FlowLevel.medium,
  List<String> tags = const [],
  String? note,
}) {
  return DayEntry(
    id: '',
    profileId: profileId,
    localDate: date,
    tz: 'America/Chicago',
    flow: flow,
    tags: tags,
    note: note,
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

Future<Harness> pumpLogging(
  WidgetTester tester, {
  bool readOnly = false,
  DayEntriesRepository? entryRepositoryOverride,
  Future<void> Function(LunarLogDatabase db, String profileId)? seed,
  String Function()? timezoneProvider,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = LunarLogDatabase(NativeDatabase.memory());
  final profiles = DriftProfilesRepository(db.storage);
  final settings = DriftSettingsStore(db.storage);
  final profile = await profiles.create(displayName: 'Alice', isMinor: false);
  if (seed != null) {
    await seed(db, profile.id);
  }
  final entries = DriftDayEntriesRepository(db.storage);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ProfilesRepository>.value(value: profiles),
        Provider<DayEntriesRepository>.value(
          value: entryRepositoryOverride ?? entries,
        ),
        Provider<SettingsStore>.value(value: settings),
        ChangeNotifierProvider(
          create: (_) => ProfileController(
            profilesRepository: profiles,
            settingsStore: settings,
          )..load(),
        ),
      ],
      child: MaterialApp(
        home: ProfileDetailScreen(
          profile: profile,
          readOnly: readOnly,
          todayProvider: () => kToday,
          timezoneProvider: timezoneProvider,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return Harness(db, profile, entries);
}

/// Must run as the last statement of every test that used [pumpLogging]
/// (same drift-stream teardown discipline as U4's profiles_test).
Future<void> disposeLogging(WidgetTester tester, Harness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await h.db.close();
}

Future<void> showMonth(WidgetTester tester, int year, int month) async {
  final label = '${kMonthNames[month - 1]} $year';
  var guard = 0;
  while (find.text(label).evaluate().isEmpty) {
    expect(guard++, lessThan(1200), reason: 'month never reached: $label');
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
  }
  expect(find.text(label), findsOneWidget);
}

/// Repository whose save always fails (F2 failure-state path).
class ThrowingDayEntriesRepository implements DayEntriesRepository {
  @override
  Future<DayEntry> save(DayEntry entry) async {
    throw Exception('simulated write failure');
  }

  @override
  Future<DayEntry?> find(String profileId, LocalDate localDate) async => null;

  @override
  Future<List<DayEntry>> listForProfile(String profileId) async => const [];

  @override
  Stream<List<DayEntry>> watchForProfile(String profileId) =>
      Stream.value(const []);

  @override
  Future<void> delete(String profileId, LocalDate localDate) async {}
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('F2 day logging', () {
    testWidgets('logging today (flow + 2 tags + note) persists via the '
        'repository and re-renders from the stream after reopening the sheet',
        (tester) async {
      final h = await pumpLogging(tester);

      expect(find.text('August 2026'), findsOneWidget,
          reason: "today's month is the default");

      final todayCell = find.byKey(const ValueKey('day-cell-2026-08-30'));
      await tester.tap(todayCell);
      await tester.pumpAndSettle();
      expect(find.byType(DaySheet), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Medium'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilterChip, 'Cramps'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilterChip, 'Fatigue'));
      await tester.pump();
      await tester.enterText(
          find.byKey(const ValueKey('note-field')), 'rough day');
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await tester.pumpAndSettle();

      expect(find.byType(DaySheet), findsNothing);
      final saved = await h.entries.find(h.profile.id, kToday);
      expect(saved!.flow, FlowLevel.medium);
      expect(saved.tags, unorderedEquals(['cramps', 'fatigue']));
      expect(saved.note, 'rough day');
      expect(isValidIanaTimeZone(saved.tz), isTrue,
          reason: 'persists canonical IANA timezone identifier');
      expect(find.byKey(const ValueKey('bleed-2026-08-30')), findsOneWidget,
          reason: 'stream recompute re-rendered the calendar marker');

      await tester.tap(todayCell);
      await tester.pumpAndSettle();
      expect(find.byType(DaySheet), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Medium'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Cramps'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Fatigue'))
            .selected,
        isTrue,
      );
      expect(find.text('rough day'), findsOneWidget);
      await disposeLogging(tester, h);
    });

    testWidgets('backfilling a past date stores against that civil date and '
        'the calendar marker appears', (tester) async {
      final h = await pumpLogging(tester);

      await showMonth(tester, 2026, 3);
      await tester.tap(find.byKey(const ValueKey('day-cell-2026-03-05')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Heavy'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await tester.pumpAndSettle();

      final saved = await h.entries.find(h.profile.id, LocalDate(2026, 3, 5));
      expect(saved!.localDate, LocalDate(2026, 3, 5));
      expect(saved.flow, FlowLevel.heavy);
      expect(find.byKey(const ValueKey('bleed-2026-03-05')), findsOneWidget);
      await disposeLogging(tester, h);
    });

    testWidgets('future dates cannot be selected and month navigation stops '
        'at the current month', (tester) async {
      final h = await pumpLogging(tester);

      expect(find.byKey(const ValueKey('day-cell-2026-08-31')), findsOneWidget,
          reason: 'future days render but are disabled');
      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-31')));
      await tester.pumpAndSettle();
      expect(find.byType(DaySheet), findsNothing);

      final next = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Next month'),
          matching: find.byType(IconButton),
        ),
      );
      expect(next.onPressed, isNull,
          reason: 'cannot navigate forward of the current month');
      await disposeLogging(tester, h);
    });

    testWidgets('the sheet itself refuses future dates even when opened '
        'directly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DaySheet(
              repository: ThrowingDayEntriesRepository(),
              profileId: 'p',
              date: kToday.addDays(1),
              today: kToday,
            ),
          ),
        ),
      );
      expect(find.textContaining("Future dates"), findsOneWidget);
      expect(find.byKey(const ValueKey('save-button')), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('editing flow updates the same record (no duplicate row)',
        (tester) async {
      final h = await pumpLogging(tester);

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Light'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await tester.pumpAndSettle();
      final first = await h.entries.find(h.profile.id, kToday);
      expect(first!.flow, FlowLevel.light);

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Heavy'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await tester.pumpAndSettle();

      final second = await h.entries.find(h.profile.id, kToday);
      expect(second!.flow, FlowLevel.heavy);
      expect(second.id, first.id, reason: 'upsert keyed on profile+date');

      final fullFidelity = await h.db.storage
          .getDayEntries(profileId: h.profile.id, includeTombstones: true);
      final rowsForDate =
          fullFidelity.where((row) => row.localDate == '2026-08-30').toList();
      expect(rowsForDate, hasLength(1));
      await disposeLogging(tester, h);
    });

    testWidgets('saving day entry populates canonical IANA timezone and '
        'respects injected timezoneProvider seam', (tester) async {
      final h = await pumpLogging(
        tester,
        timezoneProvider: () => 'America/New_York',
      );

      final todayCell = find.byKey(const ValueKey('day-cell-2026-08-30'));
      await tester.tap(todayCell);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Light'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await tester.pumpAndSettle();

      final saved = await h.entries.find(h.profile.id, kToday);
      expect(saved!.tz, 'America/New_York');
      expect(isValidIanaTimeZone(saved.tz), isTrue);

      await disposeLogging(tester, h);
    });

    testWidgets('editing existing entry updates legacy abbreviation to canonical IANA timezone',
        (tester) async {
      final h = await pumpLogging(
        tester,
        timezoneProvider: () => 'America/Chicago',
        seed: (db, profileId) async {
          // Simulate an existing entry previously written with platform abbreviation 'EDT'.
          await DriftDayEntriesRepository(db.storage).save(
            DayEntry(
              id: '',
              profileId: profileId,
              localDate: kToday,
              tz: 'EDT',
              flow: FlowLevel.medium,
              tags: const [],
              updatedAt: DateTime.utc(2026, 8, 30),
            ),
          );
        },
      );

      final todayCell = find.byKey(const ValueKey('day-cell-2026-08-30'));
      await tester.tap(todayCell);
      await tester.pumpAndSettle();

      // Change flow to heavy and save
      await tester.tap(find.widgetWithText(ChoiceChip, 'Heavy'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await tester.pumpAndSettle();

      final saved = await h.entries.find(h.profile.id, kToday);
      expect(saved!.flow, FlowLevel.heavy);
      expect(saved.tz, 'America/Chicago');
      expect(isValidIanaTimeZone(saved.tz), isTrue);

      await disposeLogging(tester, h);
    });

    testWidgets('delete confirms and the entry disappears from the calendar '
        'via the stream (AE2 linkage)', (tester) async {
      final h = await pumpLogging(
        tester,
        seed: (db, profileId) async {
          await DriftDayEntriesRepository(db.storage)
              .save(entryFor(profileId, kToday));
        },
      );

      expect(find.byKey(const ValueKey('bleed-2026-08-30')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete entry'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this entry?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.byType(DaySheet), findsNothing);
      expect(find.byKey(const ValueKey('bleed-2026-08-30')), findsNothing,
          reason: 'hidden from calendar after tombstone delete');
      expect(await h.entries.find(h.profile.id, kToday), isNull);

      final rows = await h.db.storage
          .getDayEntries(profileId: h.profile.id, includeTombstones: true);
      expect(rows.single.deletedAt, isNotNull,
          reason: 'tombstone persists in storage, invisible in UI');
      await disposeLogging(tester, h);
    });

    testWidgets('tag chips render exactly the curated 17 in 4 categories; '
        'toggling two tags persists both codes', (tester) async {
      final h = await pumpLogging(tester);

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();

      expect(find.byType(FilterChip), findsNWidgets(17));
      for (final header in ['Pain', 'Body', 'Mood', 'Other']) {
        expect(find.text(header), findsOneWidget);
      }
      for (final tag in kTagTaxonomy) {
        expect(find.text(tag.display), findsOneWidget);
      }

      await tester.tap(find.text('Headache'));
      await tester.pump();
      await tester.tap(find.text('Cramps'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await tester.pumpAndSettle();

      final saved = await h.entries.find(h.profile.id, kToday);
      expect(saved!.tags, unorderedEquals(['cramps', 'headache']));
      await disposeLogging(tester, h);
    });

    testWidgets('symptom-only day (flow none + tags) renders the secondary '
        'marker, not the bleed marker', (tester) async {
      final h = await pumpLogging(
        tester,
        seed: (db, profileId) async {
          await DriftDayEntriesRepository(db.storage).save(entryFor(
            profileId,
            kToday,
            flow: FlowLevel.none,
            tags: const ['cramps'],
            note: 'meh',
          ));
        },
      );

      expect(find.byKey(const ValueKey('symptom-dot-2026-08-30')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('bleed-2026-08-30')), findsNothing);
      await disposeLogging(tester, h);
    });

    testWidgets('save failure keeps the sheet open with values intact and '
        'shows the retry error', (tester) async {
      final h =
          await pumpLogging(tester, entryRepositoryOverride: ThrowingDayEntriesRepository());

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Heavy'));
      await tester.pump();
      await tester.enterText(
          find.byKey(const ValueKey('note-field')), 'kept input');
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await tester.pumpAndSettle();

      expect(find.byType(DaySheet), findsOneWidget,
          reason: 'never auto-dismiss on failure');
      expect(find.byKey(const ValueKey('save-error')), findsOneWidget);
      expect(find.text("Couldn't save — try again"), findsOneWidget);
      expect(find.text('kept input'), findsOneWidget,
          reason: 'entered values are never dropped');
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Heavy'))
            .selected,
        isTrue,
      );
      await disposeLogging(tester, h);
    });

    testWidgets('archived profile calendar is read-only: day sheet shows '
        'entry details with no save/delete affordances', (tester) async {
      final h = await pumpLogging(
        tester,
        readOnly: true,
        seed: (db, profileId) async {
          await DriftDayEntriesRepository(db.storage).save(entryFor(
            profileId,
            LocalDate(2026, 3, 1),
            tags: const ['cramps'],
            note: 'spotty',
          ));
        },
      );

      await showMonth(tester, 2026, 3);
      await tester.tap(find.byKey(const ValueKey('day-cell-2026-03-01')));
      await tester.pumpAndSettle();

      expect(find.byType(DaySheet), findsOneWidget);
      expect(find.text('2026-03-01'), findsOneWidget);
      expect(find.text('Medium'), findsOneWidget);
      expect(find.text('Cramps'), findsOneWidget);
      expect(find.text('spotty'), findsOneWidget);
      expect(find.byKey(const ValueKey('save-button')), findsNothing);
      expect(find.byTooltip('Delete entry'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(FilterChip), findsNothing);

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.byType(DaySheet), findsNothing);

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-03-02')));
      await tester.pumpAndSettle();
      expect(find.byType(DaySheet), findsNothing,
          reason: 'no entry-creation affordance in read-only mode');
      await disposeLogging(tester, h);
    });
  });
}
