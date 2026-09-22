/// One-tap "Log today"/"Period started today" quick-log rule (issue #209;
/// B-10, A2-40, B-29). Pure Dart (R14/R16): the flow level a quick-log tap
/// resolves to, given whatever (if anything) is already logged for today.
///
/// Idempotency (the issue's own acceptance criterion): a second tap must
/// never create a second entry -- guaranteed for free by
/// [DayEntriesRepository.save]'s upsert-by-(profileId, localDate) identity,
/// unrelated to this file -- and must never *downgrade* an existing flow
/// level. [quickLogFlowLevel] is the rule that keeps the second half of
/// that promise: it only ever raises a day's flow up to
/// [kQuickLogFlowLevel], never down past whatever the operator (or a prior
/// tap) already recorded.
library;

import '../models/day_entry.dart';
import '../models/flow_level.dart';
import '../models/local_date.dart';
import '../repositories/day_entries_repository.dart';

/// The flow level a bare "period started today" tap writes for a day with
/// no existing entry (or an existing entry logged below this level).
/// [FlowLevel.medium] reads as an honest, unremarkable default -- not the
/// lightest level (spotting undercounts what "period started" usually
/// means) and not the heaviest (heavy is a specific report the operator
/// should choose deliberately, not one this shortcut guesses at).
const FlowLevel kQuickLogFlowLevel = FlowLevel.medium;

/// The flow level a quick-log tap should write, given today's [existing]
/// flow (null when there is no entry yet for today).
///
/// * No entry yet → [kQuickLogFlowLevel].
/// * An entry already at or above [kQuickLogFlowLevel] → returned
///   unchanged -- a second tap (or a day already logged heavier than the
///   quick-log default, e.g. by the full day sheet) is never downgraded.
/// * An entry below [kQuickLogFlowLevel] (e.g. [FlowLevel.none],
///   [FlowLevel.notBleeding], or the deprecated [FlowLevel.spotting]) →
///   raised to [kQuickLogFlowLevel].
///
/// **Enum declaration order is load-bearing here (review finding, PR
/// #335):** the "below"/"at or above" comparison is plain `.index`
/// comparison against [FlowLevel]'s declaration order (`none, spotting,
/// notBleeding, light, medium, heavy, superHeavy`), not any severity
/// ranking maintained independently of it. Reordering that enum -- e.g.
/// inserting a future member between `notBleeding` and `light` -- would
/// silently change which existing values this function treats as "below"
/// [kQuickLogFlowLevel] without touching a single line here.
/// `test/domain/logging/quick_log_test.dart` pins the declaration order
/// directly (`FlowLevel.values` compared index-for-index) so a reorder
/// fails loudly instead of only changing quick-log behaviour by accident.
FlowLevel quickLogFlowLevel(FlowLevel? existing) {
  if (existing == null) return kQuickLogFlowLevel;
  return existing.index >= kQuickLogFlowLevel.index
      ? existing
      : kQuickLogFlowLevel;
}

/// Restores exactly what a quick-log write overwrote (issue #316 review
/// item 5): the prior [DayEntry] (flow/tags/note preserved) if the day
/// already had one, or a tombstone — through the repository's own delete
/// path, so sync dirty-marking applies exactly as it would to any other
/// edit — if the quick-log tap is what created it.
///
/// The one Undo semantics for every quick-log caller: the overview's Today
/// card (its snackbar's Undo action) and, since issue #1016, the widget
/// quick-log's own snackbar — [previous] is whatever the caller captured
/// immediately before its write ([WidgetQuickLogOutcome.previousEntry] on
/// the widget path).
Future<void> undoQuickLog(
  DayEntriesRepository repository, {
  required String profileId,
  required DayEntry? previous,
  required LocalDate date,
}) async {
  if (previous == null) {
    await repository.delete(profileId, date);
  } else {
    await repository.save(previous);
  }
}
