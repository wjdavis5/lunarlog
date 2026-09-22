/// Widget tests for Issue #850 U6: the calendar's guardian-lens layer
/// defaults (plan D-8).
///
/// A subject keeps the pre-#850 default (the profile's most-used symptom
/// tags). An accepted non-subject member (any logging role) opens with no
/// symptom layers active, so the front calendar answers "when" without a
/// symptom map — flow is not a layer and still renders from the logged
/// entries. Every toggle stays intact: a guardian can turn a symptom layer
/// back on, and that per-device choice then wins over the default. The
/// change is presentation only — no permission or content restriction.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profile_guardians_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';

final LocalDate kToday = LocalDate(2026, 8, 30);

/// Steady 30-day cycles with 4-day bleeds (mirrors
/// `forecast_calendar_test.dart`'s `kSteadyStarts`), so an active estimate
/// renders and the logged bleed fills exercise the always-on flow layer.
final List<LocalDate> kBleedStarts = [
  LocalDate(2026, 6, 6),
  LocalDate(2026, 7, 6),
  LocalDate(2026, 8, 5),
];

/// headache ×3, fatigue ×2, cramps ×1 → the subject's default layer set is
/// [headache, fatigue, cramps].
final Map<LocalDate, List<String>> kTagDays = {
  LocalDate(2026, 8, 10): const ['headache'],
  LocalDate(2026, 8, 11): const ['headache', 'cramps'],
  LocalDate(2026, 8, 12): const ['fatigue'],
  LocalDate(2026, 8, 13): const ['headache', 'fatigue'],
};

/// Materializes a server-authored guardian row locally (mirrors
/// `analysis_tab_test.dart`'s helper), with the #802 `isSubject` marker the
/// lens derives from.
RemoteProfileGuardianRow guardianRow(
  String profileId,
  String id,
  String userId,
  String role, {
  bool isSubject = false,
}) => RemoteProfileGuardianRow(
  id: id,
  profileId: profileId,
  userId: userId,
  role: role,
  status: 'accepted',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  serverVersion: 1,
  isSubject: isSubject,
);

class Harness {
  Harness(this.db, this.entries);

  final LunarLogDatabase db;
  final DriftDayEntriesRepository entries;
}

/// Mounts one [MonthCalendar] for a single accepted membership — the
/// viewer's own row, subject or guardian — resolved through the same
/// `guardiansRepository`/`AuthController` seams production uses.
Future<Harness> pumpCalendar(
  WidgetTester tester, {
  required bool isSubject,
  required String viewerId,
}) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = LunarLogDatabase(NativeDatabase.memory());
  final profiles = DriftProfilesRepository(db.storage);
  final entries = DriftDayEntriesRepository(db.storage);
  final guardians = DriftProfileGuardiansRepository(db.storage);
  final profile = await profiles.create(displayName: 'Alice', isMinor: false);

  for (final start in kBleedStarts) {
    for (var i = 0; i < 4; i++) {
      await entries.save(
        DayEntry(
          id: '',
          profileId: profile.id,
          localDate: start.addDays(i),
          tz: 'America/Chicago',
          flow: FlowLevel.medium,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
    }
  }
  for (final day in kTagDays.entries) {
    await entries.save(
      DayEntry(
        id: '',
        profileId: profile.id,
        localDate: day.key,
        tz: 'America/Chicago',
        flow: FlowLevel.none,
        tags: day.value,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
  }
  await db.storage.applyRemoteRows([
    guardianRow(
      profile.id,
      'g-$viewerId',
      viewerId,
      isSubject ? 'primary_guardian' : 'co_parent',
      isSubject: isSubject,
    ),
  ]);

  final auth = FakeAuthService()
    ..emit(AuthSessionState.signedIn, user: AuthUser(id: viewerId));
  final authController = AuthController(authService: auth);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<DayEntriesRepository>.value(value: entries),
        ChangeNotifierProvider<AuthController>.value(value: authController),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MonthCalendar(
            profileId: profile.id,
            todayProvider: () => kToday,
            guardiansRepository: guardians,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return Harness(db, entries);
}

Future<void> disposeCalendar(WidgetTester tester, Harness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await h.db.close();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('subject lens keeps the unchanged most-used-tags default', (
    tester,
  ) async {
    final h = await pumpCalendar(tester, isSubject: true, viewerId: 'user-mom');

    // The three most-used tags are active, so the layers row shows and each
    // matching day carries a named layer dot.
    expect(
      find.byKey(const ValueKey('symptom-layers-toggle')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('layer-dot-headache-2026-08-10')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('layer-dot-fatigue-2026-08-12')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('symptom-dot-2026-08-10')),
      findsNothing,
      reason: 'a matched layer dot replaces the generic symptom marker',
    );
    expect(find.byKey(const ValueKey('bleed-2026-08-05')), findsOneWidget);

    await disposeCalendar(tester, h);
  });

  testWidgets('guardian lens defaults symptom layers off, flow on', (
    tester,
  ) async {
    final h = await pumpCalendar(tester, isSubject: false, viewerId: 'user-dad');

    // No symptom layer is selected: the inline layers row (which only
    // renders with a non-empty layer set) is absent...
    expect(
      find.byKey(const ValueKey('symptom-layers-toggle')),
      findsNothing,
    );
    // ...and the tag day falls back to the generic symptom marker, never a
    // named layer dot.
    expect(
      find.byKey(const ValueKey('layer-dot-headache-2026-08-10')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('symptom-dot-2026-08-10')),
      findsOneWidget,
    );
    // Flow is not a layer — the logged bleed fill still renders.
    expect(find.byKey(const ValueKey('bleed-2026-08-05')), findsOneWidget);

    await disposeCalendar(tester, h);
  });

  testWidgets('a guardian can still toggle a symptom layer on', (
    tester,
  ) async {
    final h = await pumpCalendar(tester, isSubject: false, viewerId: 'user-dad');

    expect(
      find.byKey(const ValueKey('layer-dot-headache-2026-08-10')),
      findsNothing,
    );

    // With no layer active the inline toggle is hidden, so the chooser is
    // reached through the info sheet — the same path a real guardian uses.
    await tester.tap(find.byKey(const ValueKey('legend-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('symptom-layers-open')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('symptom-layers-panel')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('layer-chip-headache')));
    await tester.pumpAndSettle();

    // Dismiss the chooser; the parent calendar's selection is already set.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // The toggle wins over the guardian default: the layer dot now renders
    // and the inline layers row appears.
    expect(
      find.byKey(const ValueKey('layer-dot-headache-2026-08-10')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('symptom-layers-toggle')),
      findsOneWidget,
    );

    await disposeCalendar(tester, h);
  });
}
