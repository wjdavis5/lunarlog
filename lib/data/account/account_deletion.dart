/// In-app account deletion (U1; R14): the operator keeps a copy and deletes
/// the account without contacting anyone.
///
/// Order is the contract: the privileged server cascade runs first (online,
/// confirmed by the caller), then the Apple token revocation on a
/// best-effort basis (an email-only account skips it cleanly), and only then
/// the device reset to first-run through the root's one destructive path.
/// A server failure resets nothing: revocation and reset never run.
///
/// Failures are kinds only ([AccountDeletionError]) — never provider text,
/// never content (R18). The typed confirmation and the non-blocking
/// export-first offer live in the account UI, which calls [deleteAccount]
/// after both.
library;

import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:meta/meta.dart';

/// What went wrong while deleting the account. Fieldless by design.
@immutable
sealed class AccountDeletionError implements Exception {
  const AccountDeletionError();

  const factory AccountDeletionError.offline() = AccountDeletionOfflineError;

  const factory AccountDeletionError.notSignedIn() =
      AccountDeletionNotSignedInError;

  const factory AccountDeletionError.server() = AccountDeletionServerError;

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// The server could not be reached (offline, DNS, timeout). Nothing was
/// removed: the cascade never ran, so revocation and reset never started.
final class AccountDeletionOfflineError extends AccountDeletionError {
  const AccountDeletionOfflineError();

  @override
  String toString() => 'AccountDeletionError.offline';
}

/// No session exists; the cascade needs one. No server call was made.
final class AccountDeletionNotSignedInError extends AccountDeletionError {
  const AccountDeletionNotSignedInError();

  @override
  String toString() => 'AccountDeletionError.notSignedIn';
}

/// The cascade was reached but failed, or an unexpected failure escaped a
/// collaborator. The device was not reset.
final class AccountDeletionServerError extends AccountDeletionError {
  const AccountDeletionServerError();

  @override
  String toString() => 'AccountDeletionError.server';
}

/// The privileged server cascade (the `request_account_deletion` RPC over a
/// `SupabaseClient` in production, a recorder in tests). Throws
/// [AccountDeletionError].
typedef DeleteServerData = Future<void> Function();

/// Best-effort Apple token revocation. Any throw is swallowed: revocation
/// must never block the reset. Skipped entirely for non-Apple accounts.
typedef RevokeAppleToken = Future<void> Function();

/// The root's one destructive path to first-run.
typedef ResetDevice = Future<void> Function();

class AccountDeletionService {
  AccountDeletionService({
    required this.deleteServerData,
    required this.revokeAppleToken,
    required this.resetDevice,
  });

  final DeleteServerData deleteServerData;
  final RevokeAppleToken revokeAppleToken;
  final ResetDevice resetDevice;

  /// Deletes the account: cascade, then best-effort Apple revocation for
  /// Apple-linked accounts, then the device reset. Throws
  /// [AccountDeletionError].
  Future<void> deleteAccount({
    required bool signedIn,
    required List<String> providers,
  }) async {
    if (!signedIn) {
      throw const AccountDeletionError.notSignedIn();
    }
    try {
      await deleteServerData();
    } on AccountDeletionError {
      rethrow;
    } catch (_) {
      throw const AccountDeletionError.server();
    }
    if (providers.contains(AuthProviders.apple)) {
      try {
        await revokeAppleToken();
      } catch (_) {
        // Best effort only: a failed revocation never blocks the reset.
      }
    }
    await resetDevice();
  }
}
