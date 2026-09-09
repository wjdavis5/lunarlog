/// Widget tests for issue #223: the Analysis tab — headline cycle
/// statistics rendered from [ActivePrediction] fields (#213), the honest
/// not-enough-history state below three valid cycles, the R17 disclaimer
/// (rendered exactly once, not duplicated by the embedded history
/// section), `irregular` care-mode's tier-caption-only suppression
/// (#131), the cycle-history list (#132) mounted as this tab's scrollable
/// section with viewer-role read-only gating wired in (review
/// finding on #315), and the `didUpdateWidget` profile-switch branch.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/data/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/insights/analysis_tab.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';

const String kDisclaimer = 'Estimates only — not medical advice.';

/// Fixed "today" so every derived number is deterministic.
final LocalDate kToday = LocalDate(2026, 8, 30);

/// Seven 30-day episodes ending 2026-08-05: mean cycle length 30 days, a
/// full kAverageWindowCycles(6) completed-cycle window, so the spread is
/// exactly 0 and the tier reads `high` (matches
/// `test/ui/cycle_history_test.dart`'s `kSteadyStarts`).
final List<LocalDate> kSteadyStarts = [
  LocalDate(2026, 2, 6),
  LocalDate(2026, 3, 8),
  LocalDate(2026, 4, 7),
  LocalDate(2026, 5, 7),
  LocalDate(2026, 6, 6),
  LocalDate(2026, 7, 6),
  LocalDate(2026, 8, 5),
];

/// Two episodes only: 1 valid cycle < 3 → [NotEnoughHistory].
final List<LocalDate> kNotEnoughStarts = [
  LocalDate(2026, 7, 1),
  LocalDate(2026, 7, 29),
];

/// Lengths 28, 28, 20, 28 (matches `test/ui/cycle_history_test.dart`'s
/// fixture of the same name): the 20-day cycle is the one STARTING Apr 5.
/// All four feed the mean exactly (26.0); omitting the short one leaves
/// [28, 28, 28] (28.0 exactly) -- a clean, whole-number transition for
/// asserting the headline stat moves when a cycle is omitted through the
/// mounted history section (issue #314).
final List<LocalDate> kShortOutlierStarts = [
  LocalDate(2026, 2, 8),
  LocalDate(2026, 3, 8),
  LocalDate(2026, 4, 5), // the short outlier
  LocalDate(2026, 4, 25),
  LocalDate(2026, 5, 23), // open cycle
];

Future<void> seedEpisodes(
  DriftDayEntriesRepository entries,
  String profileId,
  List<LocalDate> starts, {
  int lengthDays = 4,
}) async {
  for (final start in starts) {
    for (var i = 0; i < lengthDays; i++) {
      await entries.save(DayEntry(
        id: '',
        profileId: profileId,
        localDate: start.addDays(i),
        tz: 'America/Chicago',
        flow: FlowLevel.medium,
        tags: const [],
        note: null,
        updatedAt: DateTime.utc(2026, 1, 1),
        deletedAt: null,
      ));
    }
  }
}

/// Materializes a server-authored guardian row locally, mirroring
/// `test/ui/logging_test.dart`/`test/ui/sharing_flow_test.dart`'s
/// `guardianRow` helper so the viewer-role fixture is honest about where
/// `role`/`status` come from.
RemoteProfileGuardianRow guardianRow(
  String profileId,
  String id,
  String userId,
  String role,
) => RemoteProfileGuardianRow(
  id: id,
  profileId: profileId,
  userId: userId,
  role: role,
  status: 'accepted',
  displayName: null,
  invitedBy: null,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  serverVersion: 1,
);

class Harness {
  Harness(this.tester) : db = LunarLogDatabase(NativeDatabase.memory());

  final WidgetTester tester;
  final LunarLogDatabase db;

  Widget widgetFor(
    String profileId, {
    ProfileMode mode = ProfileMode.standard,
    bool readOnly = false,
    AuthController? authController,
    ProfileGuardiansRepository? guardiansRepository,
    LocalDate? today,
  }) {
    final settings = DriftSettingsStore(db.storage);
    final entries = DriftDayEntriesRepository(db.storage);
    return MultiProvider(
      providers: [
        Provider<CyclePredictionService>.value(
          value: CyclePredictionService(entries, settings: settings),
        ),
        Provider<CycleHistoryService>.value(
          value: CycleHistoryService(entries, settings: settings),
        ),
        Provider<CycleExclusionList>.value(
          value: CycleExclusionList(settings),
        ),
        if (authController != null)
          ChangeNotifierProvider<AuthController>.value(value: authController),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: AnalysisTab(
            profileId: profileId,
            mode: mode,
            todayProvider: () => today ?? kToday,
            readOnly: readOnly,
            guardiansRepository: guardiansRepository,
          ),
        ),
      ),
    );
  }

  Future<String> pump({
    ProfileMode mode = ProfileMode.standard,
    List<LocalDate> starts = const [],
    int lengthDays = 4,
    bool readOnly = false,
    AuthController? authController,
    ProfileGuardiansRepository? guardiansRepository,
    LocalDate? today,
  }) async {
    final profiles = DriftProfilesRepository(db.storage);
    final entries = DriftDayEntriesRepository(db.storage);
    final profile =
        await profiles.create(displayName: 'Alice', isMinor: false);
    if (starts.isNotEmpty) {
      await seedEpisodes(entries, profile.id, starts, lengthDays: lengthDays);
    }
    await tester.pumpWidget(widgetFor(
      profile.id,
      mode: mode,
      readOnly: readOnly,
      authController: authController,
      guardiansRepository: guardiansRepository,
      today: today,
    ));
    await tester.pumpAndSettle();
    return profile.id;
  }

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await db.close();
  }
}

