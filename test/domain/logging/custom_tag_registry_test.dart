/// Issue #257: the custom-tag registry's domain model and pure helpers —
/// [customTagCodeFromLabel]'s Clue-shaped derivation (the issue's own
/// observed real values: `"BACK PAIN"`, `"vulva pain?!"`, `"!"`),
/// [validateCustomTagLabel]'s accept/reject matrix, and the
/// [CustomTag.offered]/[CustomTag.renders] lifecycle getters
/// (retirement-not-deletion).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/logging/custom_tag_registry.dart';

CustomTag tag(
  String code, {
  String displayName = 'Label',
  DateTime? hiddenAt,
  DateTime? deletedAt,
}) =>
    CustomTag(
      id: '01J8ZQ9K7MC2X3V4B5N6P7Q${code.length.toString().padLeft(2, '0')}',
      profileId: '01J8ZQ9K7MC2X3V4B5N6P7Q8R9',
      code: code,
      displayName: displayName,
      category: 'custom',
      hiddenAt: hiddenAt,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
      deletedAt: deletedAt,
    );

void main() {
  group('customTagCodeFromLabel', () {
    test('lowercases and collapses separators (Clue free-text shapes)', () {
      expect(customTagCodeFromLabel('BACK PAIN'), 'back_pain');
      expect(customTagCodeFromLabel('vulva pain?!'), 'vulva_pain');
      expect(customTagCodeFromLabel('back cracking'), 'back_cracking');
      expect(customTagCodeFromLabel('  high   libido  '), 'high_libido');
    });

    test('null when nothing alphanumeric survives', () {
      expect(customTagCodeFromLabel('!'), isNull);
      expect(customTagCodeFromLabel('---'), isNull);
      expect(customTagCodeFromLabel(' ?! '), isNull);
    });

    test('clamps to kMaxTagLength (the server per-element bound)', () {
      final code = customTagCodeFromLabel('a' * 100);
      expect(code, isNotNull);
      expect(code!.length, 64);
    });
  });

  group('validateCustomTagLabel', () {
    test('accepts a fresh label', () {
      expect(validateCustomTagLabel('Back cracking', const []), isNull);
    });

    test('rejects empty and whitespace-only labels', () {
      expect(validateCustomTagLabel('', const []),
          CustomTagLabelError.empty);
      expect(validateCustomTagLabel('   ', const []),
          CustomTagLabelError.empty);
    });

    test('rejects labels past the 40-character CHECK bound', () {
      expect(validateCustomTagLabel('a' * 41, const []),
          CustomTagLabelError.tooLong);
      expect(validateCustomTagLabel('a' * 40, const []), isNull);
    });

    test('rejects labels with no letters or digits', () {
      expect(validateCustomTagLabel('?!', const []),
          CustomTagLabelError.noLettersOrDigits);
    });

    test('rejects a duplicate code case-insensitively (live rows)', () {
      expect(
        validateCustomTagLabel('BACK CRACKING', [tag('back_cracking')]),
        CustomTagLabelError.duplicateCode,
      );
    });

    test('a tombstoned entry frees its code', () {
      expect(
        validateCustomTagLabel('Back cracking', [
          tag('back_cracking', deletedAt: DateTime.utc(2026, 9, 2)),
        ]),
        isNull,
      );
    });

    test('rejects a label deriving a taxonomy code (no shadowing)', () {
      expect(validateCustomTagLabel('Cramps', const []),
          CustomTagLabelError.collidesWithTaxonomy);
      expect(validateCustomTagLabel('HAPPY', const []),
          CustomTagLabelError.collidesWithTaxonomy);
    });
  });

  group('CustomTag lifecycle getters', () {
    test('a live entry is offered and renders', () {
      final live = tag('back_cracking');
      expect(live.offered, isTrue);
      expect(live.renders, isTrue);
    });

    test('a retired entry stops being offered but still renders', () {
      final retired = tag('back_cracking', hiddenAt: DateTime.utc(2026, 9, 2));
      expect(retired.offered, isFalse);
      expect(retired.renders, isTrue,
          reason: 'retirement removes the picker chip, never stored rows');
    });

    test('a tombstoned entry neither offers nor renders', () {
      final dead = tag('back_cracking', deletedAt: DateTime.utc(2026, 9, 2));
      expect(dead.offered, isFalse);
      expect(dead.renders, isFalse);
    });
  });
}
