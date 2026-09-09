/// Converts a Clue-side [ClueFlowLevel] to the app's own [FlowLevel], now
/// that Issue #247 has shipped `superHeavy` and `notBleeding`.
///
/// `docs/import/clue-mapping.md`'s "`ClueFlowLevel` — interim collapse
/// rules" section is obsolete as of this file: this mapping is lossless —
/// every [ClueFlowLevel] has an exact [FlowLevel] counterpart
/// (`superHeavy -> superHeavy`, `notBleeding -> notBleeding`), never the
/// two enums' `.index` (their ordinals do not line up — see
/// `clue_datapoint.dart`'s [ClueFlowLevel] doc comment).
library;

import '../../models/flow_level.dart';
import 'clue_datapoint.dart';

/// The lossless [ClueFlowLevel] -> [FlowLevel] mapping (Issue #247, #190
/// review). Never used for [FlowLevel.spotting] — Clue spotting is its
/// own `ClueObservationDatapoint(category: 'spotting')`, never a
/// [CluePeriodDatapoint]/[ClueFlowLevel] value in the first place.
FlowLevel flowLevelFromClue(ClueFlowLevel level) => switch (level) {
      ClueFlowLevel.notBleeding => FlowLevel.notBleeding,
      ClueFlowLevel.light => FlowLevel.light,
      ClueFlowLevel.medium => FlowLevel.medium,
      ClueFlowLevel.heavy => FlowLevel.heavy,
      ClueFlowLevel.superHeavy => FlowLevel.superHeavy,
    };