String? textAt(WidgetTester tester, String key) {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<Text>(finder).data;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets(
      'headline stats render from ActivePrediction fields, and the '
      'disclaimer is present', (tester) async {
    final h = Harness(tester);
    await h.pump(starts: kSteadyStarts);

    expect(find.text('Analysis'), findsOneWidget);
    expect(find.byKey(const ValueKey('analysis-stats')), findsOneWidget);
    expect(textAt(tester, 'analysis-mean-cycle-length'), '30 days');
    expect(textAt(tester, 'analysis-mean-period-length'), '4 days');
    expect(textAt(tester, 'analysis-variability'),
        'High confidence (±0 days)');
    expect(textAt(tester, 'analysis-disclaimer'), kDisclaimer);

    await h.dispose();
  });

  testWidgets(
      'fewer than 3 valid cycles shows an honest not-enough-history state, '
      'not a misleading chart', (tester) async {
    final h = Harness(tester);
    await h.pump(starts: kNotEnoughStarts);

    expect(find.byKey(const ValueKey('analysis-not-enough')), findsOneWidget);
    expect(find.text('Not enough history yet'), findsOneWidget);
    expect(textAt(tester, 'analysis-not-enough-disclaimer'), kDisclaimer);
    expect(find.byKey(const ValueKey('analysis-stats')), findsNothing);

    await h.dispose();
  });

  testWidgets(
      'irregular hides the tier caption but still shows the statistics '
      '(#131: showsTierCaption scopes the caption only, never the '
      'digits)', (tester) async {
    final h = Harness(tester);
    await h.pump(starts: kSteadyStarts, mode: ProfileMode.irregular);

    expect(textAt(tester, 'analysis-mean-cycle-length'), '30 days');
    expect(textAt(tester, 'analysis-mean-period-length'), '4 days');
    // The tier-name prefix ("High confidence") is the caption — silenced
    // in irregular mode — but the spread digit itself still renders. (The
    // history section below independently renders its own "High
    // confidence" confidence chip — unrelated to this headline row, and
    // out of scope for this assertion.)
    expect(textAt(tester, 'analysis-variability'), '±0 days');

    await h.dispose();
  });

  testWidgets(
      'renders exactly one disclaimer and no duplicate history stats row '
      '— the headline card owns the numbers on this tab (review finding '
      'on #315)', (tester) async {
    final h = Harness(tester);
    await h.pump(starts: kSteadyStarts);

    expect(find.text(kDisclaimer), findsOneWidget);
    expect(find.byKey(const ValueKey('history-stats')), findsNothing);
    expect(find.byKey(const ValueKey('history-disclaimer')), findsNothing);
    expect(find.textContaining('Avg cycle'), findsNothing);

    await h.dispose();
  });

  testWidgets('the existing cycle-history section is mounted on this tab',
      (tester) async {
    final h = Harness(tester);
    await h.pump(starts: kSteadyStarts);

    expect(find.byKey(const ValueKey('history-card')), findsOneWidget);
    expect(find.text('Cycle history'), findsOneWidget);

    await h.dispose();
  });

  testWidgets(
      'issue #314: omitting a cycle through the mounted history section '
      'updates this tab\'s own headline stats -- both read the same '
      'CyclePredictionService/CycleExclusionList now that Overview no '
      'longer has its own copy of either the section or the estimate to '
      'cross-check against', (tester) async {
    final h = Harness(tester);
    await h.pump(starts: kShortOutlierStarts, today: LocalDate(2026, 6, 21));

    // Lengths [28, 28, 20, 28] average to 26.0 exactly.
    expect(textAt(tester, 'analysis-mean-cycle-length'), '26 days');

    await tester.tap(find.byKey(const ValueKey('history-omit-2026-04-05')));
    await tester.pumpAndSettle();

    // Omitting the 20-day cycle leaves [28, 28, 28] -- 28.0 exactly. The
    // headline card and the history section below it derive this from
    // the same CyclePredictionService/CycleExclusionList pair, so the
    // omit tap (a history-section affordance) is reflected here with no
    // separate wiring.
    expect(textAt(tester, 'analysis-mean-cycle-length'), '28 days');
    expect(find.text('Excluded from averages'), findsOneWidget);

    await h.dispose();
  });

  group('viewer-role read-only gating (review finding on #315)', () {
    testWidgets(
        'a viewer-role guardian sees no omit/include affordance in the '
        'history section', (tester) async {
      final h = Harness(tester);
      final profiles = DriftProfilesRepository(h.db.storage);
      final entries = DriftDayEntriesRepository(h.db.storage);
      final profile =
          await profiles.create(displayName: 'Alice', isMinor: false);
      await seedEpisodes(entries, profile.id, kSteadyStarts);
      await h.db.storage.applyRemoteRows([
        guardianRow(profile.id, 'g-doc', 'user-doc', 'viewer'),
      ]);
      final auth = FakeAuthService()
        ..emit(AuthSessionState.signedIn, user: const AuthUser(id: 'user-doc'));
      final authController = AuthController(authService: auth);

      await h.tester.pumpWidget(h.widgetFor(
        profile.id,
        authController: authController,
        guardiansRepository: ProfileGuardiansRepository(h.db.storage),
      ));
      await h.tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('history-card')), findsOneWidget);
      expect(find.textContaining('Omit'), findsNothing);
      expect(find.textContaining('Include'), findsNothing);

      await h.dispose();
    });

    testWidgets('readOnly: true does the same, with no guardian row needed',
        (tester) async {
      final h = Harness(tester);
      await h.pump(starts: kSteadyStarts, readOnly: true);

      expect(find.byKey(const ValueKey('history-card')), findsOneWidget);
      expect(find.textContaining('Omit'), findsNothing);
      expect(find.textContaining('Include'), findsNothing);

      await h.dispose();
    });

    testWidgets(
        'an accepted co-parent guardian keeps the omit affordance '
        '(sanity check: the gate is role-specific, not "any guardian '
        'row")', (tester) async {
      final h = Harness(tester);
      final profiles = DriftProfilesRepository(h.db.storage);
      final entries = DriftDayEntriesRepository(h.db.storage);
      final profile =
          await profiles.create(displayName: 'Alice', isMinor: false);
      await seedEpisodes(entries, profile.id, kSteadyStarts);
      await h.db.storage.applyRemoteRows([
        guardianRow(profile.id, 'g-dad', 'user-dad', 'co_parent'),
      ]);
      final auth = FakeAuthService()
        ..emit(AuthSessionState.signedIn, user: const AuthUser(id: 'user-dad'));
      final authController = AuthController(authService: auth);

      await h.tester.pumpWidget(h.widgetFor(
        profile.id,
        authController: authController,
        guardiansRepository: ProfileGuardiansRepository(h.db.storage),
      ));
      await h.tester.pumpAndSettle();

      expect(find.textContaining('Omit'), findsWidgets);

      await h.dispose();
    });
  });

  testWidgets(
      'didUpdateWidget: switching profileId swaps this tab\'s content with '
      'no carryover from the previous profile', (tester) async {
    final h = Harness(tester);
    final profiles = DriftProfilesRepository(h.db.storage);
    final entries = DriftDayEntriesRepository(h.db.storage);
    final alice =
        await profiles.create(displayName: 'Alice', isMinor: false);
    final bob = await profiles.create(displayName: 'Bob', isMinor: false);
    await seedEpisodes(entries, alice.id, kSteadyStarts);
    await seedEpisodes(entries, bob.id, kNotEnoughStarts);

    await tester.pumpWidget(h.widgetFor(alice.id));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('analysis-stats')), findsOneWidget);
    expect(textAt(tester, 'analysis-mean-cycle-length'), '30 days');

    // Same widget tree shape (no keys differ), so this rebuilds the same
    // State and exercises AnalysisTab's didUpdateWidget branch rather than
    // tearing down and remounting a fresh one.
    await tester.pumpWidget(h.widgetFor(bob.id));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('analysis-not-enough')), findsOneWidget);
    expect(find.byKey(const ValueKey('analysis-stats')), findsNothing,
        reason: 'no cross-profile carryover');

    await h.dispose();
  });

  group('auth-driven attribution seam (moved from '
      'test/ui/cycle_history_test.dart under issue #314 -- this tab now '
      'has the same auth listener OverviewPanel does, and is the only '
      'screen still mounting CycleHistorySection alongside it)', () {
    testWidgets(
        'signing in while this tab is mounted updates the attribution '
        'context without disturbing the history section below', (tester) async {
      final h = Harness(tester);
      final profiles = DriftProfilesRepository(h.db.storage);
      final entries = DriftDayEntriesRepository(h.db.storage);
      final profile =
          await profiles.create(displayName: 'Alice', isMinor: false);
      await seedEpisodes(entries, profile.id, kSteadyStarts);

      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      final authController = AuthController(authService: auth);
      addTearDown(authController.dispose);

      await tester.pumpWidget(h.widgetFor(
        profile.id,
        authController: authController,
      ));
      await tester.pumpAndSettle();

      // A sign-in while mounted re-runs this tab's auth listener; the
      // history section stays coherent across the change.
      auth.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'user-1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('history-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('analysis-stats')), findsOneWidget);

      await h.dispose();
    });
  });
}
