/// Upload consent (U6; R14, AS4, F2). Shown when a confirmed session meets
/// a non-empty, unbound database: the operator sees how many rows this
/// device holds (tombstones included — deletions upload too), the
/// duplicate-profile consequence, and chooses to upload now or later.
/// "Not now" leaves the engine in `awaitingUploadConsent`; the Settings
/// tile reopens this screen.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/sync/local_row_counts.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:provider/provider.dart';

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
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.accountUploadConsentTitle),
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
                return Text(l10n.accountUploadConsentLoadingBody);
              }
              return Text(
                l10n.accountUploadConsentBody(
                  counts.profiles,
                  counts.dayEntries,
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(l10n.accountUploadConsentDuplicateNote),
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
                : Text(l10n.accountUploadConsentUploadAction),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('consent-not-now'),
            onPressed: _busy ? null : widget.onNotNow,
            child: Text(l10n.accountUploadConsentNotNow),
          ),
        ],
      ),
    );
  }
}
