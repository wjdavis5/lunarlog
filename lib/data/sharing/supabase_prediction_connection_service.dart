/// [PredictionConnectionService] implementation over Supabase RPCs (issue
/// #151), mirroring [SupabaseOwnershipTransferService] and
/// [SupabaseSharingService] line-for-line where the flows match.
///
/// Server contract (20260909200000_prediction_connections.sql): the token
/// hash is the only credential the server holds; `prediction_connections`
/// is readable by the sharer/primary guardian/active recipient with a
/// column grant that excludes token_hash, so every client SELECT here
/// names explicit columns and never references the hash (mirroring the
/// #114/#242 discipline); the projection flows through the two RPCs whose
/// payload the server allowlists to derived phases only.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/sharing/prediction_connection_service.dart';
import '../../domain/sharing/prediction_projection.dart';

class SupabasePredictionConnectionService
    implements PredictionConnectionService {
  SupabasePredictionConnectionService({required this.client, Random? random})
      : _random = random ?? Random.secure();

  final SupabaseClient client;
  final Random _random;

  @override
  Future<GeneratedPredictionInvite> createConnection({
    required String profileId,
    String? recipientLabel,
    Duration ttl = const Duration(hours: 72),
  }) async {
    // 1. 32 bytes (256 bits) of secure random entropy, as the other
    //    invite flows use.
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final rawToken = base64UrlEncode(bytes).replaceAll('=', '');

    // 2. SHA-256 hex; the plaintext never leaves this device except via
    //    the invite link the sharer delivers out of band.
    final tokenHash = sha256.convert(utf8.encode(rawToken)).toString();

    try {
      final res = await client.rpc<dynamic>(
        'create_prediction_connection',
        params: {
          'p_profile_id': profileId,
          'p_token_hash': tokenHash,
          'p_recipient_label': recipientLabel,
          'p_ttl_hours': ttl.inHours,
        },
      );

      if (res is! Map) {
        throw const PredictionConnectionFailure.other();
      }

      final id = res['id'] as String;
      final expiresAt = DateTime.parse(res['expires_at'] as String).toUtc();

      return GeneratedPredictionInvite(
        connectionId: id,
        profileId: profileId,
        rawToken: rawToken,
        tokenHash: tokenHash,
        inviteUri: Uri(
          scheme: 'lunarlog',
          host: 'invite',
          queryParameters: {
            'code': rawToken,
            'kind': 'prediction',
          },
        ),
        expiresAt: expiresAt,
      );
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<AcceptedPredictionConnection> acceptConnection({
    required String rawToken,
  }) async {
    final tokenHash = sha256.convert(utf8.encode(rawToken)).toString();

    try {
      final res = await client.rpc<dynamic>(
        'accept_prediction_connection',
        params: {'p_token_hash': tokenHash},
      );

      if (res is! Map) {
        throw const PredictionConnectionFailure.other();
      }

      return AcceptedPredictionConnection(
        connectionId: res['connection_id'] as String,
        profileId: res['profile_id'] as String,
        profileName: res['profile_name'] as String,
      );
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<void> revokeConnection({required String connectionId}) async {
    try {
      await client.rpc<dynamic>(
        'revoke_prediction_connection',
        params: {'p_connection_id': connectionId},
      );
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<ActivePredictionConnection?> getActiveConnection({
    required String profileId,
  }) async {
    try {
      // Explicit column list: token_hash is not even readable by
      // authenticated (#114/#242), so referencing it here would fail the
      // request; keeping the list explicit makes that permanent.
      final rows = await client
          .from('prediction_connections')
          .select(
              'id, profile_id, recipient_user_id, recipient_label, created_at, expires_at')
          .eq('profile_id', profileId)
          .isFilter('revoked_at', null)
          .order('created_at', ascending: false);
      // No .limit(): prediction_connections_one_live_uq guarantees at most
      // one non-revoked row per profile, so the client-side first-take is
      // the whole list.

      if (rows.isEmpty) return null;
      final row = rows.first;
      return ActivePredictionConnection(
        connectionId: row['id'] as String,
        profileId: row['profile_id'] as String,
        pending: row['recipient_user_id'] == null,
        recipientLabel: row['recipient_label'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
        expiresAt: DateTime.parse(row['expires_at'] as String).toUtc(),
      );
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<Set<String>> outgoingConnectedProfileIds() async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) return const {};
    try {
      // Explicit owner filter: the SELECT policy also admits a primary
      // guardian and (for their own rows) the recipient, so direction must
      // be pinned client-side — the publisher only uploads for profiles
      // this account shares OUT.
      final rows = await client
          .from('prediction_connections')
          .select('profile_id')
          .eq('owner_user_id', uid)
          .isFilter('revoked_at', null)
          .not('recipient_user_id', 'is', null);
      return {
        for (final row in rows) row['profile_id'] as String,
      };
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<List<IncomingPredictionConnection>> listIncomingConnections() async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) return const [];
    try {
      // Same direction pin, incoming side: only rows this account is the
      // named recipient of (an active, unrevoked connection — the policy's
      // recipient branch filters revoked rows, and the explicit filter
      // keeps a guardian's own shares off this list).
      final rows = await client
          .from('prediction_connections')
          .select('id, profile_id, accepted_at')
          .eq('recipient_user_id', uid)
          .order('accepted_at', ascending: true);
      return [
        for (final row in rows)
          IncomingPredictionConnection(
            connectionId: row['id'] as String,
            profileId: row['profile_id'] as String,
            acceptedAt: DateTime.parse(row['accepted_at'] as String).toUtc(),
          ),
      ];
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<PredictionProjection?> fetchProjection({
    required String profileId,
  }) async {
    try {
      final res = await client.rpc<dynamic>(
        'get_prediction_projection',
        params: {'p_profile_id': profileId},
      );
      // Null: no live connection, nothing published yet, or not eligible —
      // all indistinguishable by design.
      if (res == null) return null;
      if (res is! Map) {
        throw const PredictionConnectionFailure.other();
      }
      return PredictionProjection.fromJson(Map<String, dynamic>.from(res));
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<void> publishProjection({
    required String profileId,
    required PredictionProjection projection,
  }) async {
    try {
      await client.rpc<dynamic>(
        'upsert_prediction_projection',
        params: {
          'p_profile_id': profileId,
          'p_projection': projection.toJson(),
        },
      );
    } catch (e) {
      throw _mapError(e);
    }
  }

  PredictionConnectionFailure _mapError(Object error) {
    if (error is PredictionConnectionFailure) return error;
    if (error is SocketException || error is http.ClientException) {
      return const PredictionConnectionFailure.network();
    }
    if (error is PostgrestException) {
      return _mapPostgrestError(error);
    }
    return const PredictionConnectionFailure.other();
  }

  PredictionConnectionFailure _mapPostgrestError(PostgrestException error) {
    final msg = error.message.toLowerCase();
    final code = error.code ?? '';

    if (code == 'PGRST301' || code == '42501' || msg.contains('permission')) {
      return const PredictionConnectionFailure.unauthorized();
    }
    final business = _mapBusinessError(code, msg);
    if (business != null) return business;
    final status = int.tryParse(code);
    if (status != null && status >= 500) {
      return const PredictionConnectionFailure.network();
    }
    return const PredictionConnectionFailure.other();
  }

  // Ordered substring -> failure lookup, checked before the code-based
  // mapping (the SupabaseOwnershipTransferService pattern).
  static const Map<String, PredictionConnectionFailure> _messageFailures = {
    'not found': PredictionConnectionFailure.notFound(),
    'already accepted': PredictionConnectionFailure.alreadyAccepted(),
    'has expired': PredictionConnectionFailure.expired(),
    'you are already a guardian': PredictionConnectionFailure.alreadyGuardian(),
    'pregnancy mode': PredictionConnectionFailure.pregnancyMode(),
    'already has a prediction-only connection':
        PredictionConnectionFailure.alreadyConnected(),
    'cannot share and view':
        PredictionConnectionFailure.oneDirectional(),
    // Issue #373: the server's is_minor gate (create AND accept).
    "for a minor's profile": PredictionConnectionFailure.minorProfile(),
    'token_hash': PredictionConnectionFailure.invalidToken(),
  };

  PredictionConnectionFailure? _mapBusinessError(
      String code, String msg) {
    if (code == 'P0002') {
      return const PredictionConnectionFailure.notFound();
    }
    if (code == '23505') {
      return const PredictionConnectionFailure.alreadyConnected();
    }
    if (code == '22023' && msg.contains('token')) {
      return const PredictionConnectionFailure.invalidToken();
    }
    for (final entry in _messageFailures.entries) {
      if (msg.contains(entry.key)) return entry.value;
    }
    return null;
  }
}
