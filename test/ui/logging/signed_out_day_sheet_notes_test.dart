/// Issue #872 widget coverage: the day sheet's "Notes from guardians"
/// section is only rendered when the profile actually has guardians to
/// share with. A signed-out, guardian-less local profile used to end with
/// two note boxes and two near-identical "anyone with access" disclosures,
/// even though there was no guardian, no one else with access, and no
/// actionable difference between the two. It now keeps exactly the single
/// shared "Note" box it has always had.
///
/// The guardian-notes repository is provided (a real Drift-backed one over
/// an in-memory database) so the section *would* render if the call-site
/// gate were absent — the regression this suite exists to catch.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_guardian_notes_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/guardian_notes_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/care/guardian_notes_section.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:provider/provider.dart';

final _today = LocalDate(2026, 8, 30);

ProfileGuardian _guardian(String userId) => ProfileGuardian(
  id: 'g-$userId',
  profileId: 'unused',
  userId: userId,
  role: GuardianRole.coParent,
  status: GuardianStatus.accepted,
  displayName: 'Mom',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

Future<LunarLogDatabase> _pumpSheet(
  WidgetTester tester, {
  required String? currentUserId,
  required List<ProfileGuardian> guardians,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = LunarLogDatabase(NativeDatabase.memory());
  final profile = await DriftProfilesRepository(
    db.storage,
  ).create(displayName: 'Alice', isMinor: false);
  final entries = DriftDayEntriesRepository(db.storage);
  final observations = DriftObservationsRepository(db.storage);
  final notes = DriftGuardianNotesRepository(db.storage);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<DayEntriesRepository>.value(value: entries),
        Provider<ObservationsRepository>.value(value: observations),
        Provider<GuardianNotesRepository>.value(value: notes),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DaySheet(
            repository: entries,
            profileId: profile.id,
            date: _today,
            today: _today,
            currentUserId: currentUserId,
            guardians: guardians,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

void main() {
  testWidgets(
    'a signed-out, guardian-less profile renders exactly one note field '
    'and one disclosure (issue #872)',
    (tester) async {
      final db = await _pumpSheet(
        tester,
        currentUserId: null,
        guardians: const [],
      );

      // The shared day "Note" box is still there, exactly once.
      expect(find.byKey(const ValueKey('note-field')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('day-note-disclosure')),
        findsOneWidget,
      );

      // The guardian-notes section — its second box and near-identical
      // disclosure — is gone.
      expect(
        find.byType(GuardianNotesSection),
        findsNothing,
        reason: 'no guardians means no one to share a guardian note with',
      );
      expect(
        find.byKey(const ValueKey('guardian-note-field')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('guardian-notes-disclosure')),
        findsNothing,
      );
      expect(find.text('Notes from guardians'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    },
  );

  testWidgets(
    'a signed-in guardian-less profile also keeps the single shared note '
    'box (issue #872 keys on guardians too)',
    (tester) async {
      final db = await _pumpSheet(
        tester,
        currentUserId: 'user-mom',
        guardians: const [],
      );

      expect(find.byKey(const ValueKey('note-field')), findsOneWidget);
      expect(find.byType(GuardianNotesSection), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    },
  );

  testWidgets(
    'a profile with an accepted guardian still renders the guardian-notes '
    'section as before (issue #872 must not regress the shared case)',
    (tester) async {
      final db = await _pumpSheet(
        tester,
        currentUserId: 'user-mom',
        guardians: [_guardian('user-mom')],
      );

      expect(find.byType(GuardianNotesSection), findsOneWidget);
      expect(find.text('Notes from guardians'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('guardian-notes-disclosure')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('guardian-note-field')),
        findsOneWidget,
      );
      // The shared day note is still present alongside it.
      expect(find.byKey(const ValueKey('note-field')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    },
  );
}
