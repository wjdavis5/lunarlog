/// Dialog for generating a caregiver or viewer invitation link (U8; R6, R7, R8).
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:lunarlog/l10n/app_localizations.dart';

import '../../domain/models/profile_guardian.dart';
import '../../domain/sharing/sharing_service.dart';
import '../components/inline_error.dart';
import '../help/help_card_view.dart';
import '../l10n/sharing_failure_copy.dart';

class InviteGuardianDialog extends StatefulWidget {
  const InviteGuardianDialog({
    super.key,
    required this.profileId,
    required this.profileName,
    required this.sharingService,
    this.subjectInviteAvailable = false,
  });

  final String profileId;
  final String profileName;
  final SharingService sharingService;

  /// Issue #802: the "her own profile" preset is offered (and preselected)
  /// only when the caller determined the profile is the invitee's own —
  /// the profile's relationship is daughter/son/child or the profile is a
  /// minor's. False keeps the dialog exactly the pre-#802 helper invite.
  final bool subjectInviteAvailable;

  @override
  State<InviteGuardianDialog> createState() => _InviteGuardianDialogState();
}

/// Issue #802: the dialog's choices are presets, not bare roles — the
/// fourth one ([_InvitePreset.subject], shown only when
/// [InviteGuardianDialog.subjectInviteAvailable]) grants the caregiver
/// role *plus* the subject marker, so the daughter joins her own profile
/// instead of being labelled a caregiver of it.
enum _InvitePreset {
  coParent,
  caregiver,
  viewer,
  subject;

  GuardianRole get role => switch (this) {
        coParent => GuardianRole.coParent,
        caregiver => GuardianRole.caregiver,
        viewer => GuardianRole.viewer,
        // The issue's recommended default: a minor must not be able to
        // remove her parent from the profile before a transfer — a
        // caregiver cannot manage guardians, edit the profile, or delete
        // it. The server re-checks the pairing ("a subject invitation
        // must grant the caregiver role").
        subject => GuardianRole.caregiver,
      };

  bool get stampsSubject => this == subject;
}

class _InviteGuardianDialogState extends State<InviteGuardianDialog> {
  /// Issue #802: the subject preset is the default when it is offered, so
  /// "her own profile" is the two-tap path from Manage guardians — the
  /// helper roles stay one explicit selection away.
  late _InvitePreset _selectedPreset = widget.subjectInviteAvailable
      ? _InvitePreset.subject
      : _InvitePreset.coParent;
  final TextEditingController _labelController = TextEditingController();

  bool _loading = false;
  GeneratedInvite? _generatedInvite;
  String? _error;

