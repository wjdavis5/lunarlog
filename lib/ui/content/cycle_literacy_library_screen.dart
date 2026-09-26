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
  }) =>
      MaterialPageRoute<void>(
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
                    setState(() => _selectedAudience = CycleLiteracyAudience.all);
                  }
                },
              ),
              ChoiceChip(
                key: const ValueKey('cycle-literacy-filter-teen'),
                label: Text(l10n.cycleLiteracyAudienceFilterTeen),
                selected: _selectedAudience == CycleLiteracyAudience.teen,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _selectedAudience = CycleLiteracyAudience.teen);
                  }
                },
              ),
              ChoiceChip(
                key: const ValueKey('cycle-literacy-filter-guardian'),
                label: Text(l10n.cycleLiteracyAudienceFilterGuardian),
                selected: _selectedAudience == CycleLiteracyAudience.guardian,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _selectedAudience = CycleLiteracyAudience.guardian);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Categories & Articles
          for (final category in CycleLiteracyCategory.values) ...[
            _CategorySection(
              category: category,
              articles: CycleLiteracyLibrary.getArticlesByCategory(category)
                  .where((a) =>
                      _selectedAudience == CycleLiteracyAudience.all ||
                      a.audience == _selectedAudience ||
                      a.audience == CycleLiteracyAudience.all)
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
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      article.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (article.audience != CycleLiteracyAudience.all) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        article.audience.displayName,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
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
          ),
        ],
      ],
    );
  }
}
