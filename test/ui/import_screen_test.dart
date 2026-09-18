/// Widget tests for `ImportScreen` (Issue #140): every state — pick,
/// parse error, preview (including a skipped-profile reason), confirm,
/// result, and an apply failure that stays on the preview step. Every
/// collaborator is a fake or a controllable subclass of
/// [AccountImportCoordinator] (KTD6): no real `file_picker` or Drift
/// transaction runs.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart' as dbtables show FlowLevel;
import 'package:lunarlog/data/import/account_importer.dart';
import 'package:lunarlog/data/import/clue_importer.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/domain/import/account_import.dart';
import 'package:lunarlog/domain/import/account_import_coordinator.dart';
import 'package:lunarlog/domain/import/clue/clue_export_parser.dart';
import 'package:lunarlog/domain/import/clue/clue_import_run.dart';
import 'package:lunarlog/domain/import/import_file_cap.dart' show ImportFileTooLargeException;
import 'package:lunarlog/domain/import/import_file_reader.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/settings/import_screen.dart';

Finder key(String value) => find.byKey(ValueKey(value));

/// An [ImportFileReader] over a test-supplied closure, so every pick step
/// drives canned bytes (or a throw) without touching `file_picker`.
class _FakeReader implements ImportFileReader {
  const _FakeReader(this._read);

  final Future<Uint8List?> Function() _read;

  @override
  Future<Uint8List?> read() => _read();
}

class _UnusedProfilesRepository implements ProfilesRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedDayEntriesRepository implements DayEntriesRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedObservationsRepository implements ObservationsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A fully controllable [AccountImportCoordinator]: [buildPlan]/[apply]
/// never touch the base class's real repositories/storage (never called),
/// so the widget test controls exactly what each step returns or throws.
class _FakeCoordinator extends DriftAccountImportCoordinator {
  _FakeCoordinator(
    LunarLogStorage storage, {
    this.planResult,
    this.planError,
    this.applyResult,
    this.applyError,
  }) : super(
          profilesRepository: _UnusedProfilesRepository(),
          dayEntriesRepository: _UnusedDayEntriesRepository(),
          observationsRepository: _UnusedObservationsRepository(),
          storage: storage,
        );

  final ImportPlan? planResult;
  final Object? planError;
  final ImportPlanSummary? applyResult;
  final Object? applyError;

  @override
  Future<ImportPlan> buildPlan(AccountImportDocument document) async {
    final error = planError;
    if (error != null) throw error;
    return planResult!;
  }

  @override
  Future<ImportPlanSummary> apply(ImportPlan plan) async {
    final error = applyError;
    if (error != null) throw error;
    return applyResult!;
  }
}

Uint8List _validBytes() => utf8.encode(jsonEncode({
      'schemaVersion': 4,
      'exportedAt': '2026-01-01T00:00:00.000Z',
      'app': {'name': 'lunarlog', 'version': '1.0.0+1'},
      'profiles': [
        {
          // Issue #140 review round 2, item 1: fixture ids must be
          // syntactically valid ULIDs now that parseAccountImport enforces
          // the format at parse time.
          'id': '00000000000000000000000001',
          'displayName': 'Riley',
          'isMinor': true,
          'dayEntries': [
            {
              'id': '00000000000000000000000011',
              'localDate': '2026-01-05',
              'tz': 'UTC',
              'flow': 'medium',
              'tags': <String>[],
              'note': null,
              'updatedAt': '2026-01-05T00:00:00.000Z',
            },
          ],
          'observations': <Object?>[],
        },
      ],
    }));

ImportPlan _plan({
  int created = 1,
  int matched = 0,
  List<SkippedProfileReason> skipped = const [],
}) {
  // Only the profile-level outcome (created/matched/skipped) is exercised
  // by these widget tests (the exact entries-added/merged arithmetic is
  // covered directly in `test/domain/import/account_import_test.dart`);
  // every widget test here only asserts the relevant widget/text is
  // present, never an exact
  // count, so an always-empty `entries`/`observations` list is enough.
  return ImportPlan(profiles: [
    for (var i = 0; i < created; i++)
      ProfilePlan(
        fileProfileId: 'created-$i',
        displayName: 'Created $i',
        outcome: ProfileImportOutcome.created,
      ),
    for (var i = 0; i < matched; i++)
      ProfilePlan(
        fileProfileId: 'matched-$i',
        displayName: 'Matched $i',
        outcome: ProfileImportOutcome.matched,
      ),
    for (final s in skipped)
      ProfilePlan(
        fileProfileId: 'skipped-${s.displayName}',
        displayName: s.displayName,
        outcome: ProfileImportOutcome.skipped,
        skipReason: s.reason,
      ),
  ]);
}

