library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/safe_launch_url.dart';

/// The canonical full policy this screen's action opens (issue #1164) —
/// the same URL the site footer and the Health Connect rationale screen
/// use, rendered from PRIVACY.md.
const String kFullPrivacyPolicyUrl = 'https://lunarlog.app/privacy';

/// In-app privacy summary screen (Issue #250; summary-first retitling and
/// the tappable full-policy action, Issue #1164).
///
/// The screen carries the eight-bullet ARB summary — deliberately *not*
/// the full policy, which lives at [kFullPrivacyPolicyUrl] (rendered from
/// PRIVACY.md at lunarlog.app/privacy). A "Read the full privacy policy"
/// button opens that URL through [safeLaunchUrl] (the `https` scheme is in
/// the default allowlist); a failed launch — or one that throws — is never
/// silent: a calm inline line names the URL, the same failure fallback
/// pattern as the crisis resources card (Issue #1155). [launchUrlFn] is
/// the injected-launcher test seam; production passes nothing and the real
/// platform launcher runs.
class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key, this.launchUrlFn});

  final LaunchUrlFn? launchUrlFn;

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  /// Whether the last full-policy launch attempt failed, so the calm
  /// fallback line is showing (a later success clears it again).
  bool _openFailed = false;

  Future<void> _openFullPolicy() async {
    bool launched;
    try {
      launched = await safeLaunchUrl(
        Uri.parse(kFullPrivacyPolicyUrl),
        launch: widget.launchUrlFn,
      );
    } catch (_) {
      // url_launcher can throw (e.g. a PlatformException when the OS has no
      // handler for the URL). Either way the reader must not be left with a
      // silent button — fall through to the same calm fallback as a `false`
      // result.
      launched = false;
    }
    if (!mounted) return;
    setState(() => _openFailed = !launched);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsPrivacyDialogTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.settingsClose),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.settingsPrivacySummaryNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.settingsPrivacyDialogBody,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('open-full-privacy-policy'),
                onPressed: () => unawaited(_openFullPolicy()),
                child: Text(l10n.settingsPrivacyOpenFullPolicy),
              ),
              if (_openFailed) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    key: const ValueKey('privacy-policy-open-failed-note'),
                    l10n.settingsPrivacyOpenFullPolicyFailed,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
