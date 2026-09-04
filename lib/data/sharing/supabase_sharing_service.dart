/// [SharingService] implementation over Supabase RPCs (U5; KTD3).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/profile_guardian.dart';
import '../../domain/sharing/sharing_service.dart';
import '../../domain/sync/sync_engine.dart';

class SupabaseSharingService implements SharingService {
  SupabaseSharingService({
    required this.client,
    required this.syncEngine,
    Random? random,
  }) : _random = random ?? Random.secure();

  final SupabaseClient client;
  final SyncEngine syncEngine;
  final Random _random;

  @override
  Future<GeneratedInvite> createInvite({
    required String profileId,
    required GuardianRole role,
    String? recipientLabel,
    Duration ttl = const Duration(hours: 48),
  }) async {
    // 1. Generate 32 bytes of secure random entropy (256 bits).
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final rawToken = base64UrlEncode(bytes).replaceAll('=', '');

    // 2. Compute SHA-256 hash in hex format.
    final tokenHash = sha256.convert(utf8.encode(rawToken)).toString();

    // 3. Call Supabase RPC create_guardian_invitation.
    try {
      final res = await client.rpc<dynamic>('create_guardian_invitation', params: {
        'p_profile_id': profileId,
        'p_role': role.toDb(),
        'p_recipient_label': recipientLabel,
        'p_token_hash': tokenHash,
        'p_ttl_hours': ttl.inHours,
      });

      if (res is! Map) {
        throw const SharingFailure.other();
      }

      final id = res['id'] as String;
      final expiresAtStr = res['expires_at'] as String;
      final expiresAt = DateTime.parse(expiresAtStr).toUtc();

      final inviteUri = Uri(
        scheme: 'lunarlog',
        host: 'invite',
        queryParameters: {
          'code': rawToken,
          'profile': profileId,
        },
      );

      return GeneratedInvite(
        invitationId: id,
        profileId: profileId,
        role: role,
        rawToken: rawToken,
        tokenHash: tokenHash,
        inviteUri: inviteUri,
        expiresAt: expiresAt,
      );
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<AcceptedInviteResult> acceptInvite({
    required String rawToken,
    String? displayName,
  }) async {
    final tokenHash = sha256.convert(utf8.encode(rawToken)).toString();

    try {
      final res = await client.rpc<dynamic>('accept_guardian_invitation', params: {
        'p_token_hash': tokenHash,
        'p_guardian_display_name': displayName,
      });

      if (res is! Map) {
        throw const SharingFailure.other();
      }

      final profileId = res['profile_id'] as String;
      final profileName = res['profile_name'] as String;
      final roleStr = res['role'] as String;
      final role = GuardianRole.fromDb(roleStr);

      // Trigger full reconcile so this client downloads the newly joined profile and entries.
      syncEngine.triggerFullReconcile();

      return AcceptedInviteResult(
        profileId: profileId,
        profileName: profileName,
        role: role,
      );
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<void> revokeGuardian({
    required String profileId,
    required String targetUserId,
  }) async {
    try {
      await client.rpc<dynamic>('revoke_guardian', params: {
        'p_profile_id': profileId,
        'p_target_user_id': targetUserId,
      });
      syncEngine.requestSync();
    } catch (e) {
      throw _mapError(e);
    }
  }

  SharingFailure _mapError(Object error) {
    if (error is SharingFailure) return error;
    if (error is SocketException || error is http.ClientException) {
      return const SharingFailure.network();
    }
    if (error is PostgrestException) {
      return _mapPostgrestError(error);
    }
    return const SharingFailure.other();
  }

  SharingFailure _mapPostgrestError(PostgrestException error) {
    final msg = error.message.toLowerCase();
    final code = error.code ?? '';

    if (_isUnauthorized(code, msg)) {
      return const SharingFailure.unauthorized();
    }
    final businessFailure = _mapBusinessError(code, msg);
    if (businessFailure != null) {
      return businessFailure;
    }
    final status = int.tryParse(code);
    if (status != null && status >= 500) {
      return const SharingFailure.network();
    }
    return const SharingFailure.other();
  }

  SharingFailure? _mapBusinessError(String code, String msg) {
    if (code == 'P0002' || msg.contains('not found')) {
      return const SharingFailure.notFound();
    }
    if (msg.contains('already accepted')) {
      return const SharingFailure.alreadyAccepted();
    }
    if (msg.contains('expired')) {
      return const SharingFailure.expired();
    }
    if (code == '23505' || msg.contains('already an active guardian')) {
      return const SharingFailure.alreadyGuardian();
    }
    if (code == '22023' || msg.contains('invalid') || msg.contains('token_hash')) {
      return const SharingFailure.invalidToken();
    }
    return null;
  }

  bool _isUnauthorized(String code, String msg) =>
      code == 'PGRST301' ||
      code == '42501' ||
      msg.contains('permission') ||
      msg.contains('unauthorized');
}
