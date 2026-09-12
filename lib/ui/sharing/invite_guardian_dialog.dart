/// Dialog for generating a caregiver or viewer invitation link (U8; R6, R7, R8).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/models/profile_guardian.dart';
import '../../domain/sharing/sharing_service.dart';
import '../help/help_card_view.dart';

class InviteGuardianDialog extends StatefulWidget {
  const InviteGuardianDialog({
    super.key,
    required this.profileId,
    required this.profileName,
    required this.sharingService,
  });

  final String profileId;
  final String profileName;
  final SharingService sharingService;

  @override
  State<InviteGuardianDialog> createState() => _InviteGuardianDialogState();
}

class _InviteGuardianDialogState extends State<InviteGuardianDialog> {
  GuardianRole _selectedRole = GuardianRole.coParent;
  final TextEditingController _labelController = TextEditingController();

  bool _loading = false;
  GeneratedInvite? _generatedInvite;
  String? _error;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _createInvite() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final invite = await widget.sharingService.createInvite(
        profileId: widget.profileId,
        role: _selectedRole,
        recipientLabel: _labelController.text.trim().isEmpty ? null : _labelController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _generatedInvite = invite;
          _loading = false;
        });
      }
    } on SharingFailure catch (failure) {
      // Issue #535 (d): distinct failure types (unauthorized vs. network,
      // etc.) get their own accurate copy via userFacingMessage, rather
      // than collapsing every SharingFailure into the generic connection
      // message below — matching AcceptInviteSheet's own catch clause.
      if (mounted) {
        setState(() {
          _error = failure.userFacingMessage;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to generate invite. Please check your connection and try again.';
          _loading = false;
        });
      }
    }
  }

  void _copyLink() {
    if (_generatedInvite == null) return;
    Clipboard.setData(ClipboardData(text: _generatedInvite!.inviteUri.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite link copied to clipboard')),
    );
  }

  // Issue #535 (c): share_plus 13.x deprecated the old static
  // `Share.share(String)` in favor of `SharePlus.instance.share(ShareParams
  // (...))` (see TransferOwnershipScreen._shareLink, the sibling pattern
  // this mirrors). Plain text share of the bare link, same as Copy Link.
  void _shareLink() {
    if (_generatedInvite == null) return;
    SharePlus.instance.share(ShareParams(text: _generatedInvite!.inviteUri.toString()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_generatedInvite != null) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Invitation Created', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Share this single-use link with the caregiver for ${widget.profileName}:',
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          _generatedInvite!.inviteUri.toString(),
                          style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Expires in 48 hours. Can be redeemed once.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                overflowSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                  FilledButton.icon(
                    onPressed: _copyLink,
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy Link'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _shareLink,
                    icon: const Icon(Icons.share, size: 16),
                    label: const Text('Share'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Invite Caregiver to ${widget.profileName}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null) ...[
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                      const SizedBox(height: 8),
                    ],
                    const Text('Role:'),
                    const SizedBox(height: 4),
                    DropdownButton<GuardianRole>(
                      value: _selectedRole,
                      isExpanded: true,
                      onChanged: _loading
                          ? null
                          : (role) {
                              if (role != null) setState(() => _selectedRole = role);
                            },
                      items: const [
                        DropdownMenuItem(
                          value: GuardianRole.coParent,
                          child: Text('Co-Parent (Can log, edit profile & invite)'),
                        ),
                        DropdownMenuItem(
                          value: GuardianRole.caregiver,
                          child: Text('Caregiver (Can log symptoms & periods)'),
                        ),
                        DropdownMenuItem(
                          value: GuardianRole.viewer,
                          child: Text('Viewer (Read-only access)'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _labelController,
                      enabled: !_loading,
                      decoration: const InputDecoration(
                        labelText: 'Nickname / Label (Optional)',
                        hintText: 'e.g. Dad, Grandma, School Nurse',
                      ),
                    ),
                    // Issue #139: contextual entry point to the invitations card.
                    const HelpCardLink(
                      cardId: 'invitations',
                      label: 'How do invitations work?',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              overflowSpacing: 8,
              children: [
                TextButton(
                  onPressed: _loading ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: _loading ? null : _createInvite,
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create Link'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Sheet alias for [InviteGuardianDialog] following the dialog/sheet rule (Issue #250).
typedef InviteGuardianSheet = InviteGuardianDialog;
