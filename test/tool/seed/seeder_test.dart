import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../../tool/seed_test_accounts/payload_generator.dart';
import '../../../tool/seed_test_accounts/seed_config.dart';
import '../../../tool/seed_test_accounts/seeder.dart';
import '../../../tool/seed_test_accounts/state_store.dart';
import '../../../tool/seed_test_accounts/supabase_seed_client.dart';

/// Routes requests to a handler and records every RPC + write call.
class _ScriptedClient extends http.BaseClient {
  _ScriptedClient(this.handler);

  final Future<http.Response> Function(http.Request request) handler;
  final calls = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest baseRequest) async {
    final request = baseRequest as http.Request;
    final path = request.url.path;
    if (path.contains('/rpc/')) {
      calls.add('RPC ${path.split('/').last}');
    } else if (path.contains('/token')) {
      calls.add('SIGNIN');
    } else if (path.contains('/admin/')) {
      calls.add('ADMIN ${request.method} $path');
    } else {
      calls.add('GET $path');
    }
    final response = await handler(request);
    return http.StreamedResponse(
      http.ByteStream.fromBytes(response.bodyBytes),
      response.statusCode,
      headers: {
        'content-type': 'application/json',
        ...response.headers,
      },
    );
  }
}

http.Response _json(Object? body,
        {int status = 200, Map<String, String>? headers}) =>
    http.Response(jsonEncode(body), status,
        headers: headers ?? const <String, String>{});

DateTime _fixedClock() => DateTime.utc(2026, 9, 14, 9, 30);

SeedToolConfig _config() => SeedToolConfig(
      supabaseUrl: 'http://127.0.0.1:54321',
      publishableKey: 'pk-test',
      secretKey: 'sk-test',
      target: const SeedAccount(
          email: 'seed.e2e.local@example.com', password: 'pw-target'),
      partner: const SeedAccount(
          email: 'seed.partner@example.com', password: 'pw-partner'),
      allowlist: const [
        'seed.e2e.local@example.com',
        'seed.partner@example.com',
      ],
    );

class _MemoryStateStore extends SeedStateStore {
  SeedState state = const SeedState();
  String? lastWrite;

  @override
  SeedState load(String path) => state;

  @override
  void write(String path, SeedState state) {
    lastWrite = state.encode();
    this.state = state;
  }
}

