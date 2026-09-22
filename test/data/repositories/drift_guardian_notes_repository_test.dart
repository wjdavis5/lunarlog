/// Unit tests for [DriftGuardianNotesRepository] (Issue #801): the thin
/// drift-row → domain mapping over [FakeGuardianNoteStore], plus
/// `findOwnNoteForDate`, the client-side half of the author-ownership rule.
///
/// Issue #551 problem 1 follow-up: this used to open a real drift database
/// solely to feed the repository. It now drives a hand-written
/// [FakeGuardianNoteStore] with no database at all; the storage SQL itself
/// is proven in `storage_guardian_notes_test.dart`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/data/repositories/drift_guardian_notes_repository.dart';

import '../../support/fakes/fake_guardian_note_store.dart';

void main() {
  late FakeGuardianNoteStore store;
  late DriftGuardianNotesRepository repository;

  final date = LocalDate(2026, 9, 12);

  setUp(() {
    store = FakeGuardianNoteStore();
    addTearDown(store.close);
    repository = DriftGuardianNotesRepository(store);
  });

  test('save/list round-trips a dated note as a domain model', () async {
    final saved = await repository.save(
      profileId: 'p1',
      localDate: date,
      tz: 'America/New_York',
      body: 'Seemed withdrawn this week.',
      loggedByUserId: 'u1',
    );
    expect(saved.profileId, 'p1');
    expect(saved.localDate, date);
    expect(saved.tz, 'America/New_York');
    expect(saved.body, 'Seemed withdrawn this week.');
    expect(saved.deletedAt, isNull);

    final listed = await repository.listForProfile('p1');
    expect(listed, hasLength(1));
    expect(listed.single, saved);
  });

  test('save with an id revises; delete tombstones from list results',
      () async {
    final saved = await repository.save(
      profileId: 'p1',
      localDate: date,
      tz: 'UTC',
      body: 'First.',
      loggedByUserId: 'u1',
    );
    final revised = await repository.save(
      id: saved.id,
      profileId: 'p1',
      localDate: date,
      tz: 'UTC',
      body: 'Revised.',
      loggedByUserId: 'u1',
    );
    expect(revised.id, saved.id);
    expect(revised.body, 'Revised.');

    await repository.delete(saved.id);
    expect(await repository.listForProfile('p1'), isEmpty);
  });

  test('findOwnNoteForDate returns only the calling author\'s live note',
      () async {
    final mine = await repository.save(
      profileId: 'p1',
      localDate: date,
      tz: 'UTC',
      body: 'Mine.',
      loggedByUserId: 'u1',
    );
    await repository.save(
      profileId: 'p1',
      localDate: date,
      tz: 'UTC',
      body: 'Theirs.',
      loggedByUserId: 'u2',
    );

    final found = await repository.findOwnNoteForDate(
        profileId: 'p1', localDate: date, authorUserId: 'u1');
    expect(found?.id, mine.id);
    expect(
        await repository.findOwnNoteForDate(
            profileId: 'p1',
            localDate: LocalDate(2026, 9, 13),
            authorUserId: 'u1'),
        isNull);
    expect(
        await repository.findOwnNoteForDate(
            profileId: 'p1', localDate: date, authorUserId: null),
        isNull,
        reason: 'an unknown author has no own note');
  });

  test('watch emits the list reactively', () async {
    final emissions = <int>[];
    final sub = repository.watchForProfile('p1').listen((rows) {
      emissions.add(rows.length);
    });
    addTearDown(sub.cancel);
    await repository.save(
      profileId: 'p1',
      localDate: date,
      tz: 'UTC',
      body: 'One.',
      loggedByUserId: 'u1',
    );
    await pumpEventQueue();
    expect(emissions.last, 1);
  });
}