  /// #558: the "copied" confirmation used to go through
  /// `ScaffoldMessenger.of(context).showSnackBar` -- resolved against the
  /// *underlying screen's* Scaffold (this dialog itself hosts none), which
  /// paints in an OverlayEntry inserted *before* this dialog's own barrier,
  /// so the SnackBar rendered behind the scrim, invisible. Rendering the
  /// confirmation inside the dialog's own content instead needs no such
  /// z-order reasoning.
  bool _justCopied = false;

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
        role: _selectedPreset.role,
        recipientLabel: _labelController.text.trim().isEmpty
            ? null
            : _labelController.text.trim(),
        subject: _selectedPreset.stampsSubject,
      );
      if (mounted) {
        setState(() {
          _generatedInvite = invite;
          _loading = false;
        });
      }
    } on SharingFailure catch (failure) {
      // Issue #535 (d): distinct failure types (unauthorized vs. network,
      // etc.) get their own accurate copy via sharingFailureCopy, rather
      // than collapsing every SharingFailure into the generic connection
      // message below — matching AcceptInviteSheet's own catch clause.
      if (mounted) {
        setState(() {
          _error = sharingFailureCopy(AppLocalizations.of(context), failure);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context)
              .sharingInviteGuardianGenerateFailed;
          _loading = false;
        });
      }
    }
  }

  void _copyLink() {
    if (_generatedInvite == null) return;
    unawaited(
      Clipboard.setData(
        ClipboardData(text: _generatedInvite!.inviteUri.toString()),
      ),
    );
    setState(() => _justCopied = true);
  }

  // Issue #535 (c): share_plus 13.x deprecated the old static
  // `Share.share(String)` in favor of `SharePlus.instance.share(ShareParams
  // (...))` (see TransferOwnershipScreen._shareLink, the sibling pattern
  // this mirrors). Plain text share of the bare link, same as Copy Link.
  void _shareLink() {
    if (_generatedInvite == null) return;
    unawaited(
      SharePlus.instance.share(
        ShareParams(text: _generatedInvite!.inviteUri.toString()),
      ),
    );
  }

  /// The generated state's share line, split out of [build] for the CRAP
  /// gate's per-method complexity cap (Issue #802): the subject preset
  /// promises "her own profile", a helper invite addresses the guardian.
  Widget _shareLine(BuildContext context) => Text(
        key: ValueKey(_selectedPreset.stampsSubject
            ? 'invite-created-share-subject'
            : 'invite-created-share-guardian'),
        _selectedPreset.stampsSubject
            ? AppLocalizations.of(context)
                  .inviteCreatedShareSubject(widget.profileName)
            : AppLocalizations.of(context)
                  .inviteCreatedShareGuardian(widget.profileName),
      );

  /// The preset picker (the "Role:" dropdown plus the subject preset's
  /// consequence line), split out of [build] for the same CRAP-cap reason
  /// as [_shareLine].
  Widget _presetPicker(ThemeData theme) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context).sharingInviteGuardianRoleLabel),
          const SizedBox(height: 4),
          DropdownButton<_InvitePreset>(
            key: const ValueKey('invite-preset-dropdown'),
            value: _selectedPreset,
            isExpanded: true,
            onChanged: _loading
                ? null
                : (preset) {
                    if (preset != null) {
                      setState(() => _selectedPreset = preset);
                    }
                  },
            items: [
              DropdownMenuItem(
                value: _InvitePreset.coParent,
                child: Text(
                  AppLocalizations.of(context)
                      .sharingInviteGuardianPresetCoParent,
                ),
              ),
              DropdownMenuItem(
                value: _InvitePreset.caregiver,
                child: Text(
                  AppLocalizations.of(context)
                      .sharingInviteGuardianPresetCaregiver,
                ),
              ),
              DropdownMenuItem(
                value: _InvitePreset.viewer,
                child: Text(
                  AppLocalizations.of(context).sharingInviteGuardianPresetViewer,
                ),
              ),
              // Issue #802: offered (and preselected) only
              // for a profile that is the invitee's own.
              if (widget.subjectInviteAvailable)
                DropdownMenuItem(
                  key: const ValueKey('invite-preset-subject'),
                  value: _InvitePreset.subject,
                  child: Text(
                    AppLocalizations.of(context)
                        .inviteSubjectOption(widget.profileName),
                  ),
                ),
            ],
          ),
          if (_selectedPreset == _InvitePreset.subject)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                key: const ValueKey('invite-preset-subject-detail'),
                AppLocalizations.of(context)
                    .inviteSubjectOptionDetail(widget.profileName),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      );

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
              Text(
                AppLocalizations.of(context).sharingInviteGuardianCreatedTitle,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _shareLine(context),
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
                        AppLocalizations.of(context)
                            .sharingInviteGuardianExpiry,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      if (_justCopied) ...[
                        const SizedBox(height: 8),
                        Semantics(
                          liveRegion: true,
                          child: Row(
                            key: const ValueKey('invite-copied-confirmation'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle,
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                AppLocalizations.of(context)
                                    .sharingInviteGuardianCopied,
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
              ),
              const SizedBox(height: 16),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                overflowSpacing: 8,
                children: [
                  TextButton(
                    key: const ValueKey('invite-done'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      AppLocalizations.of(context).sharingInviteGuardianDone,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _copyLink,
                    icon: const Icon(Icons.copy, size: 16),
                    label: Text(
                      AppLocalizations.of(context).sharingInviteGuardianCopyLink,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _shareLink,
                    icon: const Icon(Icons.share, size: 16),
                    label: Text(
                      AppLocalizations.of(context).sharingInviteGuardianShare,
                    ),
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
              AppLocalizations.of(context)
                  .sharingInviteGuardianTitle(widget.profileName),
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
                      InlineError(
                        message: _error!,
                        onRetry: _loading ? null : _createInvite,
                      ),
                      const SizedBox(height: 8),
                    ],
                    // #557: MergeSemantics folds "Role:" into the dropdown's own
                    // announcement, so a screen reader hears "Role, <value>"
                    // instead of just the bare value. The preset picker lives
                    // in its own method (Issue #802: the CRAP gate's
                    // per-method complexity cap on build).
                    MergeSemantics(
                      child: _presetPicker(theme),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _labelController,
                      enabled: !_loading,
                      // #165: the form's only text field — "done" is the
                      // Create Link action.
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (!_loading) unawaited(_createInvite());
                      },
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context)
                            .sharingInviteGuardianNicknameLabel,
                        hintText: AppLocalizations.of(context)
                            .sharingInviteGuardianNicknameHint,
                      ),
                    ),
                    // Issue #139: contextual entry point to the invitations card.
                    HelpCardLink(
                      cardId: 'invitations',
                      label: AppLocalizations.of(context)
                          .sharingInviteGuardianHelpLabel,
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
                  child: Text(
                    AppLocalizations.of(context).sharingInviteGuardianCancel,
                  ),
                ),
                FilledButton(
                  onPressed: _loading ? null : _createInvite,
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          AppLocalizations.of(context)
                              .sharingInviteGuardianCreateLink,
                        ),
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
