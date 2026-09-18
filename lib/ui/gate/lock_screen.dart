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
    final theme = Theme.of(context);
    return MaterialApp(
      title: 'lunarlog',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      // Issue #160: same localization scaffolding as the main MaterialApp
      // in `lib/app.dart` — this screen renders above (and independent of)
      // the app content, so it must carry its own delegates.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
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
                Text('lunarlog is locked',
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                // #271 D-6: once the PIN step is reached — after a granted
                // device credential, or standing alone with none enrolled —
                // it replaces the device-credential content entirely.
                if (controller.pinRequired)
                  PinUnlockSection(controller: controller)
                else if (controller.denialReason ==
                    GateDenialReason.noCredentialEnrolled)
                  ..._noCredentialContent(theme)
                else
                  ..._normalContent(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// [GateDenialReason.none] (never attempted, or last attempt succeeded)
  /// and [GateDenialReason.deniedByUser]: the OS did present a prompt, so
  /// "try again" is the primary action.
  List<Widget> _normalContent(ThemeData theme) => [
        // Issue #258: "Your data is protected" assumed the reader owns the
        // record — this screen may be guarding someone else's (a minor's)
        // profile. Name the device as the thing that is protected; see
        // docs/product/voice-and-copy.md ("second person for the reader").
        const Text(
          'Everything logged on this device stays protected. Unlock to '
          'continue.',
          textAlign: TextAlign.center,
        ),
        if (controller.denialReason == GateDenialReason.deniedByUser &&
            !controller.authenticating) ...[
          const SizedBox(height: 12),
          const Text(
            key: ValueKey('lock-denied-message'),
            'Not unlocked. The profiles on this device stay hidden until '
            'the device credential is accepted.',
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
              : const Text('Unlock'),
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
  List<Widget> _noCredentialContent(ThemeData theme) => [
        Text(
          key: const ValueKey('no-credential-message'),
          'This device has no screen lock set. lunarlog protects your '
          "family's data using your device's own screen lock, so it can't "
          'open until you add one — a passcode, PIN, pattern, or biometric '
          'lock all work.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const ValueKey('open-device-settings-button'),
          onPressed: () => openDeviceSettings(),
          icon: const Icon(Icons.settings),
          label: const Text('Open device settings'),
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
              : const Text('Try again'),
        ),
      ];
}
