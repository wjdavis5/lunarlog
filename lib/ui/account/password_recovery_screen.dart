/// "Set a new password" (U6; R2, F4, AE8). Rendered by the home gate while
/// the auth service holds a recovery latch *and* the device gate is
/// unlocked (KTD8). Saving calls `updatePassword` and consumes the latch;
/// "Not now" consumes it without a change (the recovery session stays
/// usable).
///
/// Issue #165 (form accessibility): the new-password and confirm fields
/// sit in one [AutofillGroup] (`newPassword` on the new-password field, so
/// password managers can offer to fill or generate), "next" on the
/// new-password field advances to the confirm field, "done" on the confirm
/// field saves, and each obscured field carries a local-only reveal
/// toggle — the toggles flip nothing but their own field's `obscureText`.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/components/inline_error.dart';
import 'package:lunarlog/ui/l10n/auth_failure_copy.dart';
import 'package:provider/provider.dart';

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key});

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  /// #165: the explicit focus chain — "next" on the new-password field
  /// advances to the confirm field.
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  /// #165: each obscured field's own reveal-toggle state. Local-only by
  /// design: flipping one changes that field's `obscureText`, nothing else.
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_password.text.length < kMinPasswordLength) {
      setState(
        () => _error =
            'Use at least $kMinPasswordLength characters for the password.',
      );
      return;
    }
    // #165: the confirm field's match check — same imperative-error shape
    // as the length check above it.
    if (_confirm.text != _password.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthController>();
    try {
      await auth.updatePassword(_password.text);
      auth.consumeRecovery();
    } on AuthFailure catch (failure) {
      if (mounted) {
        setState(
          () => _error = authFailureCopy(AppLocalizations.of(context), failure),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set a new password'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'You opened a password reset link. Choose a new password for '
            'your account.',
          ),
          const SizedBox(height: 16),
          // #165: one AutofillGroup over the password pair so password
          // managers see a single saveable form.
          AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('recovery-new-password'),
                  controller: _password,
                  focusNode: _passwordFocus,
                  enabled: !_busy,
                  obscureText: _obscureNew,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _confirmFocus.requestFocus(),
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: 'New password',
                    helperText: 'At least $kMinPasswordLength characters',
                    suffixIcon: IconButton(
                      key: const ValueKey('recovery-new-password-reveal'),
                      onPressed: () =>
                          setState(() => _obscureNew = !_obscureNew),
                      tooltip: _obscureNew ? 'Show password' : 'Hide password',
                      icon: Icon(
                        _obscureNew
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('recovery-confirm-password'),
                  controller: _confirm,
                  focusNode: _confirmFocus,
                  enabled: !_busy,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    labelText: 'Confirm password',
                    suffixIcon: IconButton(
                      key: const ValueKey('recovery-confirm-password-reveal'),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                      tooltip:
                          _obscureConfirm ? 'Show password' : 'Hide password',
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            // Matches `sign_in_screen.dart`'s own 'auth-error' slot: no
            // onRetry (the Save password button right below is the retry
            // affordance).
            InlineError(key: const ValueKey('auth-error'), message: _error!),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('recovery-save'),
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    key: ValueKey('auth-pending'),
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save password'),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('recovery-skip'),
            onPressed: _busy
                ? null
                : () => context.read<AuthController>().consumeRecovery(),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}
