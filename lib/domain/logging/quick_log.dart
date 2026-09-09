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

import '../models/flow_level.dart';

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
/// * An entry below [kQuickLogFlowLevel] (e.g. [FlowLevel.none] or
///   [FlowLevel.spotting]) → raised to [kQuickLogFlowLevel].
FlowLevel quickLogFlowLevel(FlowLevel? existing) {
  if (existing == null) return kQuickLogFlowLevel;
  return existing.index >= kQuickLogFlowLevel.index
      ? existing
      : kQuickLogFlowLevel;
}
