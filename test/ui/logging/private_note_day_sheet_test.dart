/// Issue #849 (re-scoped) widget coverage: the per-note private toggle.
///
/// The subject (a membership stamped `isSubject`) sees the "Keep this note
/// private" toggle above the note field while the note is being written, and
/// the flag rides the entry into storage. Every other guardian — even the
/// profile owner — never sees the toggle, and a private note whose text the
/// server masked to null renders as the "Private note" placeholder instead of
/// an editor.
///
/// Issue #1071 adds the write-then-decide coverage: the toggle is never
/// hidden, the first persist of a non-empty note is held back until the
/// writer chooses (or the sheet leaves), and a locked note keeps the control
/// visible and disabled with the saved hint.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/sync/remote_rows.dart' show SyncTable;
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

/// The pump harness: the database, the profile it created, and the entry
/// repository — so a test can query saved rows and re-open a sheet on the
/// same store.
class _Sheet {
  _Sheet(this.db, this.profileId, this.entries);

  final LunarLogDatabase db;
  final String profileId;
  final DriftDayEntriesRepository entries;
}

Future<_Sheet> _pumpSheet(
  WidgetTester tester, {
  required String? viewerId,
  required DayEntry? existing,
  bool readOnly = false,
  String? pushedNote,
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

  final scoped = pushedNote == null
      ? _scope(existing, profile.id)
      : await _persistPushedNote(db, entries, profile.id, pushedNote);

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
  return _Sheet(db, profile.id, entries);
}

/// Re-points an [existing] fixture at the freshly created profile id (the
/// fixture is written before the profile exists).
DayEntry? _scope(DayEntry? existing, String profileId) => existing == null
    ? null
    : DayEntry(
        id: existing.id,
        profileId: profileId,
        localDate: existing.localDate,
        tz: existing.tz,
        flow: existing.flow,
        note: existing.note,
        notePrivate: existing.notePrivate,
        updatedAt: existing.updatedAt,
        loggedByUserId: existing.loggedByUserId,
      );

/// Persists a note and then clears the row's `dirty` flag the way a completed
/// sync push would, so `DayEntrySyncStateReader.hasBeenShared` reads true —
/// the real "the note has been shared" state, no sign-in involved.
Future<DayEntry> _persistPushedNote(
  LunarLogDatabase db,
  DriftDayEntriesRepository entries,
  String profileId,
  String note,
) async {
  final saved = await entries.save(
    DayEntry(
      id: 'entry-1',
      profileId: profileId,
      localDate: _today,
      tz: 'America/New_York',
      flow: FlowLevel.medium,
      note: note,
      updatedAt: DateTime.utc(2026, 8, 30, 12),
      loggedByUserId: _daughter,
    ),
  );
  final row = (await db.storage.getDayEntry(
    profileId: profileId,
    localDate: _today.iso,
  ))!;
  await db.storage.markPushed(
    table: SyncTable.dayEntries,
    id: saved.id,
    localRevAtPush: row.localRev,
  );
  return DayEntry(
    id: saved.id,
    profileId: profileId,
    localDate: _today,
    tz: 'America/New_York',
    flow: FlowLevel.medium,
    note: note,
    updatedAt: row.updatedAt,
    loggedByUserId: _daughter,
  );
}

DayEntry _savedNote(String? note) => DayEntry(
      id: 'entry-1',
      profileId: 'unused',
      localDate: _today,
      tz: 'America/New_York',
      flow: FlowLevel.medium,
      note: note,
      updatedAt: DateTime.utc(2026, 8, 30, 12),
      loggedByUserId: _daughter,
    );

Future<void> _enterNote(WidgetTester tester, String text) async {
  final field = find.byKey(const ValueKey('note-field'));
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, text);
}

/// Pumps past the autosave debounce and settles, so whatever write was armed
/// has completed by the time it returns.
Future<void> _pumpAutosave(WidgetTester tester) async {
  await tester.pump(kDaySheetAutosaveDelay);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
}

Future<void> _tearDown(WidgetTester tester, LunarLogDatabase db) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await db.close();
}

