/// The confidence-tier chip ("High confidence", "Learning", ...) shown on
/// the Today card and beside the cycle history.
///
/// One widget for both, because the two copies it replaces had the same
/// fault: the label was drawn *in* the tier colour, on a tint of that same
/// colour. The tier colours are badge tones, which the theme guarantees at
/// 3:1 against the surface — the minimum for a graphic, not for text — and
/// the tint under the label took that lower still. Measured on a rendered
/// Today card, "High confidence" came to about 2.5:1 in both the light and
/// the dark theme, where small text needs 4.5:1.
///
/// The label is now set in `onSurface`. The tier colour stays where it is
/// a graphic: the outline and the tint. So the chip still reads green,
/// amber, red-orange or blue at a glance, and its words can be read.
library;

import 'package:flutter/material.dart';

import '../../domain/prediction/prediction.dart' show CycleConfidence;
import '../../l10n/app_localizations.dart';
import '../l10n/tiers.dart';
import '../theme/lunarlog_colors.dart';
import '../theme/tokens.dart';

/// How strongly the tier colour tints the chip's fill.
const double kConfidenceChipTintAlpha = 0.16;

/// The tier's badge colour: the chip's outline and the base of its tint.
///
/// A theme with no [LunarLogColors] extension (a bare `ThemeData()` in an
/// older test harness) falls back to the colour-scheme roles the history
/// chip used before issue #209 rather than throwing.
Color confidenceChipAccent(ThemeData theme, CycleConfidence tier) {
  final colors = theme.extension<LunarLogColors>();
  if (colors == null) {
    return switch (tier) {
      CycleConfidence.high => theme.colorScheme.primary,
      CycleConfidence.learning => theme.colorScheme.tertiary,
      CycleConfidence.irregular => theme.colorScheme.error,
      CycleConfidence.provisional => theme.colorScheme.secondary,
    };
  }
  return switch (tier) {
    CycleConfidence.high => colors.confidenceHigh,
    CycleConfidence.learning => colors.confidenceLearning,
    CycleConfidence.irregular => colors.confidenceIrregular,
    CycleConfidence.provisional => colors.confidenceProvisional,
  };
}

/// The colour the chip's label is drawn in: the scheme's ordinary text
/// colour, never the tier colour (see the library doc).
Color confidenceChipLabelColor(ThemeData theme) => theme.colorScheme.onSurface;

class ConfidenceChip extends StatelessWidget {
  const ConfidenceChip({super.key, required this.tier});

  final CycleConfidence tier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = confidenceChipAccent(theme, tier);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LLSpace.space2,
        vertical: LLSpace.space1,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: kConfidenceChipTintAlpha),
        borderRadius: BorderRadius.circular(LLRadius.rFull),
        border: Border.all(color: accent),
      ),
      child: Text(
        // Issue #218: the label routes through AppLocalizations (via the
        // shared tier-vocabulary mapper) rather than the domain enum's own
        // `label`, so every tier renders localized copy.
        tierLabel(AppLocalizations.of(context), tier),
        style: theme.textTheme.labelMedium?.copyWith(
          color: confidenceChipLabelColor(theme),
        ),
      ),
    );
  }
}
