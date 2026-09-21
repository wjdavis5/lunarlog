/// Issue #869 widget coverage: a read-only day sheet — the one a `viewer`
/// (or any guardian without a logging role) gets — renders the guardian-notes
/// section in its read-only shape, so the viewer can actually read every
/// guardian note as `PRIVACY.md` §5 and the open-and-transparent decision on
/// issue #800 say she can.
///
/// Before the fix the section was built only inside the editable body, so
/// `GuardianNotesSection(canWrite: false)` was unreachable from production
/// wiring: the one role the policy names as read-only could not read at all.
///
/// The repository is a real Drift-backed one over an in-memory database so a
/// co-parent's note can be seeded and then found in the viewer's sheet.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_guardian_notes_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
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
const _mom = 'user-mom';
const _doc = 'user-doc';
const _momNote = 'Seemed withdrawn, then rallied by the weekend.';

ProfileGuardian _guardian(String userId, GuardianRole role, String name) =>
    ProfileGuardian(
      id: 'g-$userId',
      profileId: 'unused',
      userId: userId,
      role: role,
      status: GuardianStatus.accepted,
      displayName: name,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

final _guardians = [
  _guardian(_mom, GuardianRole.coParent, 'Mom'),
  _guardian(_doc, GuardianRole.viewer, 'Dr. Lee'),
];

/// Pumps a read-only sheet for the viewer `doc`, after `mom` has written a
/// guardian note for the day. [withEntry] controls whether a shared day
/// entry exists for the date — a guardian note is keyed by date, not by
/// entry, so both read-only branches must show it.
Future<LunarLogDatabase> _pumpViewerSheet(
  WidgetTester tester, {
  required bool withEntry,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = LunarLogDatabase(NativeDatabase.memory());
  final profile = await DriftProfilesRepository(
    db.storage,
  ).create(displayName: 'Alice', isMinor: true);
  final entries = DriftDayEntriesRepository(db.storage);
  final observations = DriftObservationsRepository(db.storage);
  final notes = DriftGuardianNotesRepository(db.storage);

  await notes.save(
    profileId: profile.id,
    localDate: _today,
    tz: 'America/New_York',
    body: _momNote,
    loggedByUserId: _mom,
  );

  DayEntry? existing;
  if (withEntry) {
    existing = DayEntry(
      id: 'entry-1',
      profileId: profile.id,
      localDate: _today,
      tz: 'America/New_York',
      flow: FlowLevel.medium,
      note: 'shared day note',
      updatedAt: DateTime.utc(2026, 8, 30, 12),
      loggedByUserId: _mom,
    );
  }

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
            existing: existing,
            readOnly: true,
            currentUserId: _doc,
            guardians: _guardians,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

Future<void> _tearDown(WidgetTester tester, LunarLogDatabase db) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await db.close();
}

void main() {
  testWidgets(
    'a viewer reads a co-parent\'s guardian note on a read-only sheet with '
    'an entry, and gets no editor (issue #869)',
    (tester) async {
      final db = await _pumpViewerSheet(tester, withEntry: true);

      expect(find.byType(GuardianNotesSection), findsOneWidget);
      expect(find.text('Notes from guardians'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('guardian-notes-disclosure')),
        findsOneWidget,
      );
      // The note itself, attributed to its author, is readable.
      expect(find.text(_momNote), findsOneWidget);
      expect(find.text('Mom'), findsOneWidget);
      // Read-only: no editor, no remove affordance.
      expect(find.byKey(const ValueKey('guardian-note-field')), findsNothing);
      expect(find.byKey(const ValueKey('guardian-note-remove')), findsNothing);
      // And the sheet is still the read-only variant (no shared note editor).
      expect(find.byKey(const ValueKey('note-field')), findsNothing);

      await _tearDown(tester, db);
    },
  );

  testWidgets(
    'a viewer reads the guardian note even when nobody logged an entry for '
    'that day (issue #869: notes are keyed by date, not entry)',
    (tester) async {
      final db = await _pumpViewerSheet(tester, withEntry: false);

      expect(find.byType(GuardianNotesSection), findsOneWidget);
      expect(find.text(_momNote), findsOneWidget);
      expect(find.byKey(const ValueKey('guardian-note-field')), findsNothing);

      await _tearDown(tester, db);
    },
  );
}
