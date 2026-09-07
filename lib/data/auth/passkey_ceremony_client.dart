/// Seam between [SupabaseAuthService] and a platform passkey ceremony
/// (#30 U3; KTD2). Deliberately not backed by a plugin yet: the default
/// [UnsupportedPasskeyCeremonyClient] always fails cleanly (R7), and a
/// plugin-backed implementation is deferred to activation — see the plan's
/// KTD2 for why (a native dependency that cannot function without a
/// relying-party domain, and a risk to the shipped minimum OS versions).
library;

import 'package:lunarlog/domain/auth/auth_service.dart';

/// What [SupabaseAuthService] needs from a platform passkey API.
///
/// Both methods take and return W3C WebAuthn Level 3 JSON maps with binary
/// fields base64url-encoded — deliberately the same shape `gotrue`'s
/// `GoTruePasskeyApi` speaks (#30 KTD1), so this interface needs no
/// knowledge of the relying-party id at all: the server supplies it inside
/// `options`, and no implementation of this interface should ever read or
/// send one. **A null return means the operator dismissed the ceremony**,
/// mirroring the null-means-cancelled convention `GoogleSignInClient` uses
/// for a dismissed picker.
///
/// An implementation over a typed-request plugin (for example the
/// `passkeys` package's `RegisterRequestType` / `AuthenticateRequestType`)
/// owns the translation between that plugin's types and these JSON maps
/// (#30 KTD2) — this interface is deliberately plugin-shape-agnostic so it
/// does not need to change when the plugin choice or version does.
abstract interface class PasskeyCeremonyClient {
  /// Creates a new passkey credential from [options] (a
  /// `PublicKeyCredentialCreationOptionsJSON`). Returns the credential as a
  /// `RegistrationResponseJSON` map, or null if the operator dismissed the
  /// enrolment ceremony.
  Future<Map<String, dynamic>?> create(Map<String, dynamic> options);

  /// Obtains an assertion from [options] (a
  /// `PublicKeyCredentialRequestOptionsJSON`). Returns the assertion as an
  /// `AuthenticationResponseJSON` map, or null if the operator dismissed the
  /// sign-in ceremony.
  Future<Map<String, dynamic>?> get(Map<String, dynamic> options);
}

/// The default [PasskeyCeremonyClient] until a platform adapter is adopted
/// at activation (#30 KTD2). Pure Dart with no plugin import, so it is
/// unit-testable and deliberately **not** coverage-excluded — that omission
/// is the point: a flag-on build with no adapter must fail as
/// [AuthFailure.providerUnavailable] (R7), never crash, and this class is
/// what proves it. Both methods always throw that same failure — the same
/// generic outcome a Google picker that cannot run produces — never a
/// crash and never a provider-specific message.
class UnsupportedPasskeyCeremonyClient implements PasskeyCeremonyClient {
  const UnsupportedPasskeyCeremonyClient();

  @override
  Future<Map<String, dynamic>?> create(Map<String, dynamic> options) async {
    throw const AuthFailure.providerUnavailable();
  }

  @override
  Future<Map<String, dynamic>?> get(Map<String, dynamic> options) async {
    throw const AuthFailure.providerUnavailable();
  }
}
