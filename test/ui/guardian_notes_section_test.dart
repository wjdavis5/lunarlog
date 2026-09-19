/// Widget tests for the day sheet's "Notes from guardians" section (Issue
/// #801): the disclosure copy is present at the point of writing (the
/// acceptance criterion that ratifies issue #800's open-and-transparent
/// decision), a viewer gets no write affordance, and a guardian's own note
/// is editable while another author's is read-only.
///
/// The repository is a lightweight fake (not the drift-backed one) so the
/// test does not carry a live database stream — the storage behaviour itself
/// is covered by `test/data/storage_guardian_notes_test.dart`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/guardian_note.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/guardian_notes_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/care/guardian_notes_section.dart';

class _FakeGuardianNotesRepository implements GuardianNotesRepository {
  _FakeGuardianNotesRepository([List<GuardianNote> initial = const []]) {
    _notes.addAll(initial);
  }

  final List<GuardianNote> _notes = [];
  final StreamController<List<GuardianNote>> _controller =
      StreamController<List<GuardianNote>>.broadcast();

  void _emit() => _controller.add(List.unmodifiable(_notes));

  void close() => _controller.close();

  @override
  Future<List<GuardianNote>> listForProfile(String profileId) async =>
      List.unmodifiable(_notes);

  @override
  Stream<List<GuardianNote>> watchForProfile(String profileId) async* {
    yield List.unmodifiable(_notes);
    yield* _controller.stream;
  }

  @override
  Future<GuardianNote?> findOwnNoteForDate({
    required String profileId,
    required LocalDate localDate,
    required String? authorUserId,
  }) async =>
      _notes.cast<GuardianNote?>().firstWhere(
            (n) =>
                n?.localDate == localDate && n?.loggedByUserId == authorUserId,
            orElse: () => null,
          );

  @override
  Future<GuardianNote> save({
    String? id,
    required String profileId,
    required LocalDate localDate,
    required String tz,
    required String body,
    String? loggedByUserId,
  }) async {
    final saved = GuardianNote(
      id: id ?? 'generated-${_notes.length}',
      profileId: profileId,
      localDate: localDate,
      tz: tz,
      body: body,
      updatedAt: DateTime.utc(2026, 9, 12, 10),
      loggedByUserId: loggedByUserId,
    );
    _notes.removeWhere((n) => n.id == saved.id);
    _notes.add(saved);
    _emit();
    return saved;
  }

  @override
  Future<void> delete(String id) async {
    _notes.removeWhere((n) => n.id == id);
    _emit();
  }
}

void main() {
  final date = LocalDate(2026, 9, 12);
  final t0 = DateTime.utc(2026, 9, 12, 10);

  GuardianNote note(
    String id,
    String body, {
    String? author,
    LocalDate? on,
  }) =>
      GuardianNote(
        id: id,
        profileId: 'p1',
        localDate: on ?? date,
        tz: 'UTC',
        body: body,
        updatedAt: t0,
        loggedByUserId: author,
      );

  Widget wrap(
    _FakeGuardianNotesRepository repo, {
    bool canWrite = true,
    String? currentUserId = 'u1',
    List<ProfileGuardian> guardians = const [],
  }) =>
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: GuardianNotesSection(
              profileId: 'p1',
              date: date,
              tz: 'UTC',
              currentUserId: currentUserId,
              canWrite: canWrite,
              guardians: guardians,
              repository: repo,
            ),
          ),
        ),
      );

  testWidgets('states the audience at the point of writing', (tester) async {
    final repo = _FakeGuardianNotesRepository();
    addTearDown(repo.close);
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text(kGuardianNotesDisclosure), findsOneWidget);
    expect(find.byKey(const ValueKey('guardian-note-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('guardian-note-save')), findsOneWidget);
  });

  testWidgets('a viewer sees notes but has no write affordance',
      (tester) async {
    final repo = _FakeGuardianNotesRepository(
        [note('g1', 'Mom wrote this.', author: 'u-mom')]);
    addTearDown(repo.close);
    await tester.pumpWidget(wrap(repo, canWrite: false));
    await tester.pumpAndSettle();

    expect(find.text(kGuardianNotesDisclosure), findsOneWidget);
    expect(find.text('Mom wrote this.'), findsOneWidget);
    expect(find.byKey(const ValueKey('guardian-note-field')), findsNothing);
    expect(find.byKey(const ValueKey('guardian-note-save')), findsNothing);
    expect(find.byKey(const ValueKey('guardian-note-remove')), findsNothing);
  });

  testWidgets('the author can edit their own note without minting a second',
      (tester) async {
    final repo = _FakeGuardianNotesRepository(
        [note('g1', 'First draft.', author: 'u1')]);
    addTearDown(repo.close);
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('You'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('guardian-note-field')), 'Second draft.');
    await tester.tap(find.byKey(const ValueKey('guardian-note-save')));
    await tester.pumpAndSettle();

    final rows = await repo.listForProfile('p1');
    expect(rows, hasLength(1), reason: 'editing must not mint a second note');
    expect(rows.single.body, 'Second draft.');
  });

  testWidgets("another author's note is shown with attribution",
      (tester) async {
    final repo = _FakeGuardianNotesRepository(
        [note('g1', 'Dad wrote this.', author: 'u-dad')]);
    addTearDown(repo.close);
    await tester.pumpWidget(wrap(
      repo,
      guardians: [
        ProfileGuardian(
          id: 'g-dad',
          profileId: 'p1',
          userId: 'u-dad',
          role: GuardianRole.coParent,
          status: GuardianStatus.accepted,
          displayName: 'Dad',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Dad wrote this.'), findsOneWidget);
    expect(find.text('Dad'), findsOneWidget);
  });
}
