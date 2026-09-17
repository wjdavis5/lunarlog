/// Screen displayed when an empty-but-bound account fails to restore from cloud
/// (Issue #39, finding #3 in #37).
///
/// Prevents falling through to first-run profile creation on a device restoring
/// an existing account, which would cause divergent profiles and data fragmentation.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/theme/tokens.dart';
import 'package:provider/provider.dart';

class RestoreErrorScreen extends StatelessWidget {
  const RestoreErrorScreen({
    super.key,
    required this.onRetry,
    this.onContinueWithoutSyncing,
    this.onSignOut,
    this.message,
  });

  final VoidCallback onRetry;
  final VoidCallback? onContinueWithoutSyncing;
  final VoidCallback? onSignOut;
  final String? message;

  void _handleSignOut(BuildContext context) {
    if (onSignOut != null) {
      onSignOut!();
      return;
    }
    unawaited(
      context.read<AuthController?>()?.signOut(scope: AuthSignOutScope.local),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSignOut =
        onSignOut != null || Provider.of<AuthController?>(context) != null;
    return Scaffold(
      key: const ValueKey('restore-error'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
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
                // Issue #308: a full screen that stops the app cold must still
                // announce its message the way InlineError does — this was the
                // `lib/ui/README.md` follow-up ("does not do this yet").
                Semantics(
                  liveRegion: true,
                  container: true,
                  child: Text(
                    message ??
                        'We could not restore your account data from the cloud. '
                            'Please check your internet connection and try again.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const ValueKey('restore-retry-button'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
                if (onContinueWithoutSyncing != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const ValueKey('restore-continue-button'),
                    onPressed: onContinueWithoutSyncing,
                    child: const Text('Continue without syncing'),
                  ),
                ],
                if (hasSignOut) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    key: const ValueKey('restore-sign-out-button'),
                    onPressed: () => _handleSignOut(context),
                    child: const Text('Sign out'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
