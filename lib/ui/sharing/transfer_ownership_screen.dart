/// Screen for arming, sharing, and cancelling a child-profile ownership
/// transfer (Issue #4, U9; R6, R7, R9, R26).
///
/// Pushed from [ManageGuardiansScreen] for the profile's accepted primary
/// guardian, and only when an [OwnershipTransferService] is configured.
library;

import 'dart:async';

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
  // Review item #2 (P1): a transfer discovered via getActiveTransfer rather
  // than just-created — carries no rawToken/claimUri (the server never
  // stores it), so it renders as "cancel this, then arm a fresh one" rather
  // than a shareable link.
  ActiveTransfer? _activeTransfer;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Review item #2 (P1): check on open, not only after a failed create -
    // otherwise a parent revisiting this screen after an earlier
    // createTransfer response was lost (a dropped connection, or the app
    // restarting between the RPC committing and the response arriving)
    // would have to attempt (and fail) a new transfer before ever seeing a
    // way out. Best-effort and silent: a failure here just leaves the
    // ordinary armable form, which still works via the reactive
    // TransferAlreadyArmedFailure path in _armTransfer.
    unawaited(_checkForActiveTransferOnOpen());
  }

  Future<void> _checkForActiveTransferOnOpen() async {
    try {
      final active =
          await widget.service.getActiveTransfer(profileId: widget.profile.id);
      if (mounted && active != null) {
        setState(() => _activeTransfer = active);
      }
    } catch (_) {
      // Best-effort only - see initState's comment.
    }
  }

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
          _activeTransfer = null;
          _loading = false;
        });
      }
    } on TransferAlreadyArmedFailure catch (f) {
      // Review item #2 (P1): a live transfer already exists for this
      // profile — either genuinely pending, or orphaned by a lost response
      // to an earlier createTransfer call (a dropped connection, or the app
      // restarting between the RPC committing and the response arriving).
      // Without this, the parent would be stuck seeing only f's generic
      // message with no way to act, for up to the orphaned transfer's full
      // TTL. Look it up so they can cancel it and try again.
      await _loadActiveTransfer(fallbackMessage: f.userFacingMessage);
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

  Future<void> _loadActiveTransfer({required String fallbackMessage}) async {
    try {
      final active = await widget.service.getActiveTransfer(
        profileId: widget.profile.id,
      );
      if (!mounted) return;
      setState(() {
        _activeTransfer = active;
        _error = active == null ? fallbackMessage : null;
        _loading = false;
      });
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
          _error = fallbackMessage;
          _loading = false;
        });
      }
    }
  }

  Future<void> _cancelActiveTransfer() async {
    final active = _activeTransfer;
    if (active == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await widget.service.cancelTransfer(transferId: active.transferId);
      if (mounted) {
        setState(() {
          _activeTransfer = null;
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pending transfer cancelled')),
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
        child: _transfer != null
            ? _liveTransferBody(context)
            : _activeTransfer != null
                ? _orphanedTransferBody(context)
                : _armableBody(context),
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

  /// Review item #2 (P1): rendered when a transfer already exists for this
  /// profile but was discovered via getActiveTransfer rather than just
  /// created here — its raw token was never stored server-side, so there is
  /// no link to show, only a way out: cancel it, then arm a fresh one.
  Widget _orphanedTransferBody(BuildContext context) {
    final theme = Theme.of(context);
    final active = _activeTransfer!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('A Transfer Is Already Pending', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'A transfer for ${widget.profile.displayName} is already pending, '
          'but its link is not available on this screen (it may have been '
          'created earlier or on another device). Cancel it to start a new '
          'one.',
        ),
        const SizedBox(height: 12),
        Text(
          'Expires ${formatTransferExpiry(active.expiresAt)}',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 20),
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 12),
        ],
        FilledButton(
          onPressed: _loading ? null : _cancelActiveTransfer,
          style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Cancel Pending Transfer'),
        ),
      ],
    );
  }

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
