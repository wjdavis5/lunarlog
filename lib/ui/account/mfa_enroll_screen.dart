/// TOTP enrolment screen (issue #268 U1/U2): starts enrolment on open,
/// shows the QR code and manual-entry secret, and confirms with a
/// verification code from the operator's authenticator app.
///
/// Pushed from the Account section's "Set up two-factor authentication"
/// tile; pops `true` once enrolment completes, `null`/`false` otherwise.
///
/// Known gap: no in-app QR code. gotrue's enrolment response
/// ([TotpEnrollmentOffer.qrCodeDataUri]) encodes the QR only as an
/// `image/svg+xml` data URI — `Image.network`/`Image.memory` cannot
/// rasterize SVG, and `flutter_svg` is not a project dependency. Manual
/// entry of [TotpEnrollmentOffer.secret] is the only path today; every
/// authenticator app supports it, so enrolment is fully functional, just
/// one tap slower than scanning would be. Add `flutter_svg` (or an
/// SVG-to-PNG conversion) as a follow-up if that friction matters in
/// practice.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/l10n/auth_failure_copy.dart';
import 'package:lunarlog/ui/components/inline_error.dart';

class MfaEnrollScreen extends StatefulWidget {
  const MfaEnrollScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<MfaEnrollScreen> createState() => _MfaEnrollScreenState();
}

class _MfaEnrollScreenState extends State<MfaEnrollScreen> {
  late final Future<TotpEnrollmentOffer> _offer;
  final TextEditingController _codeController = TextEditingController();
  bool _verifying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _offer = widget.auth.enrollTotp();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify(String factorId) async {
    final code = _codeController.text;
    if (code.isEmpty || _verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await widget.auth.verifyTotpCode(factorId: factorId, code: code);
      if (mounted) Navigator.of(context).pop(true);
    } on AuthFailure catch (failure) {
      if (mounted) {
        setState(() =>
            _error = authFailureCopy(AppLocalizations.of(context), failure));
      }
    } catch (error) {
      debugPrint('lunarlog mfa: enrolment verify failed (${error.runtimeType})');
      if (mounted) {
        setState(() => _error = authFailureCopy(
            AppLocalizations.of(context), const AuthFailure.unknown()));
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.mfaEnrollScreenTitle)),
      body: FutureBuilder<TotpEnrollmentOffer>(
        future: _offer,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: InlineError(
                  key: const ValueKey('mfa-enroll-start-error'),
                  message: l10n.mfaErrorGeneric,
                ),
              ),
            );
          }
          final offer = snapshot.data;
          if (offer == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return _enrollmentForm(l10n, offer);
        },
      ),
    );
  }

  Widget _enrollmentForm(AppLocalizations l10n, TotpEnrollmentOffer offer) =>
      Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text(l10n.mfaEnrollInstructions),
            const SizedBox(height: 16),
            Text(l10n.mfaEnrollSecretLabel,
                style: Theme.of(context).textTheme.labelMedium),
            SelectableText(
              offer.secret,
              key: const ValueKey('mfa-enroll-secret'),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 24),
            Text(l10n.mfaEnrollCodeLabel),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('mfa-enroll-code-field'),
              controller: _codeController,
              enabled: !_verifying,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(hintText: l10n.mfaCodeHint),
              onSubmitted: (_) => _verify(offer.factorId),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              InlineError(
                  key: const ValueKey('mfa-enroll-verify-error'),
                  message: _error!),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('mfa-enroll-confirm'),
              onPressed: _verifying ? null : () => _verify(offer.factorId),
              child: _verifying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.mfaEnrollConfirmButton),
            ),
          ],
        ),
      );
}
