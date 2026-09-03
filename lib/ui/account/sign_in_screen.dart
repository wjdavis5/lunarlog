/// Sign-in / create-account screen (U6; R1, R2, R3). Email + password,
/// a mode toggle, forgot-password, and native Apple Sign-In on iOS only
/// (KTD9, injectable). Every action disables its button and shows the
/// `auth-pending` spinner while the call is in flight (the lock screen's
/// pattern); failures render generic copy under `auth-error` and never
/// echo the email or provider text (R18).
///
/// Used two ways: pushed from Settings (pops on success) and embedded as
/// the first-run account step ([embedded], with "Not now").
///
/// [authFailureCopy] is the single, exhaustive copy table for every
/// [AuthFailure], including the provider, link, code, identity, and
/// closed-sign-up kinds (#2 U2; KTD4, R14).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:provider/provider.dart';

/// Client-side minimum for a new password (the project's hosted rule).
const int kMinPasswordLength = 12;

/// Generic, email-free copy per failure kind.
String authFailureCopy(AuthFailure failure) => switch (failure) {
      AuthWrongPasswordFailure() =>
        'That email and password combination was not accepted.',
      AuthWeakPasswordFailure() =>
        'Choose a stronger password of at least $kMinPasswordLength characters.',
      AuthNetworkFailure() =>
        'Could not reach the server. Check your connection and try again.',
      AuthUnknownFailure() => 'Something went wrong. Please try again.',
      AuthProviderUnavailableFailure() =>
        "Google Sign-In isn't available on this device. Use email instead.",
      AuthExpiredLinkFailure() =>
        'That sign-in link is no longer valid. Request a new one.',
      AuthInvalidCodeFailure() =>
        'That code was not accepted. Check it or request a new email.',
      AuthIdentityTakenFailure() =>
        'That sign-in method already belongs to another account.',
      AuthSignUpClosedFailure() =>
        'New accounts for this app are set up by the account owner.',
    };

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    this.showApple,
    this.embedded = false,
    this.onSignedIn,
    this.onNotNow,
  });

  /// Whether the Apple button renders; null means "iOS only" (KTD9).
  final bool? showApple;

  /// First-run account step: no back button, a "Not now" action, and
  /// [onSignedIn] instead of popping.
  final bool embedded;

  final VoidCallback? onSignedIn;
  final VoidCallback? onNotNow;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _createMode = false;
  bool _busy = false;
  String? _error;
  String? _info;

  bool get _showApple =>
      widget.showApple ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = authFailureCopy(failure));
    } catch (error) {
      debugPrint('lunarlog auth: action failed (${error.runtimeType})');
      if (mounted) {
        setState(() => _error = authFailureCopy(const AuthFailure.unknown()));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _signedIn() {
    if (!mounted) return;
    widget.onSignedIn?.call();
    if (!widget.embedded) Navigator.of(context).maybePop();
  }

  Future<void> _signIn() => _run(() async {
        final auth = context.read<AuthController>();
        await auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
        _signedIn();
      });

  Future<void> _createAccount() async {
    if (_password.text.length < kMinPasswordLength) {
      setState(() {
        _error = 'Use at least $kMinPasswordLength characters for the password.';
        _info = null;
      });
      return;
    }
    await _run(() async {
      final auth = context.read<AuthController>();
      final settings = context.read<SettingsStore>();
      final email = _email.text.trim();
      final result = await auth.signUp(email: email, password: _password.text);
      switch (result) {
        case SignUpSession():
          _signedIn();
        case SignUpAwaitingConfirmation(email: final pending):
          await settings.set(SettingsKeys.awaitingConfirmationEmail, pending);
          if (mounted) {
            setState(() => _info =
                'Check your email to confirm the account, then open the '
                'link on this device.');
          }
      }
    });
  }

  Future<void> _forgotPassword() => _run(() async {
        final auth = context.read<AuthController>();
        await auth.sendPasswordReset(_email.text.trim());
        if (mounted) {
          setState(() => _info =
              'If an account exists for that email, a reset link is on its '
              'way. Open it on this device.');
        }
      });

  Future<void> _apple() => _run(() async {
        final auth = context.read<AuthController>();
        final result = await auth.signInWithAppleNative();
        switch (result) {
          case AppleSignInSession():
            _signedIn();
          case AppleSignInCancelled():
            // Dismissed: back to the screen, no error (KTD9).
            break;
        }
      });

  @override
  Widget build(BuildContext context) {
    final title = _createMode ? 'Create an account' : 'Sign in';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: !widget.embedded,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.embedded)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'An account keeps a copy of this device\'s data so it can be '
                'restored on another device. You can also keep everything on '
                'this device only.',
              ),
            ),
          TextField(
            key: const ValueKey('auth-email'),
            controller: _email,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('auth-password'),
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Password',
              helperText: _createMode
                  ? 'At least $kMinPasswordLength characters'
                  : null,
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
          if (_info != null) ...[
            const SizedBox(height: 12),
            Text(_info!, key: const ValueKey('auth-info')),
          ],
          const SizedBox(height: 16),
          if (_busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  key: ValueKey('auth-pending'),
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (_createMode)
            FilledButton(
              key: const ValueKey('auth-create-account'),
              onPressed: _busy ? null : _createAccount,
              child: const Text('Create account'),
            )
          else
            FilledButton(
              key: const ValueKey('auth-sign-in'),
              onPressed: _busy ? null : _signIn,
              child: const Text('Sign in'),
            ),
          if (_showApple) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('auth-apple'),
              onPressed: _busy ? null : _apple,
              icon: const Icon(Icons.apple),
              label: const Text('Sign in with Apple'),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('auth-mode-toggle'),
            onPressed: _busy
                ? null
                : () => setState(() {
                      _createMode = !_createMode;
                      _error = null;
                      _info = null;
                    }),
            child: Text(_createMode
                ? 'I already have an account'
                : 'Create an account instead'),
          ),
          if (!_createMode)
            TextButton(
              key: const ValueKey('auth-forgot-password'),
              onPressed: _busy ? null : _forgotPassword,
              child: const Text('Forgot password'),
            ),
          if (widget.embedded) ...[
            const Divider(height: 32),
            TextButton(
              key: const ValueKey('first-run-not-now'),
              onPressed: _busy ? null : widget.onNotNow,
              child: const Text('Not now'),
            ),
          ],
        ],
      ),
    );
  }
}
