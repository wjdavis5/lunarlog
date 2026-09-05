import 'dart:convert';
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
}
