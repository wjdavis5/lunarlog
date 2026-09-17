/// Widget/unit tests for issue #137 — dark mode following the system
/// appearance, with the in-app override — walked against the issue's
/// acceptance criteria:
///
/// * **System dark renders dark** — the lock screen, the fail-closed
///   screen, and the main `LunarLogApp` itself, under
///   `tester.platformBrightness = Brightness.dark` with no stored
///   override (the default `ThemeMode.system` posture).
/// * **The override flips both directions and persists** — writes into
///   the settings store (exactly what the Settings picker does) flip the
///   running app between light and dark and back to system-following,
///   and a fresh app instance over the same database re-reads the
///   persisted value ("restart", the store re-injected).
/// * **The Settings picker writes the store** — the appearance tile's
///   dialog writes `SettingsKeys.themeMode` for all three options and
///   keeps its subtitle live.
/// * **Semantic colours stay distinguishable across themes** — the
///   `LunarLogColors` roles are pairwise distinct within each theme, the
///   dark tokens are re-derived (not the light tokens reused), and the
///   rendered calendar in dark draws its fills/dots from the dark scheme
///   with the non-colour mark-count channel intact.
/// * **Surfaces resolve from the scheme** — the lock screen's and
///   fail-closed screen's scaffolds resolve from `AppTheme.darkTheme`
///   under system dark, not from a hardcoded light colour (the
///   source-scan half of this criterion lives in
///   `test/architecture/theme_wiring_test.dart`, which now requires
///   every `MaterialApp` in `lib/` to wire `darkTheme:`/`themeMode:`).
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/app_lifecycle.dart' show GateController;
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/gate/lock_screen.dart';
import 'package:lunarlog/ui/startup/fail_closed_screen.dart';
import 'package:lunarlog/ui/settings/settings_screen.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';
import 'package:lunarlog/ui/theme/appearance.dart';
import 'package:lunarlog/ui/theme/lunarlog_colors.dart';
import 'package:provider/provider.dart';

import '../support/fake_settings_store.dart';
import 'app_auth_provider_test.dart' show disposeApp, homeContext;
import 'calendar_navigation_test.dart' show disposeCalendar, pumpCalendar;
import 'gate_test.dart' show FakeGate;

/// Steady 30-day cycles with 4-day bleeds, open cycle starting Aug 5 —
/// the same history `forecast_calendar_test.dart`'s `kSteadyStarts` seeds,
/// so the estimate lands Sep 4 (a predicted band one month ahead).
final List<LocalDate> _steadyStarts = [
  LocalDate(2026, 3, 8),
  LocalDate(2026, 4, 7),
  LocalDate(2026, 5, 7),
  LocalDate(2026, 6, 6),
  LocalDate(2026, 7, 6),
  LocalDate(2026, 8, 5),
];

DayEntry _mediumBleed(String profileId, LocalDate date) => DayEntry(
      id: '',
      profileId: profileId,
      localDate: date,
      tz: 'America/Chicago',
      flow: FlowLevel.medium,
      tags: const [],
      updatedAt: DateTime.utc(2026, 1, 1),
    );

