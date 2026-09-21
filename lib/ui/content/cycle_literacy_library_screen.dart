/// Standalone browsable library of cycle literacy articles (Issue #239).
library;

import 'package:flutter/material.dart';

import '../../domain/content/cycle_literacy_library.dart';
import '../../l10n/app_localizations.dart';
import '../../observability/route_names.dart';
import 'cycle_literacy_article_sheet.dart';

class CycleLiteracyLibraryScreen extends StatelessWidget {
  const CycleLiteracyLibraryScreen({super.key});

  static MaterialPageRoute<void> route() => MaterialPageRoute<void>(
        settings: const RouteSettings(name: kRouteCycleLiteracyLibraryScreen),
        builder: (_) => const CycleLiteracyLibraryScreen(),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.cycleLiteracyLibraryTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header intro
          Text(
            l10n.cycleLiteracyLibraryIntro,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          // Categories & Articles
          for (final category in CycleLiteracyCategory.values) ...[
            _CategorySection(
              category: category,
              articles: CycleLiteracyLibrary.getArticlesByCategory(category),
            ),
            const SizedBox(height: 16),
          ],

          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              CycleLiteracyArticle.kMedicalDisclaimer,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.category,
    required this.articles,
  });

  final CycleLiteracyCategory category;
  final List<CycleLiteracyArticle> articles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (articles.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          category.displayName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        for (final article in articles) ...[
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(
                article.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                article.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => CycleLiteracyArticleSheet.show(context, article),
            ),
          ),
        ],
      ],
    );
  }
}
