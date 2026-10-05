/// Issue #151 coverage for [SupabasePredictionConnectionService]: the RPC
/// call shapes (hashing, parameters, deep-link kind), typed failure
/// mapping (pregnancy mode, the one-connection cap, the one-directional
/// rule), and the projection fetch/publish payload round trip. Mirrors
/// supabase_sharing_service_test.dart's MockClient harness.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunarlog/data/sharing/supabase_prediction_connection_service.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/prediction.dart'
    show CycleConfidence;
import 'package:lunarlog/domain/sharing/prediction_connection_service.dart';
import 'package:lunarlog/domain/sharing/prediction_projection.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';
import 'package:lunarlog/ui/l10n/prediction_connection_failure_copy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _l10n = AppLocalizationsEn();

SupabaseClient makeClient(
    Future<http.Response> Function(http.Request) handler) {
  return SupabaseClient(
    'https://example.supabase.co',
    'anon-key',
    httpClient: MockClient((request) async {
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

void main() {
  group('createConnection', () {
    test('hashes the token and calls create_prediction_connection with the '
        'invite parameters', () async {
      final client = makeClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(req.url.path, '/rest/v1/rpc/create_prediction_connection');
        expect(body['p_profile_id'], '01JABCDEF01234567890123456');
        expect(body['p_token_hash'], hasLength(64));
        expect(body['p_recipient_label'], 'Partner');
        expect(body['p_ttl_hours'], 72);

        return http.Response(
          jsonEncode({
            'id': 'conn-1',
            'profile_id': '01JABCDEF01234567890123456',
            'expires_at': '2026-09-09T12:00:00.000Z',
          }),
          200,
        );
      });

      final service = SupabasePredictionConnectionService(client: client);
      final invite = await service.createConnection(
        profileId: '01JABCDEF01234567890123456',
        recipientLabel: 'Partner',
      );

      expect(invite.connectionId, 'conn-1');
      expect(invite.inviteUri.scheme, 'lunarlog');
      expect(invite.inviteUri.host, 'invite');
      expect(invite.inviteUri.queryParameters['code'], invite.rawToken);
      expect(invite.inviteUri.queryParameters['kind'], 'prediction');
    });

    test('a pregnancy-mode refusal maps to its own typed failure', () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({
            'message':
                'prediction-only sharing is unavailable while this profile '
                    'is in Pregnancy mode',
            'code': 'P0001',
          }),
          400,
        );
      });

      final service = SupabasePredictionConnectionService(client: client);
      await expectLater(
        service.createConnection(profileId: 'p1'),
        throwsA(isA<PredictionConnectionFailure>()),
      );
    });

    test("issue #373: the server's minor-profile refusal maps to "
        'minorProfile, on create and on accept', () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({
            'message':
                "prediction-only sharing is unavailable for a minor's profile",
            'code': 'P0001',
          }),
          400,
        );
      });

      final service = SupabasePredictionConnectionService(client: client);
      await expectLater(
        service.createConnection(profileId: 'p1'),
        throwsA(const PredictionConnectionFailure.minorProfile()),
      );
      await expectLater(
        service.acceptConnection(rawToken: 'code'),
        throwsA(const PredictionConnectionFailure.minorProfile()),
      );
      expect(
        predictionConnectionFailureCopy(
            _l10n, const PredictionConnectionFailure.minorProfile()),
        contains("minor's profile"),
      );
      expect(const PredictionConnectionFailure.minorProfile().toString(),
          'PredictionConnectionFailure.minorProfile');
    });

    test('the one-connection cap maps to alreadyConnected', () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({
            'message':
                'this profile already has a prediction-only connection or '
                    'pending invite',
            'code': 'P0001',
          }),
          400,
        );
      });

      final service = SupabasePredictionConnectionService(client: client);
      await expectLater(
        service.createConnection(profileId: 'p1'),
        throwsA(isA<PredictionConnectionFailure>()),
      );
    });
  });

  group('acceptConnection', () {
    test('calls accept_prediction_connection with the token hash', () async {
      final client = makeClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(req.url.path, '/rest/v1/rpc/accept_prediction_connection');
        expect(body['p_token_hash'], hasLength(64));
        return http.Response(
          jsonEncode({
            'profile_id': '01JABCDEF01234567890123456',
            'profile_name': 'Riley',
            'connection_id': 'conn-1',
          }),
          200,
        );
      });

      final service = SupabasePredictionConnectionService(client: client);
      final result = await service.acceptConnection(rawToken: 'any-token');
      expect(result.profileId, '01JABCDEF01234567890123456');
      expect(result.profileName, 'Riley');
      expect(result.connectionId, 'conn-1');
    });

    test('the one-directional refusal maps to its own typed failure',
        () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({
            'message':
                'cannot share and view predictions with the same person at '
                    'the same time',
            'code': 'P0001',
          }),
          400,
        );
      });

      final service = SupabasePredictionConnectionService(client: client);
      await expectLater(
        service.acceptConnection(rawToken: 'any-token'),
        throwsA(isA<PredictionConnectionFailure>()),
      );
    });
  });

  // The server raises almost every refusal here with SQLSTATE 55000, and
  // the mapper read any all-digit code of 500 or more as a network failure
  // whenever no message matched. A SQLSTATE is five characters and is
  // never an HTTP status; postgrest puts the status in `code` only when
  // the body carried no code of its own, and then it is three. Same rule
  // as SupabaseSharingService (issue #1504).
  group('every refusal a code can meet', () {
    /// A client whose server answers the way PostgREST answers a
    /// `raise exception`: the SQLSTATE in the body's `code`, the HTTP
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

    // Whether the refusal comes from accepting a code (true) or making one
    // (false), its SQLSTATE, the HTTP status PostgREST gives that
    // SQLSTATE, the message, and what it reads as. Taken from the newest
    // definition of accept_prediction_connection and
    // create_prediction_connection (20260920100000).
    const refusals = <(bool, String, int, String, PredictionConnectionFailure)>[
      (
        true,
        'P0002',
        500,
        'prediction connection not found',
        PredictionConnectionFailure.notFound(),
      ),
      (
        true,
        '55000',
        500,
        'prediction connection was already accepted',
        PredictionConnectionFailure.alreadyAccepted(),
      ),
      // Was the network failure.
      (
        true,
        '55000',
        500,
        'prediction connection was revoked',
        PredictionConnectionFailure.notFound(),
      ),
      (
        true,
        '55000',
        500,
        'prediction connection has expired',
        PredictionConnectionFailure.expired(),
      ),
      // Was the network failure.
      (
        true,
        '55000',
        500,
        'the sharer cannot accept their own prediction connection',
        PredictionConnectionFailure.ownCode(),
      ),
      (
        true,
        '55000',
        500,
        "prediction-only sharing is unavailable for a minor's profile",
        PredictionConnectionFailure.minorProfile(),
      ),
      // Was the network failure.
      (
        true,
        '55000',
        500,
        'the sharer is no longer the primary guardian of this profile; the '
            'code is stale',
        PredictionConnectionFailure.notFound(),
      ),
      (
        true,
        '55000',
        500,
        'prediction-only sharing is unavailable while this profile is in '
            'Pregnancy mode',
        PredictionConnectionFailure.pregnancyMode(),
      ),
      (
        true,
        '55000',
        500,
        'you are already a guardian of this profile',
        PredictionConnectionFailure.alreadyGuardian(),
      ),
      (
        true,
        '55000',
        500,
        'cannot share and view predictions with the same person at the same '
            'time',
        PredictionConnectionFailure.oneDirectional(),
      ),
      (
        false,
        '42501',
        403,
        'only the accepted primary guardian can share predictions for this '
            'profile',
        PredictionConnectionFailure.unauthorized(),
      ),
      (
        false,
        '55000',
        500,
        "prediction-only sharing is unavailable for a minor's profile",
        PredictionConnectionFailure.minorProfile(),
      ),
      (
        false,
        '55000',
        500,
        'prediction-only sharing is unavailable while this profile is in '
            'Pregnancy mode',
        PredictionConnectionFailure.pregnancyMode(),
      ),
      (
        false,
        '23505',
        409,
        'this profile already has a prediction-only connection or pending '
            'invite',
        PredictionConnectionFailure.alreadyConnected(),
      ),
    ];

    for (final (accepting, sqlstate, status, message, expected) in refusals) {
      final what = accepting ? 'accepting' : 'making';
      test('$what a code, "$message" ($sqlstate) reads as $expected',
          () async {
        final service = SupabasePredictionConnectionService(
          client: refusing(sqlstate, status, message),
        );
        await expectLater(
          accepting
              ? service.acceptConnection(rawToken: 'any-token')
              : service.createConnection(
                  profileId: '01JABCDEF01234567890123456',
                ),
          throwsA(expected),
        );
      });
    }

    test('a refusal with a class-55 code and wording this client has never '
        'seen is not a network failure', () async {
      final service = SupabasePredictionConnectionService(
        client: refusing('55000', 500, 'a refusal added after this build'),
      );
      await expectLater(
        service.acceptConnection(rawToken: 'any-token'),
        throwsA(const PredictionConnectionFailure.other()),
      );
    });

    test('a gateway answering 503 with a page of its own is a network '
        'failure, whatever the page says', () async {
      final service = SupabasePredictionConnectionService(
        client: makeClient((req) async => http.Response(
              '<html><body>503: the service was revoked, not found, and '
              'has expired</body></html>',
              503,
              headers: {'content-type': 'text/html'},
            )),
      );
      await expectLater(
        service.acceptConnection(rawToken: 'any-token'),
        throwsA(const PredictionConnectionFailure.network()),
      );
    });

    test('a request that never completes is a network failure', () async {
      final service = SupabasePredictionConnectionService(
        client: makeClient(
          (req) async => throw http.ClientException('connection closed'),
        ),
      );
      await expectLater(
        service.acceptConnection(rawToken: 'any-token'),
        throwsA(const PredictionConnectionFailure.network()),
      );
    });
  });

  group('revokeConnection', () {
    test('calls revoke_prediction_connection', () async {
      final client = makeClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(req.url.path, '/rest/v1/rpc/revoke_prediction_connection');
        expect(body['p_connection_id'], 'conn-1');
        return http.Response('true', 200);
      });

      final service = SupabasePredictionConnectionService(client: client);
      await service.revokeConnection(connectionId: 'conn-1');
    });
  });

  group('leaveConnection', () {
    test('calls leave_prediction_connection (issue #462)', () async {
      final client = makeClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(req.url.path, '/rest/v1/rpc/leave_prediction_connection');
        expect(body['p_connection_id'], 'conn-2');
        return http.Response('true', 200);
      });

      final service = SupabasePredictionConnectionService(client: client);
      await service.leaveConnection(connectionId: 'conn-2');
    });

    test('a non-recipient refusal maps to unauthorized', () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({
            'message': "only the connection's recipient can leave it",
            'code': '42501',
          }),
          400,
        );
      });

      final service = SupabasePredictionConnectionService(client: client);
      await expectLater(
        service.leaveConnection(connectionId: 'conn-2'),
        throwsA(const PredictionConnectionFailure.unauthorized()),
      );
    });
  });

  group('fetchProjection', () {
    test('parses the derived-only payload and never anything else',
        () async {
      final client = makeClient((req) async {
        expect(req.url.path, '/rest/v1/rpc/get_prediction_projection');
        return http.Response(
          jsonEncode({
            'generated_at': '2026-09-07',
            'period_days': ['2026-09-09', '2026-09-10'],
            'fertile_days': [],
            'ovulation_days': ['2026-09-22'],
            'pms_days': ['2026-09-02'],
          }),
          200,
        );
      });

      final service = SupabasePredictionConnectionService(client: client);
      final projection =
          await service.fetchProjection(profileId: 'p1');

      expect(projection, isNotNull);
      expect(projection!.generatedAt, LocalDate(2026, 9, 7));
      expect(projection.periodDays, [LocalDate(2026, 9, 9), LocalDate(2026, 9, 10)]);
      expect(projection.ovulationDays, [LocalDate(2026, 9, 22)]);
      expect(projection.pmsDays, [LocalDate(2026, 9, 2)]);
    });

    test('a null result (no live connection) reads as null, not an error',
        () async {
      final client = makeClient((req) async {
        return http.Response('null', 200);
      });

      final service = SupabasePredictionConnectionService(client: client);
      expect(await service.fetchProjection(profileId: 'p1'), isNull);
    });
  });

  group('publishProjection', () {
    test('sends exactly the allowlisted derived keys', () async {
      final client = makeClient((req) async {
        expect(req.url.path, '/rest/v1/rpc/upsert_prediction_projection');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final projection = body['p_projection'] as Map<String, dynamic>;
        expect(projection.keys.toSet(),
            PredictionProjection.allowedKeys.toSet());
        return http.Response('null', 204);
      });

      final service = SupabasePredictionConnectionService(client: client);
      await service.publishProjection(
        profileId: 'p1',
        projection: PredictionProjection(
          generatedAt: LocalDate(2026, 9, 7),
          periodDays: [LocalDate(2026, 9, 10)],
          fertileDays: const [],
          ovulationDays: const [],
          pmsDays: const [],
        ),
      );
    });

    test('issue #593: sends confidence_tier unmodified when the projection '
        'carries one, now that prediction_projections\' server-side '
        'allowlist accepts it', () async {
      final client = makeClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final projection = body['p_projection'] as Map<String, dynamic>;
        expect(
          projection.keys.toSet(),
          {
            ...PredictionProjection.allowedKeys,
            PredictionProjection.confidenceTierKey,
          },
          reason: 'confidence_tier joined the server allowlist in '
              '20260915140000_prediction_projection_confidence_tier.sql '
              '(issue #593) - no strip needed any more',
        );
        expect(projection[PredictionProjection.confidenceTierKey], 'high');
        return http.Response('null', 204);
      });

      final service = SupabasePredictionConnectionService(client: client);
      await service.publishProjection(
        profileId: 'p1',
        projection: PredictionProjection(
          generatedAt: LocalDate(2026, 9, 7),
          periodDays: [LocalDate(2026, 9, 10)],
          fertileDays: const [],
          ovulationDays: const [],
          pmsDays: const [],
          confidenceTier: CycleConfidence.high,
        ),
      );
    });
  });

  group('retractProjection (issue LLA-061)', () {
    test('calls retract_prediction_projection with the profile id', () async {
      final client = makeClient((req) async {
        expect(req.url.path, '/rest/v1/rpc/retract_prediction_projection');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['p_profile_id'], 'p1');
        return http.Response('null', 204);
      });

      final service = SupabasePredictionConnectionService(client: client);
      await service.retractProjection(profileId: 'p1');
    });

    test('maps a server rejection through the same error mapping as every '
        'other RPC here', () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({
            'code': '42501',
            'message':
                'only an accepted guardian of this profile can retract its prediction projection',
          }),
          400,
        );
      });

      final service = SupabasePredictionConnectionService(client: client);
      await expectLater(
        service.retractProjection(profileId: 'p1'),
        throwsA(const PredictionConnectionFailure.unauthorized()),
      );
    });
  });

  group('getActiveConnection', () {
    test('selects explicit non-secret columns and maps the pending vs '
        'active shapes', () async {
      // Pending: recipient_user_id null.
      final client = makeClient((req) async {
        expect(req.url.path, '/rest/v1/prediction_connections');
        expect(req.url.queryParameters['select'],
            'id,profile_id,recipient_user_id,recipient_label,created_at,expires_at');
        return http.Response(
          jsonEncode([
            {
              'id': 'conn-1',
              'profile_id': 'p1',
              'recipient_user_id': null,
              'recipient_label': 'Partner',
              'created_at': '2026-09-07T00:00:00.000Z',
              'expires_at': '2026-09-10T00:00:00.000Z',
            }
          ]),
          200,
        );
      });

      final service = SupabasePredictionConnectionService(client: client);
      final connection = await service.getActiveConnection(profileId: 'p1');
      expect(connection, isNotNull);
      expect(connection!.pending, isTrue);
      expect(connection.recipientLabel, 'Partner');

      // Active: recipient named.
      final client2 = makeClient((req) async {
        return http.Response(
          jsonEncode([
            {
              'id': 'conn-1',
              'profile_id': 'p1',
              'recipient_user_id': '0a0a0a0a-0a0a-0a0a-0a0a-0a0a0a0a0a0a',
              'recipient_label': null,
              'created_at': '2026-09-07T00:00:00.000Z',
              'expires_at': '2026-09-10T00:00:00.000Z',
            }
          ]),
          200,
        );
      });
      final service2 = SupabasePredictionConnectionService(client: client2);
      final active = await service2.getActiveConnection(profileId: 'p1');
      expect(active!.pending, isFalse);

      // Empty: no connection.
      final client3 = makeClient((req) async {
        return http.Response(jsonEncode([]), 200);
      });
      final service3 = SupabasePredictionConnectionService(client: client3);
      expect(await service3.getActiveConnection(profileId: 'p1'), isNull);
    });
  });

  group('list short-circuits', () {
    test('outgoingConnectedProfileIds is empty while signed out',
        () async {
      var requested = false;
      final client = makeClient((req) async {
        requested = true;
        return http.Response('[]', 200);
      });

      final service = SupabasePredictionConnectionService(client: client);
      expect(await service.outgoingConnectedProfileIds(), isEmpty);
      expect(requested, isFalse,
          reason: 'no session means no query at all');
    });

    test('listIncomingConnections is empty while signed out', () async {
      var requested = false;
      final client = makeClient((req) async {
        requested = true;
        return http.Response('[]', 200);
      });

      final service = SupabasePredictionConnectionService(client: client);
      expect(await service.listIncomingConnections(), isEmpty);
      expect(requested, isFalse);
    });
  });
}
