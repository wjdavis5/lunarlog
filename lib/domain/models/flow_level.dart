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

/// The human-readable label for [flow] — the enum name, title-cased
/// (`spotting` -> `Spotting`). Moved here from `lib/ui/logging/day_sheet.dart`
/// (#157 review fix) so a pure-Dart consumer (e.g.
/// `lib/domain/export/fhir_bundle.dart`) can use the same label the UI does
/// without importing a Flutter widget file — `day_sheet.dart` and every
/// other UI call site still reach it through this import.
String flowLabel(FlowLevel flow) {
  final name = flow.name;
  return name[0].toUpperCase() + name.substring(1);
}