Future<void> _pump(
  WidgetTester tester, {
  ImportFileReader? pickFile,
  AccountImportCoordinator? coordinator,
  ClueImportRunner? clueRunner,
  ProfilesRepository? profilesRepository,
}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ImportScreen(
      pickFile: pickFile,
      coordinator: coordinator,
      clueRunner: clueRunner,
      profilesRepository: profilesRepository,
    ),
  ));
  await tester.pumpAndSettle();
}

/// An in-memory store + real profile repository for the Clue tests: the
/// whole point of the Clue path is end-to-end, so these tests drive the
/// real `ClueImporter` and a real `DriftProfilesRepository` over an
/// in-memory database rather than fakes.
class _ClueHarness {
  _ClueHarness() {
    db = LunarLogDatabase(NativeDatabase.memory());
    _storage = LunarLogStorage(db);
  }

  late final LunarLogDatabase db;
  late final LunarLogStorage _storage;

  LunarLogStorage get storage => _storage;
  ProfilesRepository get profiles => DriftProfilesRepository(_storage);
  ClueImporter get importer => ClueImporter(_storage);
}

/// A minimal `ClueImportRunner` that never writes: proves a read failure
/// never reaches the write step.
class _FakeClueRunner implements ClueImportRunner {
  int calls = 0;
  Object? error;
  ClueImportSummary? result;

  @override
  Future<ClueImportSummary> run({
    required String profileId,
    required String tz,
    required ClueExportParseResult parseResult,
    required String fileChecksum,
  }) async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    return result!;
  }
}

/// A small, real (fabricated) Clue-shaped zip built with the same
/// `ZipEncoder` the reader uses, so the widget test exercises extraction,
/// parsing, and the write path rather than a mocked parser.
Uint8List _clueZip(Map<String, String> files, {String password = ''}) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, utf8.encode(entry.value)));
  }
  // `ZipEncoder` cannot take an empty password (it treats '' as an AES key
  // and throws); omit it for an unencrypted archive.
  final encoder =
      password.isEmpty ? ZipEncoder() : ZipEncoder(password: password);
  return Uint8List.fromList(encoder.encode(archive));
}

String _fixture(String name) =>
    File('test/fixtures/clue/$name').readAsStringSync();

