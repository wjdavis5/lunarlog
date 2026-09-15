/// TOTP multi-factor authentication domain types (issue #268; D-6). Pure
/// Dart: no Supabase/gotrue type crosses into `lib/domain` (the layering
/// test in `test/architecture/layering_test.dart`) — [AuthService] maps
/// every gotrue MFA type into one of these at the `lib/data/auth/` boundary,
/// the same way it already does for [AuthUser]/[AuthFailure].
///
/// Nothing here is ever logged: the enrolment secret/QR and every TOTP code
/// stay in memory only, rendered on screen and handed straight to
/// [AuthService], never passed to `debugPrint`, a breadcrumb, or a crash
/// report (see `lib/observability/scrub.dart`'s deny-list and the
/// `debugPrint('... (${error.runtimeType})')` convention every auth failure
/// path in `lib/data/auth/` already follows).
library;

import 'package:meta/meta.dart';

/// A freshly started, not-yet-verified TOTP enrolment (#268 U1). The
/// operator adds [secret] (or scans [qrCodeDataUri]) to their authenticator
/// app, then a code from it confirms enrolment via
/// [AuthService.verifyTotpCode].
@immutable
class TotpEnrollmentOffer {
  const TotpEnrollmentOffer({
    required this.factorId,
    required this.qrCodeDataUri,
    required this.secret,
  });

  /// The unverified factor's id, passed back to [AuthService.verifyTotpCode]
  /// and [AuthService.unenrollMfaFactor].
  final String factorId;

  /// A `data:image/svg+xml` URI ready for an `Image.memory`/`SvgPicture`
  /// widget — gotrue already prepends the data-URI scheme.
  final String qrCodeDataUri;

  /// The plain secret, shown as a manual-entry fallback when the operator
  /// cannot scan the code. Never logged.
  final String secret;
}

enum MfaFactorStatus { verified, unverified }

/// One TOTP factor on the account, as the "Two-factor authentication"
/// settings list sees it (#268 U2).
@immutable
class MfaFactor {
  const MfaFactor({
    required this.id,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final MfaFactorStatus status;
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      other is MfaFactor &&
      other.id == id &&
      other.status == status &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, status, createdAt);
}

/// The session's authenticator assurance level (#268 D-6): [aal1] is an
/// ordinary sign-in, [aal2] has also completed an MFA challenge in this
/// session. [AuthService.requiresMfaStepUp] is the gate every destructive
/// account action (deletion, ownership-transfer arming, sign out
/// everywhere) consults before proceeding.
enum AuthAssuranceLevel { aal1, aal2 }
