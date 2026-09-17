/// The explicit "predictions suppressed" state, for either of the two
/// reasons [PredictionsSuppressed] carries (`lib/domain/prediction/prediction.dart`):
///
/// 1. [method] (issue #233): a distinct card — never [NotEnoughHistory]'s
///    "log more cycles" framing and never a silent late/paused line —
///    explaining that period prediction is off because the profile's
///    in-effect continuous birth-control method typically stops or
///    irregularly affects periods.
/// 2. [lifecycleMode] (issue #528): the same card shape, explaining that
///    prediction is off because the profile is in a life-stage mode
///    (pregnancy/postpartum/perimenopause) the averaging model doesn't
///    apply to.
///
/// Shared by the overview panel and the Analysis tab (both mount a card for
/// every non-active [CyclePrediction]), so the copy and the fixed
/// non-medical disclaimer render identically in both places (R17).
library;

import 'package:flutter/material.dart';

import 'package:lunarlog/domain/birth_control.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/overview/estimate_copy.dart';
import 'package:lunarlog/ui/profiles/birth_control_choices.dart';

/// Renders the suppressed-state card for exactly one of [method] (issue
/// #233) or [lifecycleMode] (issue #528) — callers pass whichever
/// [PredictionsSuppressed] carried. The birth-control method's localized
/// label is derived through the picker vocabulary (`birthControlChoiceForStored`
/// + the choice-label map) so the copy names the exact recorded method; the
/// lifecycle mode's label is [LifecycleMode.label].
class PredictionsSuppressedCard extends StatelessWidget {
  const PredictionsSuppressedCard({super.key, this.method, this.lifecycleMode})
      : assert(
          (method == null) != (lifecycleMode == null),
          'PredictionsSuppressedCard needs exactly one reason: a '
          'birth-control method or a lifecycle mode',
        );

  final BirthControlMethod? method;
  final LifecycleMode? lifecycleMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final mode = lifecycleMode;
    final body = mode != null
        ? l10n.predictionsSuppressedByModeBody(mode.label)
        : l10n.predictionsSuppressedBody(
            birthControlChoiceLabel(
              birthControlChoiceForStored(method!.toDb()),
              l10n,
            ),
          );
    return Card(
      key: const ValueKey('predictions-suppressed'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.predictionsSuppressedTitle,
              key: const ValueKey('predictions-suppressed-title'),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              key: const ValueKey('predictions-suppressed-body'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              kEstimateDisclaimer,
              key: const ValueKey('predictions-suppressed-disclaimer'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