DayEntry _tagDay(String profileId, LocalDate date, List<String> tags) =>
    DayEntry(
      id: '',
      profileId: profileId,
      localDate: date,
      tz: 'America/Chicago',
      flow: FlowLevel.none,
      tags: tags,
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();

  group('appearance codec (#137)', () {
    test('themeModeFromStored: null, absent, and unrecognized → system',
        () {
      expect(themeModeFromStored(null), ThemeMode.system);
      expect(themeModeFromStored('system'), ThemeMode.system);
      // A value this build cannot parse (including one written by a
      // future build) must degrade to system, never wedge the app.
      expect(themeModeFromStored('oled'), ThemeMode.system);
      expect(themeModeFromStored(''), ThemeMode.system);
      expect(themeModeFromStored('light'), ThemeMode.light);
      expect(themeModeFromStored('dark'), ThemeMode.dark);
    });

    test('storedThemeMode round-trips through themeModeFromStored', () {
      for (final mode in ThemeMode.values) {
        expect(themeModeFromStored(storedThemeMode(mode)), mode);
      }
    });
  });

  group('system dark renders dark (#137 AC1)', () {
    testWidgets('LockScreen follows the system dark appearance', (tester) async {
      final controller = GateController(gate: FakeGate());
      addTearDown(controller.dispose);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(LockScreen(controller: controller));
      await tester.pump();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.darkTheme, AppTheme.darkTheme,
          reason: 'the lock screen must carry the factory dark theme');
      expect(app.themeMode, ThemeMode.system,
          reason: 'no settings store exists at cold start, so the lock '
              'screen follows the system');
      expect(
        Theme.of(tester.element(find.byKey(const ValueKey('lock-screen'))))
            .brightness,
        Brightness.dark,
        reason: 'system dark must resolve the dark scheme, not the light '
            'one the screen used to hardcode',
      );
    });

    testWidgets('FailClosedApp follows the system dark appearance',
        (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(FailClosedApp(error: StateError('boom')));
      await tester.pump();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.darkTheme, AppTheme.darkTheme);
      expect(app.themeMode, ThemeMode.system,
          reason: 'the database holding the override failed to open — '
              'system-following is the only resolvable mode');
      expect(
        Theme.of(
          tester.element(find.byKey(const ValueKey('fail-closed-title'))),
        ).brightness,
        Brightness.dark,
      );
      // AC6, spot check: the surface resolves from the dark scheme rather
      // than a hardcoded light colour.
      final scaffoldContext = tester.element(find.byType(Scaffold).first);
      expect(
        Theme.of(scaffoldContext).scaffoldBackgroundColor,
        AppTheme.darkTheme.scaffoldBackgroundColor,
      );
    });

    testWidgets('the main app follows the system dark appearance',
        (tester) async {
      final db = LunarLogDatabase(NativeDatabase.memory());
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(LunarLogApp.withCollaborators(db: db));
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.darkTheme, AppTheme.darkTheme);
      expect(app.themeMode, ThemeMode.system,
          reason: 'no override stored → the default is system-following');
      expect(
        Theme.of(homeContext(tester)).brightness,
        Brightness.dark,
        reason: 'a dark-mode device must never get the light theme by '
            'default (the issue headline)',
      );

      await disposeApp(tester, db);
    });
  });

  group('the in-app override (#137 AC2)', () {
    testWidgets(
        'flips both directions from the settings store and back to '
        'system-following', (tester) async {
      final db = LunarLogDatabase(NativeDatabase.memory());
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(LunarLogApp.withCollaborators(db: db));
      await tester.pumpAndSettle();
      expect(Theme.of(homeContext(tester)).brightness, Brightness.light);

      // Dark under a light system — the override must win.
      await db.storage.setSetting(
        key: SettingsKeys.themeMode,
        value: storedThemeMode(ThemeMode.dark),
      );
      await tester.pumpAndSettle();
      expect(Theme.of(homeContext(tester)).brightness, Brightness.dark);

      // And back to light under the same light system.
      await db.storage.setSetting(
        key: SettingsKeys.themeMode,
        value: storedThemeMode(ThemeMode.light),
      );
      await tester.pumpAndSettle();
      expect(Theme.of(homeContext(tester)).brightness, Brightness.light);

      // 'system' hands control back to the platform — dark here.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await db.storage.setSetting(
        key: SettingsKeys.themeMode,
        value: storedThemeMode(ThemeMode.system),
      );
      await tester.pumpAndSettle();
      expect(Theme.of(homeContext(tester)).brightness, Brightness.dark);

      await disposeApp(tester, db);
    });

    testWidgets(
        'persists across restart: a fresh app over the same database '
        're-reads the override', (tester) async {
      final db = LunarLogDatabase(NativeDatabase.memory());
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(LunarLogApp.withCollaborators(db: db));
      await tester.pumpAndSettle();

      await db.storage.setSetting(
        key: SettingsKeys.themeMode,
        value: storedThemeMode(ThemeMode.dark),
      );
      await tester.pumpAndSettle();
      expect(Theme.of(homeContext(tester)).brightness, Brightness.dark);

      // "Restart": unmount entirely, then a brand-new LunarLogApp — and a
      // brand-new settings store constructed over it (the exact
      // re-injection `buildAppDependencies` performs on a real cold
      // start) — over the same database file.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(LunarLogApp.withCollaborators(db: db));
      await tester.pumpAndSettle();
      expect(
        Theme.of(homeContext(tester)).brightness,
        Brightness.dark,
        reason: 'the persisted override must survive the widget tree being '
            'rebuilt from scratch',
      );

      await disposeApp(tester, db);
    });

    testWidgets('the Settings picker writes the store and stays live',
        (tester) async {
      final store = FakeSettingsStore();
      addTearDown(store.close);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Provider<SettingsStore>.value(
            value: store,
            child: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tile = find.byKey(const ValueKey('appearance-tile'));
      expect(tile, findsOneWidget);
      // Default: the subtitle names the system-following option.
      expect(
        find.descendant(of: tile, matching: find.text('Follow system')),
        findsOneWidget,
      );

      // Pick Dark.
      await tester.tap(tile);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('appearance-option-dark')));
      await tester.pumpAndSettle();
      expect(await store.get(SettingsKeys.themeMode), 'dark');
      expect(
        find.descendant(of: tile, matching: find.text('Dark')),
        findsOneWidget,
        reason: 'the subtitle reads back through the same watch the app '
            'shell uses, so it stays live',
      );

      // Flip the other direction, then back to system.
      await tester.tap(tile);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('appearance-option-light')));
      await tester.pumpAndSettle();
      expect(await store.get(SettingsKeys.themeMode), 'light');

      await tester.tap(tile);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('appearance-option-system')));
      await tester.pumpAndSettle();
      expect(await store.get(SettingsKeys.themeMode), 'system');
      expect(
        find.descendant(of: tile, matching: find.text('Follow system')),
        findsOneWidget,
      );
    });
  });

  group('semantic colours across themes (#137 AC4)', () {
    final themes = <String, ThemeData>{
      'light': AppTheme.lightTheme,
      'dark': AppTheme.darkTheme,
    };

    test('flow fills, symptom dot, and prediction borders are pairwise '
        'distinct in each theme', () {
      for (final entry in themes.entries) {
        final c = entry.value.extension<LunarLogColors>()!;
        final meaning = <String, Color>{
          'flowSpotting': c.flowSpotting,
          'flowLight': c.flowLight,
          'flowMedium': c.flowMedium,
          'flowHeavy': c.flowHeavy,
          'symptomDot': c.symptomDot,
          'predictedBorder': c.predictedBorder,
          'fertileBorder': c.fertileBorder,
        };
        expect(
          meaning.values.toSet().length,
          meaning.length,
          reason: '${entry.key}: two meaning-carrying tokens collided — '
              'every colour that carries meaning must stay distinct from '
              'every other in both themes',
        );
      }
    });

    test('dark tokens are re-derived, not the light tokens reused', () {
      final light = AppTheme.lightTheme.extension<LunarLogColors>()!;
      final dark = AppTheme.darkTheme.extension<LunarLogColors>()!;
      // The #176 contract: boldness reads as "further from the background"
      // in whichever direction that is, so a heavy step pops off a dark
      // backdrop instead of receding into it.
      expect(dark.flowHeavy, isNot(light.flowHeavy));
      expect(dark.flowSpotting, isNot(light.flowSpotting));
      expect(dark.symptomDot, isNot(light.symptomDot));
      expect(dark.predictedBorder, isNot(light.predictedBorder));
      expect(dark.fertileBorder, isNot(light.fertileBorder));
    });

    testWidgets(
        'the calendar in dark draws fills/dots from the dark scheme, with '
        'the non-colour mark channel intact', (tester) async {
      final h = await pumpCalendar(
        tester,
        theme: AppTheme.darkTheme,
        // The no-service fallback derives its prediction from the ±45-day
        // window only (the documented caveat in `lib/ui/README.md`), which
        // cannot see the six-cycle history the predicted band needs — the
        // real services watch the full profile, exactly like production.
        withPredictionServices: true,
        seed: (db, profileId) async {
          final entries = DriftDayEntriesRepository(db.storage);
          for (final start in _steadyStarts) {
            for (var i = 0; i < 4; i++) {
              await entries.save(_mediumBleed(profileId, start.addDays(i)));
            }
          }
          // The same tag shape `forecast_calendar_test.dart`'s
          // generic-marker test uses: three most-used tags claim the
          // layer dots, so the bloating-only day falls back to the
          // generic symptom dot.
          await entries.save(_tagDay(profileId, LocalDate(2026, 8, 10), ['headache']));
          await entries.save(
              _tagDay(profileId, LocalDate(2026, 8, 11), ['headache', 'cramps']));
          await entries.save(
              _tagDay(profileId, LocalDate(2026, 8, 12), ['headache', 'fatigue']));
          await entries.save(
              _tagDay(profileId, LocalDate(2026, 8, 13), ['cramps', 'fatigue']));
          await entries.save(_tagDay(profileId, LocalDate(2026, 8, 14), ['bloating']));
        },
      );

      final dark = AppTheme.darkTheme.extension<LunarLogColors>()!;

      // A logged bleed fill (2026-08-05 is inside the open cycle's bleed)
      // resolves from the dark flow ramp, not a light literal.
      final bleed = tester.widget<Container>(
        find.byKey(const ValueKey('bleed-2026-08-05')),
      );
      expect(
        (bleed.decoration as BoxDecoration).color,
        dark.flowMedium,
        reason: 'the seeded steady-history bleeds are medium flow',
      );

      // The generic symptom dot resolves from the dark scheme's
      // symptomDot, and is a different colour from the bleed fill beside
      // it (the distinguishability half of AC4).
      final dot = tester.widget<Container>(
        find.byKey(const ValueKey('symptom-dot-2026-08-14')),
      );
      expect((dot.decoration as BoxDecoration).color, dark.symptomDot);
      expect(dark.symptomDot, isNot(dark.flowMedium));

      // The non-colour intensity channel still renders in dark: a medium
      // day carries exactly its three mark dots (indices 0..2).
      expect(
        find.byKey(const ValueKey('flow-level-medium-2026-08-05')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('flow-mark-2-2026-08-05')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('flow-mark-3-2026-08-05')),
        findsNothing,
        reason: 'medium is exactly three marks',
      );

      // The predicted band ahead is the hatch painter (never a solid
      // fill) in dark too — the estimated/factual distinction survives
      // without relying on colour alone.
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('predicted-2026-09-04')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('predicted-2026-09-04')),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
        reason: 'the band is hatched, not a solid fill',
      );

      await disposeCalendar(tester, h);
    });
  });
}
