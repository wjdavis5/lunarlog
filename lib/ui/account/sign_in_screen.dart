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
/// A session that arrives through a link while this screen is showing
/// completes it the same way a button does (#2 U3; KTD4, R8): the state
/// listens to the [AuthController] and funnels every completion — button
/// actions and the listener — through one `_signedIn()` guarded by a
/// `_completed` flag, because gotrue emits `signedIn` before
/// `signInWithPassword` returns. Only a signed-out → signed-in transition
/// counts; a screen opened while already signed in does not auto-complete.
///
/// [authFailureCopy] is the single, exhaustive copy table for every
/// [AuthFailure], including the provider, identity, and closed-sign-up kinds
/// (#2 U2; KTD4, R14).
///
/// Provider buttons (#2 U4; KTD6, KTD8): the providers render above the
/// email form — Apple (the package's HIG widget, iOS only) first, then
/// Google (the branded widget, only when [AppConfig.hasGoogle] or
/// [showGoogle] says so) — and a dismissed picker is not a failure.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lunarlog/app_lifecycle.dart' show GateController;
import 'package:lunarlog/config.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/google_sign_in_button.dart';
import 'package:provider/provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart'
    show SignInWithAppleButton, SignInWithAppleButtonStyle;

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
    this.showGoogle,
    this.embedded = false,
    this.onSignedIn,
    this.onNotNow,
  });

  /// Whether the Apple button renders; null means "iOS only" (KTD9).
  final bool? showApple;

  /// Whether the Google button renders; null means [AppConfig.hasGoogle]
  /// (#2 U4; R4).
  final bool? showGoogle;

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

  /// The controller this state listens to for link-delivered sessions
  /// (#2 U3; KTD4).
  AuthController? _auth;

  /// Last observed `signedIn`, so only a transition into it completes.
  bool _wasSignedIn = false;

  /// Set by the first completion; every later path returns early.
  bool _completed = false;

  bool get _showApple =>
      widget.showApple ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  bool get _showGoogle => widget.showGoogle ?? AppConfig.hasGoogle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthController>();
    if (identical(auth, _auth)) return;
    _auth?.removeListener(_onAuthChanged);
    _auth = auth..addListener(_onAuthChanged);
    _wasSignedIn = auth.signedIn;
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    _auth = null;
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// A session arrived (link, code, or a button action's early event):
  /// complete on the signed-out → signed-in edge only (#2 U3; R8).
  void _onAuthChanged() {
    final signedIn = _auth?.signedIn ?? false;
    final arrived = signedIn && !_wasSignedIn;
    _wasSignedIn = signedIn;
    if (arrived) _signedIn();
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

  /// The one completion path (KTD4): button actions and the controller
  /// listener both land here, and only the first arrival acts.
  void _signedIn() {
    if (!mounted || _completed) return;
    _completed = true;
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

  /// Runs [action] inside the gate's system-UI window when a gate is in
  /// scope (#65 U2; KTD6), so the provider's own picker cannot re-lock the
  /// app mid-sign-in and leave the operator at the lock screen. The gate is
  /// read nullably: the standalone and first-run harnesses mount this
  /// screen without one, and there is nothing to suppress there anyway.
  Future<T> _duringProviderUi<T>(Future<T> Function() action) {
    final gate = context.read<GateController?>();
    return gate == null ? action() : gate.duringSystemUi(action);
  }

  Future<void> _apple() => _run(() async {
        final auth = context.read<AuthController>();
        final result = await _duringProviderUi(auth.signInWithAppleNative);
        switch (result) {
          case AppleSignInSession():
            _signedIn();
          case AppleSignInCancelled():
            // Dismissed: back to the screen, no error (KTD9).
            break;
        }
      });

  /// Mirrors [_apple]: a dismissed picker is not a failure (#2 U4; KTD8,
  /// AE2); every other failure carries its copy through [_run].
  Future<void> _google() => _run(() async {
        final auth = context.read<AuthController>();
        final result = await _duringProviderUi(auth.signInWithGoogleNative);
        switch (result) {
          case GoogleSignInSession():
            _signedIn();
          case GoogleSignInCancelled():
            break;
        }
      });

  /// The first-run explainer above everything else, embedded mode only
  /// (#2 U6).
  List<Widget> _buildEmbeddedIntro() => [
        if (widget.embedded)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'An account keeps a copy of this device\'s data so it can be '
              'restored on another device. You can also keep everything on '
              'this device only.',
            ),
          ),
      ];

  /// Providers first: Apple above Google on iOS (KTD6, R12), then a
  /// divider when at least one provider button rendered.
  List<Widget> _buildProviderButtons() => [
        if (_showApple) ...[
          SignInWithAppleButton(
            key: const ValueKey('auth-apple'),
            onPressed: _apple,
            style: SignInWithAppleButtonStyle.black,
            height: 44,
          ),
          const SizedBox(height: 8),
        ],
        if (_showGoogle) ...[
          GoogleSignInButton(
            key: const ValueKey('auth-google'),
            onPressed: _busy ? null : _google,
          ),
          const SizedBox(height: 8),
        ],
        if (_showApple || _showGoogle)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or'),
                ),
                Expanded(child: Divider()),
              ],
            ),
          ),
      ];

  Widget _buildEmailField() => TextField(
        key: const ValueKey('auth-email'),
        controller: _email,
        enabled: !_busy,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        decoration: const InputDecoration(labelText: 'Email'),
      );

  Widget _buildPasswordField() => TextField(
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
      );

  /// The generic auth-error and info banners (R18: never the email or
  /// provider text).
  List<Widget> _buildStatusMessages(BuildContext context) => [
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
      ];

  /// The `auth-pending` spinner shown while any action is in flight.
  List<Widget> _buildPendingIndicator() => [
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
      ];

  /// The mode-specific primary button: create account or sign in.
  List<Widget> _buildPrimaryActionButton() => [
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
      ];

  List<Widget> _buildModeAndForgotSection() => [
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
      ];

  List<Widget> _buildEmbeddedFooter() => [
        if (widget.embedded) ...[
          const Divider(height: 32),
          TextButton(
            key: const ValueKey('first-run-not-now'),
            onPressed: _busy ? null : widget.onNotNow,
            child: const Text('Not now'),
          ),
        ],
      ];

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
          ..._buildEmbeddedIntro(),
          ..._buildProviderButtons(),
          _buildEmailField(),
          const SizedBox(height: 8),
          _buildPasswordField(),
          ..._buildStatusMessages(context),
          const SizedBox(height: 16),
          ..._buildPendingIndicator(),
          ..._buildPrimaryActionButton(),
          const SizedBox(height: 8),
          ..._buildModeAndForgotSection(),
          ..._buildEmbeddedFooter(),
        ],
      ),
    );
  }
}
