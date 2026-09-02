/// Web guardrails (KTD9): the web build is deliberately insecure, so it
/// carries its own warnings and an escape hatch — a non-dismissible
/// development banner and a confirm-guarded wipe-local-data action. The
/// one-time first-profile acknowledgment lives in
/// [showWebFirstRunAcknowledgment] (called from the first-run screen).
library;

import 'package:flutter/material.dart';

/// Persistent, non-dismissible banner for the web build. [onWipe] performs
/// the actual erase (the app passes the database wipe); it is always behind
/// a confirmation dialog that names the consequence.
class WebDevBanner extends StatelessWidget {
  const WebDevBanner({super.key, required this.onWipe});

  final Future<void> Function() onWipe;

  @visibleForTesting
  static const Key wipeButtonKey = Key('web-wipe-local-data');

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Development build — not for real data.',
                key: ValueKey('web-dev-banner'),
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              key: wipeButtonKey,
              onPressed: () => _confirmWipe(context),
              child: const Text('Wipe local data'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmWipe(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Erase all local data?'),
        content: const Text(
          'Erases all data stored in this browser. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('web-wipe-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Erase everything'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await onWipe();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All local data erased.')),
    );
  }
}

/// Wraps [child] with the web banner when [showBanner] is true (the app
/// passes `kIsWeb`; tests inject explicitly).
class WebGuardrails extends StatelessWidget {
  const WebGuardrails({
    super.key,
    required this.showBanner,
    required this.onWipe,
    required this.child,
  });

  final bool showBanner;
  final Future<void> Function() onWipe;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!showBanner) return child;
    return Column(
      children: [
        WebDevBanner(onWipe: onWipe),
        Expanded(child: child),
      ],
    );
  }
}

/// One-time, non-dismissible acknowledgment shown on the web build before
/// the first profile is created (KTD9). Persists via the caller-returned
/// acknowledge callback; returns whether the acknowledgment was needed.
Future<bool> showWebFirstRunAcknowledgment(
  BuildContext context, {
  required bool alreadyAcknowledged,
  required Future<void> Function() onAcknowledged,
}) async {
  if (alreadyAcknowledged) return false;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Development build'),
        content: const Text(
          'This is a development build, not for real data. Data in this '
          'browser is not encrypted and not backed up.',
        ),
        actions: [
          FilledButton(
            key: const Key('web-acknowledge'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('I understand'),
          ),
        ],
      ),
    ),
  );
  await onAcknowledged();
  return true;
}
