/// Bottom sheet presented when claiming a child-profile ownership transfer
/// (Issue #4, U10; R11, R27, R28).
///
/// Mirrors `AcceptInviteSheet` closely: a loading state, an optional-field
/// form, and [TransferFailure.userFacingMessage] rendered inline on error
/// so the sheet stays open and retryable. Success pops immediately with the
/// [ClaimedProfileResult] (matching `AcceptInviteSheet`'s shape exactly)
/// rather than showing a separate inline confirmation state — the caller
/// (or a snackbar it drives from [onClaimed]) is the simpler, more
/// consistent place for "here's what changed" copy.
library;

import 'package:flutter/material.dart';

import '../../domain/sharing/ownership_transfer_service.dart';

class ClaimProfileSheet extends StatefulWidget {
  const ClaimProfileSheet({
    super.key,
    required this.rawToken,
    required this.service,
    this.initialProfileId,
    this.onClaimed,
  });

  final String rawToken;
  final OwnershipTransferService service;
  final String? initialProfileId;
  final void Function(ClaimedProfileResult result)? onClaimed;

  @override
  State<ClaimProfileSheet> createState() => _ClaimProfileSheetState();
}

class _ClaimProfileSheetState extends State<ClaimProfileSheet> {
  final TextEditingController _childNameController = TextEditingController();
  final TextEditingController _parentNameController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _childNameController.dispose();
    _parentNameController.dispose();
    super.dispose();
  }

  Future<void> _claim() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await widget.service.claimProfile(
        rawToken: widget.rawToken,
        childDisplayName: _childNameController.text.trim().isEmpty
            ? null
            : _childNameController.text.trim(),
        parentDisplayName: _parentNameController.text.trim().isEmpty
            ? null
            : _parentNameController.text.trim(),
      );
      if (mounted) {
        widget.onClaimed?.call(res);
        Navigator.of(context).pop(res);
      }
    } on TransferFailure catch (failure) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = failure.userFacingMessage;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'An unexpected error occurred.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.swap_horiz, size: 28, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Become the Owner', style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Claiming this link makes you the owner of this profile. The '
              'parent who shared it keeps the role they chose, and every '
              'past entry stays with whoever originally logged it.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _childNameController,
              enabled: !_loading,
              decoration: const InputDecoration(
                labelText: "Child's display name (optional)",
                hintText: 'Shows on the profile',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _parentNameController,
              enabled: !_loading,
              decoration: const InputDecoration(
                labelText: 'Label for the parent (optional)',
                hintText: 'Shows when they log entries',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _loading ? null : () => Navigator.of(context).pop(),
                  child: const Text('Decline'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _loading ? null : _claim,
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Become Owner'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
