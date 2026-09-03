/// "Set a new password" (U6; R2, F4, AE8). Rendered by the home gate while
/// the auth service holds a recovery latch *and* the device gate is
/// unlocked (KTD8). Saving calls `updatePassword` and consumes the latch;
/// "Not now" consumes it without a change (the recovery session stays
/// usable).
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/sign_in_screen.dart'
    show authFailureCopy, kMinPasswordLength;
import 'package:provider/provider.dart';

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key});

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_password.text.length < kMinPasswordLength) {
      setState(() => _error =
          'Use at least $kMinPasswordLength characters for the password.');
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
      if (mounted) setState(() => _error = authFailureCopy(failure));
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
          TextField(
            key: const ValueKey('recovery-new-password'),
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'New password',
              helperText: 'At least $kMinPasswordLength characters',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              key: const ValueKey('auth-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
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
