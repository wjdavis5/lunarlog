/// Widget tests for U4: profile creation, switching, first-run gate,
/// archive/unarchive, last-active fallback and the startup error surface.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart';

const String kNoticeText =
    'Data lives only on this device. If the device is lost or reset, the '
    'history cannot be recovered — there is no backup in v1.';

Future<LunarLogDatabase> pumpApp(
  WidgetTester tester, {
  Future<void> Function(LunarLogDatabase db)? seed,
}) async {
  final db = LunarLogDatabase(NativeDatabase.memory());
  if (seed != null) {
    await seed(db);
  }
  await tester.pumpWidget(LunarLogApp(db: db));
  await tester.pumpAndSettle();
  return db;
}

/// Must run as the last statement of every test that used [pumpApp].
/// Unmounting cancels the drift query streams, which schedule zero-duration
/// timers; those must be drained (clock advance) before the widget-test
/// binding checks for pending timers, and the binding does its own tree
/// cleanup before addTearDown callbacks may pump — hence an explicit call.
Future<void> disposeApp(WidgetTester tester, LunarLogDatabase db) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await db.close();
}

DayEntry entryFor(
  String profileId,
  LocalDate date, {
  FlowLevel flow = FlowLevel.medium,
  String? note,
}) {
  return DayEntry(
    id: '',
    profileId: profileId,
    localDate: date,
    tz: 'America/Chicago',
    flow: flow,
    tags: const [],
    note: note,
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

Future<void> seedTwoProfiles(LunarLogDatabase db,
    {Future<void> Function(String aId, String bId)? extra}) async {
  final profiles = DriftProfilesRepository(db.storage);
  final a = await profiles.create(displayName: 'Alice', isMinor: false);
  final b = await profiles.create(displayName: 'Barb', isMinor: true);
  if (extra != null) await extra(a.id, b.id);
}

/// Navigates the U5 calendar back to an earlier month by tapping the
/// previous-month arrow until the month label appears (the app's "today" is
/// the real device date, so the tap count is computed dynamically).
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

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('first-run notice key follows the settled settings naming convention',
      () {
    expect(SettingsKeys.firstRunNoticeShown, 'first_run_notice_shown');
  });

  group('first run (F1)', () {
    testWidgets('zero profiles forces creation through the key-loss notice; '
        'created profile (name + minor flag) is selectable with empty history',
        (tester) async {
      final db = await pumpApp(tester);

      expect(find.text(kNoticeText), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing,
          reason: 'no name form before the notice');
      expect(find.text('Create profile'), findsNothing,
          reason: 'no skip past the notice');

      await tester.tap(find.text('I understand'));
      await tester.pumpAndSettle();
      expect(find.text(kNoticeText), findsNothing);

      await tester.enterText(find.byType(TextFormField), 'Luna');
      await tester.tap(find.text('This profile is for a minor'));
      await tester.pump();
      await tester.tap(find.text('Create profile'));
      await tester.pumpAndSettle();

      expect(find.text('Profiles'), findsOneWidget,
          reason: 'picker shows the new profile');
      expect(find.text('Luna'), findsOneWidget);

      final profiles = await DriftProfilesRepository(db.storage).list();
      expect(profiles.single.displayName, 'Luna');
      expect(profiles.single.isMinor, isTrue,
          reason: 'minor flag recorded (R5, inert in v1)');

      await tester.tap(find.text('Luna'));
      await tester.pumpAndSettle();
      expect(find.byType(MonthCalendar), findsOneWidget,
          reason: 'empty history shows the calendar with no markers');
      await disposeApp(tester, db);
    });

    testWidgets('relaunch with the same install opens the profile directly '
        'and never resurfaces the notice', (tester) async {
      final db = await pumpApp(tester);
      await tester.tap(find.text('I understand'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Luna');
      await tester.tap(find.text('Create profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Luna'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(LunarLogApp(db: db));
      await tester.pumpAndSettle();

      expect(find.text(kNoticeText), findsNothing);
      expect(find.text('Profiles'), findsNothing,
          reason: 'valid stored last-active opens the profile (R4)');
      expect(find.text('Luna'), findsOneWidget);
      expect(find.byType(MonthCalendar), findsOneWidget);
      await disposeApp(tester, db);
    });

    testWidgets('acknowledged notice is not shown again even with zero '
        'profiles', (tester) async {
      final db = await pumpApp(tester, seed: (db) async {
        await DriftSettingsStore(db.storage)
            .set(SettingsKeys.firstRunNoticeShown, 'true');
      });

      expect(find.text(kNoticeText), findsNothing);
      expect(find.byType(TextFormField), findsOneWidget,
          reason: 'straight to the name form on subsequent runs');
      await disposeApp(tester, db);
    });
  });

  group('profile switching and isolation (AE1 half, R3)', () {
    testWidgets('switching profiles swaps all visible day-entry data',
        (tester) async {
      final db = await pumpApp(tester, seed: (db) async {
        final profiles = DriftProfilesRepository(db.storage);
        final entries = DriftDayEntriesRepository(db.storage);
        final a = await profiles.create(displayName: 'Alice', isMinor: false);
        final b = await profiles.create(displayName: 'Barb', isMinor: true);
        await entries.save(entryFor(a.id, LocalDate(2026, 3, 1)));
        await entries.save(entryFor(a.id, LocalDate(2026, 3, 2), note: 'A only'));
        await entries.save(entryFor(b.id, LocalDate(2026, 4, 10)));
      });

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Barb'), findsOneWidget);

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      await showMonth(tester, 2026, 3);
      expect(find.byKey(const ValueKey('bleed-2026-03-01')), findsOneWidget);
      expect(find.byKey(const ValueKey('bleed-2026-03-02')), findsOneWidget);
      expect(find.byKey(const ValueKey('bleed-2026-04-10')), findsNothing,
          reason: 'no cross-profile leakage');

      await tester.tap(find.byTooltip('Switch profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Barb'));
      await tester.pumpAndSettle();
      await showMonth(tester, 2026, 4);
      expect(find.byKey(const ValueKey('bleed-2026-04-10')), findsOneWidget);
      expect(find.byKey(const ValueKey('bleed-2026-03-01')), findsNothing);
      expect(find.byKey(const ValueKey('bleed-2026-03-02')), findsNothing);
      await disposeApp(tester, db);
    });
  });

  group('archive (R2)', () {
    testWidgets('archiving hides from the active list and falls the '
        'active-profile pointer back to the picker', (tester) async {
      final db = await pumpApp(tester, seed: (db) async {
        await seedTwoProfiles(db, extra: (aId, bId) async {
          await DriftSettingsStore(db.storage)
              .set(SettingsKeys.lastActiveProfile, aId);
        });
      });

      expect(find.text('Alice'), findsOneWidget,
          reason: 'last-active opens the profile');

      await tester.tap(find.byTooltip('Switch profile'));
      await tester.pumpAndSettle();

      final aliceTile =
          find.ancestor(of: find.text('Alice'), matching: find.byType(ListTile));
      await tester.tap(find.descendant(
          of: aliceTile, matching: find.byType(PopupMenuButton<String>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();

      expect(find.text('Archive Alice?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
      await tester.pumpAndSettle();

      expect(find.text('Profiles'), findsOneWidget,
          reason: 'pointer fell back to the picker');
      expect(find.text('Alice'), findsNothing,
          reason: 'hidden from the active list (archived section collapsed)');
      expect(find.text('Barb'), findsOneWidget);
      await disposeApp(tester, db);
    });

    testWidgets('archived profile viewable read-only; unarchive from the '
        'read-only view restores editability', (tester) async {
      final db = await pumpApp(tester, seed: (db) async {
        await seedTwoProfiles(db, extra: (aId, bId) async {
          final entries = DriftDayEntriesRepository(db.storage);
          await entries.save(entryFor(aId, LocalDate(2026, 3, 1)));
          await DriftProfilesRepository(db.storage).setArchived(aId, true);
        });
      });

      await tester.tap(find.text('Archived (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      expect(find.text('Alice (archived)'), findsOneWidget);
      expect(find.byTooltip('Switch profile'), findsNothing,
          reason: 'read-only view');

      await showMonth(tester, 2026, 3);
      await tester.tap(find.byKey(const ValueKey('day-cell-2026-03-01')));
      await tester.pumpAndSettle();
      expect(find.text('2026-03-01'), findsOneWidget,
          reason: 'entry viewable in the read-only day sheet');
      expect(find.byKey(const ValueKey('save-button')), findsNothing,
          reason: 'no logging affordances for archived profiles');
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.text('Unarchive'), findsOneWidget);

      await tester.tap(find.text('Unarchive'));
      await tester.pumpAndSettle();

      expect(find.text('Profiles'), findsOneWidget, reason: 'back on picker');
      expect(find.text('Alice'), findsOneWidget,
          reason: 'restored to the active list');
      expect(find.textContaining('Archived'), findsNothing);

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      expect(find.text('Alice (archived)'), findsNothing,
          reason: 'editable again');
      expect(find.byTooltip('Switch profile'), findsOneWidget);
      await disposeApp(tester, db);
    });

    testWidgets('one-tap unarchive from the archived section restores the '
        'profile to the active list', (tester) async {
      final db = await pumpApp(tester, seed: (db) async {
        await seedTwoProfiles(db, extra: (aId, bId) async {
          await DriftProfilesRepository(db.storage).setArchived(aId, true);
        });
      });

      await tester.tap(find.text('Archived (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Unarchive'));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget,
          reason: 'back among active profiles');
      expect(find.textContaining('Archived'), findsNothing,
          reason: 'nothing archived left');
      await disposeApp(tester, db);
    });
  });

  group('profile names (R2)', () {
    testWidgets('whitespace-only names are rejected; duplicates are allowed '
        'with creation-date subtitles', (tester) async {
      final db = await pumpApp(tester, seed: (db) async {
        await DriftProfilesRepository(db.storage)
            .create(displayName: 'Same', isMinor: false);
      });

      await tester.tap(find.byTooltip('Add profile'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      expect(find.text('Name cannot be empty'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget,
          reason: 'dialog stays open on invalid input');

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Same'), findsNWidgets(1),
          reason: 'nothing was created from the invalid name');

      await tester.tap(find.byTooltip('Add profile'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Same');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(find.text('Same'), findsNWidgets(2),
          reason: 'duplicate names allowed');
      expect(find.textContaining('Created '), findsNWidgets(2),
          reason: 'disambiguated by creation date');
      await disposeApp(tester, db);
    });

    testWidgets('rename via the row menu', (tester) async {
      final db = await pumpApp(tester, seed: (db) async {
        await DriftProfilesRepository(db.storage)
            .create(displayName: 'Alice', isMinor: false);
      });

      final aliceTile =
          find.ancestor(of: find.text('Alice'), matching: find.byType(ListTile));
      await tester.tap(find.descendant(
          of: aliceTile, matching: find.byType(PopupMenuButton<String>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Alice'), findsOneWidget,
          reason: 'rename dialog prefilled');
      await tester.enterText(find.byType(TextFormField), 'Alicia');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Alicia'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
      await disposeApp(tester, db);
    });
  });

  group('last-active fallback (R4)', () {
    testWidgets('valid stored id opens that profile on launch', (tester) async {
      final db = await pumpApp(tester, seed: (db) async {
        await seedTwoProfiles(db, extra: (aId, bId) async {
          await DriftSettingsStore(db.storage)
              .set(SettingsKeys.lastActiveProfile, bId);
        });
      });

      expect(find.text('Barb'), findsOneWidget, reason: 'opened directly');
      expect(find.text('Profiles'), findsNothing);
      expect(find.text('Alice'), findsNothing);
      await disposeApp(tester, db);
    });

    testWidgets('archived stored id falls back to the picker', (tester) async {
      final db = await pumpApp(tester, seed: (db) async {
        await seedTwoProfiles(db, extra: (aId, bId) async {
          await DriftProfilesRepository(db.storage).setArchived(bId, true);
          await DriftSettingsStore(db.storage)
              .set(SettingsKeys.lastActiveProfile, bId);
        });
      });

      expect(find.text('Profiles'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      await disposeApp(tester, db);
    });

    testWidgets('unknown stored id falls back to the picker', (tester) async {
      final db = await pumpApp(tester, seed: (db) async {
        await DriftProfilesRepository(db.storage)
            .create(displayName: 'Alice', isMinor: false);
        await DriftSettingsStore(db.storage)
            .set(SettingsKeys.lastActiveProfile, 'bogus');
      });

      expect(find.text('Profiles'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      await disposeApp(tester, db);
    });
  });

  group('startup error surface', () {
    testWidgets('basic error widget renders the failure (full fail-closed '
        'treatment is a later unit)', (tester) async {
      await tester.pumpWidget(
          StartupErrorApp(error: Exception('boom: quarantined')));

      expect(find.textContaining('could not start'), findsOneWidget);
      expect(find.textContaining('boom: quarantined'), findsOneWidget);
    });
  });
}
