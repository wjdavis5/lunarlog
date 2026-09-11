/// Offline help-card presentation (Issue #139).
///
/// Everything here renders from the bundled [HelpCard] constants — no
/// network, no assets, no platform channels — so every card opens in
/// airplane mode. [showHelpCardSheet] presents a card; [HelpCardLink] is
/// the contextual entry point screens embed next to the question a card
/// answers.
library;

import 'package:flutter/material.dart';

import '../../domain/help/help_cards.dart';

/// Presents [card] in a modal bottom sheet built purely from bundled copy.
Future<void> showHelpCardSheet(BuildContext context, HelpCard card) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => HelpCardView(card: card),
    );

/// A contextual "Learn more" entry point to one bundled card.
///
/// The link resolves [cardId] through [HelpCards.byId] at tap time; an
/// unknown id renders nothing rather than a dead button.
class HelpCardLink extends StatelessWidget {
  const HelpCardLink({
    super.key,
    required this.cardId,
    this.label = 'Learn more',
  });

  final String cardId;
  final String label;

  @override
  Widget build(BuildContext context) {
    final card = HelpCards.byId(cardId);
    if (card == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: ValueKey('help-link-$cardId'),
        onPressed: () => showHelpCardSheet(context, card),
        icon: const Icon(Icons.help_outline, size: 18),
        label: Text(label),
      ),
    );
  }
}

/// The scrollable rendering of one bundled card: title, summary, body
/// paragraphs, then provenance (source + review date).
class HelpCardView extends StatelessWidget {
  const HelpCardView({super.key, required this.card});

  final HelpCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      key: ValueKey('help-card-${card.id}'),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            card.title,
            key: ValueKey('help-card-title-${card.id}'),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            card.summary,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < card.body.length; i++) ...[
            Text(card.body[i], style: theme.textTheme.bodyMedium),
            if (i < card.body.length - 1) const SizedBox(height: 8),
          ],
          const SizedBox(height: 16),
          const Divider(),
          Text(
            'Source: ${card.source}',
            key: ValueKey('help-card-source-${card.id}'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Reviewed: ${card.reviewDate}',
            key: ValueKey('help-card-reviewed-${card.id}'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
