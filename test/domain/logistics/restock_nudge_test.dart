/// Pure-domain tests for the Issue #851 restock nudge rule:
/// fires when an unstocked supply item exists and the next estimated
/// period start is within [kRestockLeadDays] of an injected today; never
/// fires on null estimate, no low supply, or a too-distant estimate.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/logistics/restock_nudge.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/visit_prep_item.dart';

final LocalDate today = LocalDate(2026, 9, 20);

VisitPrepItem item({
  required String id,
  String body = 'Panty liners',
  VisitPrepItemKind kind = VisitPrepItemKind.supply,
  bool isChecked = false,
  DateTime? deletedAt,
}) =>
    VisitPrepItem(
      id: id,
      profileId: 'profile-1',
      body: body,
      kind: kind,
      isChecked: isChecked,
      updatedAt: DateTime.utc(2026, 9, 1),
      deletedAt: deletedAt,
    );

void main() {
  group('restockNudgeFor (Issue #851)', () {
    test('fires when an unstocked supply exists and the estimate is within '
        'the lead window', () {
      final nudge = restockNudgeFor(
        supplies: [item(id: 's-1')],
        estimatedNextStart: LocalDate(2026, 9, 25),
        today: today,
      );
      expect(nudge, isNotNull);
      expect(nudge!.dueBy, LocalDate(2026, 9, 25));
      expect(nudge.items.map((i) => i.id), ['s-1']);
    });

    test('fires on the boundary day (exactly kRestockLeadDays out)', () {
      expect(
        restockNudgeFor(
          supplies: [item(id: 's-1')],
          estimatedNextStart: LocalDate(2026, 9, 20 + kRestockLeadDays),
          today: today,
        ),
        isNotNull,
      );
    });

    test('fires when the estimate is today or already past', () {
      expect(
        restockNudgeFor(
          supplies: [item(id: 's-1')],
          estimatedNextStart: today,
          today: today,
        ),
        isNotNull,
      );
      expect(
        restockNudgeFor(
          supplies: [item(id: 's-1')],
          estimatedNextStart: LocalDate(2026, 9, 18),
          today: today,
        ),
        isNotNull,
      );
    });

    test('does not fire one day past the lead window', () {
      expect(
        restockNudgeFor(
          supplies: [item(id: 's-1')],
          estimatedNextStart: LocalDate(2026, 9, 20 + kRestockLeadDays + 1),
          today: today,
        ),
        isNull,
      );
    });

    test('does not fire when there is no estimate', () {
      expect(
        restockNudgeFor(
          supplies: [item(id: 's-1')],
          estimatedNextStart: null,
          today: today,
        ),
        isNull,
      );
    });

    test('does not fire when every supply is stocked', () {
      expect(
        restockNudgeFor(
          supplies: [item(id: 's-1', isChecked: true)],
          estimatedNextStart: LocalDate(2026, 9, 22),
          today: today,
        ),
        isNull,
      );
    });

    test('does not fire when there are no supply items (visit prep is '
        'ignored)', () {
      expect(
        restockNudgeFor(
          supplies: [
            item(id: 'p-1', kind: VisitPrepItemKind.visitPrep),
            item(id: 's-1', isChecked: true),
          ],
          estimatedNextStart: LocalDate(2026, 9, 22),
          today: today,
        ),
        isNull,
      );
    });

    test('ignores tombstoned supply rows', () {
      expect(
        restockNudgeFor(
          supplies: [
            item(id: 's-1', deletedAt: DateTime.utc(2026, 9, 10)),
          ],
          estimatedNextStart: LocalDate(2026, 9, 22),
          today: today,
        ),
        isNull,
      );
    });

    test('returns every unstocked supply, sorted by name', () {
      final nudge = restockNudgeFor(
        supplies: [
          item(id: 's-1', body: 'Panty liners'),
          item(id: 's-2', body: 'Heat patch'),
          item(id: 's-3', body: 'Pain relief', isChecked: true),
          item(id: 's-4', body: 'Menstrual cup'),
        ],
        estimatedNextStart: LocalDate(2026, 9, 23),
        today: today,
      );
      expect(nudge, isNotNull);
      expect(
        nudge!.items.map((i) => i.body),
        ['Heat patch', 'Menstrual cup', 'Panty liners'],
      );
    });

    test('equality covers dueBy and items', () {
      final a = restockNudgeFor(
        supplies: [item(id: 's-1')],
        estimatedNextStart: LocalDate(2026, 9, 23),
        today: today,
      );
      final b = restockNudgeFor(
        supplies: [item(id: 's-1')],
        estimatedNextStart: LocalDate(2026, 9, 23),
        today: today,
      );
      final c = restockNudgeFor(
        supplies: [item(id: 's-1')],
        estimatedNextStart: LocalDate(2026, 9, 24),
        today: today,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
