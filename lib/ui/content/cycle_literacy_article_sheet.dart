/// Bottom sheet for reading a bundled cycle literacy article (Issue #239).
library;

import 'package:flutter/material.dart';

import '../../domain/content/cycle_literacy_library.dart';
import '../../l10n/app_localizations.dart';
import '../../observability/route_names.dart';

class CycleLiteracyArticleSheet extends StatelessWidget {
  const CycleLiteracyArticleSheet({
    super.key,
    required this.article,
  });

  final CycleLiteracyArticle article;

  static Future<void> show(BuildContext context, CycleLiteracyArticle article) {
    return showModalBottomSheet(
      context: context,
      routeSettings: const RouteSettings(name: kRouteCycleLiteracyArticleSheet),
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => CycleLiteracyArticleSheet(article: article),
    );
  }

  /// Renders one source as `Publisher — Title (identifier)` (Issue #1103).
  String _sourceLabel(AppLocalizations l10n, ArticleSource source) {
    final identifier = source.identifier;
    if (identifier == null) {
      return l10n.cycleLiteracySourceItem(
        source.publisher.displayName,
        source.title,
      );
    }
    return l10n.cycleLiteracySourceItemWithIdentifier(
      source.publisher.displayName,
      source.title,
      identifier,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            // Category & Reading Time Header
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    article.category.displayName,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.cycleLiteracyReadingTimeMinutes(
                    article.readingTimeMinutes,
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Title
            Text(
              article.title,
              key: ValueKey('article-title-${article.id}'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),

            // Summary Takeaway
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                article.summary,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Article Sections
            for (final section in article.sections) ...[
              Text(
                section.heading,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              for (final p in section.paragraphs) ...[
                Text(
                  p,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 8),
            ],

            const Divider(height: 32),

            // Sourced Provenance (Issue #1103): one line per cited source.
            Text(
              l10n.cycleLiteracySourceHeading,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            for (final source in article.sources)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  _sourceLabel(l10n, source),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 2),
            Text(
              l10n.cycleLiteracyLastReviewedLine(article.reviewDate),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // Standard Non-Diagnostic Disclaimer
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
          ],
        );
      },
    );
  }
}
