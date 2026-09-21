/// Dialog for arming a prediction-only connection (issue #151) — the
/// phases-only counterpart of `InviteGuardianDialog`. The sharer sends
/// the single-use code out of band; the recipient's app redeems it and
/// gets a read-only calendar of derived phases, nothing else.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/l10n/prediction_connection_failure_copy.dart';

import '../../domain/sharing/prediction_connection_service.dart';
import '../components/inline_error.dart';

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
  State<SharePredictionsDialog> createState() => _SharePredictionsDialogState();
}

class _SharePredictionsDialogState extends State<SharePredictionsDialog> {
  final TextEditingController _labelController = TextEditingController();

  bool _loading = false;
  GeneratedPredictionInvite? _invite;
  String? _error;

  /// #558: see `InviteGuardianDialog._justCopied`'s doc comment -- a
  /// `ScaffoldMessenger` SnackBar here would resolve to the underlying
  /// screen's Scaffold and paint behind this dialog's own barrier.
  bool _justCopied = false;

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
          _error = predictionConnectionFailureCopy(
            AppLocalizations.of(context),
            failure,
          );
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context)
              .sharingSharePredictionsCreateFailed;
          _loading = false;
        });
      }
    }
  }

  void _copyCode() {
    if (_invite == null) return;
    unawaited(
      Clipboard.setData(ClipboardData(text: _invite!.inviteUri.toString())),
    );
    setState(() => _justCopied = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    if (_invite != null) {
      return AlertDialog(
        title: Text(l10n.sharingSharePredictionsCreatedTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.sharingSharePredictionsSendLink(widget.profileName),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  _invite!.inviteUri.toString(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.sharingSharePredictionsCreatedBody,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_justCopied) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Row(
                    key: const ValueKey(
                      'share-predictions-copied-confirmation',
                    ),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l10n.sharingSharePredictionsCopied,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('share-predictions-done'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.sharingSharePredictionsDone),
          ),
          FilledButton.icon(
            onPressed: _copyCode,
            icon: const Icon(Icons.copy, size: 16),
            label: Text(l10n.sharingSharePredictionsCopyLink),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text(l10n.sharingSharePredictionsTitle(widget.profileName)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.sharingSharePredictionsBody),
            const SizedBox(height: 12),
            if (_error != null) ...[
              InlineError(
                message: _error!,
                onRetry: _loading ? null : _createConnection,
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _labelController,
              enabled: !_loading,
              // #165: the form's only text field — "done" is the Create
              // Link action.
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_loading) unawaited(_createConnection());
              },
              decoration: InputDecoration(
                labelText: l10n.sharingSharePredictionsNicknameLabel,
                hintText: l10n.sharingSharePredictionsNicknameHint,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.sharingSharePredictionsCancel),
        ),
        FilledButton(
          onPressed: _loading ? null : _createConnection,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.sharingSharePredictionsCreateLink),
        ),
      ],
    );
  }
}
