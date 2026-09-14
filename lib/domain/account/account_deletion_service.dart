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

  /// The Edge Function's own `apple_code_required` code (#17 P1 round 2
  /// fix): the account has an Apple identity but the client supplied no
  /// authorization code, so the Edge Function refused *before* running any
  /// destructive step - nothing was touched at all. Distinct from
  /// [AccountDeletionFailure.appleRevokeFailed], where the server-side row
  /// deletion has already run: that code's copy correctly says data was
  /// deleted, which would be false here. The operator just needs to retry -
  /// retrying the delete flow fetches a fresh Apple code (KTD3).
  const factory AccountDeletionFailure.appleCodeRequired() =
      AccountDeletionAppleCodeRequiredFailure;

  /// Client-side only (Issue #605/LLA-052) - never thrown by
  /// [AccountDeletionService.deleteAccount] itself, only by
  /// `lib/ui/account/account_section.dart`'s delete flow. The server
  /// responded [AccountDeletionFailure.appleCodeRequired] (a fresh Apple
  /// authorization code is still needed), but this platform has no native
  /// Sign in with Apple ceremony to fetch one with (e.g. Android, with
  /// Apple linked from a different, iOS device) - unlike
  /// [AccountDeletionFailure.appleCodeRequired], a bare retry can never
  /// succeed here, since the ceremony will never become available on this
  /// device. Nothing was touched (the server never even got a code
  /// request), so this account's Apple sign-in link can only be removed by
  /// finishing deletion from a device that has the ceremony, or by asking
  /// support to remove it.
  const factory AccountDeletionFailure.appleNativeCeremonyUnavailable() =
      AccountDeletionAppleNativeCeremonyUnavailableFailure;

  /// The Edge Function's own `apple_revoke_failed` code (#17 KTD4): the
  /// server-side row deletion already ran, but Apple could not confirm the
  /// revocation, so the `auth.users` row was deliberately left in place and
  /// the whole call is safe to retry.
  const factory AccountDeletionFailure.appleRevokeFailed() =
      AccountDeletionAppleRevokeFailedFailure;

  /// The Edge Function's own `apple_revocation_marker_failed` code (Issue
  /// #599): Apple confirmed the revocation itself - unlike
  /// [AccountDeletionFailure.appleRevokeFailed] - but the server's own
  /// durable record of that (retried once server-side) could not be
  /// written. Distinct from [AccountDeletionFailure.appleRevokeFailed]
  /// because its copy's "Apple could not confirm the revocation" claim
  /// would be false here; distinct from
  /// [AccountDeletionFailure.deleteUserFailed] because `deleteUser` was
  /// never even attempted.
  const factory AccountDeletionFailure.appleRevocationMarkerFailed() =
      AccountDeletionAppleRevocationMarkerFailedFailure;

  /// The Edge Function's own `attachment_cleanup_failed` code (Issue #243
  /// round 2 fix, 2026-09-08): the caller's feedback-attachments Storage
  /// listing or removal failed. This step now runs *before* the
  /// destructive `delete_account_data()` RPC and Apple revocation (the same
  /// reordering rationale as [AccountDeletionFailure.appleCodeRequired]),
  /// so unlike [AccountDeletionFailure.appleRevokeFailed] nothing was
  /// touched at all when this fires - no row, no Apple grant, no
  /// `auth.users` row. The operator just needs to retry.
  const factory AccountDeletionFailure.attachmentCleanupFailed() =
      AccountDeletionAttachmentCleanupFailedFailure;

  /// The Edge Function's own `attachment_cleanup_unbounded` code (Issue
  /// #559; Issue #605/LLA-053): the caller's own feedback-attachments
  /// Storage listing exceeded the server's object-count or depth bound. This
  /// is a bound on that account's *own* data, not a transient I/O hiccup
  /// like [AccountDeletionFailure.attachmentCleanupFailed] - retrying the
  /// exact same delete call can never succeed, since nothing about the
  /// account's attachments changes on its own. Nothing was touched at all
  /// (this step runs before the destructive RPC), so - like
  /// [AccountDeletionFailure.appleCodeRequired] and
  /// [AccountDeletionFailure.attachmentCleanupFailed] - the account, its
  /// rows, and this device's data are all still intact. Gets its own
  /// terminal, support-routed copy rather than falling through to
  /// [AccountDeletionFailure.unknown]'s "please try again", which would be
  /// actively misleading here.
  const factory AccountDeletionFailure.attachmentCleanupUnbounded() =
      AccountDeletionAttachmentCleanupUnboundedFailure;

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

/// See [AccountDeletionFailure.appleCodeRequired].
final class AccountDeletionAppleCodeRequiredFailure
    extends AccountDeletionFailure {
  const AccountDeletionAppleCodeRequiredFailure();

  @override
  String toString() => 'AccountDeletionFailure.appleCodeRequired';
}

/// See [AccountDeletionFailure.appleNativeCeremonyUnavailable].
final class AccountDeletionAppleNativeCeremonyUnavailableFailure
    extends AccountDeletionFailure {
  const AccountDeletionAppleNativeCeremonyUnavailableFailure();

  @override
  String toString() => 'AccountDeletionFailure.appleNativeCeremonyUnavailable';
}

/// See [AccountDeletionFailure.appleRevokeFailed].
final class AccountDeletionAppleRevokeFailedFailure
    extends AccountDeletionFailure {
  const AccountDeletionAppleRevokeFailedFailure();

  @override
  String toString() => 'AccountDeletionFailure.appleRevokeFailed';
}

/// See [AccountDeletionFailure.appleRevocationMarkerFailed].
final class AccountDeletionAppleRevocationMarkerFailedFailure
    extends AccountDeletionFailure {
  const AccountDeletionAppleRevocationMarkerFailedFailure();

  @override
  String toString() => 'AccountDeletionFailure.appleRevocationMarkerFailed';
}

/// See [AccountDeletionFailure.attachmentCleanupFailed].
final class AccountDeletionAttachmentCleanupFailedFailure
    extends AccountDeletionFailure {
  const AccountDeletionAttachmentCleanupFailedFailure();

  @override
  String toString() => 'AccountDeletionFailure.attachmentCleanupFailed';
}

/// See [AccountDeletionFailure.attachmentCleanupUnbounded].
final class AccountDeletionAttachmentCleanupUnboundedFailure
    extends AccountDeletionFailure {
  const AccountDeletionAttachmentCleanupUnboundedFailure();

  @override
  String toString() => 'AccountDeletionFailure.attachmentCleanupUnbounded';
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
