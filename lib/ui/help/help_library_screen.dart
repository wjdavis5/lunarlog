/// The bundled help library (Issue #139): every [HelpCard] reachable from
/// one list, each opening offline via [showHelpCardSheet].
///
/// Reached from Settings ("Help & explanations") and covered by the same
/// no-network posture as the cards themselves — this screen reads only
/// [HelpCards.all].
library;

import 'package:flutter/material.dart';

import '../../domain/help/help_cards.dart';
import 'help_card_view.dart';

/// Lists all bundled help cards; tapping one presents it in a sheet.
class HelpLibraryScreen extends StatelessWidget {
  const HelpLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cards = HelpCards.all;
    return Scaffold(
      appBar: AppBar(title: const Text('Help & explanations')),
      body: ListView.separated(
        key: const ValueKey('help-library-list'),
        itemCount: cards.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final card = cards[index];
          return ListTile(
            key: ValueKey('help-library-${card.id}'),
            leading: const Icon(Icons.help_outline),
            title: Text(card.title),
            subtitle: Text(
              card.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showHelpCardSheet(context, card),
          );
        },
      ),
    );
  }
}
