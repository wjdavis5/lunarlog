/// Unit tests for the Issue #128 domain models: [CareNote] and
/// [VisitPrepItem] — equality, copyWith (including explicit-null
/// resolution), and the redacted toString (never the body text: health
/// content about a minor must not leak into logs or crash reports).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/care_note.dart';
import 'package:lunarlog/domain/models/visit_prep_item.dart';

CareNote _note({
  String id = 'n1',
  String profileId = 'p1',
  String body = 'Prefers the blue inhaler.',
  DateTime? updatedAt,
  DateTime? deletedAt,
  String? loggedByUserId = 'user-mom',
  String? lastModifiedByUserId = 'user-mom',
}) =>
    CareNote(
      id: id,
      profileId: profileId,
      body: body,
      updatedAt: updatedAt ?? DateTime.utc(2026, 9, 2, 10),
      deletedAt: deletedAt,
      loggedByUserId: loggedByUserId,
      lastModifiedByUserId: lastModifiedByUserId,
    );

VisitPrepItem _item({
  String id = 'i1',
  String profileId = 'p1',
  String body = 'Ask about iron levels.',
  bool isChecked = false,
  String? checkedByUserId,
  DateTime? checkedAt,
  DateTime? updatedAt,
  DateTime? deletedAt,
}) =>
    VisitPrepItem(
      id: id,
      profileId: profileId,
      body: body,
      isChecked: isChecked,
      checkedByUserId: checkedByUserId,
      checkedAt: checkedAt,
      updatedAt: updatedAt ?? DateTime.utc(2026, 9, 2, 11),
      deletedAt: deletedAt,
    );

void main() {
  group('CareNote', () {
    test('equal notes compare equal with equal hashCodes', () {
      expect(_note(), _note());
      expect(_note().hashCode, _note().hashCode);
    });

    test('a differing field breaks equality', () {
      expect(_note(), isNot(_note(body: 'Different text.')));
      expect(_note(), isNot(_note(id: 'n2')));
      expect(_note(),
          isNot(_note(deletedAt: DateTime.utc(2026, 9, 3))));
    });

    test('copyWith revises the body and clears the tombstone explicitly',
        () {
      final tombstoned =
          _note(deletedAt: DateTime.utc(2026, 9, 3));
      final revived = tombstoned.copyWith(
        body: 'New text.',
        deletedAt: null,
      );
      expect(revived.body, 'New text.');
      expect(revived.deletedAt, isNull);
      expect(revived.id, tombstoned.id);
    });

    test('copyWith without overrides keeps every field', () {
      final note = _note();
      final copy = note.copyWith();
      expect(copy, note);
      expect(copy.loggedByUserId, 'user-mom');
    });

    test('toString carries ids but never the body text', () {
      final text = _note().toString();
      expect(text, contains('p1'));
      expect(text, contains('n1'));
      expect(text, isNot(contains('inhaler')));
      expect(_note(deletedAt: DateTime.utc(2026, 9, 3)).toString(),
          contains('tombstoned'));
    });
  });

  group('VisitPrepItem', () {
    test('a new item lands unchecked with no stamp', () {
      final item = _item();
      expect(item.isChecked, isFalse);
      expect(item.checkedByUserId, isNull);
      expect(item.checkedAt, isNull);
      expect(item, _item());
    });

    test('a differing check state breaks equality', () {
      expect(
          _item(),
          isNot(_item(
            isChecked: true,
            checkedByUserId: 'user-dad',
            checkedAt: DateTime.utc(2026, 9, 2, 12),
          )));
    });

    test('copyWith checks with a stamp and unchecks clearing it', () {
      final checked = _item().copyWith(
        isChecked: true,
        checkedByUserId: 'user-dad',
        checkedAt: DateTime.utc(2026, 9, 2, 12),
      );
      expect(checked.isChecked, isTrue);
      expect(checked.checkedByUserId, 'user-dad');

      final unchecked = checked.copyWith(
        isChecked: false,
        checkedByUserId: null,
        checkedAt: null,
      );
      expect(unchecked.isChecked, isFalse);
      expect(unchecked.checkedByUserId, isNull);
      expect(unchecked.checkedAt, isNull);
    });

    test('toString carries ids and check state but never the body text',
        () {
      final text = _item().toString();
      expect(text, contains('i1'));
      expect(text, isNot(contains('iron')));
      expect(
          _item(isChecked: true, checkedByUserId: 'user-dad').toString(),
          contains('checked'));
    });
  });
}
