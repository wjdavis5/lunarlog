/// Pure restock-nudge rule (Issue #851).
///
/// One sentence: **nudge when the profile has at least one unstocked supply
/// item and the next estimated period start is within [kRestockLeadDays]
/// days of [today]** (an estimate already past today counts — the window is
/// open, so restocking is still useful).
///
/// Nothing here reads a clock: [today] is injected, so the rule is
/// deterministic and testable. The estimate comes from the same
/// [ActivePrediction.estimatedNextStart] the app already computes — the
/// server holds it in `profile_reminder_windows` for the missed-entry scan,
/// but this rule is a client-side, in-app card, not a push (the
/// ahead-of-time guardian *alert* is a separate concern and is not built
/// here).
///
/// Pure Dart with no drift/Flutter imports.
library;

import '../models/local_date.dart';
import '../models/visit_prep_item.dart';

/// How many days ahead of the next estimated period start to nudge. Five is
/// the issue's own proposed `period_soon` threshold, and it is enough time
/// to actually buy the thing.
const int kRestockLeadDays = 5;

/// A due restock nudge: [dueBy] is the next estimated period start and
/// [items] are the profile's unstocked supply items, sorted by name for a
/// stable render.
class RestockNudge {
  const RestockNudge({required this.dueBy, required this.items});

  final LocalDate dueBy;
  final List<VisitPrepItem> items;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RestockNudge &&
          other.dueBy == dueBy &&
          _sameItems(other.items, items);

  @override
  int get hashCode => Object.hash(dueBy, Object.hashAll(items));

  static bool _sameItems(List<VisitPrepItem> a, List<VisitPrepItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'RestockNudge(dueBy: ${dueBy.iso}, items: ${items.length})';
}

/// Returns the restock nudge for [supplies], or null when none is due.
///
/// Null [estimatedNextStart] (insufficient history / predictions paused)
/// never nudges — the rule never guesses a date. Tombstoned rows and
/// visit-prep items are ignored; a stocked supply item does not trigger the
/// nudge, but the presence of any *unstocked* one does.
RestockNudge? restockNudgeFor({
  required List<VisitPrepItem> supplies,
  required LocalDate? estimatedNextStart,
  required LocalDate today,
}) {
  if (estimatedNextStart == null) return null;
  final low = [
    for (final item in supplies)
      if (item.kind == VisitPrepItemKind.supply &&
          item.deletedAt == null &&
          !item.isChecked)
        item,
  ]..sort((a, b) => a.body.compareTo(b.body));
  if (low.isEmpty) return null;
  if (estimatedNextStart.difference(today) > kRestockLeadDays) return null;
  return RestockNudge(dueBy: estimatedNextStart, items: low);
}
