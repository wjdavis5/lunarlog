import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunarlog/data/sharing/supabase_ownership_transfer_service.dart';
import 'package:lunarlog/domain/sharing/ownership_transfer_service.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSyncEngine implements SyncEngine {
  int fullReconcileCount = 0;
  int syncRequestCount = 0;

  @override
  void triggerFullReconcile() {
    fullReconcileCount++;
  }

  @override
  void requestSync() {
    syncRequestCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MockSyncEngine syncEngine;
  late List<http.Request> requests;

  SupabaseClient makeClient(Future<http.Response> Function(http.Request) handler) {
    return SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        final res = await handler(request);
        return http.Response(
          res.body,
          res.statusCode,
          headers: {
            'content-type': 'application/json; charset=utf-8',
            ...res.headers,
          },
          request: request,
        );
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
    );
  }

  setUp(() {
    syncEngine = MockSyncEngine();
    requests = [];
  });

  group('createTransfer', () {
    test(
        'generates 32-byte entropy token, hashes it, and calls '
        'create_ownership_transfer RPC with the right params (default ttl 72)',
        () async {
      final client = makeClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(req.url.path, '/rest/v1/rpc/create_ownership_transfer');
        expect(body['p_profile_id'], '01JABCDEF01234567890123456');
        expect(body['p_parent_post_transfer_role'], 'co_parent');
        expect(body['p_recipient_label'], 'Grandma');
        expect(body['p_ttl_hours'], 72);
        expect(body['p_token_hash'], hasLength(64));

        return http.Response(
          jsonEncode({
            'id': 'transfer-123',
            'profile_id': '01JABCDEF01234567890123456',
            'parent_post_transfer_role': 'co_parent',
            'expires_at': '2026-09-09T12:00:00.000Z',
          }),
          200,
        );
      });

      final fixedRandom = Random(42);
      final service = SupabaseOwnershipTransferService(
        client: client,
        syncEngine: syncEngine,
        random: fixedRandom,
      );

      final transfer = await service.createTransfer(
        profileId: '01JABCDEF01234567890123456',
        parentPostTransferRole: ParentPostTransferRole.coManager,
        recipientLabel: 'Grandma',
      );

      expect(transfer.transferId, 'transfer-123');
      expect(transfer.profileId, '01JABCDEF01234567890123456');
      expect(transfer.parentPostTransferRole, ParentPostTransferRole.coManager);
      expect(transfer.rawToken, isNotEmpty);
      expect(transfer.tokenHash, sha256.convert(utf8.encode(transfer.rawToken)).toString());
    });

    test('the returned claimUri carries code, profile, and kind=claim', () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({
            'id': 'transfer-123',
            'profile_id': 'p-1',
            'parent_post_transfer_role': 'viewer',
            'expires_at': '2026-09-09T12:00:00.000Z',
          }),
          200,
        );
      });

      final service = SupabaseOwnershipTransferService(
        client: client,
        syncEngine: syncEngine,
        random: Random(1),
      );

      final transfer = await service.createTransfer(
        profileId: 'p-1',
        parentPostTransferRole: ParentPostTransferRole.viewer,
      );

      expect(transfer.claimUri.scheme, 'lunarlog');
      expect(transfer.claimUri.host, 'invite');
      expect(transfer.claimUri.queryParameters['code'], transfer.rawToken);
      expect(transfer.claimUri.queryParameters['profile'], 'p-1');
      expect(transfer.claimUri.queryParameters['kind'], 'claim');
    });

    test('two consecutive calls with real randomness produce different raw tokens', () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({
            'id': 'transfer-123',
            'profile_id': 'p-1',
            'parent_post_transfer_role': 'viewer',
            'expires_at': '2026-09-09T12:00:00.000Z',
          }),
          200,
        );
      });

      final service = SupabaseOwnershipTransferService(
        client: client,
        syncEngine: syncEngine,
      );

      final first = await service.createTransfer(
        profileId: 'p-1',
        parentPostTransferRole: ParentPostTransferRole.viewer,
      );
      final second = await service.createTransfer(
        profileId: 'p-1',
        parentPostTransferRole: ParentPostTransferRole.viewer,
      );

      expect(first.rawToken, isNot(equals(second.rawToken)));
    });
  });

  group('createTransfer error mapping (Review item #2)', () {
    test('23505 (unique_violation) maps to TransferAlreadyArmedFailure', () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({'message': 'duplicate key value violates unique constraint', 'code': '23505'}),
          400,
        );
      });

      final service = SupabaseOwnershipTransferService(client: client, syncEngine: syncEngine);

      await expectLater(
        service.createTransfer(
          profileId: 'p-1',
          parentPostTransferRole: ParentPostTransferRole.viewer,
        ),
        throwsA(isA<TransferAlreadyArmedFailure>()),
      );
    });
  });

  group('getActiveTransfer (Review item #2)', () {
    test('selects ownership_transfers directly, filtered to the still-live '
        'row for the profile', () async {
      final client = makeClient((req) async {
        expect(req.method, 'GET');
        expect(req.url.path, '/rest/v1/ownership_transfers');
        expect(req.url.queryParameters['profile_id'], 'eq.p-1');
        expect(req.url.queryParameters['accepted_at'], 'is.null');
        expect(req.url.queryParameters['cancelled_at'], 'is.null');
        expect(req.url.queryParameters['select'], isNot(contains('token_hash')));

        return http.Response(
          jsonEncode([
            {
              'id': 'orphaned-1',
              'profile_id': 'p-1',
              'parent_post_transfer_role': 'co_parent',
              'recipient_label': 'Sam',
              'expires_at': '2026-09-10T08:00:00.000Z',
            }
          ]),
          200,
        );
      });

      final service = SupabaseOwnershipTransferService(client: client, syncEngine: syncEngine);

      final active = await service.getActiveTransfer(profileId: 'p-1');

      expect(active, isNotNull);
      expect(active!.transferId, 'orphaned-1');
      expect(active.profileId, 'p-1');
      expect(active.parentPostTransferRole, ParentPostTransferRole.coManager);
      expect(active.recipientLabel, 'Sam');
      expect(active.expiresAt, DateTime.utc(2026, 9, 10, 8, 0));
    });

    test('returns null when no live transfer exists for the profile', () async {
      final client = makeClient((req) async {
        return http.Response(jsonEncode(<dynamic>[]), 200);
      });

      final service = SupabaseOwnershipTransferService(client: client, syncEngine: syncEngine);

      expect(await service.getActiveTransfer(profileId: 'p-1'), isNull);
    });

    test('maps a postgrest error the same way as the other RPCs', () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({'message': 'permission denied', 'code': '42501'}),
          400,
        );
      });

      final service = SupabaseOwnershipTransferService(client: client, syncEngine: syncEngine);

      await expectLater(
        service.getActiveTransfer(profileId: 'p-1'),
        throwsA(isA<TransferUnauthorizedFailure>()),
      );
    });
  });

  group('cancelTransfer', () {
    test('calls cancel_ownership_transfer RPC and requests sync (not full reconcile)', () async {
      final client = makeClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(req.url.path, '/rest/v1/rpc/cancel_ownership_transfer');
        expect(body['p_transfer_id'], 'transfer-123');

        return http.Response(jsonEncode(true), 200);
      });

      final service = SupabaseOwnershipTransferService(
        client: client,
        syncEngine: syncEngine,
      );

      await service.cancelTransfer(transferId: 'transfer-123');

      expect(syncEngine.syncRequestCount, 1);
      expect(syncEngine.fullReconcileCount, 0);
    });
  });

  group('claimProfile', () {
    test('hashes raw token (never sends it raw) and calls accept_ownership_transfer, '
        'then triggers full reconcile exactly once', () async {
      const rawToken = 'test-transfer-token-98765';
      final expectedHash = sha256.convert(utf8.encode(rawToken)).toString();

      final client = makeClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(req.url.path, '/rest/v1/rpc/accept_ownership_transfer');
        expect(body['p_token_hash'], expectedHash);
        expect(body.values, isNot(contains(rawToken)));
        expect(body['p_child_display_name'], 'Piper');
        expect(body['p_parent_display_name'], 'Dad');

        return http.Response(
          jsonEncode({
            'profile_id': '01JABCDEF01234567890123456',
            'profile_name': 'Piper',
            'parent_role': 'co_parent',
            'day_entries_rehomed': 42,
          }),
          200,
        );
      });

      final service = SupabaseOwnershipTransferService(
        client: client,
        syncEngine: syncEngine,
      );

      final result = await service.claimProfile(
        rawToken: rawToken,
        childDisplayName: 'Piper',
        parentDisplayName: 'Dad',
      );

      expect(result.profileId, '01JABCDEF01234567890123456');
      expect(result.profileName, 'Piper');
      expect(result.parentRole, 'co_parent');
      expect(result.entriesTransferred, 42);
      expect(syncEngine.fullReconcileCount, 1);
    });

    Future<SupabaseOwnershipTransferService> serviceForError({
      required String message,
      required String code,
      int statusCode = 400,
    }) async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({'message': message, 'code': code}),
          statusCode,
        );
      });
      return SupabaseOwnershipTransferService(client: client, syncEngine: syncEngine);
    }

    test('P0002 (not found) maps to TransferNotFoundFailure', () async {
      final service = await serviceForError(message: 'transfer not found', code: 'P0002');
      await expectLater(
        service.claimProfile(rawToken: 'any'),
        throwsA(isA<TransferNotFoundFailure>()),
      );
    });

    test('a body naming expiry maps to TransferExpiredFailure', () async {
      final service = await serviceForError(message: 'this transfer has expired', code: '55000');
      await expectLater(
        service.claimProfile(rawToken: 'any'),
        throwsA(isA<TransferExpiredFailure>()),
      );
    });

    test('a body naming cancellation maps to TransferCancelledFailure', () async {
      final service =
          await serviceForError(message: 'this transfer was cancelled', code: '55000');
      await expectLater(
        service.claimProfile(rawToken: 'any'),
        throwsA(isA<TransferCancelledFailure>()),
      );
    });

    test('a body naming already accepted maps to TransferAlreadyAcceptedFailure '
        'and triggers full reconcile before rethrowing', () async {
      final service = await serviceForError(
          message: 'this transfer was already accepted', code: '55000');
      await expectLater(
        service.claimProfile(rawToken: 'any'),
        throwsA(isA<TransferAlreadyAcceptedFailure>()),
      );
      expect(syncEngine.fullReconcileCount, 1);
    });

    test('a body naming self-transfer maps to TransferSelfTransferFailure', () async {
      final service = await serviceForError(
          message: 'you cannot accept their own transfer', code: '55000');
      await expectLater(
        service.claimProfile(rawToken: 'any'),
        throwsA(isA<TransferSelfTransferFailure>()),
      );
    });

    test('a body naming stale ownership maps to TransferStaleOwnerFailure', () async {
      final service = await serviceForError(
          message: 'the arming parent no longer owns this profile', code: '55000');
      await expectLater(
        service.claimProfile(rawToken: 'any'),
        throwsA(isA<TransferStaleOwnerFailure>()),
      );
    });

    test('42501 maps to TransferUnauthorizedFailure', () async {
      final service = await serviceForError(message: 'permission denied', code: '42501');
      await expectLater(
        service.claimProfile(rawToken: 'any'),
        throwsA(isA<TransferUnauthorizedFailure>()),
      );
    });

    test('a socket/network error maps to TransferNetworkFailure', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          throw const SocketException('connection refused');
        }),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      );
      final service = SupabaseOwnershipTransferService(client: client, syncEngine: syncEngine);

      await expectLater(
        service.claimProfile(rawToken: 'any'),
        throwsA(isA<TransferNetworkFailure>()),
      );
    });

    test('a numeric 500 postgrest code maps to TransferNetworkFailure', () async {
      final service = await serviceForError(message: 'boom', code: '500', statusCode: 400);
      await expectLater(
        service.claimProfile(rawToken: 'any'),
        throwsA(isA<TransferNetworkFailure>()),
      );
    });

    test('an unrecognised error (non-numeric code, unmatched message), even '
        'delivered with an HTTP 500, maps to TransferOtherFailure', () async {
      final service =
          await serviceForError(message: 'boom', code: 'XX000', statusCode: 500);
      await expectLater(
        service.claimProfile(rawToken: 'any'),
        throwsA(isA<TransferOtherFailure>()),
      );
    });
  });
}
