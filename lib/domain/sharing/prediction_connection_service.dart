/// Domain interface for prediction-only connections (issue #151): a
/// primary guardian shares derived cycle phases only — never the
/// underlying day sheet — with exactly one recipient per profile.
///
/// Deliberately NOT part of [SharingService] or the `GuardianRole` ladder:
/// this is a grant mechanism of its own whose server table
/// (`prediction_connections`) sits outside `profile_guardians`, so a
/// future widening of guardian-role permissions can never widen this
/// relationship by accident. The recipient gains exactly one read path —
/// the projection RPC — and no sync surface of any kind.
///
/// Pure Dart: no Flutter and no Supabase types cross this boundary.
library;

import 'package:meta/meta.dart';

import 'prediction_projection.dart';

/// A freshly armed prediction-only invite.
@immutable
class GeneratedPredictionInvite {
  const GeneratedPredictionInvite({
    required this.connectionId,
    required this.profileId,
    required this.rawToken,
    required this.tokenHash,
    required this.inviteUri,
    required this.expiresAt,
  });

  final String connectionId;
  final String profileId;

  /// The high-entropy secret token (never stored server-side); delivered
  /// to the recipient out of band.
  final String rawToken;

  /// SHA-256 hex digest of [rawToken] — the only form the server holds.
  final String tokenHash;

  /// Deep link to redeem: `lunarlog://invite?code=<rawToken>&kind=prediction`.
  final Uri inviteUri;

  final DateTime expiresAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeneratedPredictionInvite &&
          other.connectionId == connectionId &&
          other.profileId == profileId &&
          other.rawToken == rawToken &&
          other.tokenHash == tokenHash &&
          other.inviteUri == inviteUri &&
          other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(
        connectionId,
        profileId,
        rawToken,
        tokenHash,
        inviteUri,
        expiresAt,
      );
}

/// The sharer-side view of their live connection (pending invite or
/// active share). Carries no token or hash — a screenshot of this row
/// must never be redeemable.
@immutable
class ActivePredictionConnection {
  const ActivePredictionConnection({
    required this.connectionId,
    required this.profileId,
    required this.pending,
    this.recipientLabel,
    required this.createdAt,
    required this.expiresAt,
  });

  final String connectionId;
  final String profileId;

  /// True while the invite is still unredeemed (the recipient column is
  /// null server-side); false once someone holds the share.
  final bool pending;

  /// The optional label the sharer typed when arming the invite.
  final String? recipientLabel;

  final DateTime createdAt;
  final DateTime expiresAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivePredictionConnection &&
          other.connectionId == connectionId &&
          other.profileId == profileId &&
          other.pending == pending &&
          other.recipientLabel == recipientLabel &&
          other.createdAt == createdAt &&
          other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(
        connectionId,
        profileId,
        pending,
        recipientLabel,
        createdAt,
        expiresAt,
      );
}

/// The recipient-side view of a connection they hold.
@immutable
class IncomingPredictionConnection {
  const IncomingPredictionConnection({
    required this.connectionId,
    required this.profileId,
    required this.acceptedAt,
  });

  final String connectionId;

  /// The shared profile's id — the projection is fetched per profile.
  final String profileId;

  final DateTime acceptedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IncomingPredictionConnection &&
          other.connectionId == connectionId &&
          other.profileId == profileId &&
          other.acceptedAt == acceptedAt;

  @override
  int get hashCode => Object.hash(connectionId, profileId, acceptedAt);
}

/// Result of redeeming an invite: the shared profile's id (for the
/// projection fetch) and its display name (for the calendar's title).
@immutable
class AcceptedPredictionConnection {
  const AcceptedPredictionConnection({
    required this.connectionId,
    required this.profileId,
    required this.profileName,
  });

  final String connectionId;
  final String profileId;
  final String profileName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcceptedPredictionConnection &&
          other.connectionId == connectionId &&
          other.profileId == profileId &&
          other.profileName == profileName;

  @override
  int get hashCode => Object.hash(connectionId, profileId, profileName);
}

/// Typed failures for prediction-connection operations. Mirrors
/// [SharingFailure]'s shape; the server's distinct reasons (pregnancy
/// mode, the one-connection cap, the one-directional rule) each get their
/// own case so the UI can name them.
@immutable
sealed class PredictionConnectionFailure implements Exception {
  const PredictionConnectionFailure();

  const factory PredictionConnectionFailure.network() =
      _PredictionNetworkFailure;
  const factory PredictionConnectionFailure.notFound() =
      _PredictionNotFoundFailure;
  const factory PredictionConnectionFailure.expired() =
      _PredictionExpiredFailure;
  const factory PredictionConnectionFailure.alreadyAccepted() =
      _PredictionAlreadyAcceptedFailure;
  const factory PredictionConnectionFailure.alreadyGuardian() =
      _PredictionAlreadyGuardianFailure;
  const factory PredictionConnectionFailure.unauthorized() =
      _PredictionUnauthorizedFailure;
  const factory PredictionConnectionFailure.invalidToken() =
      _PredictionInvalidTokenFailure;
  const factory PredictionConnectionFailure.pregnancyMode() =
      _PredictionPregnancyModeFailure;
  const factory PredictionConnectionFailure.alreadyConnected() =
      _PredictionAlreadyConnectedFailure;
  const factory PredictionConnectionFailure.oneDirectional() =
      _PredictionOneDirectionalFailure;
  const factory PredictionConnectionFailure.minorProfile() =
      _PredictionMinorProfileFailure;
  const factory PredictionConnectionFailure.other() = _PredictionOtherFailure;

