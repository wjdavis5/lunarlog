/// The explicit "predictions turned off" state card (issue #225):
/// explains that estimates, calendar prediction bands, and prediction reminders
/// are paused while logging, history, and statistics continue unchanged.
///
/// Shared by the overview panel and the Analysis tab.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/l10n/app_localizations.dart';

class PredictionsDisabledCard extends StatelessWidget {
  const PredictionsDisabledCard({super.key, this.onManageSettings});

  final VoidCallback? onManageSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Card(
      key: const ValueKey('predictions-disabled'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.predictionsDisabledTitle,
              key: const ValueKey('predictions-disabled-title'),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.predictionsDisabledBody,
              key: const ValueKey('predictions-disabled-body'),
              style: theme.textTheme.bodySmall,
            ),
            if (onManageSettings != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                key: const ValueKey('predictions-disabled-settings-btn'),
                onPressed: onManageSettings,
                child: Text(l10n.predictionsDisabledAction),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
