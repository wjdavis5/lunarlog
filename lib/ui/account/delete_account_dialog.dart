/// The account-deletion confirmation (Issue #17, Unit U6; R2). Split out of
/// `account_section.dart` because "Export first" must keep the dialog open
/// across an asynchronous export instead of popping it (the operator must
/// see the file exists before anything is destroyed) - state a plain
/// `AlertDialog` builder cannot hold, unlike `_signOutEverywhere`'s two-
/// action confirmation.
library;

import 'package:flutter/material.dart';

/// What the operator chose. `null` (from [showDeleteAccountDialog]) means
/// the dialog was dismissed some other way (e.g. the system back button);
/// callers treat that exactly like [cancel].
enum DeleteAccountDecision { cancel, delete }

class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key, required this.onExport});

  /// Runs the export (Issue #17 U5) and rethrows on failure so this dialog
  /// can show its own inline error without closing.
  final Future<void> Function() onExport;

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  bool _exporting = false;
  String? _exportError;

  Future<void> _handleExport() async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _exportError = null;
    });
    try {
      await widget.onExport();
    } catch (error) {
      if (mounted) {
        setState(() =>
            _exportError = 'Could not export your data. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exportError = _exportError;
    return AlertDialog(
      title: const Text('Delete account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This permanently removes the server rows for this account, '
            'the account itself, and this device\'s local data. This '
            'cannot be undone.',
          ),
          if (exportError != null) ...[
            const SizedBox(height: 12),
            Text(
              exportError,
              key: const ValueKey('account-delete-export-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(DeleteAccountDecision.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('account-delete-export-first'),
          onPressed: _exporting ? null : _handleExport,
          child: _exporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Export first'),
        ),
        FilledButton(
          key: const ValueKey('account-delete-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () =>
              Navigator.of(context).pop(DeleteAccountDecision.delete),
          child: const Text('Delete account'),
        ),
      ],
    );
  }
}

/// Shows [DeleteAccountDialog] and returns the operator's decision, or
/// `null` if it was dismissed some other way (treat like
/// [DeleteAccountDecision.cancel]).
Future<DeleteAccountDecision?> showDeleteAccountDialog(
  BuildContext context, {
  required Future<void> Function() onExport,
}) =>
    showDialog<DeleteAccountDecision>(
      context: context,
      builder: (_) => DeleteAccountDialog(onExport: onExport),
    );
