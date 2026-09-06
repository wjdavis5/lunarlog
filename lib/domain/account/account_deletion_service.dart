/// Account deletion contract (Issue #17, Unit U4; KTD1-KTD4). Pure Dart: no
/// Flutter and no Supabase types cross this boundary, exactly like
/// [AuthService][auth_service_link] and
/// [SharingService][sharing_service_link] beside it. The implementation
/// lives in `lib/data/account/`; the UI flow (device credential, the
/// confirmation dialog, the Apple ceremony, and the copy for each failure)
/// in `lib/ui/account/`.
///
/// [auth_service_link]: ../auth/auth_service.dart
/// [sharing_service_link]: ../sharing/sharing_service.dart
library;

import 'package:meta/meta.dart';

/// Typed failure thrown by [AccountDeletionService.deleteAccount].
/// Deliberately fieldless: no message, no code, no server response body -
/// nothing that could carry a Supabase or Apple error into a crash report
/// (R10), exactly like [AuthFailure][auth_failure_link] and
/// [SharingFailure][sharing_failure_link].
///
/// [auth_failure_link]: ../auth/auth_service.dart
/// [sharing_failure_link]: ../sharing/sharing_service.dart
@immutable
sealed class AccountDeletionFailure implements Exception {
  const AccountDeletionFailure();

  const factory AccountDeletionFailure.network() =
      AccountDeletionNetworkFailure;

  const factory AccountDeletionFailure.unauthorized() =
      AccountDeletionUnauthorizedFailure;

  /// The Edge Function's own `apple_revoke_failed` code (#17 KTD4): the
  /// server-side row deletion already ran, but Apple could not confirm the
  /// revocation, so the `auth.users` row was deliberately left in place and
  /// the whole call is safe to retry.
  const factory AccountDeletionFailure.appleRevokeFailed() =
      AccountDeletionAppleRevokeFailedFailure;

  /// The client-side call to the Edge Function timed out (#17 P1 fix):
  /// `functions_client` 2.7.1's `invoke()` has no default deadline, so
  /// [SupabaseAccountDeletionService] applies its own via `abortSignal`.
  /// Unlike [AccountDeletionFailure.network] (the request never reached the
  /// server) this means the server may still be mid-flight or may already
  /// have finished - the outcome is genuinely unknown, not "definitely
  /// didn't happen".
  const factory AccountDeletionFailure.timeout() = AccountDeletionTimeoutFailure;

  /// The Edge Function's own `delete_user_failed` code (#17 P1 fix): the
  /// server-side row deletion (and Apple revocation, if applicable) already
  /// succeeded, but the final `auth.users` deletion step itself failed. The
  /// account's sign-in may still exist even though the data is gone - the
  /// call is safe to retry (KTD4's RPC is idempotent) - so this gets its
  /// own copy rather than [AccountDeletionFailure.unknown]'s "your account
  /// was not deleted" claim, which would be false here.
  const factory AccountDeletionFailure.deleteUserFailed() =
      AccountDeletionDeleteUserFailedFailure;

  const factory AccountDeletionFailure.unknown() =
      AccountDeletionUnknownFailure;

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// The request never reached the server (offline, DNS, timeout).
final class AccountDeletionNetworkFailure extends AccountDeletionFailure {
  const AccountDeletionNetworkFailure();

  @override
  String toString() => 'AccountDeletionFailure.network';
}

/// The caller's session is no longer valid (expired or revoked JWT).
final class AccountDeletionUnauthorizedFailure extends AccountDeletionFailure {
  const AccountDeletionUnauthorizedFailure();

  @override
  String toString() => 'AccountDeletionFailure.unauthorized';
}

/// See [AccountDeletionFailure.appleRevokeFailed].
final class AccountDeletionAppleRevokeFailedFailure
    extends AccountDeletionFailure {
  const AccountDeletionAppleRevokeFailedFailure();

  @override
  String toString() => 'AccountDeletionFailure.appleRevokeFailed';
}

/// See [AccountDeletionFailure.timeout].
final class AccountDeletionTimeoutFailure extends AccountDeletionFailure {
  const AccountDeletionTimeoutFailure();

  @override
  String toString() => 'AccountDeletionFailure.timeout';
}

/// See [AccountDeletionFailure.deleteUserFailed].
final class AccountDeletionDeleteUserFailedFailure
    extends AccountDeletionFailure {
  const AccountDeletionDeleteUserFailedFailure();

  @override
  String toString() => 'AccountDeletionFailure.deleteUserFailed';
}

/// Everything else.
final class AccountDeletionUnknownFailure extends AccountDeletionFailure {
  const AccountDeletionUnknownFailure();

  @override
  String toString() => 'AccountDeletionFailure.unknown';
}

/// The account-deletion seam (#17 KTD8). Built alongside the production
/// sharing service in `lib/app_lifecycle.dart` when a `SupabaseClient`
/// exists; provided down the tree as `null` otherwise (an unconfigured
/// build, or web unless `LUNARLOG_WEB_SYNC=true`), in which case
/// `lib/ui/account/account_section.dart` renders no delete tile (R11).
abstract interface class AccountDeletionService {
  /// Deletes the caller's account: every server row the plan's
  /// `delete_account_data()` RPC reaches, the Apple identity's grant (when
  /// [appleAuthorizationCode] is supplied), and finally the `auth.users`
  /// row itself (#17 KTD4). The device-side reset
  /// (`LunarLogRootState.resetDevice`, KTD16) is the caller's
  /// responsibility, run only after this future completes without error.
  ///
  /// [appleAuthorizationCode] is a *fresh* Sign in with Apple authorization
  /// code obtained by the caller immediately before this call (#17 KTD3) -
  /// no Apple refresh token is ever stored at rest. Pass it when the
  /// account has an Apple identity; omit it otherwise.
  ///
  /// Throws [AccountDeletionFailure] on any failure. A thrown
  /// [AccountDeletionAppleRevokeFailedFailure] means the server-side rows
  /// are already gone but the `auth.users` row is not - the call is safe to
  /// retry (#17 KTD4).
  Future<void> deleteAccount({String? appleAuthorizationCode});
}
