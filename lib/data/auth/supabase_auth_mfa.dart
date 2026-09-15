part of 'supabase_auth_service.dart';

// TOTP MFA enrolment, step-up verification, and AAL surface for
// [SupabaseAuthService] (issue #268; part of `supabase_auth_service.dart`,
// mixed into the class below). Built `on SupabaseAuthProviders` purely to
// reuse its `_guard`/`_requireSignedInUser` helpers — every gateway error is
// reduced to a typed [AuthFailure] the same way every provider call already
// is, including `mfa_verification_rejected` -> [AuthInvalidCodeFailure]
// (see `supabase_auth_providers.dart`'s `_mapGoTrueAuthException`).
//
// Nothing here ever logs a secret, QR data URI, factor id, or TOTP code: a
// caught error prints only its runtime type, exactly like every other auth
// failure path in this library.
mixin SupabaseAuthMfa on SupabaseAuthProviders {
  /// #268 U1: starts enrolment and maps the unverified factor's TOTP
  /// payload into the domain type. [AuthUnknownFailure] when the response
  /// carries no `totp` payload at all (the project's `[auth.mfa.totp]` not
  /// enabled, or an unexpected factor-type response) — the same "response
  /// missing what it must carry" convention [_exchangeIdTokenForSession]
  /// uses for a session-less sign-in response.
  Future<TotpEnrollmentOffer> enrollTotp() => _guard(() async {
        _requireSignedInUser();
        final response = await _gateway.enrollTotpFactor(issuer: 'lunarlog');
        final totp = response.totp;
        if (totp == null) throw const AuthFailure.unknown();
        return TotpEnrollmentOffer(
          factorId: response.id,
          qrCodeDataUri: totp.qrCode,
          secret: totp.secret,
        );
      });

  /// #268 U2/U3: one round trip (challenge + verify) against [factorId].
  /// Used to complete an enrolment and, for an already-verified factor, as
  /// an AAL2 step-up — gotrue's `verify` promotes the session either way,
  /// and the resulting `mfaChallengeVerified` auth event already flows
  /// through `_onAuthState` in `supabase_auth_session_state.dart`.
  Future<void> verifyTotpCode({
    required String factorId,
    required String code,
  }) =>
      _guard(() => _gateway.challengeAndVerifyMfa(
            factorId: factorId,
            code: code,
          ));

  /// #268 U2: every TOTP factor on the account (verified or still
  /// pending), refreshed from the server (see [AuthGateway.listMfaFactors]).
  Future<List<MfaFactor>> listMfaFactors() => _guard(() async {
        final response = await _gateway.listMfaFactors();
        return response.totp
            .map((factor) => MfaFactor(
                  id: factor.id,
                  status: factor.status == FactorStatus.verified
                      ? MfaFactorStatus.verified
                      : MfaFactorStatus.unverified,
                  createdAt: factor.createdAt,
                ))
            .toList(growable: false);
      });

  /// #268 U2: removes [factorId]. The server itself enforces the aal2
  /// precondition for a verified factor (`insufficient_aal` maps to
  /// [AuthUnknownFailure] through the default branch — the account section
  /// always resolves [requiresMfaStepUp] first, so this is defense-in-depth
  /// for a caller that skips it).
  Future<void> unenrollMfaFactor(String factorId) =>
      _guard(() => _gateway.unenrollMfaFactor(factorId));

  /// #268 D-6: read synchronously from the session JWT gotrue already
  /// holds — no network call, so this is safe to consult on every render.
  AuthAssuranceLevel? get assuranceLevel =>
      switch (_gateway.getAuthenticatorAssuranceLevel().currentLevel) {
        AuthenticatorAssuranceLevels.aal1 => AuthAssuranceLevel.aal1,
        AuthenticatorAssuranceLevels.aal2 => AuthAssuranceLevel.aal2,
        null => null,
      };

  /// #268 D-6: the gate every destructive-action AAL2 check consults.
  /// [listMfaFactors] refreshes the session first, so this reflects a
  /// factor enrolled or removed moments ago, not a stale cached session.
  Future<bool> requiresMfaStepUp() async {
    if (assuranceLevel == AuthAssuranceLevel.aal2) return false;
    final factors = await listMfaFactors();
    return factors.any((factor) => factor.status == MfaFactorStatus.verified);
  }
}
