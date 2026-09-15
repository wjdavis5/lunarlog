/// AAL2 step-up gate (issue #268 D-6): the code prompt shown before a
/// destructive account action — deletion, ownership-transfer arming,
/// "sign out everywhere" — whenever the account has a verified TOTP factor
/// and the current session has not completed an MFA challenge.
///
/// [ensureAal2] is the single entry point every one of those three call
/// sites uses; it degrades to a no-op (returns true immediately) for an
/// account with no enrolled factor, so those paths behave exactly as they
/// did before this issue (the unaffected-path acceptance criterion).
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/l10n/auth_failure_copy.dart';
import 'package:lunarlog/ui/components/inline_error.dart';

/// Resolves [AuthController.requiresMfaStepUp] and, only when it is true,
/// shows the step-up dialog. Returns true when the action may proceed:
/// either no step-up was needed, or the operator entered a correct TOTP
/// code. False for a cancelled or failed step-up, or when `context` has
/// been unmounted by the time the check completes.
Future<bool> ensureAal2(BuildContext context, AuthController auth) async {
  final needsStepUp = await auth.requiresMfaStepUp();
  if (!needsStepUp) return true;
  if (!context.mounted) return false;
  final factors = await auth.listMfaFactors();
  MfaFactor? verified;
  for (final factor in factors) {
    if (factor.status == MfaFactorStatus.verified) {
      verified = factor;
      break;
    }
  }
  // requiresMfaStepUp() just confirmed a verified factor exists; a null
  // here means it was removed in the moment between that check and this
  // one (another device, or a concurrent removal) — fail closed rather
  // than proceed as if no MFA were enrolled.
  if (verified == null || !context.mounted) return false;
  final confirmed = await showDialog<bool>(
    context: context,
    routeSettings: const RouteSettings(name: kRouteMfaStepUpDialog),
    builder: (_) => _MfaStepUpDialog(auth: auth, factorId: verified!.id),
  );
  return confirmed ?? false;
}

class _MfaStepUpDialog extends StatefulWidget {
  const _MfaStepUpDialog({required this.auth, required this.factorId});

  final AuthController auth;
  final String factorId;

  @override
  State<_MfaStepUpDialog> createState() => _MfaStepUpDialogState();
}

class _MfaStepUpDialogState extends State<_MfaStepUpDialog> {
  final TextEditingController _codeController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeController.text;
    if (code.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.verifyTotpCode(factorId: widget.factorId, code: code);
      if (mounted) Navigator.of(context).pop(true);
    } on AuthFailure catch (failure) {
      if (mounted) {
        setState(() =>
            _error = authFailureCopy(AppLocalizations.of(context), failure));
      }
    } catch (error) {
      debugPrint('lunarlog mfa: step-up failed (${error.runtimeType})');
      if (mounted) {
        setState(() => _error = authFailureCopy(
            AppLocalizations.of(context), const AuthFailure.unknown()));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.mfaStepUpTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.mfaStepUpBody),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('mfa-step-up-code-field'),
            controller: _codeController,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(hintText: l10n.mfaCodeHint),
            onSubmitted: (_) => _verify(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            InlineError(
                key: const ValueKey('mfa-step-up-error'), message: _error!),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('mfa-step-up-confirm'),
          onPressed: _busy ? null : _verify,
          child: Text(l10n.mfaStepUpConfirmButton),
        ),
      ],
    );
  }
}
