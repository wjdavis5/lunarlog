/// Account authentication contract (U4; KTD6, R1–R5). Pure Dart: no
/// Flutter and no Supabase types cross this boundary, exactly like the
/// repository interfaces beside it. The implementation lives in
/// `lib/data/auth/`; the UI notifier in `lib/ui/account/`.
///
/// Failures are *typed* ([AuthFailure]) and carry no provider text, no
/// error description from a link, and no email — the UI chooses its own
/// copy and nothing here can leak into a crash report (R18).
///
/// Native Google Sign-In and the failure kinds for provider, link, code,
/// identity, and closed sign-ups come from the social-logins plan
/// (#2 U2; KTD1, KTD4, KTD8).
library;

import 'package:meta/meta.dart';

/// The session as the app sees it.
///
/// * [signedOut] — no session (also the state of an unconfigured or never
///   signed-in device, and after an explicit sign-out).
/// * [signedIn] — a session exists.
/// * [passwordRecovery] — a session was established from a recovery link;
///   the operator must set a new password. Also a session-holding state.
/// * [expired] — the session could not be refreshed (e.g. weeks offline,
///   refresh token revoked); local use continues, sync needs a new sign-in
///   (AE9).
///
/// "Awaiting email confirmation" is deliberately *not* a session state:
/// U6 persists it in device-local settings (AS10).
enum AuthSessionState { signedOut, signedIn, passwordRecovery, expired }

/// Which sessions [AuthService.signOut] revokes.
enum AuthSignOutScope {
  /// This device's session only.
  local,

  /// Every session of the account ("Sign out everywhere", R16). Other
  /// devices keep access until their access token expires.
  global,
}

@immutable
class AuthUser {
  const AuthUser({required this.id, this.email});

  /// The provider's stable user id (`auth.users.id`).
  final String id;

  /// May be null (e.g. Apple "Hide My Email" relays are still emails, but a
  /// provider may withhold it).
  final String? email;

  @override
  bool operator ==(Object other) =>
      other is AuthUser && other.id == id && other.email == email;

  @override
  int get hashCode => Object.hash(id, email);

  @override
  String toString() => 'AuthUser($id)';
}

/// Outcome of [AuthService.signUp].
sealed class SignUpResult {
  const SignUpResult();
}

/// Confirmation is off (or auto-confirmed): a session exists now.
final class SignUpSession extends SignUpResult {
  const SignUpSession(this.user);

  final AuthUser user;

  @override
  String toString() => 'SignUpSession($user)';
}

/// Hosted email confirmation is on (AS10): a user was created but no
/// session exists until the confirmation link is opened on this device.
@immutable
final class SignUpAwaitingConfirmation extends SignUpResult {
  const SignUpAwaitingConfirmation(this.email);

  final String email;

  @override
  bool operator ==(Object other) =>
      other is SignUpAwaitingConfirmation && other.email == email;

  @override
  int get hashCode => email.hashCode;

  @override
  String toString() => 'SignUpAwaitingConfirmation';
}

/// Outcome of [AuthService.signInWithAppleNative].
sealed class AppleSignInResult {
  const AppleSignInResult();
}

final class AppleSignInSession extends AppleSignInResult {
  const AppleSignInSession(this.user);

  final AuthUser user;

  @override
  String toString() => 'AppleSignInSession($user)';
}

/// The operator dismissed the Apple dialog: not a failure (KTD9).
@immutable
final class AppleSignInCancelled extends AppleSignInResult {
  const AppleSignInCancelled();

  @override
  bool operator ==(Object other) => other is AppleSignInCancelled;

  @override
  int get hashCode => (AppleSignInCancelled).hashCode;

  @override
  String toString() => 'AppleSignInCancelled';
}

/// Outcome of [AuthService.signInWithGoogleNative] (#2 U2; KTD1).
sealed class GoogleSignInResult {
  const GoogleSignInResult();
}

final class GoogleSignInSession extends GoogleSignInResult {
  const GoogleSignInSession(this.user);

  final AuthUser user;

  @override
  String toString() => 'GoogleSignInSession($user)';
}

/// The operator dismissed the Google picker: not a failure (#2 KTD8, AE2).
@immutable
final class GoogleSignInCancelled extends GoogleSignInResult {
  const GoogleSignInCancelled();

  @override
  bool operator ==(Object other) => other is GoogleSignInCancelled;

  @override
  int get hashCode => (GoogleSignInCancelled).hashCode;

  @override
  String toString() => 'GoogleSignInCancelled';
}

/// Typed failure thrown by every [AuthService] operation and surfaced for
/// rejected links. Deliberately fieldless: no message, no code, no email.
@immutable
sealed class AuthFailure implements Exception {
  const AuthFailure();

  const factory AuthFailure.wrongPassword() = AuthWrongPasswordFailure;

  const factory AuthFailure.weakPassword() = AuthWeakPasswordFailure;

  const factory AuthFailure.network() = AuthNetworkFailure;

  const factory AuthFailure.unknown() = AuthUnknownFailure;

  const factory AuthFailure.expiredLink() = AuthExpiredLinkFailure;

  const factory AuthFailure.invalidCode() = AuthInvalidCodeFailure;

  const factory AuthFailure.providerUnavailable() =
      AuthProviderUnavailableFailure;

  const factory AuthFailure.identityTaken() = AuthIdentityTakenFailure;

