/// Best-effort Apple token revocation for account deletion (U1; R14).
///
/// Revoking an Apple token needs the app's Apple client secret, which is a
/// server-side value the app never ships — so there is no revocation the
/// device itself can perform. This seam resolves immediately and exists so
/// the deletion order (cascade, revocation attempt, reset) is explicit and
/// a server-side revocation can plug in later without touching it.
///
/// Best-effort in the meaningful sense: the cascade already deleted the
/// account's server rows and the auth user (which ends every session), the
/// device reset signs out locally, and the short access-token expiry bounds
/// any residual token reuse.
library;

/// Attempts Apple token revocation; resolves without action (see above).
/// Never throws.
Future<void> revokeAppleTokenBestEffort() async {}
