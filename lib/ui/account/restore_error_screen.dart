/// Screen displayed when an empty-but-bound account fails to restore from cloud
/// (Issue #39, finding #3 in #37).
///
/// Prevents falling through to first-run profile creation on a device restoring
/// an existing account, which would cause divergent profiles and data fragmentation.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/ui/theme/tokens.dart';

class RestoreErrorScreen extends StatelessWidget {
  const RestoreErrorScreen({
    super.key,
    required this.onRetry,
    this.message,
  });

  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('restore-error'),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 24),
              Text(
                'Unable to restore data',
                style: LLType.headlineSmall.toTextStyle(),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                message ??
                    'We could not restore your account data from the cloud. '
                        'Please check your internet connection and try again.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const ValueKey('restore-retry-button'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
