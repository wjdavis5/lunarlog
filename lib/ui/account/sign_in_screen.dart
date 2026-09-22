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
/// Failure copy routes through [authFailureCopy] (Issue #545: moved to
/// `lib/ui/l10n/auth_failure_copy.dart` and consolidated with every other
/// …FailureCopy mapper), the single, exhaustive copy table for every
/// [AuthFailure], including the provider, identity, closed-sign-up,
/// rate-limited, and misconfigured kinds (#2 U2; KTD4, R14; #32 AC2, AC4)
/// and the last-remaining-method kind a removal can hit (#31 KTD5, R9).
///
/// Provider buttons (#2 U4; KTD6, KTD8): the providers render above the
/// email form — Apple (the package's HIG widget, iOS only) first, then
/// Google (the branded widget, only when [AppConfig.hasGoogle] or
/// [showGoogle] says so) — and a dismissed picker is not a failure.
///
/// Issue #165 (form accessibility): the email + password pair sits in one
/// [AutofillGroup] with honest hints (`email`; `password` in sign-in mode,
/// `newPassword` in create mode so password managers offer to generate),
/// every field declares its `textInputAction` ("next" advances focus into
/// the next field, "done" submits), and the password field carries a
/// local-only reveal toggle — the toggle flips nothing but this field's
/// `obscureText`.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lunarlog/app_lifecycle.dart' show GateController;
import 'package:lunarlog/config.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/util/email_address.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/google_sign_in_button.dart';
import 'package:lunarlog/ui/components/inline_error.dart';
import 'package:lunarlog/ui/l10n/auth_failure_copy.dart';
import 'package:provider/provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart'
    show SignInWithAppleButton, SignInWithAppleButtonStyle;

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    this.showApple,
    this.showGoogle,
    this.showPasskeys,
    this.embedded = false,
    this.onSignedIn,
    this.onNotNow,
    this.onRestore,
  });

  /// Whether the Apple button renders; null means "iOS only" (KTD9).
  final bool? showApple;

  /// Whether the Google button renders; null means [AppConfig.hasGoogle]
  /// (#2 U4; R4).
  final bool? showGoogle;

  /// Whether the passkey option renders; null means [AppConfig.hasPasskeys]
  /// (#30 U4; KTD5). The nullable override is what lets widget tests force
  /// the flag on even though [AppConfig] is compile-time const.
  final bool? showPasskeys;

  /// First-run account step: no back button, a "Not now" action, and
  /// [onSignedIn] instead of popping.
  final bool embedded;

  final VoidCallback? onSignedIn;
  final VoidCallback? onNotNow;

  /// First-run restore action (Issue #468).
  final VoidCallback? onRestore;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();

  /// #165: the credential fields' explicit focus chain — the email field's
  /// "next" advances here, so keyboard traversal never depends on tree
  /// order around the provider buttons above.
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  /// #165: the reveal toggle's state. Local-only by design: flipping it
  /// changes this field's `obscureText` and nothing else.
  bool _obscurePassword = true;

  bool _createMode = false;
  bool _busy = false;
  String? _error;
  String? _info;

  /// LLA-006 (#2 U4): revealed once a magic-link send succeeds, or on
  /// init when [SettingsKeys.awaitingMagicLinkEmail] is already set (a
  /// code sent before an app restart) — see [_loadPendingMagicLink].
  bool _showCodeField = false;

  /// The controller this state listens to for link-delivered sessions
  /// (#2 U3; KTD4).
  AuthController? _auth;

  /// Last observed `signedIn`, so only a transition into it completes.
  bool _wasSignedIn = false;

  /// Set by the first completion; every later path returns early.
  bool _completed = false;

  bool get _showApple =>
      widget.showApple ??
      computeAppleSignInAvailable(
        isWeb: kIsWeb,
        isIos: defaultTargetPlatform == TargetPlatform.iOS,
      );

  bool get _showGoogle => widget.showGoogle ?? AppConfig.hasGoogle;

  bool get _showPasskeys => widget.showPasskeys ?? AppConfig.hasPasskeys;

  /// #2 U4: the verify-code button stays disabled until the field holds a
  /// plausible code, mirroring the password-length guard on this same
  /// screen — Supabase OTPs are 6 digits, so a slightly wider 6-10 band
  /// tolerates a copy-pasted code with surrounding whitespace trimmed.
  bool get _codeLooksValid => RegExp(r'^\d{6,10}$').hasMatch(_code.text.trim());

  @override
  void initState() {
    super.initState();
    unawaited(_loadPendingMagicLink(context.read<SettingsStore>()));
  }

  /// #2 U4: a magic-link/code request already sent before a restart (or
  /// before this screen was last disposed) leaves its email latched in
  /// [SettingsKeys.awaitingMagicLinkEmail] — same lifecycle as
  /// [SettingsKeys.awaitingConfirmationEmail] (`_createAccount`). Reading
  /// it back here pre-fills the email and reveals the code field so a
  /// code already sitting in the inbox can be entered without resending.
  Future<void> _loadPendingMagicLink(SettingsStore settings) async {
    final pending = await settings.get(SettingsKeys.awaitingMagicLinkEmail);
    if (!mounted || pending == null || pending.isEmpty) return;
    setState(() {
      _email.text = pending;
      _showCodeField = true;
    });
  }

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
    _code.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
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
      if (mounted) {
        setState(() =>
            _error = authFailureCopy(AppLocalizations.of(context), failure));
      }
    } catch (error) {
      debugPrint('lunarlog auth: action failed (${error.runtimeType})');
      if (mounted) {
        setState(() => _error = authFailureCopy(
            AppLocalizations.of(context), const AuthFailure.unknown()));
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

  /// #1030: rejects an empty or obviously malformed email locally, before
  /// any handler hands it to the auth service. On failure it focuses the
  /// field and shows the local copy under the same `auth-error` line a
  /// server failure uses; the caller then returns without calling `_run`.
  bool _emailLooksValid(AppLocalizations l10n) {
    final email = _email.text.trim();
    final String? error;
    if (email.isEmpty) {
      error = l10n.accountSignInEmailRequired;
    } else if (!looksLikeEmail(email)) {
      error = l10n.accountSignInEmailInvalid;
    } else {
      error = null;
    }
    if (error == null) return true;
    setState(() {
      _error = error;
      _info = null;
    });
    _emailFocus.requestFocus();
    return false;
  }

  Future<void> _signIn() async {
    if (!_emailLooksValid(AppLocalizations.of(context))) return;
    await _run(() async {
      final auth = context.read<AuthController>();
      await auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      _signedIn();
    });
  }

  Future<void> _createAccount() async {
    final l10n = AppLocalizations.of(context);
    if (_password.text.length < kMinPasswordLength) {
      setState(() {
        _error = l10n.accountSignInUseAtLeast(kMinPasswordLength);
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
            setState(() => _info = l10n.accountSignInConfirmEmailInfo);
          }
      }
    });
  }

  Future<void> _forgotPassword() async {
    final l10n = AppLocalizations.of(context);
    if (!_emailLooksValid(l10n)) return;
    await _run(() async {
      final auth = context.read<AuthController>();
      await auth.sendPasswordReset(_email.text.trim());
      if (mounted) {
        setState(() => _info = l10n.accountSignInResetInfo);
      }
    });
  }

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
          case NativeSignInSession():
            _signedIn();
          case NativeSignInCancelled():
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
          case NativeSignInSession():
            _signedIn();
          case NativeSignInCancelled():
            break;
        }
      });

  /// Passkey sign-in (#30 U4; KTD5). Mirrors [_google]/[_apple]: a
  /// dismissed ceremony is not a failure (R6), and success completes the
  /// screen through the exact same [_signedIn] path a Google sign-in takes
  /// (R9), so the one-account device binding and account-mismatch screen
  /// are inherited rather than re-implemented.
  Future<void> _passkey() => _run(() async {
        final auth = context.read<AuthController>();
        final result = await _duringProviderUi(auth.signInWithPasskey);
        switch (result) {
          case NativeSignInSession():
            _signedIn();
          case NativeSignInCancelled():
            break;
        }
      });

  /// LLA-006 (#2 U4): sends a passwordless link/code for the typed email
  /// in the screen's current mode, latches [SettingsKeys.
  /// awaitingMagicLinkEmail] the same way [_createAccount] latches
  /// `awaitingConfirmationEmail`, and reveals the code field. No explicit
  /// completion here — a link opened on this device arrives through
  /// [_onAuthChanged] like any other link-delivered session (#2 U3); the
  /// code field is the same-device alternative to that link.
  Future<void> _sendMagicLink() async {
    final l10n = AppLocalizations.of(context);
    if (!_emailLooksValid(l10n)) return;
    await _run(() async {
      final auth = context.read<AuthController>();
      final settings = context.read<SettingsStore>();
      final email = _email.text.trim();
      await auth.sendMagicLink(email: email, createAccount: _createMode);
      await settings.set(SettingsKeys.awaitingMagicLinkEmail, email);
      if (mounted) {
        setState(() {
          _showCodeField = true;
          _info = l10n.accountSignInMagicLinkInfo;
        });
      }
    });
  }

  /// The same-device counterpart of [_sendMagicLink]: completes through
  /// [_signedIn] directly, matching [_apple]/[_google]/[_passkey], since a
  /// verified code produces a session on this device with no link to open.
  Future<void> _verifyCode() => _run(() async {
        final auth = context.read<AuthController>();
        await auth.verifyEmailCode(
          email: _email.text.trim(),
          code: _code.text.trim(),
        );
        _signedIn();
      });

  /// The first-run explainer above everything else, embedded mode only
  /// (#2 U6).
  List<Widget> _buildEmbeddedIntro() => [
        if (widget.embedded)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              AppLocalizations.of(context).accountSignInEmbeddedIntro,
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
        if (_showPasskeys) ...[
          OutlinedButton(
            key: const ValueKey('auth-passkey'),
            onPressed: _busy ? null : _passkey,
            child: Text(AppLocalizations.of(context).accountSignInPasskeyAction),
          ),
          const SizedBox(height: 8),
        ],
        if (_showApple || _showGoogle || _showPasskeys)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(AppLocalizations.of(context).accountSignInOr),
                ),
                const Expanded(child: Divider()),
              ],
            ),
          ),
      ];

  /// #165: "next" from the email field moves focus to the password field
  /// (an explicit [FocusNode] chain, not tree order).
  Widget _buildEmailField() => TextField(
        key: const ValueKey('auth-email'),
        controller: _email,
        focusNode: _emailFocus,
        enabled: !_busy,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => _passwordFocus.requestFocus(),
        autofillHints: const [AutofillHints.email],
        decoration: InputDecoration(
          labelText: AppLocalizations.of(context).accountSignInEmailLabel,
        ),
      );

  /// #165: "done" submits (whichever primary action the current mode
  /// shows), the hint follows the mode (`password` for signing in,
  /// `newPassword` so password managers can offer generation on create),
  /// and the suffix toggle reveals what was typed — locally only.
  Widget _buildPasswordField() => TextField(
        key: const ValueKey('auth-password'),
        controller: _password,
        focusNode: _passwordFocus,
        enabled: !_busy,
        obscureText: _obscurePassword,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _createMode ? _createAccount() : _signIn(),
        autofillHints: _createMode
            ? const [AutofillHints.newPassword]
            : const [AutofillHints.password],
        decoration: InputDecoration(
          labelText: AppLocalizations.of(context).accountSignInPasswordLabel,
          helperText: _createMode
              ? AppLocalizations.of(context)
                  .accountSignInPasswordLengthHelper(kMinPasswordLength)
              : null,
          suffixIcon: IconButton(
            key: const ValueKey('auth-password-reveal'),
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
            tooltip: _obscurePassword
                ? AppLocalizations.of(context).accountSignInShowPassword
                : AppLocalizations.of(context).accountSignInHidePassword,
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
          ),
        ),
      );

  /// The generic auth-error and info banners (R18: never the email or
  /// provider text).
  List<Widget> _buildStatusMessages(BuildContext context) => [
        if (_error != null) ...[
          const SizedBox(height: 12),
          InlineError(
            key: const ValueKey('auth-error'),
            message: _error!,
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
            child:
                Text(AppLocalizations.of(context).accountSignInCreateAccountAction),
          )
        else
          FilledButton(
            key: const ValueKey('auth-sign-in'),
            onPressed: _busy ? null : _signIn,
            child: Text(AppLocalizations.of(context).accountSignInAction),
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
              ? AppLocalizations.of(context).accountSignInToggleHaveAccount
              : AppLocalizations.of(context).accountSignInToggleCreateInstead),
        ),
        if (!_createMode)
          TextButton(
            key: const ValueKey('auth-forgot-password'),
            onPressed: _busy ? null : _forgotPassword,
            child: Text(AppLocalizations.of(context).accountSignInForgotPasswordAction),
          ),
      ];

  /// LLA-006 (#2 U4): the passwordless entry point, reachable from the
  /// same screen as the password form and providers rather than being a
  /// service with no caller. `or`-divided like [_buildProviderButtons],
  /// and always shown (unlike the providers, passwordless has no
  /// build-config gate) — button copy follows [_createMode] the same way
  /// [_buildPrimaryActionButton] does.
  List<Widget> _buildMagicLinkSection() => [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(AppLocalizations.of(context).accountSignInOr),
              ),
              const Expanded(child: Divider()),
            ],
          ),
        ),
        OutlinedButton(
          key: const ValueKey('auth-magic-link'),
          onPressed: _busy ? null : _sendMagicLink,
          child: Text(_createMode
              ? AppLocalizations.of(context).accountSignInMagicLinkCreate
              : AppLocalizations.of(context).accountSignInMagicLinkSignIn),
        ),
        ..._buildCodeField(),
      ];

  /// The revealed half of [_buildMagicLinkSection]: a numeric code field
  /// plus its verify button, disabled until the field holds a plausible
  /// code ([_codeLooksValid]). #165: `oneTimeCode` is the honest hint (an
  /// emailed OTP), and "done" verifies when the code is plausible.
  List<Widget> _buildCodeField() => [
        if (_showCodeField) ...[
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('auth-code'),
            controller: _code,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (_codeLooksValid) unawaited(_verifyCode());
            },
            autofillHints: const [AutofillHints.oneTimeCode],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).accountSignInCodeLabel,
              hintText: AppLocalizations.of(context).accountSignInCodeHint,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const ValueKey('auth-verify-code'),
            onPressed: _busy || !_codeLooksValid ? null : _verifyCode,
            child: Text(AppLocalizations.of(context).accountSignInVerifyCodeAction),
          ),
        ],
      ];

  List<Widget> _buildEmbeddedFooter() {
    if (!widget.embedded) return const [];
    final l10n = AppLocalizations.of(context);
    return [
      const Divider(height: 32),
      if (widget.onRestore != null) ...[
        OutlinedButton(
          key: const ValueKey('first-run-restore-account-step'),
          onPressed: _busy ? null : widget.onRestore,
          child: Text(l10n.firstRunRestore),
        ),
        const SizedBox(height: 8),
      ],
      TextButton(
        key: const ValueKey('first-run-not-now'),
        onPressed: _busy ? null : widget.onNotNow,
        child: Text(l10n.accountSignInNotNow),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title =
        _createMode ? l10n.accountSignInTitleCreate : l10n.accountSignInTitle;
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
          // #165: one AutofillGroup around the credential pair so iOS
          // Keychain / Android Autofill see a single fillable (and
          // saveable) form rather than two unannotated fields.
          AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildEmailField(),
                const SizedBox(height: 8),
                _buildPasswordField(),
              ],
            ),
          ),
          ..._buildStatusMessages(context),
          const SizedBox(height: 16),
          ..._buildPendingIndicator(),
          ..._buildPrimaryActionButton(),
          const SizedBox(height: 8),
          ..._buildModeAndForgotSection(),
          ..._buildMagicLinkSection(),
          ..._buildEmbeddedFooter(),
        ],
      ),
    );
  }
}
