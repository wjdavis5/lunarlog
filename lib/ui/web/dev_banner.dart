/// Web guardrails (KTD9): the web build is deliberately insecure, so it
/// carries its own warnings and an escape hatch — a non-dismissible
/// development banner and a confirm-guarded wipe-local-data action. The
/// one-time first-profile acknowledgment lives in
/// [showWebFirstRunAcknowledgment] (called from the first-run screen).
///
/// Route naming (U2 Approach 2b): both `showDialog` calls here (the
/// erase-local-data confirm and the non-dismissible dev-build notice) are
/// deliberately left unnamed — informational or trivial confirm/cancel,
/// not distinct destinations.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/config.dart';

/// Banner copy for the default web build (no account, no sync).
const String kWebBannerCopy = 'Development build — not for real data.';

/// Banner copy when the build opted into web sync (AS9, U6 Approach 11):
/// a signed-in browser holds the account's rows and a bearer token.
const String kWebBannerSyncCopy = 'Development build — this browser holds '
    'your synced family data unencrypted. Not for real data.';

/// Persistent, non-dismissible banner for the web build. [onWipe] performs
/// the actual erase (the app passes the device reset, KTD16); it is always
/// behind a confirmation dialog that names the consequence.
class WebDevBanner extends StatelessWidget {
  const WebDevBanner({
    super.key,
    required this.onWipe,
    this.webSyncEnabled = AppConfig.webSyncEnabled,
    this.navigatorKey,
  });

  final Future<void> Function() onWipe;

  /// The app's navigator, for the confirmation dialog: the banner sits in
  /// `MaterialApp.builder`, *above* the navigator, so its own context has
  /// none. Optional — a banner mounted below a navigator uses that.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Whether the build compiled with `LUNARLOG_WEB_SYNC=true`; injectable.
  final bool webSyncEnabled;

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
            Expanded(
              child: Text(
                webSyncEnabled ? kWebBannerSyncCopy : kWebBannerCopy,
                key: const ValueKey('web-dev-banner'),
                style: const TextStyle(fontWeight: FontWeight.w600),
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
    final dialogContext = Navigator.maybeOf(context) != null
        ? context
        : (navigatorKey?.currentContext ?? context);
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Erase all local data?'),
        content: Text(
          webSyncEnabled
              ? 'Erases all data stored in this browser and signs out. '
                  'This cannot be undone here; data already in your account '
                  'stays there.'
              : 'Erases all data stored in this browser. This cannot be undone.',
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
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
    this.webSyncEnabled = AppConfig.webSyncEnabled,
    this.navigatorKey,
  });

  final bool showBanner;
  final Future<void> Function() onWipe;
  final Widget child;
  final bool webSyncEnabled;

  /// See [WebDevBanner.navigatorKey].
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    if (!showBanner) return child;
    return Column(
      children: [
        WebDevBanner(
          onWipe: onWipe,
          webSyncEnabled: webSyncEnabled,
          navigatorKey: navigatorKey,
        ),
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