void main() {
  group('foreign-profile guard (refuses, touching nothing)', () {
    test('a live profile the tool did not create aborts before any write',
        () async {
      final client = _ScriptedClient((request) async {
        final path = request.url.path;
        if (path.contains('/token')) {
          return _json({
            'access_token': 'tok',
            'user': {'id': 'uid-target'},
          });
        }
        if (path.contains('/rest/v1/profiles')) {
          // A profile the tool never created.
          return _json([
            {'id': '01ARZ3NDEKTSV4RRFFQ69G5ZZZ'},
          ]);
        }
        if (path.contains('/rest/v1/profile_guardians')) {
          return _json([]);
        }
        throw StateError('unexpected request: ${request.url}');
      });
      final store = _MemoryStateStore();
      final seeder = TestAccountSeeder(SeederDeps(
        config: _config(),
        client: SupabaseSeedClient(config: _config(), httpClient: client),
        months: 12,
        seed: 7,
        statePath: 'unused',
        logger: (_) {},
        clock: _fixedClock,
        stateReaderWriter: store,
      ));

      await expectLater(
        seeder.run(),
        throwsA(isA<SeedRunException>().having(
          (e) => e.message,
          'message',
          contains('did not create'),
        )),
      );
      expect(
        client.calls.where((c) => c.startsWith('RPC')).toList(),
        isEmpty,
        reason: 'the guard refuses before ANY write, including reset',
      );
      expect(client.calls.where((c) => c.startsWith('ADMIN')).toList(),
          isEmpty);
    });
  });

  group('reset + re-seed (the idempotent re-run path)', () {
    test('delete_profile_data is invoked for exactly the state-file '
        'profiles, then the payload is re-pushed', () async {
      const priorProfileId = '01ARZ3NDEKTSV4RRFFQ69G5AAA';
      final store = _MemoryStateStore()
        ..state = SeedState(runs: {
          'seed.e2e.local@example.com': SeedStateRecord(
            targetEmail: 'seed.e2e.local@example.com',
            partnerEmail: 'seed.partner@example.com',
            profileIds: const [priorProfileId],
            months: 12,
            seed: 7,
          ),
        });

      final expectedPayload = generateSeedPayload(const SeedSpec(
        months: 12,
        seed: 7,
        clock: _fixedClock,
      ));
      final newProfileIds = expectedPayload.profiles
          .map((p) => p['id'])
          .whereType<String>()
          .toSet();
      var profilesReads = 0;

      http.Response respond(http.Request request) {
        final path = request.url.path;
        if (path.contains('/token')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final email = body['email'] as String;
          return _json({
            'access_token': 'tok-$email',
            'user': {
              'id': email.startsWith('seed.partner') ? 'uid-partner' : 'uid-target',
            },
          });
        }
        if (path.contains('/rest/v1/profiles')) {
          // Read 1 (target guard, pre-reset): only the prior tool-created
          // profile is live. Read 2 (partner guard, post-reset): nothing
          // (the reset tombstoned it). Read 3 (read-back): the fresh
          // profiles from this run's payload.
          profilesReads++;
          if (profilesReads == 1) {
            return _json([
              {'id': priorProfileId},
            ]);
          }
          if (profilesReads == 2) return _json([]);
          return _json([
            for (final id in newProfileIds) {'id': id},
          ]);
        }
        if (path.contains('/rest/v1/profile_guardians')) {
          return _json([]);
        }
        if (path.contains('/rest/v1/day_entries')) {
          return _json(
            [],
            headers: {
              'content-range': '0-0/${expectedPayload.dayEntries.length}',
            },
          );
        }
        if (path.contains('/rpc/delete_profile_data')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['p_profile_id'], priorProfileId);
          return _json({'day_entries': 365, 'observations': 400});
        }
        if (path.contains('/rpc/sync_push')) {
          return _json({'resolved': [], 'rejected': []});
        }
        if (path.contains('/rpc/')) {
          return _json({'ok': true});
        }
        throw StateError('unexpected request: ${request.url}');
      }

      final client = _ScriptedClient((request) async => respond(request));
      final seeder = TestAccountSeeder(SeederDeps(
        config: _config(),
        client: SupabaseSeedClient(config: _config(), httpClient: client),
        months: 12,
        seed: 7,
        statePath: 'unused',
        logger: (_) {},
        clock: _fixedClock,
        stateReaderWriter: store,
      ));

      final summary = await seeder.run();

      final deletes = client.calls
          .where((c) => c == 'RPC delete_profile_data')
          .toList();
      expect(deletes, hasLength(1),
          reason: 'reset runs delete_profile_data exactly once per '
              'state-file profile');
      expect(
        client.calls.where((c) => c == 'RPC sync_push').length,
        greaterThan(4),
      );
      // Sharing exercised through the real RPCs.
      expect(client.calls, contains('RPC create_guardian_invitation'));
      expect(client.calls, contains('RPC accept_guardian_invitation'));
      expect(client.calls, contains('RPC create_prediction_connection'));
      expect(client.calls, contains('RPC accept_prediction_connection'));
      expect(client.calls, contains('RPC upsert_reminder_window'));
      // The invitation roles: co_parent (adult) and caregiver (teen) —
      // pinned by the request bodies recorded below.
      expect(summary['dayEntries'], expectedPayload.dayEntries.length);

      final written = store.state
          .runs['seed.e2e.local@example.com']!;
      expect(written.profileIds, orderedEquals(newProfileIds.toList()));
      expect(written.retiredProfileIds, [priorProfileId]);
    });

    test('a config change without --reset-and-reseed is refused', () async {
      final store = _MemoryStateStore()
        ..state = SeedState(runs: {
          'seed.e2e.local@example.com': SeedStateRecord(
            targetEmail: 'seed.e2e.local@example.com',
            partnerEmail: 'seed.partner@example.com',
            profileIds: const ['01ARZ3NDEKTSV4RRFFQ69G5AAA'],
            months: 18,
            seed: 42,
          ),
        });
      final client = _ScriptedClient((request) async => throw StateError(
          'no request may happen when the config differs'));
      final seeder = TestAccountSeeder(SeederDeps(
        config: _config(),
        client: SupabaseSeedClient(config: _config(), httpClient: client),
        months: 12,
        seed: 7,
        statePath: 'unused',
        logger: (_) {},
        clock: _fixedClock,
        stateReaderWriter: store,
      ));
      await expectLater(
        seeder.run(),
        throwsA(isA<SeedRunException>().having(
          (e) => e.message,
          'message',
          contains('--reset-and-reseed'),
        )),
      );
    });
  });

  group('rejected rows fail the run loudly', () {
    test('a non-empty rejected array aborts before anything else is pushed',
        () async {
      var syncPushCalls = 0;
      final client = _ScriptedClient((request) async {
        final path = request.url.path;
        if (path.contains('/token')) {
          return _json({
            'access_token': 'tok',
            'user': {'id': 'uid-target'},
          });
        }
        if (path.contains('/rpc/sync_push')) {
          syncPushCalls++;
          return _json({
            'resolved': [],
            'rejected': [
              {'id': '01ARZ3NDEKTSV4RRFFQ69G5BAD', 'rejected': true},
            ],
          });
        }
        if (path.contains('/rpc/')) {
          return _json({'ok': true});
        }
        if (path.contains('/rest/v1/')) {
          return _json([]);
        }
        throw StateError('unexpected request: ${request.url}');
      });
      final store = _MemoryStateStore();
      final seeder = TestAccountSeeder(SeederDeps(
        config: _config(),
        client: SupabaseSeedClient(config: _config(), httpClient: client),
        months: 12,
        seed: 7,
        statePath: 'unused',
        logger: (_) {},
        clock: _fixedClock,
        stateReaderWriter: store,
      ));
      await expectLater(
        seeder.run(),
        throwsA(isA<SeedRunException>().having(
          (e) => e.message,
          'message',
          allOf(contains('REJECTED'), contains('01ARZ3NDEKTSV4RRFFQ69G5BAD')),
        )),
      );
      expect(syncPushCalls, 1,
          reason: 'the very first rejected batch stops the run');
    });
  });
}
