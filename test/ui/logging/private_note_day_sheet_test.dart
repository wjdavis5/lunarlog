/// Issue #849 (re-scoped) widget coverage: the per-note private toggle.
///
/// The subject (a membership stamped `isSubject`) sees the "Keep this note
/// private" toggle while the note is being written, and the flag rides the
/// entry into storage. Every other guardian — even the profile owner — never
/// sees the toggle, and a private note whose text the server masked to null
/// renders as the "Private note" placeholder instead of an editor.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:provider/provider.dart';

final _today = LocalDate(2026, 8, 30);
const _mom = 'user-mom';
const _daughter = 'user-daughter';
const _doc = 'user-doc';

ProfileGuardian _guardian(
  String userId,
  GuardianRole role,
  String name, {
  bool isSubject = false,
}) =>
    ProfileGuardian(
      id: 'g-$userId',
      profileId: 'unused',
      userId: userId,
      role: role,
      status: GuardianStatus.accepted,
      displayName: name,
      isSubject: isSubject,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

final _guardians = [
  _guardian(_mom, GuardianRole.coParent, 'Mom'),
  _guardian(_daughter, GuardianRole.caregiver, 'Daughter', isSubject: true),
  _guardian(_doc, GuardianRole.viewer, 'Dr. Lee'),
];

Future<LunarLogDatabase> _pumpSheet(
  WidgetTester tester, {
  required String viewerId,
  required DayEntry? existing,
  bool readOnly = false,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = LunarLogDatabase(NativeDatabase.memory());
  final profile = await DriftProfilesRepository(
    db.storage,
  ).create(displayName: 'Riley', isMinor: true);
  final entries = DriftDayEntriesRepository(db.storage);
  final observations = DriftObservationsRepository(db.storage);

  final scoped = existing == null
      ? null
      : DayEntry(
          id: existing.id,
          profileId: profile.id,
          localDate: existing.localDate,
          tz: existing.tz,
          flow: existing.flow,
          note: existing.note,
          notePrivate: existing.notePrivate,
          updatedAt: existing.updatedAt,
          loggedByUserId: existing.loggedByUserId,
        );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<DayEntriesRepository>.value(value: entries),
        Provider<ObservationsRepository>.value(value: observations),
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
            existing: scoped,
            readOnly: readOnly,
            currentUserId: viewerId,
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
    'the subject sees the private-note toggle while writing, and the flag '
    'rides the saved entry (issue #849)',
    (tester) async {
      final db = await _pumpSheet(tester, viewerId: _daughter, existing: null);

      expect(find.byKey(const ValueKey('note-field')), findsOneWidget);
      final toggle = find.byKey(const ValueKey('note-private-toggle'));
      expect(toggle, findsOneWidget);
      expect(find.text('Keep this note private'), findsOneWidget);

      expect(
        tester.widget<CheckboxListTile>(toggle).onChanged,
        isNotNull,
        reason: 'the toggle is enabled while the note is empty',
      );
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pump();
      expect(
        tester.widget<CheckboxListTile>(toggle).value,
        isTrue,
        reason: 'tapping the toggle marks the note private',
      );
      await tester.enterText(
        find.byKey(const ValueKey('note-field')),
        'only for me',
      );
      // Let the debounced autosave write.
      await tester.pump(kDaySheetAutosaveDelay);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      final rows = await db.select(db.dayEntries).get();
      final saved = rows.single;
      expect(saved.note, 'only for me');
      expect(saved.notePrivate, isTrue);

      await _tearDown(tester, db);
    },
  );

  testWidgets(
    'a guardian sees no toggle and gets the placeholder for a masked private '
    'note (issue #849)',
    (tester) async {
      final db = await _pumpSheet(
        tester,
        viewerId: _mom,
        existing: DayEntry(
          id: 'entry-1',
          profileId: 'unused',
          localDate: _today,
          tz: 'America/New_York',
          flow: FlowLevel.medium,
          note: null,
          notePrivate: true,
          updatedAt: DateTime.utc(2026, 8, 30, 12),
          loggedByUserId: _daughter,
        ),
      );

      expect(find.byKey(const ValueKey('note-private-toggle')), findsNothing);
      expect(find.byKey(const ValueKey('note-field')), findsNothing);
      expect(
        find.byKey(const ValueKey('private-note-placeholder')),
        findsOneWidget,
      );
      expect(find.text('Private note'), findsOneWidget);

      await _tearDown(tester, db);
    },
  );

  testWidgets(
    'a read-only viewer also gets the placeholder, never the editor '
    '(issue #849)',
    (tester) async {
      final db = await _pumpSheet(
        tester,
        viewerId: _doc,
        readOnly: true,
        existing: DayEntry(
          id: 'entry-1',
          profileId: 'unused',
          localDate: _today,
          tz: 'America/New_York',
          flow: FlowLevel.medium,
          note: null,
          notePrivate: true,
          updatedAt: DateTime.utc(2026, 8, 30, 12),
          loggedByUserId: _daughter,
        ),
      );

      // The read-only body renders the placeholder text (not the editable
      // field), and never the toggle.
      expect(find.text('Private note'), findsOneWidget);
      expect(find.byKey(const ValueKey('note-field')), findsNothing);
      expect(find.byKey(const ValueKey('note-private-toggle')), findsNothing);

      await _tearDown(tester, db);
    },
  );
}
