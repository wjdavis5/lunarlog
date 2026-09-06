/// [OwnershipTransferService] implementation over Supabase RPCs (Issue #4,
/// U7), mirroring [SupabaseSharingService] (U5) almost line-for-line.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/sharing/ownership_transfer_service.dart';
import '../../domain/sync/sync_engine.dart';

class SupabaseOwnershipTransferService implements OwnershipTransferService {
  SupabaseOwnershipTransferService({
    required this.client,
    required this.syncEngine,
    Random? random,
  }) : _random = random ?? Random.secure();

  final SupabaseClient client;
  final SyncEngine syncEngine;
  final Random _random;

  @override
  Future<GeneratedTransfer> createTransfer({
    required String profileId,
    required ParentPostTransferRole parentPostTransferRole,
    String? recipientLabel,
    Duration ttl = const Duration(hours: 72),
  }) async {
    // 1. Generate 32 bytes of secure random entropy (256 bits).
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final rawToken = base64UrlEncode(bytes).replaceAll('=', '');

    // 2. Compute SHA-256 hash in hex format.
    final tokenHash = sha256.convert(utf8.encode(rawToken)).toString();

    // 3. Call Supabase RPC create_ownership_transfer.
    try {
      final res = await client.rpc<dynamic>('create_ownership_transfer', params: {
        'p_profile_id': profileId,
        'p_parent_post_transfer_role': parentPostTransferRole.toDb(),
        'p_token_hash': tokenHash,
        'p_recipient_label': recipientLabel,
        'p_ttl_hours': ttl.inHours,
      });

      if (res is! Map) {
        throw const TransferFailure.other('unexpected RPC response shape');
      }

      final id = res['id'] as String;
      final expiresAtStr = res['expires_at'] as String;
      final expiresAt = DateTime.parse(expiresAtStr).toUtc();

      final claimUri = Uri(
        scheme: 'lunarlog',
        host: 'invite',
        queryParameters: {
          'code': rawToken,
          'profile': profileId,
          'kind': 'claim',
        },
      );

      return GeneratedTransfer(
        transferId: id,
        profileId: profileId,
        parentPostTransferRole: parentPostTransferRole,
        rawToken: rawToken,
        tokenHash: tokenHash,
        claimUri: claimUri,
        expiresAt: expiresAt,
      );
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<void> cancelTransfer({required String transferId}) async {
    try {
      await client.rpc<dynamic>('cancel_ownership_transfer', params: {
        'p_transfer_id': transferId,
      });
      syncEngine.requestSync();
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<ClaimedProfileResult> claimProfile({
    required String rawToken,
    String? childDisplayName,
    String? parentDisplayName,
  }) async {
    final tokenHash = sha256.convert(utf8.encode(rawToken)).toString();

    try {
      final res = await client.rpc<dynamic>('accept_ownership_transfer', params: {
        'p_token_hash': tokenHash,
        'p_child_display_name': childDisplayName,
        'p_parent_display_name': parentDisplayName,
      });

      if (res is! Map) {
        throw const TransferFailure.other('unexpected RPC response shape');
      }

      final profileId = res['profile_id'] as String;
      final profileName = res['profile_name'] as String;
      final parentRole = res['parent_role'] as String;
      final entriesTransferred = (res['day_entries_rehomed'] as num).toInt();

      // R28: trigger full reconcile so this (child's) device downloads the
      // full history of the transferred profile without a manual refresh.
      syncEngine.triggerFullReconcile();

      return ClaimedProfileResult(
        profileId: profileId,
        profileName: profileName,
        parentRole: parentRole,
        entriesTransferred: entriesTransferred,
      );
    } catch (e) {
      final failure = _mapError(e);
      // "Already accepted" (another device redeemed it, or a race with this
      // one) still means this device must pull the shared profile down -
      // reconcile before surfacing the error, mirroring
      // SupabaseSharingService.acceptInvite's handling of the same case.
      if (failure is TransferAlreadyAcceptedFailure) {
        syncEngine.triggerFullReconcile();
      }
      throw failure;
    }
  }

  TransferFailure _mapError(Object error) {
    if (error is TransferFailure) return error;
    if (error is SocketException || error is http.ClientException) {
      return const TransferFailure.network();
    }
    if (error is PostgrestException) {
      return _mapPostgrestError(error);
    }
    return TransferFailure.other(error.toString());
  }

  TransferFailure _mapPostgrestError(PostgrestException error) {
    final msg = error.message.toLowerCase();
    final code = error.code ?? '';

    if (_isUnauthorized(code, msg)) {
      return const TransferFailure.unauthorized();
    }
    final businessFailure = _mapBusinessError(code, msg);
    if (businessFailure != null) {
      return businessFailure;
    }
    final status = int.tryParse(code);
    if (status != null && status >= 500) {
      return const TransferFailure.network();
    }
    return TransferFailure.other(error.message);
  }

  // Ordered substring -> failure lookup, checked before the falls-through
  // code-based mapping below. A plain if-chain over this many cases was the
  // single largest contributor to this file's CRAP score (each condition is
  // its own branch); a map iterated in insertion order keeps the same
  // first-match-wins semantics as the original chain while adding only one
  // branch (the loop) to this method's own complexity.
  static const Map<String, TransferFailure> _messageFailures = {
    'not found': TransferFailure.notFound(),
    'already accepted': TransferFailure.alreadyAccepted(),
    'cancelled': TransferFailure.cancelled(),
    'expired': TransferFailure.expired(),
    'cannot accept their own transfer': TransferFailure.selfTransfer(),
  };

  TransferFailure? _mapBusinessError(String code, String msg) {
    if (code == 'P0002') return const TransferFailure.notFound();
    // 23505 (unique_violation) on create means a live transfer already
    // exists for this profile; there is no dedicated "already armed"
    // failure in U6's taxonomy, so it maps to TransferFailure.other with a
    // diagnostic message rather than being conflated with any of the
    // claim-side failures below.
    if (code == '23505') return TransferFailure.other(_diagnostic(code, msg));
    if (code == '22023') return _mapInvalidParameter(code, msg);
    return _mapBusinessMessage(msg);
  }

  TransferFailure _mapInvalidParameter(String code, String msg) =>
      msg.contains('token')
          ? const TransferFailure.invalidToken()
          : TransferFailure.other(_diagnostic(code, msg));

  TransferFailure? _mapBusinessMessage(String msg) {
    for (final entry in _messageFailures.entries) {
      if (msg.contains(entry.key)) return entry.value;
    }
    if (msg.contains('no longer owns this profile') ||
        msg.contains('no longer the primary guardian')) {
      return const TransferFailure.staleOwner();
    }
    return null;
  }

  String _diagnostic(String code, String msg) => 'postgrest $code: $msg';

  bool _isUnauthorized(String code, String msg) =>
      code == 'PGRST301' ||
      code == '42501' ||
      msg.contains('permission') ||
      msg.contains('unauthorized');
}
