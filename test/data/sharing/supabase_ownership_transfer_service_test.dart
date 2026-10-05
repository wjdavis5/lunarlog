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
import 'package:lunarlog/observability/breadcrumbs.dart';
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
        // Round 2 review item #2 (P2): a lapsed-but-uncancelled transfer
        // must not read back as active — see the service's own comment.
        expect(req.url.queryParameters['expires_at'], startsWith('gt.'));
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

    test('issue #552: an unrecognised error records a diagnostic breadcrumb '
        'since TransferOtherFailure itself no longer carries one', () async {
      defaultBreadcrumbLog.clear();
      final service =
          await serviceForError(message: 'boom', code: 'XX000', statusCode: 500);

      await expectLater(
        service.claimProfile(rawToken: 'any'),
        throwsA(isA<TransferOtherFailure>()),
      );

      expect(defaultBreadcrumbLog.snapshot(), isNotEmpty);
      expect(defaultBreadcrumbLog.snapshot().single, contains('ownershipTransfer'));
    });
  });

  // Issue #1504. The same fault as in the invitation mapper: any all-digit
  // code of 500 or more read as a network failure, and the transfer RPCs
  // raise their refusals with SQLSTATE 55000. Every one but the last was
  // already caught by its wording first.
  group('every refusal the ownership-transfer RPCs raise (issue #1504)', () {
    const profile = '01JABCDEF01234567890123456';

    /// Calls the service method that rides the RPC named [function].
    Future<Object?> call(
      SupabaseOwnershipTransferService service,
      String function,
    ) =>
        switch (function) {
          'create_ownership_transfer' => service.createTransfer(
              profileId: profile,
              parentPostTransferRole: ParentPostTransferRole.coManager,
            ),
          'cancel_ownership_transfer' =>
            service.cancelTransfer(transferId: 'transfer-1'),
          'accept_ownership_transfer' =>
            service.claimProfile(rawToken: 'any-token'),
          _ => throw ArgumentError.value(function, 'function'),
        };

    /// A service whose server answers every call the way PostgREST answers
    /// a `raise exception`: the SQLSTATE in the body's `code`, the HTTP
    /// status beside it.
    SupabaseOwnershipTransferService refusing(
      String sqlstate,
      int status,
      String message,
    ) =>
        SupabaseOwnershipTransferService(
          client: makeClient((req) async => http.Response(
                jsonEncode({
                  'code': sqlstate,
                  'details': null,
                  'hint': null,
                  'message': message,
                }),
                status,
              )),
          syncEngine: syncEngine,
        );

    // Function, SQLSTATE, the HTTP status PostgREST gives that SQLSTATE,
    // the message, and what it reads as. Taken from the newest definition
    // of each function in supabase/migrations: 20260915010000
    // (create_ownership_transfer, plus the one-live-transfer unique index
    // of 20260906170000), 20260906180000 (cancel_ownership_transfer) and
    // 20260920120000 (accept_ownership_transfer). The browser client's
    // webapp/test/sharing.test.ts holds the same rows with the same kinds.
    const refusals = <(String, String, int, String, TransferFailure)>[
      (
        'create_ownership_transfer',
        '42501',
        401,
        'authentication required',
        TransferFailure.unauthorized(),
      ),
      (
        'create_ownership_transfer',
        '42501',
        403,
        'only the accepted primary guardian can transfer ownership of this '
            'profile',
        TransferFailure.unauthorized(),
      ),
      (
        'create_ownership_transfer',
        '22023',
        400,
        'invalid parent_post_transfer_role: owner',
        TransferFailure.other(),
      ),
      (
        'create_ownership_transfer',
        '22023',
        400,
        'p_ttl_hours must be between 1 and 168',
        TransferFailure.other(),
      ),
      (
        'create_ownership_transfer',
        '22023',
        400,
        'token_hash must be a 64-character hex string',
        TransferFailure.invalidToken(),
      ),
      (
        'create_ownership_transfer',
        '22023',
        400,
        'recipient_label must be at most 80 characters',
        TransferFailure.other(),
      ),
      (
        'create_ownership_transfer',
        '23505',
        409,
        'duplicate key value violates unique constraint '
            '"ownership_transfers_one_live_uq"',
        TransferFailure.alreadyArmed(),
      ),
      (
        'cancel_ownership_transfer',
        '42501',
        401,
        'authentication required',
        TransferFailure.unauthorized(),
      ),
      (
        'cancel_ownership_transfer',
        'P0002',
        500,
        'transfer not found',
        TransferFailure.notFound(),
      ),
      (
        'cancel_ownership_transfer',
        '42501',
        403,
        'only the arming parent can cancel this transfer',
        TransferFailure.unauthorized(),
      ),
      (
        'accept_ownership_transfer',
        '42501',
        401,
        'authentication required',
        TransferFailure.unauthorized(),
      ),
      (
        'accept_ownership_transfer',
        '22023',
        400,
        'token_hash must be a 64-character hex string',
        TransferFailure.invalidToken(),
      ),
      (
        'accept_ownership_transfer',
        'P0002',
        500,
        'transfer not found',
        TransferFailure.notFound(),
      ),
      (
        'accept_ownership_transfer',
        '55000',
        500,
        'transfer was already accepted',
        TransferFailure.alreadyAccepted(),
      ),
      (
        'accept_ownership_transfer',
        '55000',
        500,
        'transfer was cancelled',
        TransferFailure.cancelled(),
      ),
      (
        'accept_ownership_transfer',
        '55000',
        500,
        'transfer has expired',
        TransferFailure.expired(),
      ),
      (
        'accept_ownership_transfer',
        '55000',
        500,
        'the arming parent cannot accept their own transfer',
        TransferFailure.selfTransfer(),
      ),
      (
        'accept_ownership_transfer',
        'P0002',
        500,
        'profile not found',
        TransferFailure.notFound(),
      ),
      (
        'accept_ownership_transfer',
        '55000',
        500,
        'the arming parent no longer owns this profile; the link is stale',
        TransferFailure.staleOwner(),
      ),
      (
        'accept_ownership_transfer',
        '55000',
        500,
        'the arming parent is no longer the primary guardian of this '
            'profile; the link is stale',
        TransferFailure.staleOwner(),
      ),
      // Was the network failure. The claimant's own role on the profile
      // changed after the link was made, which is what this copy says.
      (
        'accept_ownership_transfer',
        '55000',
        500,
        'guardian access to this profile was revoked; a new transfer link '
            'is required',
        TransferFailure.staleOwner(),
      ),
    ];

    for (final (function, sqlstate, status, message, expected) in refusals) {
      test('$function: "$message" ($sqlstate, HTTP $status) is $expected',
          () async {
        final service = refusing(sqlstate, status, message);

        await expectLater(call(service, function), throwsA(expected));
        expect(requests.last.url.path, '/rest/v1/rpc/$function');
      });
    }

    test('a SQLSTATE no refusal matches is the generic failure, never the '
        'network one, whatever its digits', () async {
      for (final (sqlstate, status, message) in const [
        ('55000', 500, 'a refusal this build has not heard of'),
        ('57014', 500, 'canceling statement due to statement timeout'),
        ('23514', 400, 'new row violates check constraint'),
      ]) {
        await expectLater(
          refusing(sqlstate, status, message).claimProfile(rawToken: 'any'),
          throwsA(const TransferFailure.other()),
          reason: '$sqlstate is a SQLSTATE, not an HTTP status',
        );
      }
    });
  });

  group('a transport or server failure is still the network kind '
      '(issue #1504)', () {
    /// A server that answers with [body] under [status]: not PostgREST's
    /// error document, so postgrest reports the status itself as the code.
    SupabaseOwnershipTransferService answering(int status, String body) =>
        SupabaseOwnershipTransferService(
          client: SupabaseClient(
            'https://example.supabase.co',
            'anon-key',
            httpClient: MockClient((request) async =>
                http.Response(body, status, request: request)),
            authOptions: const AuthClientOptions(autoRefreshToken: false),
            postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
          ),
          syncEngine: syncEngine,
        );

    test('an HTTP 503 whose body carries no code of its own', () async {
      for (final body in const [
        '<html><body><h1>503 Service Temporarily Unavailable</h1></body></html>',
        '{"message":"name resolution failed"}',
      ]) {
        await expectLater(
          answering(503, body).claimProfile(rawToken: 'any'),
          throwsA(const TransferFailure.network()),
          reason: 'HTTP 503 with body $body',
        );
      }
    });

    test('a gateway page is not read for a refusal, whatever it says',
        () async {
      // Each of these used to be matched on its wording before the status
      // was looked at: a not-found, a cancelled and an expired failure.
      for (final (status, body) in const [
        (502, '<html><body>The origin server was not found</body></html>'),
        (503, '<html><body>The request was cancelled upstream</body></html>'),
        (504, '<html><body>The gateway timed out; the request expired</body></html>'),
      ]) {
        await expectLater(
          answering(status, body).claimProfile(rawToken: 'any'),
          throwsA(const TransferFailure.network()),
          reason: 'HTTP $status with body $body',
        );
      }
    });
  });
}
