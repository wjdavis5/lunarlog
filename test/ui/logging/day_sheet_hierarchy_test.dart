/// Issue #812: the day sheet's type hierarchy, field order, and pinned
/// affirmative control.
///
/// These are presentation changes, so they are pinned here rather than by
/// rewriting any of the pre-existing day-sheet tests: the sheet's title must
/// outrank its section headings, and each heading must outrank the chip
/// labels it introduces; the shared note moves ahead of the numeric
/// measurement fields; and the pinned bar must carry a Done control that
/// dismisses without weakening autosave.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

final LocalDate _kToday = LocalDate(2026, 9, 19);

class _Harness {
  _Harness(this.db, this.entries, this.profileId);

  final LunarLogDatabase db;
  final DriftDayEntriesRepository entries;
  final String profileId;
}

/// Pumps [DaySheet] the way the app does — a real `showModalBottomSheet`
/// over a host page — on a phone-class viewport so the taxonomy genuinely
/// overflows and scrolls.
Future<_Harness> _pump(
  WidgetTester tester, {
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = LunarLogDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final profile = await DriftProfilesRepository(
    db.storage,
  ).create(displayName: 'Alice', isMinor: false);
  final entries = DriftDayEntriesRepository(db.storage);
  final observations = DriftObservationsRepository(db.storage);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ObservationsRepository>.value(value: observations),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const ValueKey('open-day-sheet'),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => DaySheet(
                    repository: entries,
                    profileId: profile.id,
                    date: _kToday,
                    today: _kToday,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('open-day-sheet')));
  await tester.pumpAndSettle();
  return _Harness(db, entries, profile.id);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('type hierarchy (issue #812)', () {
    testWidgets('the sheet title outranks its headings, and each heading '
        'outranks the chip labels it introduces', (tester) async {
      await _pump(tester);

      final theme = Theme.of(tester.element(find.byType(DaySheet)));
      final heading = tester.widget<Text>(find.text('Flow'));
      expect(heading.style?.fontSize, theme.textTheme.titleSmall?.fontSize);

      final title = tester.widget<Text>(
        find.byKey(const ValueKey('day-sheet-date-title')),
      );
      expect(title.style?.fontSize, theme.textTheme.titleLarge?.fontSize);

      expect(
        theme.textTheme.titleLarge!.fontSize!,
        greaterThan(theme.textTheme.titleSmall!.fontSize!),
        reason: 'the sheet title outranks the section headings',
      );
      expect(
        theme.textTheme.titleSmall!.fontSize!,
        greaterThan(theme.chipTheme.labelStyle!.fontSize!),
        reason: 'a section heading outranks the chip labels it labels',
      );
    });

    testWidgets('the Flow heading keeps its header semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      expect(
        tester.getSemantics(find.text('Flow')).flagsCollection.isHeader,
        isTrue,
      );
      handle.dispose();
    });
  });

  group('field order (issue #812)', () {
    testWidgets('the taxonomy stays under Flow and the note sits ahead of the '
        'numeric measurement fields', (tester) async {
      await _pump(tester);

      final searchY = tester
          .getTopLeft(find.byKey(const ValueKey('category-picker-search')))
          .dy;
      final noteY = tester
          .getTopLeft(find.byKey(const ValueKey('note-field')))
          .dy;
      final bbtY = tester.getTopLeft(find.byKey(const ValueKey('bbt-field'))).dy;

      expect(
        searchY,
        lessThan(noteY),
        reason: 'the chips are the primary logging surface and keep their '
            'position directly under Flow',
      );
      expect(
        noteY,
        lessThan(bbtY),
        reason: 'the note is now reached before the BBT/weight fields '
            '(issue #812 minimum), not after them',
      );
    });

    testWidgets('the note field grows with its content and carries a hint', (
      tester,
    ) async {
      await _pump(tester);

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('note-field')),
          matching: find.byType(TextField),
        ),
      );
      expect(field.minLines, 2);
      expect(field.maxLines, 6);
      expect(field.decoration?.hintText, isNotEmpty);
    });
  });

  group('pinned Done control (issue #812)', () {
    testWidgets('Done is present in the editable sheet and dismisses it', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.byKey(const ValueKey('day-sheet-done')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('day-sheet-done')));
      await tester.pumpAndSettle();
      expect(find.byType(DaySheet), findsNothing);
    });

    testWidgets('Done flushes a pending debounced note edit — autosave is '
        'untouched', (tester) async {
      final h = await _pump(tester);

      await tester.enterText(
        find.byKey(const ValueKey('note-field')),
        'written for Done',
      );
      // Deliberately do NOT wait out the autosave debounce: Done must behave
      // exactly like a scrim/back dismissal and flush the pending write.
      await tester.tap(find.byKey(const ValueKey('day-sheet-done')));
      await tester.pumpAndSettle();

      expect(find.byType(DaySheet), findsNothing);
      final saved = await h.entries.find(h.profileId, _kToday);
      expect(saved?.note, 'written for Done');
    });
  });

  group('text-scale extremes (issue #262 / #812)', () {
    for (final scale in [0.8, 2.5, 3.1]) {
      testWidgets('renders without overflow at ${scale}x text scale and keeps '
          'the Done control', (tester) async {
        await _pump(tester, textScale: scale);

        expect(tester.takeException(), isNull);
        expect(find.byType(DaySheet), findsOneWidget);
        expect(find.byKey(const ValueKey('day-sheet-done')), findsOneWidget);
      });
    }
  });
}
