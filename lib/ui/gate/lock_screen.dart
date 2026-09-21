/// Locked screen (U7, R7): the only thing visible while the gate holds.
/// Offers unlock/retry — a declined credential never shows data and never
/// exits the app. Its own [MaterialApp] because it renders above (and
/// independent of) the app content in the shell's stack.
///
/// Issue #534: [GateDenialReason.noCredentialEnrolled] gets its own
/// prominent copy and a settings deep link, distinct from
/// [GateDenialReason.deniedByUser]'s retry — a device with no screen lock
/// at all was previously stuck behind the same generic denial message and
/// a footnote below an apparently-broken Unlock button.
///
/// Issue #137: this screen renders dark under a dark system appearance
/// (and under a dark in-app override once the settings store is
/// available). [themeMode] defaults to [ThemeMode.system] — at cold start
/// the database holding the override is deliberately not open yet (AE4:
/// nothing touches it before a credential is accepted), and following the
/// system is exactly the fallback the override itself would compute; on a
/// re-lock the shell passes the resolved override through
/// `GateShell.themeMode` so a dark-forced app never flashes a light lock
/// screen in a shared dark room.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/app_lifecycle.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/gate/device_settings_launcher.dart';
import 'package:lunarlog/ui/gate/pin_unlock_section.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';

class LockScreen extends StatelessWidget {
  const LockScreen({
    super.key,
    required this.controller,
    this.openDeviceSettings = defaultOpenDeviceSettings,
    this.themeMode = ThemeMode.system,
  });

  final GateController controller;

  /// Issue #534: the "Open device settings" action's platform call.
  /// Injectable so tests substitute a fake and never touch
  /// `url_launcher`'s platform channel — same seam pattern as
  /// `AccountSection`'s `appleAuthorizationCodeRequest`.
  final DeviceSettingsLauncher openDeviceSettings;

  /// Issue #137: this MaterialApp's theme mode (see the library doc).
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) =>
          AppLocalizations.of(context).gateLockScreenAppTitle,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      // Issue #160: same localization scaffolding as the main MaterialApp
      // in `lib/app.dart` — this screen renders above (and independent of)
      // the app content, so it must carry its own delegates.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Issue #886: resolve the theme *inside* this nested MaterialApp, not
      // from the enclosing context. `Theme.of(context)` in [build] reads the
      // app that wrapped this screen (typically a light [ThemeData]), and
      // `ThemeData`'s merged text theme carries an explicit colour — so the
      // light `onSurface` ink was painted onto this app's dark `Scaffold`
      // (~1.28:1). The [Builder] sits under this app's own `Theme`, so every
      // text style and colour in the subtree comes from the theme actually
      // painting the `Scaffold`.
      home: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final l10n = AppLocalizations.of(context);
          return Scaffold(
            key: const ValueKey('lock-screen'),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline,
                        size: 56, color: theme.colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(l10n.gateLockScreenTitle,
                        style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    // #271 D-6: once the PIN step is reached — after a granted
                    // device credential, or standing alone with none enrolled —
                    // it replaces the device-credential content entirely.
                    if (controller.pinRequired)
                      PinUnlockSection(controller: controller)
                    else if (controller.denialReason ==
                        GateDenialReason.noCredentialEnrolled)
                      ..._noCredentialContent(theme, l10n)
                    else
                      ..._normalContent(theme, l10n),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// [GateDenialReason.none] (never attempted, or last attempt succeeded)
  /// and [GateDenialReason.deniedByUser]: the OS did present a prompt, so
  /// "try again" is the primary action.
  List<Widget> _normalContent(ThemeData theme, AppLocalizations l10n) => [
        // Issue #258: "Your data is protected" assumed the reader owns the
        // record — this screen may be guarding someone else's (a minor's)
        // profile. Name the device as the thing that is protected; see
        // docs/product/voice-and-copy.md ("second person for the reader").
        Text(
          l10n.gateLockScreenProtectedBody,
          textAlign: TextAlign.center,
        ),
        if (controller.denialReason == GateDenialReason.deniedByUser &&
            !controller.authenticating) ...[
          const SizedBox(height: 12),
          Text(
            key: const ValueKey('lock-denied-message'),
            l10n.gateLockScreenDeniedBody,
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          key: const ValueKey('unlock-button'),
          onPressed:
              controller.authenticating ? null : () => controller.unlock(),
          child: controller.authenticating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.gateLockScreenUnlockButton),
        ),
      ];

  /// [GateDenialReason.noCredentialEnrolled]: `local_auth` reports no
  /// credential exists at all, so no prompt was ever shown — a plain
  /// retry would just silently fail again. This is the primary, prominent
  /// message (not a footnote below a dead-end button), with "Open device
  /// settings" as the primary action. [GateController.unlock] also
  /// re-checks this automatically when the app resumes from background
  /// (issue #534), so an operator who adds a passcode and comes back
  /// unlocks without tapping anything here.
  List<Widget> _noCredentialContent(ThemeData theme, AppLocalizations l10n) => [
        Text(
          key: const ValueKey('no-credential-message'),
          l10n.gateLockScreenNoCredentialBody,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const ValueKey('open-device-settings-button'),
          onPressed: () => openDeviceSettings(),
          icon: const Icon(Icons.settings),
          label: Text(l10n.gateLockScreenOpenDeviceSettings),
        ),
        const SizedBox(height: 16),
        TextButton(
          key: const ValueKey('unlock-retry-button'),
          onPressed:
              controller.authenticating ? null : () => controller.unlock(),
          child: controller.authenticating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.gateLockScreenTryAgain),
        ),
      ];
}
