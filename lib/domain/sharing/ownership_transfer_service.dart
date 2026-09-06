/// Domain interface and data models for arming, cancelling, and claiming a
/// child-profile ownership transfer (Issue #4, U6).
///
/// Pure Dart: no Flutter and no Supabase types cross this boundary. The
/// Supabase-backed implementation (U7) sits on top of this interface and the
/// `create_ownership_transfer` / `cancel_ownership_transfer` /
/// `accept_ownership_transfer` RPCs.
library;

import 'package:meta/meta.dart';

/// The role the arming parent keeps for themselves once the transfer is
/// claimed (R7): they must choose to stay on as a co-manager or step down to
/// read-only.
enum ParentPostTransferRole {
  coManager,
  viewer;

  /// The exact string the server's `profile_guardians.role` check constraint
  /// accepts.
  String toDb() => switch (this) {
        ParentPostTransferRole.coManager => 'co_parent',
        ParentPostTransferRole.viewer => 'viewer',
      };

  /// Human-readable label for the role picker shown when arming a transfer.
  String get label => switch (this) {
        ParentPostTransferRole.coManager => 'Co-manager',
        ParentPostTransferRole.viewer => 'Viewer',
      };
}

/// Representation of a freshly armed ownership transfer.
@immutable
class GeneratedTransfer {
  const GeneratedTransfer({
    required this.transferId,
    required this.profileId,
    required this.parentPostTransferRole,
    required this.rawToken,
    required this.tokenHash,
    required this.claimUri,
    required this.expiresAt,
  });

  final String transferId;
  final String profileId;

  /// The role the arming parent chose to keep for themselves (R7).
  final ParentPostTransferRole parentPostTransferRole;

  /// The high-entropy secret token (not stored on the server).
  final String rawToken;

  /// SHA-256 hex digest of [rawToken] stored on the server.
  final String tokenHash;

  /// Deep link URI to claim this transfer:
  /// `lunarlog://invite?code=<rawToken>&profile=<profileId>&kind=claim`.
  final Uri claimUri;

  final DateTime expiresAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeneratedTransfer &&
          _sameTransferIdentity(other) &&
          _sameTransferContent(other);

  bool _sameTransferIdentity(GeneratedTransfer other) =>
      other.transferId == transferId &&
      other.profileId == profileId &&
      other.parentPostTransferRole == parentPostTransferRole;

  bool _sameTransferContent(GeneratedTransfer other) =>
      other.rawToken == rawToken &&
      other.tokenHash == tokenHash &&
      other.claimUri == claimUri &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(
        transferId,
        profileId,
        parentPostTransferRole,
        rawToken,
        tokenHash,
        claimUri,
        expiresAt,
      );
}

/// Result returned upon claiming a transfer (R11): the presenting user
/// becomes the profile's owner.
@immutable
class ClaimedProfileResult {
  const ClaimedProfileResult({
    required this.profileId,
    required this.profileName,
    required this.parentRole,
    required this.entriesTransferred,
  });

  final String profileId;
  final String profileName;

  /// The arming parent's resulting role, as returned by the RPC (e.g.
  /// `'co_parent'`/`'viewer'`).
  final String parentRole;

  final int entriesTransferred;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClaimedProfileResult &&
          runtimeType == other.runtimeType &&
          profileId == other.profileId &&
          profileName == other.profileName &&
          parentRole == other.parentRole &&
          entriesTransferred == other.entriesTransferred;

  @override
  int get hashCode =>
      Object.hash(profileId, profileName, parentRole, entriesTransferred);
}

/// Typed failures for ownership transfer operations (R20: an expired,
/// cancelled, already-accepted, or self-presented token must be refused with
/// a distinguishable reason).
@immutable
sealed class TransferFailure implements Exception {
  const TransferFailure();

