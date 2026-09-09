/// Unit tests for [DriftCareContentRepository] (Issue #128): the thin
/// drift-row → domain mapping over [LunarLogStorage], exercised against an
/// in-memory database. Storage semantics themselves are proven in
/// `storage_care_content_test.dart`; this file only pins the seam.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/repositories/drift_care_content_repository.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late DriftCareContentRepository repository;

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    repository = DriftCareContentRepository(db.storage);
    await db.storage.upsertProfile(
        id: 'p1',
        displayName: 'Riley',
        isMinor: true,
        updatedAt: DateTime.utc(2026, 9, 1, 8));
  });

  group('care notes', () {
    test('save/list round-trips a note as a domain model', () async {
      final saved = await repository.saveCareNote(
          profileId: 'p1', body: 'Prefers the blue inhaler.');
      expect(saved.profileId, 'p1');
      expect(saved.body, 'Prefers the blue inhaler.');
      expect(saved.deletedAt, isNull);

      final listed = await repository.listCareNotes('p1');
      expect(listed, hasLength(1));
      expect(listed.single, saved);
    });

    test('save with an id revises; delete tombstones from list results',
        () async {
      final saved = await repository.saveCareNote(
          profileId: 'p1', body: 'First.');
      final revised = await repository.saveCareNote(
          id: saved.id, profileId: 'p1', body: 'Revised.');
      expect(revised.id, saved.id);
      expect(revised.body, 'Revised.');

      await repository.deleteCareNote(saved.id);
      expect(await repository.listCareNotes('p1'), isEmpty);
    });

    test('watch emits the list reactively', () async {
      final emissions = <int>[];
      final sub = repository.watchCareNotes('p1').listen((rows) {
        emissions.add(rows.length);
      });
      addTearDown(sub.cancel);
      await repository.saveCareNote(profileId: 'p1', body: 'One.');
      await pumpEventQueue();
      expect(emissions.last, 1);
    });
  });

  group('visit prep items', () {
    test('add/list round-trips an unchecked item as a domain model',
        () async {
      final added = await repository.addPrepItem(
          profileId: 'p1', body: 'Ask about iron levels.');
      expect(added.isChecked, isFalse);

      final listed = await repository.listPrepItems('p1');
      expect(listed, hasLength(1));
      expect(listed.single, added);
    });

    test('edit/check/uncheck/delete thread through to storage', () async {
      final added = await repository.addPrepItem(
          profileId: 'p1', body: 'Bring the chart.');
      final edited = await repository.editPrepItem(
          id: added.id, body: 'Bring the growth chart.');
      expect(edited!.body, 'Bring the growth chart.');
      expect(edited.isChecked, isFalse);

      final checked = await repository.setPrepItemChecked(
          id: added.id, checked: true, checkedByUserId: 'user-dad');
      expect(checked!.isChecked, isTrue);
      expect(checked.checkedByUserId, 'user-dad');

      final unchecked = await repository.setPrepItemChecked(
          id: added.id, checked: false);
      expect(unchecked!.isChecked, isFalse);
      expect(unchecked.checkedByUserId, isNull);

      await repository.deletePrepItem(added.id);
      expect(await repository.listPrepItems('p1'), isEmpty);
    });

    test('edit/check on an unknown id resolve to null', () async {
      expect(
          await repository.editPrepItem(id: 'missing', body: 'x'),
          isNull);
      expect(
          await repository.setPrepItemChecked(
              id: 'missing', checked: true),
          isNull);
    });

    test('clearCheckedPrepItems reports the cleared count', () async {
      final open =
          await repository.addPrepItem(profileId: 'p1', body: 'Open.');
      final done =
          await repository.addPrepItem(profileId: 'p1', body: 'Done.');
      await repository.setPrepItemChecked(
          id: done.id, checked: true, checkedByUserId: 'u1');
      expect(await repository.clearCheckedPrepItems('p1'), 1);
      expect((await repository.listPrepItems('p1')).map((i) => i.id),
          [open.id]);
    });

    test('watch emits the list reactively', () async {
      final emissions = <int>[];
      final sub = repository.watchPrepItems('p1').listen((rows) {
        emissions.add(rows.length);
      });
      addTearDown(sub.cancel);
      await repository.addPrepItem(profileId: 'p1', body: 'One.');
      await pumpEventQueue();
      expect(emissions.last, 1);
    });
  });
}
