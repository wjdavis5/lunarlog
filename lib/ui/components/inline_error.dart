/// Shared in-place error presentation (issue #187; B-8, B-20): a message
/// plus an optional Retry action, wrapped in a live region so a
/// screen-reader user hears the failure the moment it happens instead of
/// silence with focus stuck on whatever control triggered it. Use this for
/// every retryable, in-place failure — see `lib/ui/README.md` for the full
/// inline-vs-snackbar-vs-full-screen rule this component is one leg of.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class InlineError extends StatelessWidget {
  const InlineError({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;

  /// Null when the surrounding UI already offers its own retry affordance
  /// (e.g. a Save/Export button the operator can simply press again).
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onRetry = this.onRetry;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: LLSpace.space2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
          ],
        ),
      ),
    );
  }
}
