/// Upload consent (U6; R14, AS4, F2). Shown when a confirmed session meets
/// a non-empty, unbound database: the operator sees how many rows this
/// device holds (tombstones included — deletions upload too), the
/// duplicate-profile consequence, and chooses to upload now or later.
/// "Not now" leaves the engine in `awaitingUploadConsent`; the Settings
/// tile reopens this screen.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:provider/provider.dart';

/// Row counts of the two synced tables, tombstones included. Structurally
/// the record `LunarLogStorage.countAllRows` returns; the app provides
/// that method as the [LocalRowCounter] so no drift type crosses into
/// `lib/ui`.
typedef LocalRowCounts = ({int profiles, int dayEntries});

typedef LocalRowCounter = Future<LocalRowCounts> Function();

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

class UploadConsentScreen extends StatefulWidget {
  const UploadConsentScreen({super.key, required this.onNotNow});

  final VoidCallback onNotNow;

  @override
  State<UploadConsentScreen> createState() => _UploadConsentScreenState();
}

class _UploadConsentScreenState extends State<UploadConsentScreen> {
  late final Future<LocalRowCounts> _counts;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _counts = context.read<LocalRowCounter>()();
  }

  Future<void> _upload() async {
    if (_busy) return;
    setState(() => _busy = true);
    final sync = context.read<SyncStatusController?>();
    try {
      await sync?.confirmUpload();
    } catch (error) {
      debugPrint('lunarlog sync: upload consent failed (${error.runtimeType})');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload to your account?'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FutureBuilder<LocalRowCounts>(
            future: _counts,
            builder: (context, snapshot) {
              final counts = snapshot.data;
              if (counts == null) {
                return const Text('This device holds data that is not in '
                    'your account yet.');
              }
              return Text(
                'This device holds ${_plural(counts.profiles, 'profile', 'profiles')} '
                'and ${_plural(counts.dayEntries, 'entry', 'entries')} that are '
                'not in your account yet. Uploading copies them to the '
                'account, deletions included, and keeps this device in sync '
                'from now on.',
              );
            },
          ),
          const SizedBox(height: 12),
          const Text(
            'If another device also created the same person while offline, '
            'you will see two profiles after the upload; archive the one you '
            'do not want.',
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const ValueKey('consent-upload'),
            onPressed: _busy ? null : _upload,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Upload to my account'),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('consent-not-now'),
            onPressed: _busy ? null : widget.onNotNow,
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}
