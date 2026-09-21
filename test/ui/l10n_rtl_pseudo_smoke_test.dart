/// Issue #460's second half: an RTL + pseudo-locale smoke over the four
/// primary surfaces (overview, calendar, day sheet, settings).
///
/// Epic #179's "ship in more than one language without a later rewrite"
/// needs more than the #160 scaffolding — nothing today ever renders the
/// app right-to-left or with non-English-length strings, so a Row with
/// hardcoded `EdgeInsets.only(left:)`, a too-tight label slot, or any
/// other layout that only survives short LTR English would ship
/// unnoticed. This pass wraps each surface in [Directionality.rtl] and
/// resolves [AppLocalizations] to a pseudo instance whose every getter
/// returns an accented, bracketed, ~1.3–2x-expanded string, then asserts
/// the surface lays out with **no overflow exception** on a phone-class
/// viewport (390x844 — the same class `a11y_pass_test.dart` uses).
///
/// The pseudo instance implements the abstract [AppLocalizations] surface
/// through `noSuchMethod`, so it tracks the ARB automatically — a newly
/// added message needs no test change to be covered by the smoke. The
/// ~380 not-yet-localized literals (see
/// `test/architecture/hardcoded_ui_strings_test.dart`) still render in
/// plain English underneath, which keeps the pass representative of the
/// mixed state a real second locale would first ship into.
///
/// What "no overflow" means here: `tester.takeException()` is null after
/// every settle — RenderFlex overflow, unbounded-constraint, and any
/// thrown build/layout error all surface as framework exceptions in
/// widget tests, so one assertion covers them.
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart' show DaySheet;
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_detail_screen.dart';
import 'package:lunarlog/ui/settings/settings_screen.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

import '../support/fake_settings_store.dart';

/// Fixed "today" — the same date the logging/overview suites pin, so the
/// calendar's seeded month, the today ring, and the day-sheet target are
/// deterministic.
final LocalDate kToday = LocalDate(2026, 8, 30);

/// Six 30-day episodes ending 2026-08-05 (the same fixture shape
/// `overview_test.dart`'s active-estimate starts use): enough history for
/// the overview tab to render its fullest state — active estimate, phase,
/// and the cycle-history section — instead of an empty/not-enough state.
final List<LocalDate> kActiveStarts = [
  LocalDate(2026, 3, 8),
  LocalDate(2026, 4, 7),
  LocalDate(2026, 5, 7),
  LocalDate(2026, 6, 6),
  LocalDate(2026, 7, 6),
  LocalDate(2026, 8, 5),
];

/// The accented filler every pseudo string is cut from. Latin-1 accented
/// characters only (single UTF-16 code units each) so the test font's
/// fixed-advance metrics make the expansion a pure character-count
/// effect — no zero-width combining marks to shrink the stress.
const String _kPseudoPhrase = 'psèüdø löçàlîzéð çöpy èxpañdéð fôr RTL çhéck ';

/// The pseudo value for any [AppLocalizations] member: a deterministic,
/// bracketed, accented string whose length tracks the member name's
/// (a rough proxy for the real copy's length), so short labels expand
/// hard while long paragraphs stay near their real footprint.
String pseudoUiCopy(Symbol member) {
  final target = (member.toString().length + 8).clamp(20, 48).toInt();
  return '[${(_kPseudoPhrase * 3).substring(0, target)}]';
}

/// An [AppLocalizations] whose every message resolves to [pseudoUiCopy].
/// Extends the abstract generated base and implements its abstract
/// members through `noSuchMethod`, so it never needs regenerating when
/// the ARB grows.
class _PseudoAppLocalizations extends AppLocalizations {
  _PseudoAppLocalizations() : super('en');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      pseudoUiCopy(invocation.memberName);
}

class _PseudoAppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _PseudoAppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(_PseudoAppLocalizations());

  @override
  bool shouldReload(_PseudoAppLocalizationsDelegate old) => false;
}

