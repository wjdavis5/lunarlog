/// Fail-closed startup surface (U7, R6): the full-screen operator-facing
/// error for database open/quarantine/migration failures, replacing U4's
/// basic StartupErrorApp. Shows no profile data and offers no destructive
/// action (never a wipe/recreate button — the settled posture); a single
/// Close action exits. Message differs per failure class using U2's typed
/// errors; the raw error stays selectable for operator diagnostics.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lunarlog/data/db/errors.dart';

class FailClosedApp extends StatelessWidget {
  const FailClosedApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'lunarlog',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00696F)),
      ),
      home: FailClosedScreen(error: error),
    );
  }
}

class FailClosedScreen extends StatelessWidget {
  const FailClosedScreen({super.key, required this.error});

  final Object error;

  (String, String) get _copy {
    switch (error) {
      case DatabaseQuarantineError():
        return (
          'lunarlog could not open your data',
          'The data saved on this device could not be opened. Nothing was '
              'changed and nothing was deleted — the data file was left '
              'exactly as it was, untouched.',
        );
      case CorruptDatabaseKeyError():
        return (
          'lunarlog could not read its unlock key',
          'The key that decrypts your data on this device is damaged. '
              'Nothing was changed. Do not reinstall or reset the app '
              'unless losing the data is acceptable.',
        );
      case EncryptionUnavailableError():
        return (
          'This build cannot protect data',
          'Encryption support is missing from this build of the app, so no '
              'data can be opened or created. Install a proper build.',
        );
      default:
        return (
          'lunarlog could not start',
          'Something went wrong before any data was opened. Nothing on this '
              'device was changed.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, body) = _copy;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock, size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  key: const ValueKey('fail-closed-title'),
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  key: const ValueKey('fail-closed-body'),
                  body,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  key: const ValueKey('fail-closed-close'),
                  onPressed: () => SystemNavigator.pop(),
                  child: const Text('Close'),
                ),
                const SizedBox(height: 32),
                Text(
                  'Technical detail (for the device owner):',
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(height: 4),
                SelectableText(error.toString()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
