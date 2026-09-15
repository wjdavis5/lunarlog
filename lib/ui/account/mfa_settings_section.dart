/// "Two-factor authentication" tile group in the Account section (issue
/// #268 U2): offers enrolment when the account has no factor, or shows the
/// enrolled factor with a "Remove" action. Self-contained (owns its own
/// factor list + reload), so `account_section.dart`'s diff for this
/// feature is a single tile-group insertion.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/mfa_enroll_screen.dart';
import 'package:lunarlog/ui/components/inline_error.dart';

class MfaSettingsSection extends StatefulWidget {
  const MfaSettingsSection({super.key, required this.auth});

  final AuthController auth;

  @override
  State<MfaSettingsSection> createState() => _MfaSettingsSectionState();
}

class _MfaSettingsSectionState extends State<MfaSettingsSection> {
  late Future<List<MfaFactor>> _factors;
  bool _removing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _factors = widget.auth.listMfaFactors();
  }

  void _reload() {
    final future = widget.auth.listMfaFactors();
    // A block body, not `=> _factors = future`: an arrow body's value is
    // the assignment's own value (the Future itself), and Flutter's
    // setState explicitly rejects a callback that returns a Future,
    // however that Future was obtained.
    setState(() {
      _factors = future;
    });
  }

  Future<void> _enroll() async {
    final enrolled = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        settings: const RouteSettings(name: kRouteMfaEnrollScreen),
        builder: (_) => MfaEnrollScreen(auth: widget.auth),
      ),
    );
    if (enrolled == true && mounted) _reload();
  }

  Future<void> _remove(String factorId) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: kRouteMfaRemoveFactorDialog),
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.mfaRemoveFactorTitle),
        content: Text(l10n.mfaRemoveFactorBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('mfa-remove-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.mfaRemoveFactorConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _removing = true;
      _error = null;
    });
    try {
      await widget.auth.unenrollMfaFactor(factorId);
      if (mounted) _reload();
    } catch (error) {
      debugPrint('lunarlog mfa: unenroll failed (${error.runtimeType})');
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).mfaErrorGeneric);
      }
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<List<MfaFactor>>(
      future: _factors,
      builder: (context, snapshot) {
        final factors = snapshot.data;
        if (factors == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(l10n.mfaSectionTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ..._tiles(l10n, factors),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: InlineError(
                  key: const ValueKey('mfa-remove-error'),
                  message: _error!,
                ),
              ),
          ],
        );
      },
    );
  }

  List<Widget> _tiles(AppLocalizations l10n, List<MfaFactor> factors) {
    if (factors.isEmpty) {
      return [
        ListTile(
          key: const ValueKey('mfa-enroll-tile'),
          leading: const Icon(Icons.verified_user_outlined),
          title: Text(l10n.mfaEnrollTileTitle),
          subtitle: Text(l10n.mfaEnrollTileSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: _enroll,
        ),
      ];
    }
    return [
      for (final factor in factors)
        ListTile(
          key: ValueKey('mfa-factor-tile-${factor.id}'),
          leading: const Icon(Icons.verified_user_outlined),
          title: Text(l10n.mfaFactorTileTitle),
          subtitle: Text(factor.status == MfaFactorStatus.verified
              ? l10n.mfaFactorTileSubtitleVerified
              : l10n.mfaFactorTileSubtitlePending),
          trailing: _removing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  key: ValueKey('mfa-remove-${factor.id}'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _remove(factor.id),
                ),
        ),
    ];
  }
}
