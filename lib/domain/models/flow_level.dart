/// Domain flow-level value type (R14/R16: this is the copy the UI sees;
/// the drift enum in `lib/data/db/tables.dart` is mapped at the repository
/// boundary and never leaves `lib/data/`).
///
/// Ordered from none to heaviest; anything above [none] counts as a bleed
/// day for episode derivation (spotting included).
library;

enum FlowLevel { none, spotting, light, medium, heavy }

/// Whether [flow] records bleeding (anything above none).
bool isBleed(FlowLevel flow) => flow != FlowLevel.none;
