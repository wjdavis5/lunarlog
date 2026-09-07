import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunarlog/data/sharing/supabase_sharing_service.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
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

  group('createInvite', () {
    test('generates 32-byte entropy token, hashes it, and calls create_guardian_invitation RPC', () async {
      final client = makeClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(req.url.path, '/rest/v1/rpc/create_guardian_invitation');
        expect(body['p_profile_id'], '01JABCDEF01234567890123456');
        expect(body['p_role'], 'co_parent');
        expect(body['p_recipient_label'], 'Dad');
        expect(body['p_ttl_hours'], 48);
        expect(body['p_token_hash'], hasLength(64));

        return http.Response(
          jsonEncode({
            'id': 'invite-123',
            'profile_id': '01JABCDEF01234567890123456',
            'role': 'co_parent',
            'expires_at': '2026-09-06T12:00:00.000Z',
          }),
          200,
        );
      });

      final fixedRandom = Random(42);
      final service = SupabaseSharingService(
        client: client,
        syncEngine: syncEngine,
        random: fixedRandom,
      );

      final invite = await service.createInvite(
        profileId: '01JABCDEF01234567890123456',
        role: GuardianRole.coParent,
        recipientLabel: 'Dad',
      );

      expect(invite.invitationId, 'invite-123');
      expect(invite.profileId, '01JABCDEF01234567890123456');
      expect(invite.role, GuardianRole.coParent);
      expect(invite.rawToken, isNotEmpty);
      expect(invite.tokenHash, sha256.convert(utf8.encode(invite.rawToken)).toString());
      expect(invite.inviteUri.scheme, 'lunarlog');
      expect(invite.inviteUri.host, 'invite');
      expect(invite.inviteUri.queryParameters['code'], invite.rawToken);
      expect(invite.inviteUri.queryParameters['profile'], '01JABCDEF01234567890123456');
    });
  });

  group('acceptInvite', () {
    test('hashes raw token and calls accept_guardian_invitation RPC, then triggers full reconcile', () async {
      const rawToken = 'test-token-value-12345';
      final expectedHash = sha256.convert(utf8.encode(rawToken)).toString();

      final client = makeClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(req.url.path, '/rest/v1/rpc/accept_guardian_invitation');
        expect(body['p_token_hash'], expectedHash);
        expect(body['p_guardian_display_name'], 'Dad');

        return http.Response(
          jsonEncode({
            'profile_id': '01JABCDEF01234567890123456',
            'profile_name': 'Luna',
            'role': 'co_parent',
          }),
          200,
        );
      });

      final service = SupabaseSharingService(
        client: client,
        syncEngine: syncEngine,
      );

      final result = await service.acceptInvite(
        rawToken: rawToken,
        displayName: 'Dad',
      );

      expect(result.profileId, '01JABCDEF01234567890123456');
      expect(result.profileName, 'Luna');
      expect(result.role, GuardianRole.coParent);
      expect(syncEngine.fullReconcileCount, 1);
    });

    test('maps postgrest errors to typed SharingFailure', () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({'message': 'invitation has expired', 'code': 'P0001'}),
          400,
        );
      });

      final service = SupabaseSharingService(
        client: client,
        syncEngine: syncEngine,
      );

      expect(
        () => service.acceptInvite(rawToken: 'any-token'),
        throwsA(isA<SharingExpiredFailure>()),
      );
    });

    test('already-accepted / already-guardian failures still trigger the '
        'full reconcile (the profile must land on this device)', () async {
      for (final message in [
        'invitation already accepted',
        'user is already an active guardian of this profile',
      ]) {
        syncEngine = MockSyncEngine();
        final client = makeClient((req) async {
          return http.Response(
            jsonEncode({'message': message, 'code': '55000'}),
            400,
          );
        });
        final service = SupabaseSharingService(
          client: client,
          syncEngine: syncEngine,
        );

        await expectLater(
          service.acceptInvite(rawToken: 'any-token'),
          throwsA(isA<SharingFailure>()),
        );
        expect(syncEngine.fullReconcileCount, 1,
            reason: 'failure "$message" must still reconcile');
      }
    });
  });

  group('revokeGuardian', () {
    test('calls revoke_guardian RPC and requests sync', () async {
      final client = makeClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(req.url.path, '/rest/v1/rpc/revoke_guardian');
        expect(body['p_profile_id'], '01JABCDEF01234567890123456');
        expect(body['p_target_user_id'], 'user-uuid-123');

        return http.Response(
          jsonEncode(true),
          200,
        );
      });

      final service = SupabaseSharingService(
        client: client,
        syncEngine: syncEngine,
      );

      await service.revokeGuardian(
        profileId: '01JABCDEF01234567890123456',
        targetUserId: 'user-uuid-123',
      );

      expect(syncEngine.syncRequestCount, 1);
    });

    test('maps postgrest and network errors correctly', () async {
      final errorCodes = <String, Type>{
        'PGRST301': SharingUnauthorizedFailure,
        'P0002': SharingNotFoundFailure,
        '23505': SharingAlreadyGuardianFailure,
        '22023': SharingInvalidTokenFailure,
        '500': SharingNetworkFailure,
        'other': SharingOtherFailure,
      };

      for (final entry in errorCodes.entries) {
        final client = makeClient((req) async {
          return http.Response(
            jsonEncode({'message': 'error message', 'code': entry.key}),
            400,
          );
        });

        final service = SupabaseSharingService(
          client: client,
          syncEngine: syncEngine,
        );

        expect(
          () => service.revokeGuardian(profileId: 'p1', targetUserId: 'u1'),
          throwsA(isA<SharingFailure>()),
        );
      }
    });
  });

  group('listPendingInvites', () {
    test('maps a row set to PendingInvites in created_at order, parsing '
        'expires_at to UTC', () async {
      final client = makeClient((req) async {
        expect(req.url.path, '/rest/v1/guardian_invitations');
        expect(req.method, 'GET');
        expect(req.url.queryParameters['profile_id'], 'eq.01JABCDEF01234567890123456');
        expect(req.url.queryParameters['accepted_at'], 'is.null');
        expect(req.url.queryParameters['revoked_at'], 'is.null');
        expect(req.url.queryParameters['order'], 'created_at.asc.nullslast');
        return http.Response(
          jsonEncode([
            {
              'id': 'inv-1',
              'profile_id': '01JABCDEF01234567890123456',
              'role': 'caregiver',
              'recipient_label': 'Sitter',
              'created_at': '2026-09-06T10:00:00+00:00',
              'expires_at': '2026-09-08T10:00:00+00:00',
            },
          ]),
          200,
        );
      });

      final service = SupabaseSharingService(client: client, syncEngine: syncEngine);
      final invites = await service.listPendingInvites('01JABCDEF01234567890123456');

      expect(invites, hasLength(1));
      expect(invites.single.invitationId, 'inv-1');
      expect(invites.single.profileId, '01JABCDEF01234567890123456');
      expect(invites.single.role, GuardianRole.caregiver);
      expect(invites.single.recipientLabel, 'Sitter');
      expect(invites.single.createdAt, DateTime.utc(2026, 9, 6, 10));
      expect(invites.single.expiresAt, DateTime.utc(2026, 9, 8, 10));
      expect(invites.single.expiresAt.isUtc, isTrue);
    });

    test('returns an empty list when the profile has no live invitations', () async {
      final client = makeClient((req) async {
        return http.Response(jsonEncode(<Object?>[]), 200);
      });

      final service = SupabaseSharingService(client: client, syncEngine: syncEngine);
      expect(await service.listPendingInvites('p1'), isEmpty);
    });

    test('never requests or exposes token_hash - a future edit that adds it '
        'back to the selected column list fails this test', () async {
      String? selectParam;
      final client = makeClient((req) async {
        selectParam = req.url.queryParameters['select'];
        return http.Response(jsonEncode(<Object?>[]), 200);
      });

      final service = SupabaseSharingService(client: client, syncEngine: syncEngine);
      await service.listPendingInvites('p1');

      expect(selectParam, isNotNull);
      expect(selectParam, isNot(contains('token_hash')));
      expect(
        selectParam!.split(','),
        unorderedEquals(
            ['id', 'profile_id', 'role', 'recipient_label', 'created_at', 'expires_at']),
      );
    });

    test('maps a transport failure to SharingFailure.network', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          throw const SocketException('connection refused');
        }),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      );

      final service = SupabaseSharingService(client: client, syncEngine: syncEngine);
      expect(
        () => service.listPendingInvites('p1'),
        throwsA(isA<SharingNetworkFailure>()),
      );
    });
  });

  group('cancelInvite', () {
    test('sends the invitation id as p_invitation_id and maps '
        'outcome: "revoked" to InviteCancellation.revoked', () async {
      final client = makeClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(req.url.path, '/rest/v1/rpc/revoke_guardian_invitation');
        expect(body['p_invitation_id'], 'inv-1');
        return http.Response(jsonEncode({'outcome': 'revoked', 'invitation_id': 'inv-1'}), 200);
      });

      final service = SupabaseSharingService(client: client, syncEngine: syncEngine);
      expect(await service.cancelInvite('inv-1'), InviteCancellation.revoked);
    });

    test('maps each terminal outcome to its enum value rather than throwing (R5)', () async {
      final outcomes = <String, InviteCancellation>{
        'already_revoked': InviteCancellation.alreadyRevoked,
        'already_accepted': InviteCancellation.alreadyAccepted,
        'expired': InviteCancellation.expired,
      };

      for (final entry in outcomes.entries) {
        final client = makeClient((req) async {
          return http.Response(jsonEncode({'outcome': entry.key}), 200);
        });
        final service = SupabaseSharingService(client: client, syncEngine: syncEngine);
        expect(await service.cancelInvite('inv-1'), entry.value,
            reason: 'outcome "${entry.key}" must map cleanly, not throw');
      }
    });

    test('maps a 42501/insufficient_privilege RPC error to SharingFailure.unauthorized', () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({'message': 'caller lacks permission to cancel this invitation', 'code': '42501'}),
          400,
        );
      });
      final service = SupabaseSharingService(client: client, syncEngine: syncEngine);
      expect(
        () => service.cancelInvite('inv-1'),
        throwsA(isA<SharingUnauthorizedFailure>()),
      );
    });

    test('maps an unrecognised outcome string to SharingFailure.other rather '
        'than silently reporting success', () async {
      final client = makeClient((req) async {
        return http.Response(jsonEncode({'outcome': 'not_a_real_outcome'}), 200);
      });
      final service = SupabaseSharingService(client: client, syncEngine: syncEngine);
      expect(
        () => service.cancelInvite('inv-1'),
        throwsA(isA<SharingOtherFailure>()),
      );
    });
  });
}