  String get userFacingMessage;

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class _PredictionNetworkFailure extends PredictionConnectionFailure {
  const _PredictionNetworkFailure();
  @override
  String get userFacingMessage => 'Network error. Please check your connection.';
  @override
  String toString() => 'PredictionConnectionFailure.network';
}

final class _PredictionNotFoundFailure extends PredictionConnectionFailure {
  const _PredictionNotFoundFailure();
  @override
  String get userFacingMessage => 'That code is not valid.';
  @override
  String toString() => 'PredictionConnectionFailure.notFound';
}

final class _PredictionExpiredFailure extends PredictionConnectionFailure {
  const _PredictionExpiredFailure();
  @override
  String get userFacingMessage => 'That code has expired.';
  @override
  String toString() => 'PredictionConnectionFailure.expired';
}

final class _PredictionAlreadyAcceptedFailure
    extends PredictionConnectionFailure {
  const _PredictionAlreadyAcceptedFailure();
  @override
  String get userFacingMessage => 'That code was already used.';
  @override
  String toString() => 'PredictionConnectionFailure.alreadyAccepted';
}

final class _PredictionAlreadyGuardianFailure
    extends PredictionConnectionFailure {
  const _PredictionAlreadyGuardianFailure();
  @override
  String get userFacingMessage =>
      'You already have full guardian access to this profile.';
  @override
  String toString() => 'PredictionConnectionFailure.alreadyGuardian';
}

final class _PredictionUnauthorizedFailure extends PredictionConnectionFailure {
  const _PredictionUnauthorizedFailure();
  @override
  String get userFacingMessage => 'You do not have permission for this action.';
  @override
  String toString() => 'PredictionConnectionFailure.unauthorized';
}

final class _PredictionInvalidTokenFailure
    extends PredictionConnectionFailure {
  const _PredictionInvalidTokenFailure();
  @override
  String get userFacingMessage => 'Invalid connection code.';
  @override
  String toString() => 'PredictionConnectionFailure.invalidToken';
}

final class _PredictionPregnancyModeFailure
    extends PredictionConnectionFailure {
  const _PredictionPregnancyModeFailure();
  @override
  String get userFacingMessage =>
      'Prediction sharing is unavailable while this profile is in '
      'Pregnancy mode.';
  @override
  String toString() => 'PredictionConnectionFailure.pregnancyMode';
}

final class _PredictionAlreadyConnectedFailure
    extends PredictionConnectionFailure {
  const _PredictionAlreadyConnectedFailure();
  @override
  String get userFacingMessage =>
      'This profile already has a prediction connection. Revoke it before '
      'sharing with someone else.';
  @override
  String toString() => 'PredictionConnectionFailure.alreadyConnected';
}

final class _PredictionOneDirectionalFailure
    extends PredictionConnectionFailure {
  const _PredictionOneDirectionalFailure();
  @override
  String get userFacingMessage =>
      'You cannot share and view predictions with the same person at the '
      'same time.';
  @override
  String toString() => 'PredictionConnectionFailure.oneDirectional';
}

/// Issue #373: PRIVACY.md's "minor profiles are never shared" rule, which
/// the server enforces at create AND at accept (`is_minor` can change
/// between arming a code and its redemption, like the life-stage mode).
final class _PredictionMinorProfileFailure
    extends PredictionConnectionFailure {
  const _PredictionMinorProfileFailure();
  @override
  String get userFacingMessage =>
      "Prediction sharing is not available for a minor's profile.";
  @override
  String toString() => 'PredictionConnectionFailure.minorProfile';
}

final class _PredictionOtherFailure extends PredictionConnectionFailure {
  const _PredictionOtherFailure();
  @override
  String get userFacingMessage =>
      'Something went wrong. Please try again.';
  @override
  String toString() => 'PredictionConnectionFailure.other';
}

/// Contract for prediction-only connections (issue #151). The sharer's
/// operations arm/revoke; the recipient's redeem and read the projection.
abstract interface class PredictionConnectionService {
  /// Arms a new invite for [profileId]. Server-side this is primary
  /// guardian only, refused in Pregnancy mode, and capped at one live
  /// (pending or active) connection per profile — [ttl] is bounded by the
  /// server to 1..168 hours regardless of what is asked for here.
  Future<GeneratedPredictionInvite> createConnection({
    required String profileId,
    String? recipientLabel,
    Duration ttl = const Duration(hours: 72),
  });

  /// Redeems [rawToken] on the signed-in account. Single-use.
  Future<AcceptedPredictionConnection> acceptConnection({
    required String rawToken,
  });

  /// Revokes the connection. The sharer or the profile's current primary
  /// guardian may call it; idempotent; the recipient's next fetch already
  /// returns nothing.
  Future<void> revokeConnection({required String connectionId});

  /// The sharer's live (pending or active) connection for [profileId], or
  /// null. Read on demand from the server — never synced locally.
  Future<ActivePredictionConnection?> getActiveConnection({
    required String profileId,
  });

  /// The profile ids the signed-in account currently shares predictions
  /// for (the projection publisher only uploads for these).
  Future<Set<String>> outgoingConnectedProfileIds();

  /// The connections the signed-in account receives (the recipient's list
  /// screen). Read on demand — never synced locally.
  Future<List<IncomingPredictionConnection>> listIncomingConnections();

  /// The recipient's (or a guardian's) read of the shared profile's
  /// derived phases. Null when there is no live connection or nothing
  /// has been published yet — an unauthorized caller and an unshared
  /// profile are indistinguishable.
  Future<PredictionProjection?> fetchProjection({required String profileId});

  /// Publishes [projection] for [profileId]. Server-side this is a no-op
  /// (which also deletes any stale snapshot) unless an active connection
  /// exists, so a publish racing a revocation can never leave derived
  /// data behind.
  Future<void> publishProjection({
    required String profileId,
    required PredictionProjection projection,
  });
}