/// The delegate set of `AppLocalizations.localizationsDelegates` with the
/// app delegate swapped for the pseudo one — Material/Cupertino/Widgets
/// globals stay real so chrome (tooltips, snackbars, picker copy)
/// resolves normally for `en`.
const List<LocalizationsDelegate<dynamic>> _kPseudoDelegates = [
  _PseudoAppLocalizationsDelegate(),
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

/// Asserts no layout exception (overflow, unbounded constraints, or a
/// thrown build error — all surface as framework exceptions in widget
/// tests) is pending for [surface].
void expectNoLayoutOverflow(WidgetTester tester, String surface) {
  expect(
    tester.takeException(),
    isNull,
    reason: '$surface threw a layout/build exception under RTL + the '
        'pseudo-locale (issue #460 smoke)',
  );
}

/// The RTL + pseudo host every surface pumps inside: real theme, real
/// Material/Cupertino localizations, pseudo app copy, and a
/// `Directionality.rtl` injected through the `MaterialApp.builder` so it
/// is the nearest directionality for everything below the navigator.
Widget rtlPseudoHost({required Widget home}) {
  return MaterialApp(
    localizationsDelegates: _kPseudoDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: AppTheme.lightTheme,
    builder: (context, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
    home: home,
  );
}

/// Drags a scrollable by a screen-ish step and settles, so lazily-built
/// rows below the fold also lay out under the pseudo copy. [dy] negative
/// scrolls down through the content, positive scrolls back up.
/// [scrollable] overrides which scrollable gets dragged — while a modal
/// sheet is open, its own first descendant scrollable is the right
/// target, since the screen's scrollable sits behind the barrier and a
/// nested horizontal chip row may be the tree's last. Bounded to [steps]
/// drags; a no-op when there is nothing scrollable.
Future<void> scrollThrough(
  WidgetTester tester, {
  int steps = 4,
  double dy = -320,
  Finder? scrollable,
}) async {
  final finder = scrollable ?? find.byType(Scrollable).first;
  if (finder.evaluate().isEmpty) return;
  for (var i = 0; i < steps; i++) {
    await tester.drag(finder, Offset(0, dy));
    await tester.pumpAndSettle();
  }
}

DayEntry _episodeStart(String profileId, LocalDate date) => DayEntry(
      id: '',
      profileId: profileId,
      localDate: date,
      tz: 'America/Chicago',
      flow: FlowLevel.heavy,
      tags: const [],
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Pumps [ProfileDetailScreen] (the tree `test/ui/logging_test.dart`'s
/// harness mounts — overview tab by default, calendar one segment away,
/// day sheet one day-cell tap away) against a seeded in-memory store, on
/// a phone-class viewport, under RTL + the pseudo-locale.
Future<LunarLogDatabase> pumpDetailTree(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = LunarLogDatabase(NativeDatabase.memory());
  final profiles = DriftProfilesRepository(db.storage);
  final settings = DriftSettingsStore(db.storage);
  final profile = await profiles.create(displayName: 'Alice', isMinor: false);
  final entries = DriftDayEntriesRepository(db.storage);
  final observations = DriftObservationsRepository(db.storage);
  for (final start in kActiveStarts) {
    await entries.save(_episodeStart(profile.id, start));
  }
  // A rich "today": flow + tags + note, so the day sheet opens with its
  // fullest local state rather than an empty form.
  await entries.save(
    DayEntry(
      id: '',
      profileId: profile.id,
      localDate: kToday,
      tz: 'America/Chicago',
      flow: FlowLevel.medium,
      tags: const ['cramps'],
      note: 'existing note',
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ProfilesRepository>.value(value: profiles),
        Provider<DayEntriesRepository>.value(value: entries),
        Provider<ObservationsRepository>.value(value: observations),
        Provider<SettingsStore>.value(value: settings),
        ChangeNotifierProvider(
          create: (_) {
            final controller = ProfileController(
              profilesRepository: profiles,
              settingsStore: settings,
            );
            unawaited(controller.load());
            return controller;
          },
        ),
      ],
      child: rtlPseudoHost(
        home: ProfileDetailScreen(
          profile: profile,
          todayProvider: () => kToday,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('RTL + pseudo-locale smoke (#460)', () {
    testWidgets('overview, calendar, and day sheet lay out without overflow',
        (tester) async {
      final db = await pumpDetailTree(tester);
      addTearDown(() => db.close());

      // The smoke is only meaningful if the harness is actually doing
      // what it claims: pseudo copy resolved for AppLocalizations, and
      // RTL the direction everything below the navigator lays out in.
      expect(find.textContaining('[psèüdø'), findsWidgets,
          reason: 'no pseudo-locale copy rendered — the delegate swap is '
              'inert and this pass would be testing plain English');
      expect(
        Directionality.of(
          tester.element(find.byType(ProfileDetailScreen)),
        ),
        TextDirection.rtl,
      );

      // Surface 1: the overview tab (default) — estimate card, phase,
      // cycle history.
      expectNoLayoutOverflow(tester, 'the overview surface');
      await scrollThrough(tester);
      expectNoLayoutOverflow(tester, 'the scrolled overview surface');

      // Surface 2: the calendar tab. The segment labels are localized now
      // (issue #1004 tranche 3), so under the pseudo-locale they render as
      // pseudo copy and are reached by position — the second segment of
      // the tab toggle — rather than by literal text.
      await scrollThrough(tester, steps: 4, dy: 320); // back to the top
      await tester.tap(
        find
            .descendant(
              of: find.byKey(const ValueKey('detail-tab-toggle')),
              matching: find.byType(Text),
            )
            .at(1),
      );
      await tester.pumpAndSettle();
      expectNoLayoutOverflow(tester, 'the calendar surface');
      await scrollThrough(tester);
      expectNoLayoutOverflow(tester, 'the scrolled calendar surface');

      // Surface 3: the day sheet over today's rich entry. August 30 sits
      // below the fold on this viewport, so scroll it into view first.
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('day-cell-2026-08-30')),
        find.byType(Scrollable).first,
        const Offset(0, -160),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('day-cell-2026-08-30')));
      await tester.pumpAndSettle();
      expect(find.byType(DaySheet), findsOneWidget,
          reason: 'tapping today\'s cell must open the day sheet for the '
              'smoke to cover it');
      expectNoLayoutOverflow(tester, 'the day sheet surface');
      // The sheet's own vertical scrollable, not the screen's (which sits
      // behind the modal barrier and would swallow the drag).
      await scrollThrough(
        tester,
        scrollable: find
            .descendant(
              of: find.byType(DaySheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expectNoLayoutOverflow(tester, 'the scrolled day sheet surface');

      // Same drift-stream teardown discipline as logging_test's harness.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('settings lays out without overflow', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<SettingsStore>.value(value: FakeSettingsStore()),
            Provider<ProfilesRepository>.value(
              value: _FakeProfilesRepository([
                Profile(
                  id: 'p1',
                  displayName: 'Alice',
                  isMinor: false,
                  createdAt: DateTime.utc(2026, 1, 1),
                  updatedAt: DateTime.utc(2026, 1, 1),
                ),
              ]),
            ),
            Provider<DayEntriesRepository>.value(
              value: _FakeDayEntriesRepository(),
            ),
          ],
          child: rtlPseudoHost(home: const SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('[psèüdø'), findsWidgets,
          reason: 'no pseudo-locale copy rendered — the delegate swap is '
              'inert and this pass would be testing plain English');
      expectNoLayoutOverflow(tester, 'the settings surface');
      await scrollThrough(tester, steps: 6);
      expectNoLayoutOverflow(tester, 'the scrolled settings surface');
    });
  });
}

/// A [ProfilesRepository] whose `watch` emits a fixed list immediately —
/// the same shape `test/ui/settings_test.dart` uses (each suite keeps its
/// own tiny copy rather than sharing one).
class _FakeProfilesRepository implements ProfilesRepository {
  _FakeProfilesRepository(this.profiles);
  final List<Profile> profiles;

  @override
  Future<List<Profile>> list() async => profiles;

  @override
  Stream<List<Profile>> watch() => Stream.value(profiles);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Answers the calls `SettingsScreen`'s data tiles make (`listForProfile`,
/// `hasAnyEntries`, `watchHasAnyEntries`) and nothing else.
class _FakeDayEntriesRepository implements DayEntriesRepository {
  @override
  Future<List<DayEntry>> listForProfile(String profileId) async => const [];

  @override
  Future<bool> hasAnyEntries(String profileId) async => false;

  @override
  Stream<bool> watchHasAnyEntries(String profileId) => Stream.value(false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
