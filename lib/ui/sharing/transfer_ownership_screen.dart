/// Screen for arming, sharing, and cancelling a child-profile ownership
/// transfer (Issue #4, U9; R6, R7, R9, R26).
///
/// Pushed from [ManageGuardiansScreen] for the profile's accepted primary
/// guardian, and only when an [OwnershipTransferService] is configured.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/models/profile.dart';
import '../../domain/sharing/ownership_transfer_service.dart';

/// Renders [utc] in the device's local time as `YYYY-MM-DD HH:MM`, mirroring
/// `formatCreatedDate` in `profile_picker_screen.dart`.
String formatTransferExpiry(DateTime utc) {
  final local = utc.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

class TransferOwnershipScreen extends StatefulWidget {
  const TransferOwnershipScreen({
    super.key,
    required this.profile,
    required this.service,
  });

  final Profile profile;
  final OwnershipTransferService service;

  @override
  State<TransferOwnershipScreen> createState() =>
      _TransferOwnershipScreenState();
}

class _TransferOwnershipScreenState extends State<TransferOwnershipScreen> {
  ParentPostTransferRole? _selectedRole;
  final TextEditingController _labelController = TextEditingController();

  bool _loading = false;
  GeneratedTransfer? _transfer;
  String? _error;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _handleTransferPressed() async {
    // R7: arming requires an explicit post-transfer role choice — the
    // confirm dialog (and createTransfer) must never fire without one.
    final role = _selectedRole;
    if (role == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transfer ownership?'),
        content: Text(
          '${widget.profile.displayName} will become the owner of this '
          "profile. You'll keep access as ${role.label}, and they can "
          'remove that access at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Transfer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _armTransfer(role);
  }

  Future<void> _armTransfer(ParentPostTransferRole role) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final transfer = await widget.service.createTransfer(
        profileId: widget.profile.id,
        parentPostTransferRole: role,
        recipientLabel: _labelController.text.trim().isEmpty
            ? null
            : _labelController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _transfer = transfer;
          _loading = false;
        });
      }
    } on TransferFailure catch (f) {
      if (mounted) {
        setState(() {
          _error = f.userFacingMessage;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Something went wrong. Please try again.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _cancelTransfer() async {
    final transfer = _transfer;
    if (transfer == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await widget.service.cancelTransfer(transferId: transfer.transferId);
      if (mounted) {
        setState(() {
          _transfer = null;
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transfer cancelled')),
        );
      }
    } on TransferFailure catch (f) {
      if (mounted) {
        setState(() {
          _error = f.userFacingMessage;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Something went wrong. Please try again.';
          _loading = false;
        });
      }
    }
  }

  void _copyLink() {
    final transfer = _transfer;
    if (transfer == null) return;
    Clipboard.setData(ClipboardData(text: transfer.claimUri.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Transfer link copied to clipboard')),
    );
  }

  void _shareLink() {
    final transfer = _transfer;
    if (transfer == null) return;
    // share_plus 13.x deprecated the old static `Share.share(String)` in
    // favor of `SharePlus.instance.share(ShareParams(...))`; this is a plain
    // text share (the link is a custom `lunarlog://` scheme, not a
    // browsable http(s) URL, so `ShareParams.text` is the right field
    // rather than `ShareParams.uri`).
    SharePlus.instance.share(ShareParams(text: transfer.claimUri.toString()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Transfer ${widget.profile.displayName}'s Profile"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _transfer == null
            ? _armableBody(context)
            : _liveTransferBody(context),
      ),
    );
  }

  Widget _armableBody(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What changes', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _bullet("${widget.profile.displayName} becomes this profile's owner."),
        _bullet('You keep the role you choose below.'),
        _bullet('They can remove your access at any time.'),
        _bullet(
          "If they later delete their account, this profile's history goes "
          'with it.',
        ),
        const SizedBox(height: 20),
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 12),
        ],
        Text('Your role after the transfer', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<ParentPostTransferRole>(
          segments: [
            ButtonSegment(
              value: ParentPostTransferRole.coManager,
              label: Text(ParentPostTransferRole.coManager.label),
            ),
            ButtonSegment(
              value: ParentPostTransferRole.viewer,
              label: Text(ParentPostTransferRole.viewer.label),
            ),
          ],
          // R7: no default selection — arming requires an explicit choice.
          selected: _selectedRole == null ? const {} : {_selectedRole!},
          emptySelectionAllowed: true,
          onSelectionChanged: _loading
              ? null
              : (selected) => setState(
                    () => _selectedRole = selected.isEmpty ? null : selected.first,
                  ),
        ),
        const SizedBox(height: 8),
        Text(
          _selectedRole == ParentPostTransferRole.viewer
              ? 'Viewer: read-only access to their calendar and entries.'
              : 'Co-manager: keep logging entries and managing this profile.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _labelController,
          enabled: !_loading,
          decoration: const InputDecoration(
            labelText: 'Recipient label (optional)',
            hintText: 'e.g. Sam',
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _loading || _selectedRole == null
              ? null
              : _handleTransferPressed,
          style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Transfer Ownership'),
        ),
      ],
    );
  }

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('•  '),
            Expanded(child: Text(text)),
          ],
        ),
      );

  Widget _liveTransferBody(BuildContext context) {
    final theme = Theme.of(context);
    final transfer = _transfer!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Transfer Ready', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('Share this single-use link with ${widget.profile.displayName}:'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            transfer.claimUri.toString(),
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Expires ${formatTransferExpiry(transfer.expiresAt)}',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 20),
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _copyLink,
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy Link'),
            ),
            OutlinedButton.icon(
              onPressed: _loading ? null : _shareLink,
              icon: const Icon(Icons.share, size: 16),
              label: const Text('Share'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        TextButton(
          onPressed: _loading ? null : _cancelTransfer,
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Cancel transfer'),
        ),
      ],
    );
  }
}
