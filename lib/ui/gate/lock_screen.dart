/// Locked screen (U7, R7): the only thing visible while the gate holds.
/// Offers unlock/retry — a declined credential never shows data and never
/// exits the app. Its own [MaterialApp] because it renders above (and
/// independent of) the app content in the shell's stack.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/app_lifecycle.dart';

class LockScreen extends StatelessWidget {
  const LockScreen({super.key, required this.controller});

  final GateController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MaterialApp(
      title: 'lunarlog',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00696F)),
      ),
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
                const Text(
                  'Your data is protected. Unlock to continue.',
                  textAlign: TextAlign.center,
                ),
                if (controller.lastAttemptDenied &&
                    !controller.authenticating) ...[
                  const SizedBox(height: 12),
                  const Text(
                    key: ValueKey('lock-denied-message'),
                    'Not unlocked. Your data stays hidden until the device '
                    'credential is accepted.',
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  key: const ValueKey('unlock-button'),
                  onPressed: controller.authenticating
                      ? null
                      : () => controller.unlock(),
                  child: controller.authenticating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Unlock'),
                ),
                const SizedBox(height: 16),
                Text(
                  'If this device has no screen lock set, add one in system '
                  'settings — lunarlog will not open without it.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
