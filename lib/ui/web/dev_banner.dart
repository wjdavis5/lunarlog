/// Web guardrails (KTD9; resolved by epic #831's Option A — web is a
/// first-class client): the browser build ships with its own disclosures and
/// an escape hatch.
///
/// Two honest states, selected by whether the build opted into sync with
/// `LUNARLOG_WEB_SYNC=true` ([AppConfig.webSyncEnabled]):
///
/// * **Sync off** (today's default): no account, no token, no synced rows.
///   The banner is the non-dismissible "development build — not for real
///   data" warning and the confirm-guarded wipe action, unchanged.
/// * **Sync on**: the browser holds the signed-in profiles' data unencrypted
///   alongside the session, so the banner is a truthful, *per-session
///   dismissible* browser-build notice that says exactly that and that
///   signing out clears it. It must never say "not for real data".
///
/// The one-time first-profile acknowledgement ([showWebFirstRunAcknowledgment])
/// is rewritten for the same two states rather than deleted.
///
/// Route naming (U2 Approach 2b): the banner's dialogs are deliberately left
/// unnamed — informational or trivial confirm/cancel, not distinct
/// destinations.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/config.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/destructive_button.dart';
import 'package:lunarlog/ui/theme/tokens.dart';

/// Persistent banner for the web build. [onWipe] performs the actual erase
/// (the app passes the device reset, KTD16); it is always behind a
/// confirmation dialog that names the consequence.
class WebDevBanner extends StatefulWidget {
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

  /// The dismiss control only exists on the sync-on browser-build notice.
  @visibleForTesting
  static const Key dismissButtonKey = Key('web-browser-notice-dismiss');

  @override
  State<WebDevBanner> createState() => _WebDevBannerState();
}

class _WebDevBannerState extends State<WebDevBanner> {
  /// Per-session only: a page reload (or a fresh mount) brings the notice
  /// back. Never persisted — dismissing it is not consent to hide the
  /// disclosure for future sessions.
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (widget.webSyncEnabled && _dismissed) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      // The sync-on notice is informational (primaryContainer); the sync-off
      // warning keeps the errorContainer role it always had.
      color: widget.webSyncEnabled
          ? colorScheme.primaryContainer
          : colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.webSyncEnabled
                    ? l10n.webBannerSyncedCopy
                    : l10n.webBannerDevCopy,
                key: const ValueKey('web-dev-banner'),
                style: LLType.labelLarge.toTextStyle(),
              ),
            ),
            if (widget.webSyncEnabled)
              IconButton(
                key: WebDevBanner.dismissButtonKey,
                tooltip: l10n.webBrowserNoticeDismissTooltip,
                onPressed: () => setState(() => _dismissed = true),
                icon: const Icon(Icons.close),
                visualDensity: VisualDensity.compact,
              ),
            TextButton(
              key: WebDevBanner.wipeButtonKey,
              onPressed: () => _confirmWipe(context),
              child: Text(l10n.webWipeAction),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmWipe(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final dialogContext = Navigator.maybeOf(context) != null
        ? context
        : (widget.navigatorKey?.currentContext ?? context);
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.webWipeConfirmTitle),
        content: SingleChildScrollView(
          child: Text(
            widget.webSyncEnabled
                ? l10n.webWipeConfirmSyncedBody
                : l10n.webWipeConfirmDevBody,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.webWipeCancel),
          ),
          DestructiveButton(
            key: const Key('web-wipe-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.webWipeConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.onWipe();
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(l10n.webWipeDone)),
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
///
/// The copy follows the same two honest states as [WebDevBanner]: a
/// sync-off build keeps the "not for real data" warning, a sync-on build
/// states the real browser-storage story instead. [webSyncEnabled] defaults
/// to the build's own [AppConfig.webSyncEnabled] and is injectable for tests.
Future<bool> showWebFirstRunAcknowledgment(
  BuildContext context, {
  required bool alreadyAcknowledged,
  required Future<void> Function() onAcknowledged,
  bool webSyncEnabled = AppConfig.webSyncEnabled,
}) async {
  if (alreadyAcknowledged) return false;
  final l10n = AppLocalizations.of(context);
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(
          webSyncEnabled
              ? l10n.webFirstRunSyncedTitle
              : l10n.webFirstRunDevTitle,
        ),
        content: SingleChildScrollView(
          child: Text(
            webSyncEnabled
                ? l10n.webFirstRunSyncedBody
                : l10n.webFirstRunDevBody,
          ),
        ),
        actions: [
          FilledButton(
            key: const Key('web-acknowledge'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.webFirstRunAcknowledge),
          ),
        ],
      ),
    ),
  );
  await onAcknowledged();
  return true;
}
