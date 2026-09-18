/// The Postpartum-mode Cycle View card (Issue #455): replaces the ordinary
/// cycle countdown (which never renders in Postpartum mode — prediction is
/// suppressed, #528) with a day-count since the profile entered the mode,
/// plus the "cycles have returned" offer once a bleed has been logged
/// during the interval.
///
/// Mirrors `lib/ui/components/pregnancy_card.dart` exactly: pure display,
/// the math lives in `lib/domain/postpartum.dart` (`daysSincePostpartumStart`)
/// and is unit-tested there, and this widget only renders what the caller
/// computed. The return offer is a callback because the mode switch itself
/// (and the exit-exclusion offer that follows it) is a caller concern —
/// this card never writes anything.
///
/// An unrecorded start renders the quiet "start wasn't recorded" line
/// instead — an honest no-data state, never a fabricated day count.
library;

import 'package:flutter/material.dart';

import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/theme/tokens.dart';

class PostpartumCard extends StatelessWidget {
  const PostpartumCard({
    super.key,
    this.daysSinceStart,
    this.showReturnOffer = false,
    this.canSwitch = true,
    this.onSwitchToTracking,
  });

  /// Whole days since the profile entered Postpartum mode
  /// (`daysSincePostpartumStart`), or null when no start date is recorded.
  final int? daysSinceStart;

  /// Whether a bleed has been logged during the interval — the
  /// cycles-have-returned offer's trigger. Ignored (and the offer omitted)
  /// while [daysSinceStart] is null, since an absent interval has no
  /// honest "since when" to attach the offer to.
  final bool showReturnOffer;

  /// Whether the caller may switch the profile's mode (false for a
  /// read-only guardian or an archived profile): the offer renders as copy
  /// only, with no action, rather than a dead button.
  final bool canSwitch;

  /// Invoked by the offer's action; the caller switches the mode and
  /// offers the interval exclusion.
  final VoidCallback? onSwitchToTracking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final days = daysSinceStart;
    return Card(
      key: const ValueKey('postpartum-card'),
      child: Padding(
        padding: const EdgeInsets.all(LLSpace.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (days != null) ...[
              Text(
                l10n.postpartumDayTitle(days),
                key: const ValueKey('postpartum-day'),
                style: theme.textTheme.headlineSmall,
              ),
            ] else
              Text(
                l10n.postpartumStartMissing,
                key: const ValueKey('postpartum-start-missing'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (days != null && showReturnOffer) ...[
              const SizedBox(height: LLSpace.space3),
              _returnOffer(context, theme, l10n),
            ],
          ],
        ),
      ),
    );
  }

  Widget _returnOffer(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    return Container(
      key: const ValueKey('postpartum-return-offer'),
      padding: const EdgeInsets.all(LLSpace.space3),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(LLRadius.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.postpartumReturnTitle,
            key: const ValueKey('postpartum-return-title'),
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: LLSpace.space1),
          Text(
            l10n.postpartumReturnBody,
            key: const ValueKey('postpartum-return-body'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          if (canSwitch && onSwitchToTracking != null) ...[
            const SizedBox(height: LLSpace.space2),
            FilledButton(
              key: const ValueKey('postpartum-return-action'),
              onPressed: onSwitchToTracking,
              child: Text(l10n.postpartumReturnAction),
            ),
          ],
        ],
      ),
    );
  }
}