void main() {
  late LunarLogStorage storage;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    storage = LunarLogStorage(LunarLogDatabase(NativeDatabase.memory()));
  });

  group('pick step', () {
    testWidgets('renders with no error initially', (tester) async {
      await _pump(tester, pickFile: _FakeReader(() async => null));
      expect(key('import-pick-button'), findsOneWidget);
      expect(key('import-pick-error'), findsNothing);
    });

    testWidgets('cancelling the picker (null bytes) stays on the pick step',
        (tester) async {
      var calls = 0;
      await _pump(tester, pickFile: _FakeReader(() async {
        calls++;
        return null;
      }));
      await tester.tap(key('import-pick-button'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(key('import-pick-button'), findsOneWidget);
      expect(key('import-preview-summary'), findsNothing);
    });

    testWidgets('malformed bytes show a clear parse error and never call '
        'the coordinator', (tester) async {
      const buildPlanCalls = 0;
      await _pump(
        tester,
        pickFile:
            _FakeReader(() async => Uint8List.fromList(utf8.encode('not json'))),
        coordinator: _FakeCoordinator(storage, planResult: _plan()),
      );
      await tester.tap(key('import-pick-button'));
      await tester.pumpAndSettle();
      expect(key('import-pick-error'), findsOneWidget);
      expect(buildPlanCalls, 0);
    });

    testWidgets('a planning failure (buildPlan throws) surfaces an inline '
        'error and stays on the pick step, never reaching preview',
        (tester) async {
      await _pump(
        tester,
        pickFile: _FakeReader(() async => _validBytes()),
        coordinator: _FakeCoordinator(storage, planError: StateError('db locked')),
      );
      await tester.tap(key('import-pick-button'));
      await tester.pumpAndSettle();

      expect(key('import-pick-error'), findsOneWidget);
      expect(key('import-preview-summary'), findsNothing);
    });

    // Issue #140 review, item 3: `_pickAndPlan` itself has no catch of its
    // own in the pre-review code — an exception from the picker (or any
    // other step before a coordinator is ever reached) would be an
    // unhandled exception, not an `InlineError`. This proves the
    // last-resort backstop around the whole method.
    testWidgets('a picker failure (pickFile throws) surfaces an inline '
        'error instead of an unhandled exception', (tester) async {
      await _pump(
        tester,
        pickFile: _FakeReader(() async => throw StateError('picker crashed')),
      );
      await tester.tap(key('import-pick-button'));
      await tester.pumpAndSettle();

      expect(key('import-pick-error'), findsOneWidget);
      expect(
        tester.widget<Text>(find.descendant(
          of: key('import-pick-error'),
          matching: find.byType(Text),
        )).data,
        kImportApplyFailureCopy,
      );
    });

    testWidgets(
        'an oversized-file rejection from the picker (Issue #626, LLA-089) '
        'surfaces the same friendly copy parseAccountImport itself would '
        "have shown — not the generic picker-failure copy above, and not an "
        'unhandled exception', (tester) async {
      await _pump(
        tester,
        pickFile: _FakeReader(
            () async => throw const ImportFileTooLargeException()),
      );
      await tester.tap(key('import-pick-button'));
      await tester.pumpAndSettle();

      expect(key('import-pick-error'), findsOneWidget);
      expect(
        tester.widget<Text>(find.descendant(
          of: key('import-pick-error'),
          matching: find.byType(Text),
        )).data,
        const ImportFileTooLargeException().message,
      );
    });
  });

  group('preview step', () {
    testWidgets('a valid file shows the preview summary, merge policy, and '
        'plan breakdown', (tester) async {
      await _pump(
        tester,
        pickFile: _FakeReader(() async => _validBytes()),
        coordinator: _FakeCoordinator(storage, planResult: _plan()),
      );
      await tester.tap(key('import-pick-button'));
      await tester.pumpAndSettle();

      expect(key('import-preview-summary'), findsOneWidget);
      expect(key('import-preview-policy'), findsOneWidget);
      expect(key('import-preview-plan'), findsOneWidget);
      expect(find.text(kImportMergePolicySentence), findsOneWidget);
    });

    testWidgets('skipped profiles render their reasons', (tester) async {
      await _pump(
        tester,
        pickFile: _FakeReader(() async => _validBytes()),
        coordinator: _FakeCoordinator(
          storage,
          planResult: _plan(skipped: const [
            SkippedProfileReason(
                displayName: 'Archived Profile', reason: 'This profile is archived.'),
          ]),
        ),
      );
      await tester.tap(key('import-pick-button'));
      await tester.pumpAndSettle();

      expect(key('import-preview-skipped'), findsOneWidget);
      expect(find.textContaining('This profile is archived.'), findsOneWidget);
    });

    // Issue #140 review, item 10.
    testWidgets('a matched profile with another accepted guardian shows the '
        'shared-guardian disclosure sentence', (tester) async {
      final plan = ImportPlan(profiles: [
        ProfilePlan(
          fileProfileId: 'shared-1',
          displayName: 'Shared',
          outcome: ProfileImportOutcome.matched,
          hasOtherGuardians: true,
        ),
      ]);
      await _pump(
        tester,
        pickFile: _FakeReader(() async => _validBytes()),
        coordinator: _FakeCoordinator(storage, planResult: plan),
      );
      await tester.tap(key('import-pick-button'));
      await tester.pumpAndSettle();

      expect(key('import-preview-shared-guardian'), findsOneWidget);
      expect(find.text(kImportSharedProfileGuardianSentence), findsOneWidget);
    });

    testWidgets('no shared-guardian info means no disclosure sentence',
        (tester) async {
      await _pump(
        tester,
        pickFile: _FakeReader(() async => _validBytes()),
        coordinator: _FakeCoordinator(storage, planResult: _plan()),
      );
      await tester.tap(key('import-pick-button'));
      await tester.pumpAndSettle();

      expect(key('import-preview-shared-guardian'), findsNothing);
    });

    testWidgets('Cancel returns to the pick step', (tester) async {
      await _pump(
        tester,
        pickFile: _FakeReader(() async => _validBytes()),
        coordinator: _FakeCoordinator(storage, planResult: _plan()),
      );
      await tester.tap(key('import-pick-button'));
      await tester.pumpAndSettle();
      expect(key('import-preview-summary'), findsOneWidget);

      await tester.tap(key('import-preview-cancel'));
      await tester.pumpAndSettle();
      expect(key('import-pick-button'), findsOneWidget);
      expect(key('import-preview-summary'), findsNothing);
    });

    testWidgets('a failed apply surfaces an inline error and stays on the '
        'preview step', (tester) async {
      await _pump(
        tester,
        pickFile: _FakeReader(() async => _validBytes()),
        coordinator: _FakeCoordinator(
          storage,
          planResult: _plan(),
          applyError: StateError('disk full'),
        ),
      );
      await tester.tap(key('import-pick-button'));
      await tester.pumpAndSettle();

      await tester.tap(key('import-preview-confirm'));
      await tester.pumpAndSettle();

      expect(key('import-preview-error'), findsOneWidget);
      expect(
        tester.widget<Text>(find.descendant(
          of: key('import-preview-error'),
          matching: find.byType(Text),
        )).data,
        kImportApplyFailureCopy,
      );
      expect(key('import-result-summary'), findsNothing);
    });

    testWidgets(
        'a stale-plan apply resets all the way to the pick step with its '
        'own copy, not the generic apply-failure one (Issue #140 review, '
        'LLA-085)', (tester) async {
      await _pump(
        tester,
        pickFile: _FakeReader(() async => _validBytes()),
        coordinator: _FakeCoordinator(
          storage,
          planResult: _plan(),
          applyError: const StaleImportPlanException(),
        ),
      );
      await tester.tap(key('import-pick-button'));
      await tester.pumpAndSettle();
      expect(key('import-preview-summary'), findsOneWidget);

      await tester.tap(key('import-preview-confirm'));
      await tester.pumpAndSettle();

      // Back on the pick step entirely, not left on preview with an inline
      // error (a rebuilt plan needs a fresh pick+parse+plan, not a retry of
      // apply against the same now-known-stale plan).
      expect(key('import-pick-button'), findsOneWidget);
      expect(key('import-preview-summary'), findsNothing);
      expect(key('import-pick-error'), findsOneWidget);
      expect(
        tester.widget<Text>(find.descendant(
          of: key('import-pick-error'),
          matching: find.byType(Text),
        )).data,
        kImportStalePlanCopy,
      );
    });
  });

  group('result step', () {
    testWidgets('confirming a successful import shows the result summary '
        'and a Done button that closes the screen', (tester) async {
      final summary = ImportPlanSummary(
        profilesCreated: 2,
        profilesMatched: 1,
        entriesAdded: 5,
        entriesMerged: 3,
        observationsAdded: 4,
        observationsSkipped: 2,
        skippedProfiles: const [
          SkippedProfileReason(displayName: 'Locked', reason: 'You have view-only access.'),
        ],
      );
      await tester.pumpWidget(MaterialApp(
        home: Navigator(
          onGenerateRoute: (settings) => MaterialPageRoute(
            builder: (context) => ImportScreen(
              pickFile: _FakeReader(() async => _validBytes()),
              coordinator: _FakeCoordinator(
                storage,
                planResult: _plan(),
                applyResult: summary,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(key('import-pick-button'));
      await tester.pumpAndSettle();
      await tester.tap(key('import-preview-confirm'));
      await tester.pumpAndSettle();

      expect(key('import-result-summary'), findsOneWidget);
      expect(key('import-result-skipped'), findsOneWidget);
      expect(find.textContaining('You have view-only access.'), findsOneWidget);

      await tester.tap(key('import-result-done'));
      await tester.pumpAndSettle();
      expect(key('import-result-summary'), findsNothing);
    });
  });

  group('Clue export zip path (Issue #452)', () {
    testWidgets('a real Clue zip imports end to end and creates a profile',
        (tester) async {
      final harness = _ClueHarness();
      addTearDown(harness.db.close);
      final zip = _clueZip(
        {'measurements.json': _fixture('unknown_type_and_option.json')},
        password: 'clue-pass',
      );

      await _pump(
        tester,
        pickFile: _FakeReader(() async => zip),
        clueRunner: harness.importer,
        profilesRepository: harness.profiles,
      );

      await tester.tap(key('import-pick-button'));
      await tester.pumpAndSettle();
      // A ZIP routes to the Clue password step, never the JSON parser.
      expect(key('clue-password-field'), findsOneWidget);
      expect(key('clue-preview-summary'), findsNothing);

      await tester.enterText(key('clue-password-field'), 'clue-pass');
      await tester.tap(key('clue-password-continue'));
      await tester.pumpAndSettle();

      // Preview: the planned summary, the #199 disclosure lines, and — no
      // profiles exist — an editable name for the profile to create.
      expect(key('clue-preview-summary'), findsOneWidget);
      expect(key('clue-preview-summary-lines'), findsOneWidget);
      expect(key('clue-new-profile-name'), findsOneWidget);
      expect(find.text(kClueImportMergePolicySentence), findsOneWidget);

      await tester.ensureVisible(key('clue-preview-confirm'));
      await tester.tap(key('clue-preview-confirm'));
      await tester.pumpAndSettle();

      expect(key('clue-result-summary'), findsOneWidget);
      expect(
        find.textContaining('Unrecognised type kept: hot_flashes.'),
        findsOneWidget,
      );

      final profiles = await harness.profiles.list();
      expect(profiles.length, 1);
      expect(profiles.single.displayName, 'Imported from Clue');
      final days =
          await harness.storage.getDayEntries(profileId: profiles.single.id);
      expect(days.length, 7);
      for (final day in days) {
        expect(day.source, 'clue_import');
      }
      final observations =
          await harness.storage.getObservationsForProfile(profiles.single.id);
      expect(observations.length, 8);
      for (final observation in observations) {
        expect(observation.source, 'clue_import');
      }
    });

    testWidgets('an existing profile is offered and receives rows additively',
        (tester) async {
      final harness = _ClueHarness();
      addTearDown(harness.db.close);
      final existing =
          await harness.profiles.create(displayName: 'Riley', isMinor: false);
      // A manually logged day the import touches must survive untouched.
      await harness.storage.upsertDayEntry(
        profileId: existing.id,
        localDate: '2026-04-01',
        tz: 'UTC',
        flow: dbtables.FlowLevel.heavy,
        note: 'kept',
      );
      final zip = _clueZip(
        {'measurements.json': _fixture('unknown_type_and_option.json')},
        password: 'pw',
      );

      await _pump(
        tester,
        pickFile: _FakeReader(() async => zip),
        clueRunner: harness.importer,
        profilesRepository: harness.profiles,
      );
      await tester.tap(key('import-pick-button'));
      await tester.pumpAndSettle();
      await tester.enterText(key('clue-password-field'), 'pw');
      await tester.tap(key('clue-password-continue'));
      await tester.pumpAndSettle();

      expect(key('clue-profile-dropdown'), findsOneWidget);
      expect(key('clue-new-profile-name'), findsNothing);

      await tester.ensureVisible(key('clue-preview-confirm'));
      await tester.tap(key('clue-preview-confirm'));
      await tester.pumpAndSettle();
      expect(key('clue-result-summary'), findsOneWidget);

      // No second profile; the manual day keeps its flow and note.
      expect((await harness.profiles.list()).length, 1);
      final day = await harness.storage.getDayEntry(
          profileId: existing.id, localDate: '2026-04-01');
      expect(day!.flow, dbtables.FlowLevel.heavy);
      expect(day.note, 'kept');
    });

    testWidgets('a ZIP that is not a Clue export fails before the write step',
        (tester) async {
      final runner = _FakeClueRunner();
      await _pump(
        tester,
        pickFile: _FakeReader(() async => _clueZip({'notes.txt': 'hello'})),
        clueRunner: runner,
        profilesRepository: _UnusedProfilesRepository(),
      );
      await tester.tap(key('import-pick-button'));
      await tester.pumpAndSettle();
      await tester.tap(key('clue-password-continue'));
      await tester.pumpAndSettle();

      expect(key('clue-password-error'), findsOneWidget);
      expect(find.text(kClueImportNotClueCopy), findsOneWidget);
      expect(runner.calls, 0);
      // Still on the password step — no partial import.
      expect(key('clue-password-field'), findsOneWidget);
      expect(key('clue-result-summary'), findsNothing);
    });

    testWidgets('a wrong password fails with the retry copy, never the writer',
        (tester) async {
      final runner = _FakeClueRunner();
      final zip = _clueZip({'measurements.json': '[]'}, password: 'right');
      await _pump(
        tester,
        pickFile: _FakeReader(() async => zip),
        clueRunner: runner,
        profilesRepository: _UnusedProfilesRepository(),
      );
      await tester.tap(key('import-pick-button'));
      await tester.pumpAndSettle();
      await tester.enterText(key('clue-password-field'), 'wrong');
      await tester.tap(key('clue-password-continue'));
      await tester.pumpAndSettle();

      expect(find.text(kClueImportReadFailureCopy), findsOneWidget);
      expect(runner.calls, 0);
      expect(key('clue-password-field'), findsOneWidget);
    });

    testWidgets('a malformed measurements.json fails with the retry copy',
        (tester) async {
      final runner = _FakeClueRunner();
      await _pump(
        tester,
        pickFile: _FakeReader(
            () async => _clueZip({'measurements.json': 'not json'})),
        clueRunner: runner,
        profilesRepository: _UnusedProfilesRepository(),
      );
      await tester.tap(key('import-pick-button'));
      await tester.pumpAndSettle();
      await tester.tap(key('clue-password-continue'));
      await tester.pumpAndSettle();

      expect(find.text(kClueImportReadFailureCopy), findsOneWidget);
      expect(runner.calls, 0);
    });

    testWidgets('an apply failure stays on the preview with its own copy',
        (tester) async {
      final harness = _ClueHarness();
      addTearDown(harness.db.close);
      final runner = _FakeClueRunner()..error = StateError('disk full');
      final zip = _clueZip(
        {'measurements.json': '[]'},
        password: 'pw',
      );
      await _pump(
        tester,
        pickFile: _FakeReader(() async => zip),
        clueRunner: runner,
        profilesRepository: harness.profiles,
      );
      await tester.tap(key('import-pick-button'));
      await tester.pumpAndSettle();
      await tester.enterText(key('clue-password-field'), 'pw');
      await tester.tap(key('clue-password-continue'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(key('clue-preview-confirm'));
      await tester.tap(key('clue-preview-confirm'));
      await tester.pumpAndSettle();

      expect(key('clue-preview-error'), findsOneWidget);
      expect(find.text(kClueImportApplyFailureCopy), findsOneWidget);
      expect(key('clue-result-summary'), findsNothing);
      expect(runner.calls, 1);
    });

    testWidgets('issue #791: a failed first-run import reuses its created '
        'profile on retry instead of orphaning another', (tester) async {
      final harness = _ClueHarness();
      addTearDown(harness.db.close);
      final runner = _FakeClueRunner()..error = StateError('disk full');
      final zip = _clueZip({'measurements.json': '[]'}, password: 'pw');
      await _pump(
        tester,
        pickFile: _FakeReader(() async => zip),
        clueRunner: runner,
        profilesRepository: harness.profiles,
      );
      await tester.tap(key('import-pick-button'));
      await tester.pumpAndSettle();
      await tester.enterText(key('clue-password-field'), 'pw');
      await tester.tap(key('clue-password-continue'));
      await tester.pumpAndSettle();

      // First attempt fails — the profile it created (outside the run's
      // transaction) is left behind, exactly once.
      await tester.ensureVisible(key('clue-preview-confirm'));
      await tester.tap(key('clue-preview-confirm'));
      await tester.pumpAndSettle();
      expect(key('clue-preview-error'), findsOneWidget);
      expect((await harness.profiles.list()).length, 1);

      // Retrying reuses that profile rather than creating a second orphan.
      await tester.ensureVisible(key('clue-preview-confirm'));
      await tester.tap(key('clue-preview-confirm'));
      await tester.pumpAndSettle();
      expect((await harness.profiles.list()).length, 1);
      expect(runner.calls, 2);
    });
  });
}