  const factory AuthFailure.signUpClosed() = AuthSignUpClosedFailure;

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Wrong email/password combination (the provider does not say which).
final class AuthWrongPasswordFailure extends AuthFailure {
  const AuthWrongPasswordFailure();

  @override
  String toString() => 'AuthFailure.wrongPassword';
}

/// The provider rejected the password as too weak.
final class AuthWeakPasswordFailure extends AuthFailure {
  const AuthWeakPasswordFailure();

  @override
  String toString() => 'AuthFailure.weakPassword';
}

/// The request never reached the provider (offline, DNS, timeout).
final class AuthNetworkFailure extends AuthFailure {
  const AuthNetworkFailure();

  @override
  String toString() => 'AuthFailure.network';
}

/// Everything else, including rejected or expired links.
final class AuthUnknownFailure extends AuthFailure {
  const AuthUnknownFailure();

  @override
  String toString() => 'AuthFailure.unknown';
}

/// A sign-in link that was rejected, expired, reused, or opened on a device
/// other than the one that requested it (#2 KTD4, R7).
final class AuthExpiredLinkFailure extends AuthFailure {
  const AuthExpiredLinkFailure();

  @override
  String toString() => 'AuthFailure.expiredLink';
}

/// A wrong or expired emailed code (#2 KTD4).
final class AuthInvalidCodeFailure extends AuthFailure {
  const AuthInvalidCodeFailure();

  @override
  String toString() => 'AuthFailure.invalidCode';
}

/// The native provider could not sign in for any reason other than
/// cancellation: no credentials, no Play Services, misconfiguration
/// (#2 KTD8, R3).
final class AuthProviderUnavailableFailure extends AuthFailure {
  const AuthProviderUnavailableFailure();

  @override
  String toString() => 'AuthFailure.providerUnavailable';
}

/// The identity already belongs to another account (#2 KTD4).
final class AuthIdentityTakenFailure extends AuthFailure {
  const AuthIdentityTakenFailure();

  @override
  String toString() => 'AuthFailure.identityTaken';
}

/// Sign-ups are closed for the project; new accounts are created by the
/// account owner (#2 KTD3).
final class AuthSignUpClosedFailure extends AuthFailure {
  const AuthSignUpClosedFailure();

  @override
  String toString() => 'AuthFailure.signUpClosed';
}

/// The account seam. Constructed before the first frame by the bootstrap
/// (KTD8) so a cold-start recovery link is latched before any widget
/// exists; `null` in `lib/main.dart` when the build has no Supabase
/// configuration (KTD11) — there is no no-op implementation.
abstract interface class AuthService {
  /// Creates the account. Returns [SignUpAwaitingConfirmation] when the
  /// provider created a user but no session (hosted confirmation on),
  /// [SignUpSession] otherwise. Throws [AuthFailure].
  Future<SignUpResult> signUp({
    required String email,
    required String password,
  });

  /// Throws [AuthFailure] ([AuthWrongPasswordFailure] for a bad
  /// combination).
  Future<AuthUser> signInWithPassword({
    required String email,
    required String password,
  });

  /// Sends the reset email; the link must be opened on this device (R2).
  /// Throws [AuthFailure].
  Future<void> sendPasswordReset(String email);

  /// Sets a new password for the current session (recovery or signed-in).
  /// Throws [AuthFailure].
  Future<void> updatePassword(String newPassword);

  /// Native Apple Sign-In (iOS only, KTD9). Throws [UnsupportedError] on
  /// every other platform; returns [AppleSignInCancelled] when the dialog
  /// is dismissed; throws [AuthFailure] otherwise.
  Future<AppleSignInResult> signInWithAppleNative();

  /// Native Google Sign-In through the platform picker (iOS and Android,
  /// #2 KTD1). Throws [UnsupportedError] on every other platform and when
  /// the build carries no Google client ids; returns
  /// [GoogleSignInCancelled] when the picker is dismissed; throws
  /// [AuthFailure] otherwise ([AuthProviderUnavailableFailure] for any
  /// provider-side failure, #2 KTD8).
  Future<GoogleSignInResult> signInWithGoogleNative();

  /// Throws [AuthFailure]; a [AuthSignOutScope.local] failure still leaves
  /// no session on this device.
  Future<void> signOut({AuthSignOutScope scope = AuthSignOutScope.local});

  /// The current user, or null without a session.
  AuthUser? get currentUser;

  String? get currentUserId;

  /// Current state — readable synchronously so a late subscriber (the
  /// controller) starts from truth instead of waiting for an event.
  AuthSessionState get state;

  /// Every state transition after subscription; see [state] for the
  /// initial value.
  Stream<AuthSessionState> get states;

  /// True from the moment a recovery link was exchanged until
  /// [consumeRecovery]. Set by the service, possibly before any widget
  /// exists; the home gate consumes it only once the device gate is
  /// unlocked (AE8).
  bool get pendingRecovery;

  void consumeRecovery();

  /// A rejected incoming link (expired, tampered, no matching verifier)
  /// held until [consumeLinkFailure]; never carries the link's text.
  AuthFailure? get pendingLinkFailure;

  /// Emits each rejected link's failure as it happens (the latched value in
  /// [pendingLinkFailure] covers the cold-start case with no subscriber).
  Stream<AuthFailure> get linkFailures;

  void consumeLinkFailure();
}
