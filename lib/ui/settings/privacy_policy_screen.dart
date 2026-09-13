library;

import 'package:flutter/material.dart';
import 'package:lunarlog/l10n/app_localizations.dart';

/// Full-screen display of LunarLog's privacy policy (Issue #250).
///
/// Promoted from a modal dialog following the dialog/sheet/full-screen rule:
/// long informational content belongs on a scrollable screen, not in a dialog.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

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
          child: Text(
            l10n.settingsPrivacyDialogBody,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}
