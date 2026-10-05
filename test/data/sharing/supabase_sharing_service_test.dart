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

/// A base64url JWT-shaped string whose payload decodes to `{sub, exp, iat}`
/// — enough for `GoTrueClient.recoverSession` to accept it as a live session
/// with no network call, so `client.auth.currentUser?.id` resolves locally
/// (the `test/data/import/supabase_bulk_importer_test.dart` helper).
String _fakeJwt({required String sub, required DateTime exp}) {
  String segment(Map<String, Object?> claims) =>
      base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '');
  final header = segment({'alg': 'HS256', 'typ': 'JWT'});
  final payload = segment({
    'sub': sub,
    'exp': exp.millisecondsSinceEpoch ~/ 1000,
    'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
  });
  return '$header.$payload.fake-signature';
}

Future<void> signIn(SupabaseClient client, String uid) async {
  final jwt = _fakeJwt(
    sub: uid,
    exp: DateTime.now().add(const Duration(hours: 1)),
  );
  await client.auth.recoverSession(jsonEncode({
    'access_token': jwt,
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'a-refresh-token',
    'user': {
      'id': uid,
      'aud': 'authenticated',
      'app_metadata': <String, Object?>{},
      'created_at': '2026-01-01T00:00:00Z',
    },
  }));
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

    test('a subject invitation refused because the profile already has a '
        'subject (issue #1499) is the generic failure, not a network or '
        'permission one', () async {
      // The exact error the server's guardian_invitations trigger raises
      // (pinned in supabase/tests/self_profile_subject_test.sql): P0001,
      // and wording none of the specific mappings match.
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({
            'message': 'this profile already has a subject; a subject '
                'invitation cannot be created for it',
            'code': 'P0001',
          }),
          400,
        );
      });
      await signIn(client, 'user-mom');
      final service = SupabaseSharingService(client: client, syncEngine: syncEngine);

      expect(
        () => service.createInvite(
          profileId: '01JABCDEF01234567890123456',
          role: GuardianRole.caregiver,
          subject: true,
        ),
        throwsA(isA<SharingOtherFailure>()),
      );
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

  group('previewInvite', () {
    test('hashes raw token, calls preview_guardian_invitation RPC, and '
        'parses the returned preview', () async {
      const rawToken = 'preview-token-value-12345';
      final expectedHash = sha256.convert(utf8.encode(rawToken)).toString();

      final client = makeClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(req.url.path, '/rest/v1/rpc/preview_guardian_invitation');
        expect(body['p_token_hash'], expectedHash);
        expect(body.containsKey('p_guardian_display_name'), isFalse,
            reason: 'preview never sends a display name - it commits nothing');

        return http.Response(
          jsonEncode({
            'profile_display_name': 'Riley',
            'role': 'caregiver',
            // Fixed fixture expiry (issue #949): parsed and compared, never
            // measured against the real clock.
            'expires_at': '2026-09-20T12:00:00.000Z',
          }),
          200,
        );
      });

      final service = SupabaseSharingService(client: client, syncEngine: syncEngine);
      final preview = await service.previewInvite(rawToken: rawToken);

      expect(preview, isNotNull);
      expect(preview!.profileDisplayName, 'Riley');
      expect(preview.role, GuardianRole.caregiver);
      // Issue #949: fixed fixture expiry, decoded verbatim.
      expect(preview.expiresAt, DateTime.utc(2026, 9, 20, 12));
      expect(syncEngine.fullReconcileCount, 0,
          reason: 'a preview never triggers a reconcile - it commits nothing');
    });

    test('returns null for the RPC''s uniform "not available" result '
        '(SQL null)', () async {
      final client = makeClient((req) async {
        return http.Response('null', 200);
      });

      final service = SupabaseSharingService(client: client, syncEngine: syncEngine);
      final preview = await service.previewInvite(rawToken: 'dead-token');

      expect(preview, isNull);
    });

    test('an unrecognised role string fails closed to viewer (#540\'s '
        'pattern, same as acceptInvite)', () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({
            'profile_display_name': 'Riley',
            'role': 'some_future_role',
            // Issue #949: fixed fixture expiry, never measured against now.
            'expires_at': '2026-09-20T12:00:00.000Z',
          }),
          200,
        );
      });

      final service = SupabaseSharingService(client: client, syncEngine: syncEngine);
      final preview = await service.previewInvite(rawToken: 'any-token');

      expect(preview!.role, GuardianRole.viewer);
    });

    test('maps postgrest errors (e.g. the rate limit) to a typed SharingFailure', () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({'message': 'too many preview attempts; wait a moment and try again', 'code': '55000'}),
          400,
        );
      });

      final service = SupabaseSharingService(client: client, syncEngine: syncEngine);

      expect(
        () => service.previewInvite(rawToken: 'any-token'),
        throwsA(isA<SharingFailure>()),
      );
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
      final now = DateTime.now().toUtc();
      final createdAt = now.subtract(const Duration(hours: 2)).toIso8601String();
      final expiresAt = now.add(const Duration(hours: 46)).toIso8601String();
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
              'created_at': createdAt,
              'expires_at': expiresAt,
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
      expect(invites.single.createdAt.isUtc, isTrue);
      expect(invites.single.expiresAt.isUtc, isTrue);
      expect(invites.single.isExpiredAt(DateTime.now().toUtc()), isFalse);
    });

    test('filters by the recently-expired cutoff (now - window), not by now, '
        'so recently expired rows are returned', () async {
      String? expiresParam;
      final client = makeClient((req) async {
        expiresParam = req.url.queryParameters['expires_at'];
        final expiredAt = DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 2))
            .toIso8601String();
        final createdAt = DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 50))
            .toIso8601String();
        return http.Response(
          jsonEncode([
            {
              'id': 'inv-expired',
              'profile_id': 'p1',
              'role': 'caregiver',
              'recipient_label': 'Sitter',
              'created_at': createdAt,
              'expires_at': expiredAt,
            },
          ]),
          200,
        );
      });

      final service = SupabaseSharingService(client: client, syncEngine: syncEngine);
      final invites = await service.listPendingInvites('p1');

      // The expired-within-window row is returned, not filtered out.
      expect(invites, hasLength(1));
      expect(invites.single.invitationId, 'inv-expired');
      expect(invites.single.isExpiredAt(DateTime.now().toUtc()), isTrue);

      // The request admits anything expiring after now - window.
      expect(expiresParam, isNotNull);
      expect(expiresParam, startsWith('gt.'));
      final cutoff =
          DateTime.parse(expiresParam!.substring('gt.'.length)).toUtc();
      final expectedCutoff = DateTime.now()
          .toUtc()
          .subtract(SupabaseSharingService.recentlyExpiredWindow);
      expect(
        cutoff.difference(expectedCutoff).abs(),
        lessThan(const Duration(minutes: 5)),
        reason: 'expires_at filter must be now - recentlyExpiredWindow',
      );
      expect(cutoff.isBefore(DateTime.now().toUtc()), isTrue,
          reason: 'a now-based filter would exclude expired rows');
    });

    test('recentlyExpiredWindow bounds the list so it cannot grow without bound',
        () async {
      expect(SupabaseSharingService.recentlyExpiredWindow,
          const Duration(days: 7));
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
        unorderedEquals(['id', 'profile_id', 'role', 'recipient_label',
            'created_at', 'expires_at', 'is_subject']),
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
      // Issue #885: this test's original harness was signed out, so the
      // refusal mapped to notSignedIn instead. The mapping under test is
      // the *permission* one, so sign the caller in first — the signed-out
      // case has its own test below.
      await signIn(client, 'user-mom');
      final service = SupabaseSharingService(client: client, syncEngine: syncEngine);
      expect(
        () => service.cancelInvite('inv-1'),
        throwsA(isA<SharingUnauthorizedFailure>()),
      );
    });

    test('maps a no-session refusal to SharingFailure.notSignedIn, not '
        'SharingFailure.unauthorized (issue #885)', () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({'message': 'caller lacks permission to cancel this invitation', 'code': '42501'}),
          400,
        );
      });
      // Deliberately no signIn(): the client holds no session.
      final service = SupabaseSharingService(client: client, syncEngine: syncEngine);
      expect(
        () => service.cancelInvite('inv-1'),
        throwsA(isA<SharingNotSignedInFailure>()),
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

  group('updateGuardianRole', () {
    test('calls update_guardian_role RPC with the role db value and requests sync',
        () async {
      final client = makeClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(req.url.path, '/rest/v1/rpc/update_guardian_role');
        expect(body['p_profile_id'], '01JABCDEF01234567890123456');
        expect(body['p_target_user_id'], 'user-uuid-123');
        expect(body['p_new_role'], 'caregiver');

        return http.Response(
          jsonEncode({
            'profile_id': '01JABCDEF01234567890123456',
            'role': 'caregiver',
            'updated': true,
          }),
          200,
        );
      });

      final service = SupabaseSharingService(
        client: client,
        syncEngine: syncEngine,
      );

      await service.updateGuardianRole(
        profileId: '01JABCDEF01234567890123456',
        targetUserId: 'user-uuid-123',
        newRole: GuardianRole.caregiver,
      );

      // The changed row re-pulls on the next cycle, so the call must wake
      // the sync engine - this is what delivers the role to the target.
      expect(syncEngine.syncRequestCount, 1);
    });

    test('maps insufficient_privilege to unauthorized and no_data_found to notFound',
        () async {
      final cases = <String, Type>{
        'caller lacks permission to change this guardian\'s role':
            SharingUnauthorizedFailure,
        'cannot change your own role': SharingUnauthorizedFailure,
        'primary_guardian cannot be granted through update_guardian_role':
            SharingUnauthorizedFailure,
      };
      for (final entry in cases.entries) {
        final client = makeClient((req) async {
          return http.Response(
            jsonEncode({'message': entry.key, 'code': '42501'}),
            400,
          );
        });
        // Issue #885: this harness was signed out, so a 42501 refusal now
        // maps to notSignedIn. The mapping under test is the *permission*
        // one, so sign the caller in first.
        await signIn(client, 'user-mom');
        final service = SupabaseSharingService(
          client: client,
          syncEngine: syncEngine,
        );
        await expectLater(
          service.updateGuardianRole(
            profileId: 'p1',
            targetUserId: 'u1',
            newRole: GuardianRole.viewer,
          ),
          throwsA(isA<SharingUnauthorizedFailure>()),
          reason: '"${entry.key}" must map to unauthorized',
        );
      }

      final notFoundClient = makeClient((req) async {
        return http.Response(
          jsonEncode({
            'message': 'target is not an active guardian of this profile',
            'code': 'P0002',
          }),
          400,
        );
      });
      final notFoundService = SupabaseSharingService(
        client: notFoundClient,
        syncEngine: syncEngine,
      );
      await expectLater(
        notFoundService.updateGuardianRole(
          profileId: 'p1',
          targetUserId: 'u1',
          newRole: GuardianRole.viewer,
        ),
        throwsA(isA<SharingNotFoundFailure>()),
      );
    });
  });

  // Issue #1504. The server raised several ordinary refusals with SQLSTATE
  // 55000, and the mapper read any all-digit code of 500 or more as a
  // network failure before it looked at the message. A SQLSTATE is five
  // characters and is never an HTTP status; postgrest puts the status in
  // `code` only when the body carried no code of its own, and then it is
  // three.
  group('every refusal the sharing RPCs raise (issue #1504)', () {
    const profile = '01JABCDEF01234567890123456';

    /// Calls the service method that rides the RPC named [function].
    Future<Object?> call(SupabaseSharingService service, String function) =>
        switch (function) {
          'create_guardian_invitation' => service.createInvite(
              profileId: profile,
              role: GuardianRole.caregiver,
            ),
          'accept_guardian_invitation' =>
            service.acceptInvite(rawToken: 'any-token'),
          'preview_guardian_invitation' =>
            service.previewInvite(rawToken: 'any-token'),
          'revoke_guardian_invitation' => service.cancelInvite('inv-1'),
          'revoke_guardian' => service.revokeGuardian(
              profileId: profile,
              targetUserId: 'u1',
            ),
          'update_guardian_role' => service.updateGuardianRole(
              profileId: profile,
              targetUserId: 'u1',
              newRole: GuardianRole.viewer,
            ),
          _ => throw ArgumentError.value(function, 'function'),
        };

    /// A client whose server answers every call the way PostgREST answers
    /// a `raise exception`: the SQLSTATE in the body's `code`, the HTTP
    /// status beside it.
    SupabaseClient refusing(String sqlstate, int status, String message) =>
        makeClient((req) async => http.Response(
              jsonEncode({
                'code': sqlstate,
                'details': null,
                'hint': null,
                'message': message,
              }),
              status,
            ));

    // Function, SQLSTATE, the HTTP status PostgREST gives that SQLSTATE,
    // the message, and what it reads as. Taken from the newest definition
    // of each function in supabase/migrations: 20260920120000 (create,
    // accept and preview_guardian_invitation), 20260906190000
    // (revoke_guardian_invitation), 20260918160000 (revoke_guardian),
    // 20260915010000 (update_guardian_role), and the 20261005143105 trigger
    // on a second subject invitation. The browser client's
    // webapp/test/sharing.test.ts holds the same rows with the same kinds.
    // Each is read as a signed-in caller; "authentication required" is
    // below.
    const refusals = <(String, String, int, String, SharingFailure)>[
      (
        'create_guardian_invitation',
        '42501',
        403,
        'caller lacks permission to invite guardians for this profile',
        SharingFailure.unauthorized(),
      ),
      (
        'create_guardian_invitation',
        '22023',
        400,
        'invalid role: owner',
        SharingFailure.invalidToken(),
      ),
      (
        'create_guardian_invitation',
        '42501',
        403,
        'only the primary guardian can invite a co-parent',
        SharingFailure.unauthorized(),
      ),
      (
        'create_guardian_invitation',
        '22023',
        400,
        'a subject invitation must grant the caregiver role',
        SharingFailure.invalidToken(),
      ),
      (
        'create_guardian_invitation',
        '22023',
        400,
        'p_ttl_hours must be between 1 and 168',
        SharingFailure.invalidToken(),
      ),
      (
        'create_guardian_invitation',
        '22023',
        400,
        'token_hash must be a 64-character hex string',
        SharingFailure.invalidToken(),
      ),
      (
        'create_guardian_invitation',
        'P0001',
        400,
        'this profile already has a subject; a subject invitation cannot be '
            'created for it',
        SharingFailure.other(),
      ),
      (
        'accept_guardian_invitation',
        '22023',
        400,
        'token_hash must be a 64-character hex string',
        SharingFailure.invalidToken(),
      ),
      (
        'accept_guardian_invitation',
        'P0002',
        500,
        'invitation not found',
        SharingFailure.notFound(),
      ),
      (
        'accept_guardian_invitation',
        '55000',
        500,
        'invitation already accepted',
        SharingFailure.alreadyAccepted(),
      ),
      // Was the network failure.
      (
        'accept_guardian_invitation',
        '55000',
        500,
        'invitation was revoked',
        SharingFailure.revoked(),
      ),
      (
        'accept_guardian_invitation',
        '55000',
        500,
        'invitation has expired',
        SharingFailure.expired(),
      ),
      (
        'accept_guardian_invitation',
        '23505',
        409,
        'user is already an active guardian of this profile',
        SharingFailure.alreadyGuardian(),
      ),
      // Was the network failure.
      (
        'accept_guardian_invitation',
        '55000',
        500,
        'guardian access to this profile was revoked; a new invitation is '
            'required',
        SharingFailure.revoked(),
      ),
      (
        'preview_guardian_invitation',
        '22023',
        400,
        'token_hash must be a 64-character hex string',
        SharingFailure.invalidToken(),
      ),
      // Was the network failure. Neither client shows a preview's kind
      // (both say the preview could not be loaded), so it needs no copy of
      // its own.
      (
        'preview_guardian_invitation',
        '55000',
        500,
        'too many preview attempts; wait a moment and try again',
        SharingFailure.other(),
      ),
      (
        'revoke_guardian_invitation',
        '42501',
        403,
        'caller lacks permission to cancel this invitation',
        SharingFailure.unauthorized(),
      ),
      (
        'revoke_guardian',
        '42501',
        403,
        'caller is not a guardian of this profile',
        SharingFailure.unauthorized(),
      ),
      // Was the network failure. Manage guardians shows its own line for a
      // failed removal, whatever the kind.
      (
        'revoke_guardian',
        '55000',
        500,
        'the sole primary guardian cannot leave the profile',
        SharingFailure.other(),
      ),
      (
        'revoke_guardian',
        '42501',
        403,
        'insufficient permission to revoke this guardian',
        SharingFailure.unauthorized(),
      ),
      (
        'update_guardian_role',
        '42501',
        403,
        'primary_guardian cannot be granted through update_guardian_role',
        SharingFailure.unauthorized(),
      ),
      (
        'update_guardian_role',
        '22023',
        400,
        'invalid role: owner',
        SharingFailure.invalidToken(),
      ),
      (
        'update_guardian_role',
        '42501',
        403,
        'cannot change your own role',
        SharingFailure.unauthorized(),
      ),
      (
        'update_guardian_role',
        '42501',
        403,
        'caller is not a guardian of this profile',
        SharingFailure.unauthorized(),
      ),
      (
        'update_guardian_role',
        'P0002',
        500,
        'target is not an active guardian of this profile',
        SharingFailure.notFound(),
      ),
      (
        'update_guardian_role',
        '42501',
        403,
        "insufficient permission to change this guardian's role",
        SharingFailure.unauthorized(),
      ),
    ];

    for (final (function, sqlstate, status, message, expected) in refusals) {
      test('$function: "$message" ($sqlstate, HTTP $status) is $expected',
          () async {
        final client = refusing(sqlstate, status, message);
        await signIn(client, 'user-mom');
        final service =
            SupabaseSharingService(client: client, syncEngine: syncEngine);

        await expectLater(call(service, function), throwsA(expected));
        expect(requests.last.url.path, '/rest/v1/rpc/$function');
      });
    }

    // Every one of the six opens with the same check. It can only be
    // raised when there is no session, which reads as "sign in" (#885).
    for (final function in const [
      'create_guardian_invitation',
      'accept_guardian_invitation',
      'preview_guardian_invitation',
      'revoke_guardian_invitation',
      'revoke_guardian',
      'update_guardian_role',
    ]) {
      test('$function: "authentication required" (42501, HTTP 401) is '
          '${const SharingFailure.notSignedIn()}', () async {
        final client = refusing('42501', 401, 'authentication required');
        // Deliberately no signIn(): the client holds no session.
        final service =
            SupabaseSharingService(client: client, syncEngine: syncEngine);

        await expectLater(
          call(service, function),
          throwsA(const SharingFailure.notSignedIn()),
        );
      });
    }

    test('a SQLSTATE no refusal matches is the generic failure, never the '
        'network one, whatever its digits', () async {
      for (final (sqlstate, status, message) in const [
        ('55000', 500, 'a refusal this build has not heard of'),
        ('57014', 500, 'canceling statement due to statement timeout'),
        ('23514', 400, 'new row violates check constraint'),
      ]) {
        final client = refusing(sqlstate, status, message);
        await signIn(client, 'user-mom');
        final service =
            SupabaseSharingService(client: client, syncEngine: syncEngine);

        await expectLater(
          service.acceptInvite(rawToken: 'any-token'),
          throwsA(const SharingFailure.other()),
          reason: '$sqlstate is a SQLSTATE, not an HTTP status',
        );
      }
    });
  });

  group('a transport or server failure is still the network kind '
      '(issue #1504)', () {
    SupabaseSharingService serviceOver(http.Client httpClient) =>
        SupabaseSharingService(
          client: SupabaseClient(
            'https://example.supabase.co',
            'anon-key',
            httpClient: httpClient,
            authOptions: const AuthClientOptions(autoRefreshToken: false),
            postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
          ),
          syncEngine: syncEngine,
        );

    /// A server that answers with [body] under [status]: not PostgREST's
    /// error document, so postgrest reports the status itself as the code.
    SupabaseSharingService answering(int status, String body) => serviceOver(
          MockClient((request) async =>
              http.Response(body, status, request: request)),
        );

    test('a request that never completes', () async {
      for (final Object error in [
        const SocketException('connection refused'),
        http.ClientException('Connection closed before full header was received'),
      ]) {
        final service = serviceOver(MockClient((request) async => throw error));

        await expectLater(
          service.acceptInvite(rawToken: 'any-token'),
          throwsA(const SharingFailure.network()),
          reason: '${error.runtimeType} is a transport failure',
        );
      }
    });

    test('an HTTP 503 whose body carries no code of its own', () async {
      for (final body in const [
        '<html><body><h1>503 Service Temporarily Unavailable</h1></body></html>',
        '{"message":"name resolution failed"}',
      ]) {
        await expectLater(
          answering(503, body).acceptInvite(rawToken: 'any-token'),
          throwsA(const SharingFailure.network()),
          reason: 'HTTP 503 with body $body',
        );
      }
    });

    test('a gateway page is not read for a refusal, whatever it says',
        () async {
      // Each of these used to be matched on its wording before the status
      // was looked at: an invalid-link, a not-found and an expired failure.
      for (final (status, body) in const [
        (526, '<html><head><title>Invalid SSL certificate</title></head></html>'),
        (502, '<html><body>The origin server was not found</body></html>'),
        (504, '<html><body>The gateway timed out; the request expired</body></html>'),
      ]) {
        await expectLater(
          answering(status, body).acceptInvite(rawToken: 'any-token'),
          throwsA(const SharingFailure.network()),
          reason: 'HTTP $status with body $body',
        );
      }
    });
  });
}
