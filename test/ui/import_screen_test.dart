/// Widget tests for `ImportScreen` (Issue #140): every state — pick,
/// parse error, preview (including a skipped-profile reason), confirm,
/// result, and an apply failure that stays on the preview step. Every
/// collaborator is a fake or a controllable subclass of
/// [AccountImportCoordinator] (KTD6): no real `file_picker` or Drift
/// transaction runs.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/import/account_importer.dart';
import 'package:lunarlog/data/import/import_file_picker.dart';
import 'package:lunarlog/domain/import/account_import.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/ui/settings/import_screen.dart';

Finder key(String value) => find.byKey(ValueKey(value));

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
class _FakeCoordinator extends AccountImportCoordinator {
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
}) async {
  await tester.pumpWidget(MaterialApp(
    home: ImportScreen(pickFile: pickFile, coordinator: coordinator),
  ));
  await tester.pumpAndSettle();
}

void main() {
  late LunarLogStorage storage;

  setUpAll(() {
    storage = LunarLogStorage(LunarLogDatabase(NativeDatabase.memory()));
  });

  group('pick step', () {
    testWidgets('renders with no error initially', (tester) async {
      await _pump(tester, pickFile: () async => null);
      expect(key('import-pick-button'), findsOneWidget);
      expect(key('import-pick-error'), findsNothing);
    });

    testWidgets('cancelling the picker (null bytes) stays on the pick step',
        (tester) async {
      var calls = 0;
      await _pump(tester, pickFile: () async {
        calls++;
        return null;
      });
      await tester.tap(key('import-pick-button'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(key('import-pick-button'), findsOneWidget);
      expect(key('import-preview-summary'), findsNothing);
    });

    testWidgets('malformed bytes show a clear parse error and never call '
        'the coordinator', (tester) async {
      var buildPlanCalls = 0;
      await _pump(
        tester,
        pickFile: () async => Uint8List.fromList(utf8.encode('not json')),
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
        pickFile: () async => _validBytes(),
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
        pickFile: () async => throw StateError('picker crashed'),
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
  });

  group('preview step', () {
    testWidgets('a valid file shows the preview summary, merge policy, and '
        'plan breakdown', (tester) async {
      await _pump(
        tester,
        pickFile: () async => _validBytes(),
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
        pickFile: () async => _validBytes(),
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
        pickFile: () async => _validBytes(),
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
        pickFile: () async => _validBytes(),
        coordinator: _FakeCoordinator(storage, planResult: _plan()),
      );
      await tester.tap(key('import-pick-button'));
      await tester.pumpAndSettle();

      expect(key('import-preview-shared-guardian'), findsNothing);
    });

    testWidgets('Cancel returns to the pick step', (tester) async {
      await _pump(
        tester,
        pickFile: () async => _validBytes(),
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
        pickFile: () async => _validBytes(),
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
              pickFile: () async => _validBytes(),
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
}