  const factory TransferFailure.network() = TransferNetworkFailure;
  const factory TransferFailure.notFound() = TransferNotFoundFailure;
  const factory TransferFailure.expired() = TransferExpiredFailure;
  const factory TransferFailure.cancelled() = TransferCancelledFailure;
  const factory TransferFailure.alreadyAccepted() = TransferAlreadyAcceptedFailure;
  const factory TransferFailure.selfTransfer() = TransferSelfTransferFailure;
  const factory TransferFailure.staleOwner() = TransferStaleOwnerFailure;
  const factory TransferFailure.unauthorized() = TransferUnauthorizedFailure;
  const factory TransferFailure.invalidToken() = TransferInvalidTokenFailure;
  const factory TransferFailure.other(String message) = TransferOtherFailure;

  String get userFacingMessage;

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class TransferNetworkFailure extends TransferFailure {
  const TransferNetworkFailure();
  @override
  String get userFacingMessage => 'Network error. Please check your connection.';
  @override
  String toString() => 'TransferFailure.network';
}

final class TransferNotFoundFailure extends TransferFailure {
  const TransferNotFoundFailure();
  @override
  String get userFacingMessage => 'Transfer not found or invalid link.';
  @override
  String toString() => 'TransferFailure.notFound';
}

final class TransferExpiredFailure extends TransferFailure {
  const TransferExpiredFailure();
  @override
  String get userFacingMessage => 'This transfer link has expired.';
  @override
  String toString() => 'TransferFailure.expired';
}

final class TransferCancelledFailure extends TransferFailure {
  const TransferCancelledFailure();
  @override
  String get userFacingMessage => 'This transfer was cancelled.';
  @override
  String toString() => 'TransferFailure.cancelled';
}

final class TransferAlreadyAcceptedFailure extends TransferFailure {
  const TransferAlreadyAcceptedFailure();
  @override
  String get userFacingMessage => 'This transfer was already accepted.';
  @override
  String toString() => 'TransferFailure.alreadyAccepted';
}

final class TransferSelfTransferFailure extends TransferFailure {
  const TransferSelfTransferFailure();
  @override
  String get userFacingMessage => "You can't claim a transfer you created yourself.";
  @override
  String toString() => 'TransferFailure.selfTransfer';
}

final class TransferStaleOwnerFailure extends TransferFailure {
  const TransferStaleOwnerFailure();
  @override
  String get userFacingMessage =>
      'Your role on this profile has changed, so this transfer is no longer valid.';
  @override
  String toString() => 'TransferFailure.staleOwner';
}

final class TransferUnauthorizedFailure extends TransferFailure {
  const TransferUnauthorizedFailure();
  @override
  String get userFacingMessage => 'You do not have permission for this action.';
  @override
  String toString() => 'TransferFailure.unauthorized';
}

final class TransferInvalidTokenFailure extends TransferFailure {
  const TransferInvalidTokenFailure();
  @override
  String get userFacingMessage => 'Invalid transfer link.';
  @override
  String toString() => 'TransferFailure.invalidToken';
}

/// Catch-all failure, carrying a diagnostic [message] that is never shown to
/// the operator (mirrors [TransferFailure.userFacingMessage]'s no-raw-error
/// rule) but is useful in logs and `toString`.
final class TransferOtherFailure extends TransferFailure {
  const TransferOtherFailure(this.message);

  final String message;

  @override
  String get userFacingMessage => 'Something went wrong. Please try again.';
  @override
  String toString() => 'TransferFailure.other: $message';
}

/// Contract for arming, cancelling, and claiming an ownership transfer.
abstract interface class OwnershipTransferService {
  /// Arms a new transfer with a 256-bit cryptographically secure token
  /// (R6: only the accepted primary guardian may call this, and only one
  /// live transfer may exist per profile at a time — both enforced server
  /// side).
  Future<GeneratedTransfer> createTransfer({
    required String profileId,
    required ParentPostTransferRole parentPostTransferRole,
    String? recipientLabel,
    Duration ttl = const Duration(hours: 72),
  });

  /// Cancels a live transfer (R9: only the arming parent may do this).
  Future<void> cancelTransfer({required String transferId});

  /// Claims a transfer using the [rawToken], making the presenting signed-in
  /// user the profile's new owner (R11).
  Future<ClaimedProfileResult> claimProfile({
    required String rawToken,
    String? childDisplayName,
    String? parentDisplayName,
  });
}
