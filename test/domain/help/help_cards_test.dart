/// Structural and copy tests for the bundled help cards (Issue #139).
///
/// Enforces AC5 (every card carries a source and a review date), AC6 (no
/// fertility/ovulation/conception content per PRIVACY.md), AC7 (no
/// individualised medical advice), and the trigger-map shape behind AC1.
/// Pure Dart — no widgets, no network.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/help/help_cards.dart';

/// Substrings that must never appear in card copy (case-insensitive),
/// covering fertility, ovulation, and conception in educational or feature
/// form. `conce` covers conceive/conception/concept-alike spellings; card
/// copy avoids the whole family.
const List<String> kBannedSubstrings = [
  'fertil',
  'ovulat',
  'conce',
  'pregnan',
  'luteal',
];

/// Markers of individualised medical advice (case-insensitive). Cards may
/// route worry to a clinician but must never direct, diagnose, or treat.
const List<String> kMedicalAdviceMarkers = [
  'you should',
  'diagnos',
  'treatment',
  'recommend',
  'prescrib',
  'normal for you',
];

String _copyOf(HelpCard card) =>
    '${card.title}\n${card.summary}\n${card.body.join('\n')}';

void main() {
  group('HelpCards set shape (AC1)', () {
    test('ships roughly two dozen cards', () {
      expect(HelpCards.all.length, 24);
    });

    test('ids are unique and non-empty', () {
      final ids = HelpCards.all.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final id in ids) {
        expect(id, isNotEmpty);
      }
    });

    test('every card has a title, summary, and body', () {
      for (final card in HelpCards.all) {
        expect(card.title, isNotEmpty, reason: card.id);
        expect(card.summary, isNotEmpty, reason: card.id);
        expect(card.body, isNotEmpty, reason: card.id);
        for (final paragraph in card.body) {
          expect(paragraph.trim(), isNotEmpty, reason: card.id);
        }
      }
    });

    test('byId resolves every card and null for unknown ids', () {
      for (final card in HelpCards.all) {
        expect(HelpCards.byId(card.id), same(card));
      }
      expect(HelpCards.byId('no-such-card'), isNull);
    });
  });

  group('trigger map (AC1)', () {
    test('every card names at least one screen', () {
      for (final card in HelpCards.all) {
        expect(card.screens, isNotEmpty, reason: card.id);
      }
    });

    test('every card is reachable through byScreen', () {
      final reachable = HelpCards.byScreen.values.expand((c) => c).toSet();
      expect(reachable, containsAll(HelpCards.all));
    });

    test('forScreen answers the not-enough-history screens', () {
      for (final screen in ['overview-not-enough', 'analysis-not-enough']) {
        final ids = HelpCards.forScreen(screen).map((c) => c.id);
        expect(ids, contains('why-no-estimate-yet'), reason: screen);
      }
    });

    test('forScreen is empty for an unknown screen', () {
      expect(HelpCards.forScreen('no-such-screen'), isEmpty);
    });

    test('guardian ladder, invitations, revocation, and transfer each '
        'have a card (AC3)', () {
      expect(HelpCards.byId('guardian-roles'), isNotNull);
      expect(HelpCards.byId('invitations'), isNotNull);
      expect(HelpCards.byId('revocation'), isNotNull);
      expect(HelpCards.byId('ownership-transfer'), isNotNull);
    });
  });

  group('provenance (AC5)', () {
    test('every card carries a source and a review date', () {
      for (final card in HelpCards.all) {
        expect(card.source.trim(), isNotEmpty, reason: card.id);
        expect(card.reviewDate.trim(), isNotEmpty, reason: card.id);
      }
    });

    test('every review date is a valid ISO-8601 calendar date', () {
      final datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
      for (final card in HelpCards.all) {
        expect(datePattern.hasMatch(card.reviewDate), isTrue,
            reason: '${card.id}: ${card.reviewDate}');
        // Throws on a non-date such as 2026-13-40.
        expect(() => DateTime.parse(card.reviewDate), returnsNormally,
            reason: card.id);
      }
    });
  });

  group('no fertility content (AC6)', () {
    test('no card copy contains a banned term', () {
      for (final card in HelpCards.all) {
        final copy = _copyOf(card).toLowerCase();
        for (final banned in kBannedSubstrings) {
          expect(copy.contains(banned), isFalse,
              reason: '${card.id} contains "$banned"');
        }
      }
    });

    test('no card copy references a network location', () {
      for (final card in HelpCards.all) {
        final copy = _copyOf(card).toLowerCase();
        expect(copy.contains('http://'), isFalse, reason: card.id);
        expect(copy.contains('https://'), isFalse, reason: card.id);
        expect(copy.contains('www.'), isFalse, reason: card.id);
      }
    });
  });

  group('no individualised medical advice (AC7)', () {
    test('no card copy directs, diagnoses, or treats', () {
      for (final card in HelpCards.all) {
        final copy = _copyOf(card).toLowerCase();
        for (final marker in kMedicalAdviceMarkers) {
          expect(copy.contains(marker), isFalse,
              reason: '${card.id} contains "$marker"');
        }
      }
    });

    test('estimate cards carry the non-medical framing', () {
      const estimateCards = [
        'why-no-estimate-yet',
        'confidence-levels',
        'what-estimate-means',
        'period-late',
        'unusually-long-cycle',
        'period-length-average',
      ];
      for (final id in estimateCards) {
        final copy = _copyOf(HelpCards.byId(id)!).toLowerCase();
        expect(copy.contains('not medical advice'), isTrue, reason: id);
      }
    });
  });

  group('copy accuracy against sources of truth', () {
    test('three-cycle requirement matches the prediction engine', () {
      final copy = _copyOf(HelpCards.byId('why-no-estimate-yet')!);
      expect(copy, contains('three'));
    });

    test('role card names every rung of the ladder', () {
      final copy =
          _copyOf(HelpCards.byId('guardian-roles')!).toLowerCase();
      for (final role in ['primary guardian', 'co-parent', 'caregiver', 'viewer']) {
        expect(copy.contains(role), isTrue, reason: role);
      }
    });

    test('invitation and transfer cards state their expiry windows', () {
      expect(_copyOf(HelpCards.byId('invitations')!), contains('48 hours'));
      expect(
          _copyOf(HelpCards.byId('ownership-transfer')!), contains('72 hours'));
    });
  });
}
