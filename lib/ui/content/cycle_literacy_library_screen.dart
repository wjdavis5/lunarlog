/// Standalone browsable library of cycle literacy articles (Issue #239).
library;

import 'package:flutter/material.dart';

import '../../domain/content/cycle_literacy_library.dart';
import '../../l10n/app_localizations.dart';
import '../../observability/route_names.dart';
import 'cycle_literacy_article_sheet.dart';

class CycleLiteracyLibraryScreen extends StatefulWidget {
  const CycleLiteracyLibraryScreen({
    super.key,
    this.initialAudience = CycleLiteracyAudience.all,
  });

  /// The audience pre-selected when opening the library.
  final CycleLiteracyAudience initialAudience;

  static MaterialPageRoute<void> route({
    CycleLiteracyAudience initialAudience = CycleLiteracyAudience.all,
  }) => MaterialPageRoute<void>(
    settings: const RouteSettings(name: kRouteCycleLiteracyLibraryScreen),
    builder: (_) =>
        CycleLiteracyLibraryScreen(initialAudience: initialAudience),
  );

  @override
  State<CycleLiteracyLibraryScreen> createState() =>
      _CycleLiteracyLibraryScreenState();
}

class _CycleLiteracyLibraryScreenState
    extends State<CycleLiteracyLibraryScreen> {
  late CycleLiteracyAudience _selectedAudience;

  @override
  void initState() {
    super.initState();
    _selectedAudience = widget.initialAudience;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.cycleLiteracyLibraryTitle)),
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
          const SizedBox(height: 12),

          // Audience Filter Chips (Issue #854)
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                key: const ValueKey('cycle-literacy-filter-all'),
                label: Text(l10n.cycleLiteracyAudienceFilterAll),
                selected: _selectedAudience == CycleLiteracyAudience.all,
                onSelected: (selected) {
                  if (selected) {
                    setState(
                      () => _selectedAudience = CycleLiteracyAudience.all,
                    );
                  }
                },
              ),
              ChoiceChip(
                key: const ValueKey('cycle-literacy-filter-teen'),
                label: Text(l10n.cycleLiteracyAudienceFilterTeen),
                selected: _selectedAudience == CycleLiteracyAudience.teen,
                onSelected: (selected) {
                  if (selected) {
                    setState(
                      () => _selectedAudience = CycleLiteracyAudience.teen,
                    );
                  }
                },
              ),
              ChoiceChip(
                key: const ValueKey('cycle-literacy-filter-guardian'),
                label: Text(l10n.cycleLiteracyAudienceFilterGuardian),
                selected: _selectedAudience == CycleLiteracyAudience.guardian,
                onSelected: (selected) {
                  if (selected) {
                    setState(
                      () => _selectedAudience = CycleLiteracyAudience.guardian,
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Featured Audience Section (#1088): when an audience is selected,
          // surface that audience's targeted articles at the very top.
          if (_selectedAudience != CycleLiteracyAudience.all) ...[
            _AudienceSection(
              title: _audienceSectionTitle(l10n, _selectedAudience),
              articles: CycleLiteracyLibrary.getArticlesForExactAudience(
                _selectedAudience,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Categories & Articles
          for (final category in CycleLiteracyCategory.values) ...[
            _CategorySection(
              category: category,
              articles: CycleLiteracyLibrary.getArticlesByCategory(category)
                  .where(
                    (a) => _selectedAudience == CycleLiteracyAudience.all
                        ? true
                        : a.audience == CycleLiteracyAudience.all,
                  )
                  .toList(),
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

String _audienceSectionTitle(
  AppLocalizations l10n,
  CycleLiteracyAudience audience,
) => switch (audience) {
  CycleLiteracyAudience.teen => l10n.cycleLiteracySectionWrittenForTeens,
  CycleLiteracyAudience.guardian =>
    l10n.cycleLiteracySectionWrittenForGuardians,
  CycleLiteracyAudience.all => '',
};

String _audienceBadgeLabel(
  AppLocalizations l10n,
  CycleLiteracyAudience audience,
) => switch (audience) {
  CycleLiteracyAudience.teen => l10n.cycleLiteracyAudienceFilterTeen,
  CycleLiteracyAudience.guardian => l10n.cycleLiteracyAudienceFilterGuardian,
  CycleLiteracyAudience.all => l10n.cycleLiteracyAudienceFilterAll,
};

class _AudienceSection extends StatelessWidget {
  const _AudienceSection({required this.title, required this.articles});

  final String title;
  final List<CycleLiteracyArticle> articles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (articles.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        for (final article in articles) _ArticleCard(article: article),
      ],
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({required this.category, required this.articles});

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
        for (final article in articles) _ArticleCard(article: article),
      ],
    );
  }
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({required this.article});

  final CycleLiteracyArticle article;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (article.audience != CycleLiteracyAudience.all) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _audienceBadgeLabel(l10n, article.audience),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            Text(
              article.title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
    );
  }
}
