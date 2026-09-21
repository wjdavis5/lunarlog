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
  /// Issue #1003: `coManager` is the `co_parent` role, so it reads as the
  /// canonical "Co-Parent" label the rest of the app uses — never
  /// "Co-manager".
  String get label => switch (this) {
    ParentPostTransferRole.coManager => 'Co-Parent',
    ParentPostTransferRole.viewer => 'Viewer',
  };

  /// Inverse of [toDb]. Returns `null` for anything else rather than
  /// throwing, matching `ProfileRelationship.fromDb`'s tolerant-unknown-value
  /// convention (used by [SupabaseOwnershipTransferService.getActiveTransfer]
  /// when decoding a row read directly off `ownership_transfers`).
  static ParentPostTransferRole? fromDb(String value) => switch (value) {
    'co_parent' => ParentPostTransferRole.coManager,
    'viewer' => ParentPostTransferRole.viewer,
    _ => null,
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
  /// `lunarlog://invite?code=<rawToken>&profile=<profileId>&kind=claim`,
  /// or the `https://<domain>/invite?...` universal-link form when a hosted
  /// domain is configured (issue #129).
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

/// A still-live transfer for a profile, as read back directly from
/// `ownership_transfers` rather than returned by `createTransfer` (Review
/// item #2, P1). The raw token is never stored server-side, so this cannot
/// carry a working [GeneratedTransfer.claimUri] — it exists so a parent whose
/// earlier `createTransfer` response never reached their device (a dropped
/// connection, or the app restarting between the RPC committing and the
/// response arriving) can still discover and [OwnershipTransferService.cancelTransfer]
/// the orphaned transfer, rather than being locked out of the feature for up
/// to its full TTL by `create_ownership_transfer`'s one-live-transfer
/// constraint.
@immutable
class ActiveTransfer {
  const ActiveTransfer({
    required this.transferId,
    required this.profileId,
    required this.parentPostTransferRole,
    required this.expiresAt,
    this.recipientLabel,
  });

  final String transferId;
  final String profileId;
  final ParentPostTransferRole parentPostTransferRole;
  final DateTime expiresAt;
  final String? recipientLabel;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActiveTransfer &&
          other.transferId == transferId &&
          other.profileId == profileId &&
          other.parentPostTransferRole == parentPostTransferRole &&
          other.expiresAt == expiresAt &&
          other.recipientLabel == recipientLabel;

  @override
  int get hashCode => Object.hash(
    transferId,
    profileId,
    parentPostTransferRole,
    expiresAt,
    recipientLabel,
  );
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
  const factory TransferFailure.alreadyAccepted() =
      TransferAlreadyAcceptedFailure;
  const factory TransferFailure.selfTransfer() = TransferSelfTransferFailure;
  const factory TransferFailure.staleOwner() = TransferStaleOwnerFailure;
  const factory TransferFailure.alreadyArmed() = TransferAlreadyArmedFailure;
  const factory TransferFailure.unauthorized() = TransferUnauthorizedFailure;
  const factory TransferFailure.invalidToken() = TransferInvalidTokenFailure;
  const factory TransferFailure.other() = TransferOtherFailure;

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class TransferNetworkFailure extends TransferFailure {
  const TransferNetworkFailure();
  @override
  String toString() => 'TransferFailure.network';
}

final class TransferNotFoundFailure extends TransferFailure {
  const TransferNotFoundFailure();
  @override
  String toString() => 'TransferFailure.notFound';
}

final class TransferExpiredFailure extends TransferFailure {
  const TransferExpiredFailure();
  @override
  String toString() => 'TransferFailure.expired';
}

final class TransferCancelledFailure extends TransferFailure {
  const TransferCancelledFailure();
  @override
  String toString() => 'TransferFailure.cancelled';
}

final class TransferAlreadyAcceptedFailure extends TransferFailure {
  const TransferAlreadyAcceptedFailure();
  @override
  String toString() => 'TransferFailure.alreadyAccepted';
}

final class TransferSelfTransferFailure extends TransferFailure {
  const TransferSelfTransferFailure();
  @override
  String toString() => 'TransferFailure.selfTransfer';
}

final class TransferStaleOwnerFailure extends TransferFailure {
  const TransferStaleOwnerFailure();
  @override
  String toString() => 'TransferFailure.staleOwner';
}

/// Review item #2 (P1): `create_ownership_transfer`'s one-live-transfer
/// constraint (23505) means a still-live transfer already exists for this
/// profile — either genuinely pending, or orphaned by a lost response to an
/// earlier `createTransfer` call. [OwnershipTransferService.getActiveTransfer]
/// finds it so the parent can cancel it rather than being stuck for up to
/// its full TTL.
final class TransferAlreadyArmedFailure extends TransferFailure {
  const TransferAlreadyArmedFailure();
  @override
  String toString() => 'TransferFailure.alreadyArmed';
}

final class TransferUnauthorizedFailure extends TransferFailure {
  const TransferUnauthorizedFailure();
  @override
  String toString() => 'TransferFailure.unauthorized';
}

final class TransferInvalidTokenFailure extends TransferFailure {
  const TransferInvalidTokenFailure();
  @override
  String toString() => 'TransferFailure.invalidToken';
}

/// Catch-all failure. Fieldless like the other nine variants (issue #552):
/// [TransferFailure]'s inherited `operator==` compares only `runtimeType`,
/// so a variant carrying a payload the operator never sees would make two
/// unrelated diagnoses compare equal — every distinct diagnostic instead
/// goes to a breadcrumb at its own throw site in
/// `supabase_ownership_transfer_service.dart` (`_mapError`, `_mapPostgrestError`,
/// `_mapInvalidParameter`, and the two `unexpected ... shape` sites), never
/// shown to the operator. User-facing copy for this failure lives in
/// `lib/ui/l10n/transfer_failure_copy.dart` (Issue #545) — the domain layer
/// itself never hardcodes English (mirrors the no-raw-error rule the old
/// `userFacingMessage` getter followed).
final class TransferOtherFailure extends TransferFailure {
  const TransferOtherFailure();

  @override
  String toString() => 'TransferFailure.other';
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

  /// Returns the still-live transfer for [profileId], if any (Review item
  /// #2, P1) — read directly off `ownership_transfers` rather than tracked
  /// client-side, so it survives a lost `createTransfer` response, an app
  /// restart, or opening the transfer screen on a different device. `null`
  /// when no transfer is currently armed for this profile.
  Future<ActiveTransfer?> getActiveTransfer({required String profileId});

  /// Claims a transfer using the [rawToken], making the presenting signed-in
  /// user the profile's new owner (R11).
  Future<ClaimedProfileResult> claimProfile({
    required String rawToken,
    String? childDisplayName,
    String? parentDisplayName,
  });
}
