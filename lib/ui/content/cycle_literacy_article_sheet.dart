/// Bottom sheet for reading a bundled cycle literacy article (Issue #239).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/content/cycle_literacy_library.dart';
import '../../l10n/app_localizations.dart';
import '../../observability/route_names.dart';
import '../components/safe_launch_url.dart';

class CycleLiteracyArticleSheet extends StatelessWidget {
  const CycleLiteracyArticleSheet({
    super.key,
    required this.article,
    this.launchUrlFn,
  });

  final CycleLiteracyArticle article;
  final LaunchUrlFn? launchUrlFn;

  static Future<void> show(
    BuildContext context,
    CycleLiteracyArticle article, {
    LaunchUrlFn? launchUrlFn,
  }) {
    return showModalBottomSheet(
      context: context,
      routeSettings: const RouteSettings(name: kRouteCycleLiteracyArticleSheet),
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) =>
          CycleLiteracyArticleSheet(article: article, launchUrlFn: launchUrlFn),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
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
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 12),
              ],
              if (section.callout != null) ...[
                CrisisResourcesCard(
                  callout: section.callout!,
                  launchUrlFn: launchUrlFn,
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

/// Renders a structured crisis support block in a calm, discreet tinted card
/// with one-tap action targets (Issue #1132).
///
/// A failed launch is never silent here (Issue #1151): `safeLaunchUrl`
/// returning `false` — the Wi-Fi-iPad `tel:` failure — or the platform
/// launcher throwing shows a calm inline line under the buttons that names
/// the number, so the card's most important information stays visible on a
/// device that can't place calls.
class CrisisResourcesCard extends StatefulWidget {
  const CrisisResourcesCard({
    super.key,
    required this.callout,
    this.launchUrlFn,
  });

  final CrisisResources callout;
  final LaunchUrlFn? launchUrlFn;

  @override
  State<CrisisResourcesCard> createState() => _CrisisResourcesCardState();
}

class _CrisisResourcesCardState extends State<CrisisResourcesCard> {
  /// The dialable number of the last action whose launch failed, or `null`
  /// while no launch has failed (a later success clears it again).
  String? _failedNumber;

  Future<void> _launch(CrisisAction action) async {
    bool launched;
    try {
      launched = await safeLaunchUrl(action.uri, launch: widget.launchUrlFn);
    } catch (_) {
      // url_launcher can throw (e.g. a PlatformException when the OS refuses
      // the scheme). Either way the reader must not be left with a silent
      // button — fall through to the same calm fallback as a `false` result.
      launched = false;
    }
    if (!mounted) return;
    setState(() {
      _failedNumber = launched ? null : action.uri.path;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final callout = widget.callout;
    final failedNumber = _failedNumber;

    return Container(
      key: const ValueKey('crisis-resources-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            callout.text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSecondaryContainer,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final action in callout.actions)
                Semantics(
                  button: true,
                  label: action.semanticsLabel,
                  // TalkBack/VoiceOver double-tap dispatches SemanticsAction.tap
                  // on this node, so the activation must live on the semantics
                  // node itself (Issue #1196): the ExcludeSemantics child below
                  // deliberately strips the OutlinedButton's own semantics to
                  // keep the custom announced label, which would otherwise leave
                  // the node announced but unactivatable (actionsBitmask == 0).
                  onTap: () => unawaited(_launch(action)),
                  child: ExcludeSemantics(
                    child: OutlinedButton(
                      key: ValueKey('crisis-action-${action.label}'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(44, 44),
                        tapTargetSize: MaterialTapTargetSize.padded,
                        foregroundColor: colorScheme.onSecondaryContainer,
                        side: BorderSide(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                      onPressed: () => unawaited(_launch(action)),
                      child: Text(action.label),
                    ),
                  ),
                ),
            ],
          ),
          if (failedNumber != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                key: const ValueKey('crisis-launch-failed-note'),
                l10n.crisisLaunchFailed(failedNumber),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSecondaryContainer,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
