/// Dialog for arming a prediction-only connection (issue #151) — the
/// phases-only counterpart of `InviteGuardianDialog`. The sharer sends
/// the single-use code out of band; the recipient's app redeems it and
/// gets a read-only calendar of derived phases, nothing else.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/sharing/prediction_connection_service.dart';

class SharePredictionsDialog extends StatefulWidget {
  const SharePredictionsDialog({
    super.key,
    required this.profileId,
    required this.profileName,
    required this.service,
  });

  final String profileId;
  final String profileName;
  final PredictionConnectionService service;

  @override
  State<SharePredictionsDialog> createState() =>
      _SharePredictionsDialogState();
}

class _SharePredictionsDialogState extends State<SharePredictionsDialog> {
  final TextEditingController _labelController = TextEditingController();

  bool _loading = false;
  GeneratedPredictionInvite? _invite;
  String? _error;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _createConnection() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final invite = await widget.service.createConnection(
        profileId: widget.profileId,
        recipientLabel: _labelController.text.trim().isEmpty
            ? null
            : _labelController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _invite = invite;
          _loading = false;
        });
      }
    } on PredictionConnectionFailure catch (failure) {
      if (mounted) {
        setState(() {
          _error = failure.userFacingMessage;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Failed to create the connection. Please check your connection '
              'and try again.';
          _loading = false;
        });
      }
    }
  }

  void _copyCode() {
    if (_invite == null) return;
    Clipboard.setData(ClipboardData(text: _invite!.inviteUri.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Connection link copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_invite != null) {
      return AlertDialog(
        title: const Text('Connection created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Send this single-use link to the person who should see '
                '${widget.profileName}\'s predictions:'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _invite!.inviteUri.toString(),
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'They will see estimated period, fertile, ovulation, and PMS '
              'days on a read-only calendar — no notes or logs. The code '
              'expires in 72 hours and can be redeemed once.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: _copyCode,
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Link'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text('Share predictions of ${widget.profileName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Creates a read-only connection that sees estimated period, '
              'fertile, ovulation, and PMS days — never notes, tags, or '
              'logs. One connection per profile.',
            ),
            const SizedBox(height: 12),
            if (_error != null) ...[
              Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _labelController,
              enabled: !_loading,
              decoration: const InputDecoration(
                labelText: 'Nickname / Label (Optional)',
                hintText: 'e.g. Partner, Aunt',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : _createConnection,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create Link'),
        ),
      ],
    );
  }
}
