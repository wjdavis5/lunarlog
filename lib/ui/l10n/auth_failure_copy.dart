/// Localized copy for [AuthFailure] (Issue #545): moved out of
/// `sign_in_screen.dart` (a screen file acting as a shared copy module) and
/// consolidated with every other …FailureCopy mapper under `lib/ui/l10n/`
/// — the "two incompatible conventions" issue #545 called out. The `en`
/// ARB values are character-identical to the literals this replaces, so
/// this is copy-neutral.
///
/// [authFailureCopy] is the single, exhaustive copy table for every
/// [AuthFailure], including the provider, identity, closed-sign-up,
/// rate-limited, and misconfigured kinds (#2 U2; KTD4, R14; #32 AC2, AC4)
/// and the last-remaining-method kind a removal can hit (#31 KTD5, R9).
library;

import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';

/// Client-side minimum for a new password (the project's hosted rule).
const int kMinPasswordLength = 12;

/// Generic, email-free copy per failure kind. Split into this dispatcher
/// plus [_rareAuthFailureCopy] — same exhaustive switch over the sealed
/// [AuthFailure] hierarchy, just spread across two methods so neither
/// trips the CRAP gate's per-method complexity threshold (#31; no
/// behavior change). This function's switch is still the one the compiler
/// checks for exhaustiveness: a new [AuthFailure] kind fails to compile
/// here (either as its own arm or added to the combined arm below) before
/// [_rareAuthFailureCopy] is ever reached.
String authFailureCopy(AppLocalizations l10n, AuthFailure failure) =>
    switch (failure) {
      AuthWrongPasswordFailure() => l10n.authFailureWrongPassword,
      AuthWeakPasswordFailure() =>
        l10n.authFailureWeakPassword(kMinPasswordLength),
      AuthNetworkFailure() => l10n.commonServerUnreachable,
      AuthUnknownFailure() => l10n.commonSomethingWentWrong,
      // Generic on purpose (#30 U4; R5): this same fieldless kind now also
      // covers a passkey ceremony that could not run, so the copy must
      // never name Google, Apple, or "passkey" specifically.
      AuthProviderUnavailableFailure() =>
        l10n.authFailureProviderUnavailable,
      // Issue #32 AC2: throttled, not rejected — the copy names waiting,
      // never a bad code.
      AuthRateLimitedFailure() => l10n.authFailureRateLimited,
      // Issue #32 AC4: the dashboard is not set up for this operation —
      // a project-setup problem, not a bug in-app.
      AuthMisconfiguredFailure() => l10n.authFailureMisconfigured,
      AuthExpiredLinkFailure() ||
      AuthInvalidCodeFailure() ||
      AuthIdentityTakenFailure() ||
      AuthSignUpClosedFailure() ||
      AuthLastSignInMethodFailure() =>
        _rareAuthFailureCopy(l10n, failure),
    };

/// The less-common failure kinds (#2/#31), split out of [authFailureCopy]
/// purely to keep its cyclomatic complexity under the CRAP gate's
/// threshold. Only ever called with the five kinds [authFailureCopy]
/// delegates; the wildcard arm is unreachable in practice and returns the
/// same generic copy [AuthUnknownFailure] uses rather than throwing, so a
/// future refactor mistake fails safe instead of crashing the UI.
String _rareAuthFailureCopy(AppLocalizations l10n, AuthFailure failure) =>
    switch (failure) {
      AuthExpiredLinkFailure() => l10n.authFailureExpiredLink,
      AuthInvalidCodeFailure() => l10n.authFailureInvalidCode,
      AuthIdentityTakenFailure() => l10n.authFailureIdentityTaken,
      AuthSignUpClosedFailure() => l10n.authFailureSignUpClosed,
      AuthLastSignInMethodFailure() => l10n.authFailureLastSignInMethod,
      _ => l10n.commonSomethingWentWrong,
    };
