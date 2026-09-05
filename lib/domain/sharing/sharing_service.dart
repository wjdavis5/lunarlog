/// Domain interface and data models for guardian invitations and membership sharing.
///
/// Pure Dart: no Flutter and no Supabase types cross this boundary.
library;

import 'package:meta/meta.dart';

import '../models/profile_guardian.dart';

/// Representation of a freshly created guardian invitation.
@immutable
class GeneratedInvite {
  const GeneratedInvite({
    required this.invitationId,
    required this.profileId,
    required this.role,
    required this.rawToken,
    required this.tokenHash,
    required this.inviteUri,
    required this.expiresAt,
  });

  final String invitationId;
  final String profileId;
  final GuardianRole role;

  /// The high-entropy secret token (not stored on the server).
  final String rawToken;

  /// SHA-256 hex digest of [rawToken] stored on the server.
  final String tokenHash;

  /// Deep link URI to redeem this invite: `lunarlog://invite?code=<rawToken>&profile=<profileId>`.
  final Uri inviteUri;

  final DateTime expiresAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeneratedInvite &&
          _sameInviteIdentity(other) &&
          _sameInviteContent(other);

  bool _sameInviteIdentity(GeneratedInvite other) =>
      other.invitationId == invitationId &&
      other.profileId == profileId &&
      other.role == role;

  bool _sameInviteContent(GeneratedInvite other) =>
      other.rawToken == rawToken &&
      other.tokenHash == tokenHash &&
      other.inviteUri == inviteUri &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(
        invitationId,
        profileId,
        role,
        rawToken,
        tokenHash,
        inviteUri,
        expiresAt,
      );
}

/// Result returned upon accepting an invitation.
@immutable
class AcceptedInviteResult {
  const AcceptedInviteResult({
    required this.profileId,
    required this.profileName,
    required this.role,
  });

  final String profileId;
  final String profileName;
  final GuardianRole role;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcceptedInviteResult &&
          runtimeType == other.runtimeType &&
          profileId == other.profileId &&
          profileName == other.profileName &&
          role == other.role;

  @override
  int get hashCode => Object.hash(profileId, profileName, role);
}

/// Typed failures for sharing and invitation operations.
@immutable
sealed class SharingFailure implements Exception {
  const SharingFailure();

  const factory SharingFailure.network() = SharingNetworkFailure;
  const factory SharingFailure.notFound() = SharingNotFoundFailure;
  const factory SharingFailure.expired() = SharingExpiredFailure;
  const factory SharingFailure.alreadyAccepted() = SharingAlreadyAcceptedFailure;
  const factory SharingFailure.alreadyGuardian() = SharingAlreadyGuardianFailure;
  const factory SharingFailure.unauthorized() = SharingUnauthorizedFailure;
  const factory SharingFailure.invalidToken() = SharingInvalidTokenFailure;
  const factory SharingFailure.other() = SharingOtherFailure;

  String get userFacingMessage;

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class SharingNetworkFailure extends SharingFailure {
  const SharingNetworkFailure();
  @override
  String get userFacingMessage => 'Network error. Please check your connection.';
  @override
  String toString() => 'SharingFailure.network';
}

final class SharingNotFoundFailure extends SharingFailure {
  const SharingNotFoundFailure();
  @override
  String get userFacingMessage => 'Invitation not found or invalid link.';
  @override
  String toString() => 'SharingFailure.notFound';
}

final class SharingExpiredFailure extends SharingFailure {
  const SharingExpiredFailure();
  @override
  String get userFacingMessage => 'This invitation has expired.';
  @override
  String toString() => 'SharingFailure.expired';
}

final class SharingAlreadyAcceptedFailure extends SharingFailure {
  const SharingAlreadyAcceptedFailure();
  @override
  String get userFacingMessage => 'This invitation was already accepted.';
  @override
  String toString() => 'SharingFailure.alreadyAccepted';
}

final class SharingAlreadyGuardianFailure extends SharingFailure {
  const SharingAlreadyGuardianFailure();
  @override
  String get userFacingMessage => 'You are already an active guardian for this child.';
  @override
  String toString() => 'SharingFailure.alreadyGuardian';
}

final class SharingUnauthorizedFailure extends SharingFailure {
  const SharingUnauthorizedFailure();
  @override
  String get userFacingMessage => 'You do not have permission for this action.';
  @override
  String toString() => 'SharingFailure.unauthorized';
}

final class SharingInvalidTokenFailure extends SharingFailure {
  const SharingInvalidTokenFailure();
  @override
  String get userFacingMessage => 'Invalid invitation link.';
  @override
  String toString() => 'SharingFailure.invalidToken';
}

final class SharingOtherFailure extends SharingFailure {
  const SharingOtherFailure();
  @override
  String get userFacingMessage => 'Failed to accept invitation. Please try again.';
  @override
  String toString() => 'SharingFailure.other';
}

/// Contract for managing guardian sharing and invitations.
abstract interface class SharingService {
  /// Generates a new invitation with a 256-bit cryptographically secure token.
  Future<GeneratedInvite> createInvite({
    required String profileId,
    required GuardianRole role,
    String? recipientLabel,
    Duration ttl = const Duration(hours: 48),
  });

  /// Redeems an invitation using the [rawToken].
  Future<AcceptedInviteResult> acceptInvite({
    required String rawToken,
    String? displayName,
  });

  /// Revokes an active guardian or removes oneself.
  Future<void> revokeGuardian({
    required String profileId,
    required String targetUserId,
  });
}