void main() {
  testWidgets(
    'ticking first then writing persists the private flag (issue #849)',
    (tester) async {
      final sheet = await _pumpSheet(
        tester,
        viewerId: _daughter,
        existing: null,
      );

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

      await _enterNote(tester, 'only for me');
      await _pumpAutosave(tester);

      final saved = (await sheet.db.select(sheet.db.dayEntries).get()).single;
      expect(saved.note, 'only for me');
      expect(saved.notePrivate, isTrue);

      await _tearDown(tester, sheet.db);
    },
  );

  testWidgets(
    'writing first then ticking still saves the flag private (issue #1071)',
    (tester) async {
      final sheet = await _pumpSheet(
        tester,
        viewerId: _daughter,
        existing: null,
      );

      await _enterNote(tester, 'Felt off today');
      await _pumpAutosave(tester);

      // The control never disappears: after the first autosave the note is
      // still unchosen, so the toggle stays visible and enabled.
      final toggle = find.byKey(const ValueKey('note-private-toggle'));
      expect(toggle, findsOneWidget);
      expect(find.text('Keep this note private'), findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(toggle).onChanged,
        isNotNull,
        reason: 'the writer can still choose privacy after typing',
      );

      final before = (await sheet.db.select(sheet.db.dayEntries).get()).single;
      expect(
        before.note,
        isNull,
        reason: 'the first persist of the note is held back for the choice',
      );

      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pump();
      await _pumpAutosave(tester);

      final saved = (await sheet.db.select(sheet.db.dayEntries).get()).single;
      expect(saved.note, 'Felt off today');
      expect(saved.notePrivate, isTrue);

      await _tearDown(tester, sheet.db);
    },
  );

  testWidgets(
    'a pushed (dirty == false) note locks the toggle but keeps it visible '
    'with the hint (issue #1071 follow-up)',
    (tester) async {
      final sheet = await _pumpSheet(
        tester,
        viewerId: _daughter,
        existing: null,
        pushedNote: 'already shared',
      );

      final toggle = find.byKey(const ValueKey('note-private-toggle'));
      expect(
        toggle,
        findsOneWidget,
        reason: 'a locked note never hides the control',
      );
      expect(
        tester.widget<CheckboxListTile>(toggle).onChanged,
        isNull,
        reason: 'a note that was already shared can no longer be made private',
      );
      expect(
        find.text(
          "Privacy is chosen when the note is written, and can't be changed "
          "after it's saved.",
        ),
        findsOneWidget,
      );

      await _tearDown(tester, sheet.db);
    },
  );

  testWidgets(
    'a local-only operator can type then choose private — the lock no longer '
    'special-cases sign-in (issue #1071 follow-up)',
    (tester) async {
      final sheet = await _pumpSheet(
        tester,
        viewerId: null,
        existing: null,
      );

      await _enterNote(tester, 'Felt off today');
      await _pumpAutosave(tester);

      final toggle = find.byKey(const ValueKey('note-private-toggle'));
      expect(toggle, findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(toggle).onChanged,
        isNotNull,
        reason: 'a local-only row never pushes, so its choice stays open',
      );

      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pump();
      await _pumpAutosave(tester);

      final saved = (await sheet.db.select(sheet.db.dayEntries).get()).single;
      expect(saved.note, 'Felt off today');
      expect(saved.notePrivate, isTrue);

      await _tearDown(tester, sheet.db);
    },
  );

  testWidgets(
    'a signed-in subject with an unpushed (dirty) note can still choose '
    'private (issue #1071 follow-up)',
    (tester) async {
      final sheet = await _pumpSheet(
        tester,
        viewerId: _daughter,
        existing: null,
      );

      await _enterNote(tester, 'offline note');
      await _pumpAutosave(tester);

      // The held first persist leaves the server empty and the row unsynced,
      // so nothing has been shared and the choice is still legal.
      final mid = (await sheet.db.select(sheet.db.dayEntries).get()).single;
      expect(
        mid.note,
        isNull,
        reason: 'the first persist of the note is still held back',
      );
      expect(
        mid.dirty,
        isTrue,
        reason: 'a local write is not yet shared with the server',
      );

      final toggle = find.byKey(const ValueKey('note-private-toggle'));
      expect(
        tester.widget<CheckboxListTile>(toggle).onChanged,
        isNotNull,
        reason: 'never-pushed means never-locked, signed in or not',
      );

      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pump();
      await _pumpAutosave(tester);

      final saved = (await sheet.db.select(sheet.db.dayEntries).get()).single;
      expect(saved.note, 'offline note');
      expect(
        saved.notePrivate,
        isTrue,
        reason: 'the flip is still legal because the server note is empty',
      );

      await _tearDown(tester, sheet.db);
    },
  );

  testWidgets(
    'dismissing with an unchosen note shares it as written (issue #1071)',
    (tester) async {
      final sheet = await _pumpSheet(
        tester,
        viewerId: _daughter,
        existing: null,
      );

      await _enterNote(tester, 'typed then closed');
      // Deliberately do not wait out the autosave debounce: teardown must
      // flush the held note rather than drop it.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      final saved = (await sheet.db.select(sheet.db.dayEntries).get()).single;
      expect(saved.note, 'typed then closed');
      expect(
        saved.notePrivate,
        isFalse,
        reason: 'no privacy choice was made, so the note is shared as written',
      );

      await sheet.db.close();
    },
  );

  testWidgets(
    'backgrounding the app flushes a held note so a kill cannot lose it '
    '(issue #1071)',
    (tester) async {
      final sheet = await _pumpSheet(
        tester,
        viewerId: _daughter,
        existing: null,
      );

      await _enterNote(tester, 'typed then backgrounded');
      // Drive the sheet's own observer directly: the global lifecycle
      // dispatch also reaches an AppLifecycleListener elsewhere in the
      // tree, whose transition assertions do not accept a bare
      // paused -> resumed.
      (tester.state(find.byType(DaySheet)) as WidgetsBindingObserver)
          .didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      final saved = (await sheet.db.select(sheet.db.dayEntries).get()).single;
      expect(saved.note, 'typed then backgrounded');
      expect(saved.notePrivate, isFalse);

      await _tearDown(tester, sheet.db);
    },
  );

  testWidgets(
    'a guardian sees no toggle and gets the placeholder for a masked private '
    'note (issue #849)',
    (tester) async {
      final sheet = await _pumpSheet(
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

      await _tearDown(tester, sheet.db);
    },
  );

  testWidgets(
    'a guardian never sees the toggle even for a non-private note '
    '(issue #849/#1071)',
    (tester) async {
      final sheet = await _pumpSheet(
        tester,
        viewerId: _mom,
        existing: _savedNote('visible to everyone'),
      );

      expect(find.byKey(const ValueKey('note-field')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('note-private-toggle')),
        findsNothing,
        reason: 'only the subject may mark a note private',
      );

      await _tearDown(tester, sheet.db);
    },
  );

  testWidgets(
    'a read-only viewer also gets the placeholder, never the editor '
    '(issue #849)',
    (tester) async {
      final sheet = await _pumpSheet(
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

      await _tearDown(tester, sheet.db);
    },
  );
}
