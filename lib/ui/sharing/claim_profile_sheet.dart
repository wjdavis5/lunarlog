/// Bottom sheet presented when claiming a child-profile ownership transfer
/// (Issue #4, U10; R11, R27, R28).
///
/// Mirrors `AcceptInviteSheet` closely: a loading state, an optional-field
/// form, and [transferFailureCopy] rendered inline on error so the sheet
/// stays open and retryable. Success pops immediately with the
/// [ClaimedProfileResult] (matching `AcceptInviteSheet`'s shape exactly)
/// rather than showing a separate inline confirmation state — the caller
/// (or a snackbar it drives from [onClaimed]) is the simpler, more
/// consistent place for "here's what changed" copy.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/l10n/transfer_failure_copy.dart';

import '../../domain/sharing/ownership_transfer_service.dart';
import '../components/inline_error.dart';

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

  /// #165: the sheet's two-field focus chain — "next" on the child-name
  /// field advances to the parent-label field.
  final _childNameFocus = FocusNode();
  final _parentNameFocus = FocusNode();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _childNameController.dispose();
    _parentNameController.dispose();
    _childNameFocus.dispose();
    _parentNameFocus.dispose();
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
          _error = transferFailureCopy(AppLocalizations.of(context), failure);
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

  /// Issue #642, LLA-012: the title row's [Text] is wrapped in [Expanded]
  /// (was a bare [Row] child), mirroring `AcceptInviteSheet`'s own fix, so
  /// a long localization or 200% text scaling wraps to a second line
  /// instead of overflowing horizontally past the leading icon.
  Widget _titleRow(ThemeData theme) => Row(
        children: [
          Icon(Icons.swap_horiz, size: 28, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Become the Owner', style: theme.textTheme.titleLarge),
          ),
        ],
      );

  /// Issue #642, LLA-012: [Wrap], not a fixed [Row] — mirrors
  /// `AcceptInviteSheet._actionsRow`'s own fix: at 320×568 with 200% text
  /// scaling, "Decline" plus "Become Owner" (plus the loading spinner it
  /// turns into) can exceed the sheet's width; `Wrap` flows the second
  /// action to its own line instead of overflowing horizontally.
  Widget _actionsRow() => Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton(
            key: const ValueKey('claim-profile-decline'),
            onPressed: _loading ? null : () => Navigator.of(context).pop(),
            child: const Text('Decline'),
          ),
          FilledButton(
            key: const ValueKey('claim-profile-become-owner'),
            onPressed: _loading ? null : _claim,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    AppLocalizations.of(context)
                        .claimProfileBecomeGuardianAction,
                  ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      // Issue #642, LLA-012: bounded via `ConstrainedBox` +
      // `SingleChildScrollView` (was an unbounded `Column`), mirroring
      // `AcceptInviteSheet`'s own fix — two optional-name fields, an
      // inline error, and the keyboard inset together could exceed the
      // available height on a small screen or with large text scaling.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SingleChildScrollView(
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
                _titleRow(theme),
                const SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context).claimProfileBody,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _childNameController,
                  focusNode: _childNameFocus,
                  enabled: !_loading,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _parentNameFocus.requestFocus(),
                  decoration: const InputDecoration(
                    labelText: "Child's display name (optional)",
                    hintText: 'Shows on the profile',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _parentNameController,
                  focusNode: _parentNameFocus,
                  enabled: !_loading,
                  // #165: the form's last field — "done" is the Become
                  // Owner action.
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (!_loading) unawaited(_claim());
                  },
                  decoration: const InputDecoration(
                    labelText: 'Label for the parent (optional)',
                    hintText: 'Shows when they log entries',
                  ),
                ),
                if (_error != null)
                  // No onRetry: the primary action button right below is
                  // the retry affordance. No leading SizedBox either --
                  // InlineError already carries its own vertical padding,
                  // and this sheet's tight modal height has no room for
                  // both plus a TextButton row.
                  InlineError(message: _error!),
                const SizedBox(height: 20),
                _actionsRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
