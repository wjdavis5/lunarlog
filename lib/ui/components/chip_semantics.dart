/// Shared accessible-chip semantics wrapper (Issue #234): wraps a chip so a
/// screen reader hears its group, its label, and its selected state as one
/// node, with an accessibility tap action wired to the same toggle the
/// visible chip performs.
///
/// Mirrors `lib/ui/logging/day_sheet.dart`'s pre-existing
/// `groupedChipSemantics` (Issue #138) byte-for-byte, kept as a second copy
/// here in `lib/ui/components` rather than an import so the new reusable
/// pickers ([CategoryPicker], [IntensitySelector]) do not depend on a
/// screen-level file — the day sheet keeps its own copy unchanged, which
/// limits this issue's change surface to the components it actually adds.
library;

import 'package:flutter/material.dart';

/// Wraps [child] (typically a [FilterChip]/[ChoiceChip]) with one merged
/// semantics node: `'<group>, <label>'`, [selected], and — when [onTap] is
/// non-null — an accessible tap action. The visible chip's own semantics
/// are excluded and rebuilt here: a raw chip announces only its own text
/// plus its selected flag, never which group of controls it belongs to.
Widget groupedChipSemantics({
  required String group,
  required String label,
  required bool selected,
  required Widget child,
  VoidCallback? onTap,
}) {
  return Semantics(
    label: '$group, $label',
    button: onTap != null,
    enabled: onTap != null,
    selected: selected,
    onTap: onTap,
    excludeSemantics: true,
    child: child,
  );
}
