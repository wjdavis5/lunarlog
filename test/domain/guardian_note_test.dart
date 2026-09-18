/// Unit tests for the Issue #801 domain model [GuardianNote] — equality,
/// copyWith (including explicit-null resolution for the nullable fields),
/// and the redacted toString (never the body text: health content about a
/// minor must not leak into logs or crash reports). Mirrors
/// `care_content_models_test.dart`'s shape.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/guardian_note.dart';
import 'package:lunarlog/domain/models/local_date.dart';

GuardianNote _note({
  String id = 'n1',
  String profileId = 'p1',
  LocalDate? localDate,
  String tz = 'UTC',
  String body = 'Seemed withdrawn this week.',
  DateTime? updatedAt,
  DateTime? deletedAt,
  String? loggedByUserId = 'user-mom',
  String? lastModifiedByUserId = 'user-mom',
}) =>
    GuardianNote(
      id: id,
      profileId: profileId,
      localDate: localDate ?? LocalDate(2026, 9, 12),
      tz: tz,
      body: body,
      updatedAt: updatedAt ?? DateTime.utc(2026, 9, 12, 10),
      deletedAt: deletedAt,
      loggedByUserId: loggedByUserId,
      lastModifiedByUserId: lastModifiedByUserId,
    );

void main() {
  group('GuardianNote', () {
    test('equal notes compare equal with equal hashCodes', () {
      expect(_note(), _note());
      expect(_note().hashCode, _note().hashCode);
    });

    test('a differing field breaks equality', () {
      expect(_note(), isNot(_note(body: 'Different text.')));
      expect(_note(), isNot(_note(id: 'n2')));
      expect(_note(),
          isNot(_note(localDate: LocalDate(2026, 9, 13))));
      expect(_note(), isNot(_note(tz: 'America/New_York')));
      expect(_note(), isNot(_note(deletedAt: DateTime.utc(2026, 9, 13))));
      expect(_note(), isNot(_note(loggedByUserId: 'user-dad')));
      expect(_note(), isNot(_note(lastModifiedByUserId: 'user-dad')));
    });

    test('copyWith revises the body and clears the tombstone explicitly',
        () {
      final tombstoned = _note(deletedAt: DateTime.utc(2026, 9, 13));
      final revived = tombstoned.copyWith(
        body: 'New text.',
        deletedAt: null,
      );
      expect(revived.body, 'New text.');
      expect(revived.deletedAt, isNull);
      expect(revived.id, tombstoned.id);
    });

    test('copyWith can clear the author stamps explicitly', () {
      final cleared = _note().copyWith(
        loggedByUserId: null,
        lastModifiedByUserId: null,
      );
      expect(cleared.loggedByUserId, isNull);
      expect(cleared.lastModifiedByUserId, isNull);
    });

    test('copyWith without overrides keeps every field', () {
      final note = _note();
      final copy = note.copyWith();
      expect(copy, note);
      expect(copy.loggedByUserId, 'user-mom');
      expect(copy.localDate, LocalDate(2026, 9, 12));
    });

    test('toString carries ids and the date but never the body text', () {
      final text = _note().toString();
      expect(text, contains('p1'));
      expect(text, contains('n1'));
      expect(text, contains('2026-09-12'));
      expect(text, isNot(contains('withdrawn')));
      expect(_note(deletedAt: DateTime.utc(2026, 9, 13)).toString(),
          contains('tombstoned'));
    });
  });
}
