/// Reusable graded-intensity control (Issue #234).
///
/// Built over the **existing** graded-intensity model (Issue #256:
/// `observations.intensity`, [kMinObservationIntensity]..
/// [kMaxObservationIntensity], 1-5) rather than a parallel
/// none/mild/moderate/severe scale — `lib/ui/logging/day_sheet.dart`'s pain
/// graded-intensity rows are this widget's first caller (it replaces that
/// file's own inline `_painIntensityRow` chip row verbatim, same keys, same
/// semantics text, same server-side range), and any future graded symptom
/// entry reuses this one component and the one 1-5 range rather than a
/// second model.
///
/// Accessibility (Issue #234): every chip gets
/// [MaterialTapTargetSize.padded] (Material's own 48x48dp minimum
/// interactive-area mechanism — it pads the chip's real hit region without
/// changing its visual size or introducing a second gesture handler, so a
/// tap anywhere in the padded area still fires the one [onChanged] path),
/// plus a [groupedChipSemantics]-wrapped label for screen readers. Labels
/// are short digits/words that keep the [Wrap] usable at 200% text scale.
library;

import 'package:flutter/material.dart';

import '../../domain/limits.dart';
import 'chip_semantics.dart';

/// The graded values this selector offers: [kMinObservationIntensity]..
/// [kMaxObservationIntensity] inclusive (today 1..5).
final List<int> kIntensitySelectorLevels = [
  for (int i = kMinObservationIntensity; i <= kMaxObservationIntensity; i++) i,
];

/// One graded-intensity control: [kIntensitySelectorLevels] choice chips
/// plus a Clear affordance. [value] is the current grade — `null` means
/// ungraded ("no severity recorded", never "low"); [onChanged] fires with
/// the tapped level, or `null` when Clear is tapped.
class IntensitySelector extends StatelessWidget {
  const IntensitySelector({
    super.key,
    required this.groupLabel,
    required this.value,
    required this.onChanged,
    this.itemLabel,
    this.enabled = true,
    this.clearLabel = 'Clear',
    this.keyPrefix,
  });

  /// The semantics group announced before each level (e.g. "Intensity").
  final String groupLabel;

  /// Prefixed onto each chip's own semantics label (e.g. a symptom's
  /// display name), so "Cramps 4" reads as one phrase. Null omits the
  /// prefix — the bare level/clear word is used instead.
  final String? itemLabel;

  final int? value;
  final ValueChanged<int?> onChanged;
  final bool enabled;

  /// Visible text (and semantics suffix, via [itemLabel]) of the Clear chip.
  final String clearLabel;

  /// When non-null, each chip carries a `'$keyPrefix-$level'` /
  /// `'$keyPrefix-clear'` [ValueKey] — the exact convention
  /// `day_sheet.dart`'s pre-#234 `_painIntensityRow` used
  /// (`pain-intensity-<code>-<level>` / `-clear`), so a caller migrating
  /// onto this widget keeps its existing widget-test keys unchanged.
  final String? keyPrefix;

  String _labelFor(String suffix) => itemLabel == null ? suffix : '$itemLabel $suffix';

  Key? _keyFor(String suffix) => keyPrefix == null ? null : ValueKey('$keyPrefix-$suffix');

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 2,
      children: [
        for (final level in kIntensitySelectorLevels)
          groupedChipSemantics(
            group: groupLabel,
            label: _labelFor('$level'),
            selected: value == level,
            onTap: enabled && value != level ? () => onChanged(level) : null,
            child: ChoiceChip(
              key: _keyFor('$level'),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              label: Text('$level'),
              selected: value == level,
              onSelected: enabled ? (_) => onChanged(level) : null,
            ),
          ),
        groupedChipSemantics(
          group: groupLabel,
          label: _labelFor(clearLabel),
          selected: false,
          onTap: enabled && value != null ? () => onChanged(null) : null,
          child: FilterChip(
            key: _keyFor('clear'),
            materialTapTargetSize: MaterialTapTargetSize.padded,
            label: Text(clearLabel),
            selected: false,
            onSelected: enabled ? (_) => onChanged(null) : null,
          ),
        ),
      ],
    );
  }
}
