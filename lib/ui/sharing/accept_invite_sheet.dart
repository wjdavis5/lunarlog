/// Bottom sheet presented when redeeming a guardian invitation link (U8; R7, R8).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:lunarlog/ui/l10n/guardian_role_copy.dart';
import 'package:lunarlog/ui/l10n/sharing_failure_copy.dart';

import '../../domain/sharing/sharing_service.dart';
import '../components/inline_error.dart';

/// Issue #594: the preview fetched in [_AcceptInviteSheetState.initState]
/// resolves to exactly one of these - `ready` carries the fetched
/// [InvitePreview], the other three carry nothing and fall back to the
/// pre-#594 neutral copy (see [_AcceptInviteSheetState._buildIntro]).
enum _PreviewState { loading, ready, unavailable, error }

class AcceptInviteSheet extends StatefulWidget {
  const AcceptInviteSheet({
    super.key,
    required this.rawToken,
    required this.sharingService,
    this.initialProfileId,
    this.onAccepted,
    this.breadcrumbLog,
  });

  final String rawToken;
  final SharingService sharingService;
  final String? initialProfileId;
  final void Function(AcceptedInviteResult result)? onAccepted;
  final BreadcrumbLog? breadcrumbLog;

  @override
  State<AcceptInviteSheet> createState() => _AcceptInviteSheetState();
}

class _AcceptInviteSheetState extends State<AcceptInviteSheet> {
  final TextEditingController _nameController = TextEditingController();
  bool _loading = false;
  String? _error;

  /// Issue #594: the accept sheet isn't blind consent - a pre-accept
  /// preview (profile display name + offered role) loads on init and is
  /// shown above the neutral copy once it resolves. Never blocks or gates
  /// [_accept]: a loading/error/unavailable preview still lets the
  /// operator tap Accept, which then surfaces `accept_guardian_invitation`'s
  /// own, more specific error if the token really isn't redeemable -
  /// this preview is a courtesy, not a second source of truth for whether
  /// the token works.
  _PreviewState _previewState = _PreviewState.loading;
  InvitePreview? _preview;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreview());
  }

  Future<void> _loadPreview() async {
    try {
      final preview =
          await widget.sharingService.previewInvite(rawToken: widget.rawToken);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _previewState =
            preview == null ? _PreviewState.unavailable : _PreviewState.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _previewState = _PreviewState.error);
    }
  }

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
          _error = sharingFailureCopy(AppLocalizations.of(context), failure);
        });
      }
    } catch (error) {
      (widget.breadcrumbLog ?? defaultBreadcrumbLog)
          .record('sharing', error.runtimeType.toString());
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'An unexpected error occurred.';
        });
      }
    }
  }

  /// Issue #535 (a) / #594: the pre-#594 neutral paragraph, still the
  /// fallback for [_PreviewState.loading]/[error]/[unavailable] - the
  /// previous wording hardcoded "child", which was wrong whenever two
  /// adults share one adult's profile, so this stays neutral rather than
  /// assuming a minor's profile. [_PreviewState.ready] replaces it
  /// entirely with the fetched name and role instead of layering on top.
  Widget _buildIntro(BuildContext context, TextTheme textTheme) {
    final preview = _preview;
    if (_previewState == _PreviewState.ready && preview != null) {
      final l10n = AppLocalizations.of(context);
      final roleLabel = guardianRoleLabel(l10n, preview.role);
      return Text(
        key: const ValueKey('accept-invite-preview-ready'),
        "You've been invited to join ${preview.profileDisplayName}'s "
        'shared profile as $roleLabel. Accepting will sync its cycle '
        'calendar and health logs to this device.',
        style: textTheme.bodyMedium,
      );
    }
    return const Text(
      "You've been invited to a shared profile in LunarLog. "
      'Accepting will sync its cycle calendar and health logs to '
      'this device.',
    );
  }

  /// The small status line above [_buildIntro] for the three non-ready
  /// preview states - absent once the preview is ready (the personalized
  /// intro speaks for itself) or never attempted.
  Widget? _buildPreviewStatus(TextTheme textTheme) => switch (_previewState) {
        _PreviewState.loading => Row(
            key: const ValueKey('accept-invite-preview-loading'),
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text('Loading invite details…', style: textTheme.bodySmall),
            ],
          ),
        _PreviewState.error => Text(
            key: const ValueKey('accept-invite-preview-error'),
            "Couldn't load invite details, but you can still continue.",
            style: textTheme.bodySmall,
          ),
        _PreviewState.unavailable => Text(
            key: const ValueKey('accept-invite-preview-unavailable'),
            'This invite link may have expired or already been used.',
            style: textTheme.bodySmall,
          ),
        _PreviewState.ready => null,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewStatus = _buildPreviewStatus(theme.textTheme);

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
            if (previewStatus != null) ...[
              previewStatus,
              const SizedBox(height: 8),
            ],
            _buildIntro(context, theme.textTheme),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              enabled: !_loading,
              decoration: const InputDecoration(
                labelText: 'Your display name (e.g. Dad, Mom, Grandma)',
                hintText: 'Shows when you log entries',
              ),
            ),
            if (_error != null)
              // No onRetry: the Join button right below is the retry
              // affordance. No leading SizedBox either -- InlineError
              // already carries its own vertical padding, and this
              // sheet's tight modal height has no room for both plus a
              // TextButton row.
              InlineError(message: _error!),
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
