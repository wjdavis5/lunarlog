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
/// non-null — an accessible tap action. [enabled] says whether the chip can
/// be used; it defaults to "has a tap action". The visible chip's own semantics
/// are excluded and rebuilt here: a raw chip announces only its own text
/// plus its selected flag, never which group of controls it belongs to.
///
/// Issue #1426: when [group] and [label] are the same word it is announced
/// once, not as "PMS, PMS" — kept in step with the day sheet's copy.
Widget groupedChipSemantics({
  required String group,
  required String label,
  required bool selected,
  required Widget child,
  VoidCallback? onTap,
  bool? enabled,
}) {
  // A chip with no tap action used to be reported as disabled. That is
  // right for a chip that cannot be used, and wrong for the chosen chip of a
  // single-choice row, which has no action only because choosing it again
  // does nothing: a screen reader announced the value the person had picked
  // as "disabled" (TalkBack) or "dimmed" (VoiceOver). Such a caller passes
  // [enabled] itself.
  final usable = enabled ?? onTap != null;
  return Semantics(
    label: group == label ? label : '$group, $label',
    button: usable,
    enabled: usable,
    selected: selected,
    onTap: onTap,
    excludeSemantics: true,
    child: child,
  );
}
