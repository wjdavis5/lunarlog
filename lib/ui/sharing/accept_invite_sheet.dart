/// Bottom sheet presented when redeeming a guardian invitation link (U8; R7, R8).
library;

import 'package:flutter/material.dart';

import '../../domain/sharing/sharing_service.dart';

class AcceptInviteSheet extends StatefulWidget {
  const AcceptInviteSheet({
    super.key,
    required this.rawToken,
    required this.sharingService,
    this.initialProfileId,
    this.onAccepted,
  });

  final String rawToken;
  final SharingService sharingService;
  final String? initialProfileId;
  final void Function(AcceptedInviteResult result)? onAccepted;

  @override
  State<AcceptInviteSheet> createState() => _AcceptInviteSheetState();
}

class _AcceptInviteSheetState extends State<AcceptInviteSheet> {
  final TextEditingController _nameController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await widget.sharingService.acceptInvite(
        rawToken: widget.rawToken,
        displayName: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
      );
      if (mounted) {
        widget.onAccepted?.call(res);
        Navigator.of(context).pop(res);
      }
    } on SharingFailure catch (failure) {
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
                Icon(Icons.family_restroom, size: 28, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Join Shared Profile', style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'You have been invited to care for a child profile in LunarLog. '
              'Accepting will sync their cycle calendar and health logs to this device.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              enabled: !_loading,
              decoration: const InputDecoration(
                labelText: 'Your display name (e.g. Dad, Mom, Grandma)',
                hintText: 'Shows when you log entries',
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
                  onPressed: _loading ? null : _accept,
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Accept & Sync'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
