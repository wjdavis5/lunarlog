/// Localized rendering of the [CycleConfidence] tier vocabulary (issue
/// #218): the domain enum's own `label`/`summary` getters stay as the
/// debug/`toString` vocabulary (matching every other domain enum here),
/// but user-facing copy routes through these mappers so the new
/// `provisional` tier — and the three #213 tiers it joins — render through
/// AppLocalizations with no hardcoded literals. The `en` ARB values are
/// character-identical to the domain literals they replace (asserted in
/// `test/ui/l10n_test.dart`'s copy-parity group), so this is copy-neutral
/// for existing tiers.
library;

import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/l10n/app_localizations.dart';

String tierLabel(AppLocalizations l10n, CycleConfidence tier) =>
    switch (tier) {
      CycleConfidence.high => l10n.cycleConfidenceHigh,
      CycleConfidence.learning => l10n.cycleConfidenceLearning,
      CycleConfidence.irregular => l10n.cycleConfidenceIrregular,
      CycleConfidence.provisional => l10n.cycleConfidenceProvisional,
    };

String tierSummary(AppLocalizations l10n, CycleConfidence tier) =>
    switch (tier) {
      CycleConfidence.high => l10n.cycleConfidenceSummaryHigh,
      CycleConfidence.learning => l10n.cycleConfidenceSummaryLearning,
      CycleConfidence.irregular => l10n.cycleConfidenceSummaryIrregular,
      CycleConfidence.provisional => l10n.cycleConfidenceSummaryProvisional,
    };
