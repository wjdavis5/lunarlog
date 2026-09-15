/// U10 (KTD2, KTD3): [SupabaseSyncTransport] over a real `SupabaseClient`
/// whose HTTP layer is a `MockClient`, so the tests pin the actual request
/// paths, bodies and query strings PostgREST will see, plus the mapping of
/// every failure class to a typed [SyncTransportError] that carries no
/// provider text.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunarlog/data/db/tables.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/data/sync/supabase_sync_transport.dart';
import 'package:lunarlog/data/sync/sync_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const baseUrl = 'https://example.supabase.co';
const profileId = '01J0000000000000000000000A';
const entryId = '01J0000000000000000000000B';

Map<String, Object?> profileJson({int version = 1}) => {
      'id': profileId,
      'user_id': '00000000-0000-0000-0000-000000000000',
      'display_name': 'Kid',
      'is_minor': true,
      'sort_order': 0,
      'archived_at': null,
      'created_at': '2026-09-01T10:00:00.123+00:00',
      'updated_at': '2026-09-01T10:00:00.123+00:00',
      'deleted_at': null,
      'server_version': version,
    };

Map<String, Object?> entryJson({int version = 2, String flow = 'light'}) => {
      'id': entryId,
      'user_id': '00000000-0000-0000-0000-000000000000',
      'profile_id': profileId,
      'local_date': '2026-09-01',
      'tz': 'UTC',
      'flow': flow,
      'tags': ['cramps'],
      'note': null,
      'created_at': '2026-09-01T10:00:00+00:00',
      'updated_at': '2026-09-01T10:00:00.5+00:00',
      'deleted_at': null,
      'server_version': version,
    };

const observationId = '01J0000000000000000000000C';

/// Issue #240.
Map<String, Object?> observationJson({int version = 3}) => {
      'id': observationId,
      'day_entry_id': entryId,
      'profile_id': profileId,
      'local_date': '2026-09-01',
      'observed_at': null,
      'tz': 'UTC',
      'category': 'pain',
      'code': 'migraine',
      'value_num': null,
      'value_text': null,
      'unit': null,
      'intensity': 3,
      'excluded': false,
      'source': 'manual',
      'source_id': null,
      'raw': null,
      'created_at': '2026-09-01T10:00:00+00:00',
      'updated_at': '2026-09-01T10:00:00.5+00:00',
      'deleted_at': null,
      'server_version': version,
    };

http.Response json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

typedef Handler = Future<http.Response> Function(http.Request request);

void main() {
  late List<http.Request> requests;
  SupabaseClient? client;

  /// A client whose every request goes to [handler]; retries and token
  /// refresh are off so failures surface immediately. The response is
  /// re-issued with its `request` attached, as a real client would.
  SupabaseClient makeClient(Handler handler) => SupabaseClient(
        baseUrl,
        'anon-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          final response = await handler(request);
          return http.Response(
            response.body,
            response.statusCode,
            headers: response.headers,
            reasonPhrase: response.reasonPhrase,
            request: request,
          );
        }),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      );

  setUp(() {
    requests = [];
  });

  tearDown(() async {
    await client?.dispose();
    client = null;
  });

  group('push', () {
    test('POSTs the batch to /rpc/sync_push and decodes the result', () async {
      client = makeClient((_) async => json({
            'resolved': [
              {...profileJson(version: 7), 'table': 'profiles'},
              {...entryJson(version: 8), 'table': 'day_entries'},
            ],
            'rejected': [
              {'id': '01J0000000000000000000000C', 'rejected': true},
              {'id': null, 'rejected': true},
            ],
            'server_now': '2026-09-02T12:00:00.654321+00:00',
          }));
      final transport = SupabaseSyncTransport(client!);
      final batch = PushBatch(
        profiles: [
          {'id': profileId, 'display_name': 'Kid', 'updated_at': 'x'}
        ],
        dayEntries: [
          {'id': entryId, 'profile_id': profileId}
        ],
      );

      final result = await transport.push(batch);

      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), '$baseUrl/rest/v1/rpc/sync_push');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(request.headers['apikey'], 'anon-key');
      expect(request.headers['Authorization'], 'Bearer anon-key');
      expect(jsonDecode(request.body), {
        'p_profiles': [
          {'id': profileId, 'display_name': 'Kid', 'updated_at': 'x'}
        ],
        'p_day_entries': [
          {'id': entryId, 'profile_id': profileId}
        ],
        'p_observations': [],
        'p_profile_modes': [],
        'p_cycle_overrides': [],
        'p_care_notes': [],
        'p_visit_prep_items': [],
        'p_merge_events': [],
      });

      expect(result.resolved, hasLength(2));
      final p = result.resolved[0] as RemoteProfileRow;
      expect(p.id, profileId);
      expect(p.serverVersion, 7);
      expect(p.updatedAt, DateTime.parse('2026-09-01T10:00:00.123000Z'));
      final d = result.resolved[1] as RemoteDayEntryRow;
      expect(d.id, entryId);
      expect(d.flow, FlowLevel.light);
      expect(d.serverVersion, 8);
      expect(result.rejectedIds, ['01J0000000000000000000000C']);
      expect(result.serverNow, DateTime.utc(2026, 9, 2, 12, 0, 0, 654, 321));
      expect(result.serverNow.isUtc, isTrue);
    });

    test('observations round-trip through p_observations (Issue #240)',
        () async {
      client = makeClient((_) async => json({
            'resolved': [
              {...observationJson(version: 12), 'table': 'observations'},
            ],
            'rejected': [],
            'server_now': '2026-09-02T12:00:00+00:00',
          }));
      final transport = SupabaseSyncTransport(client!);
      final batch = PushBatch(
        observations: [
          {
            'id': observationId,
            'day_entry_id': entryId,
            'profile_id': profileId,
            'local_date': '2026-09-01',
            'category': 'pain',
            'code': 'migraine',
            'updated_at': 'x',
          }
        ],
      );

      final result = await transport.push(batch);

      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['p_observations'], hasLength(1));
      expect((body['p_observations'] as List).single, {
        'id': observationId,
        'day_entry_id': entryId,
        'profile_id': profileId,
        'local_date': '2026-09-01',
        'category': 'pain',
        'code': 'migraine',
        'updated_at': 'x',
      });
      final o = result.resolved.single as RemoteObservationRow;
      expect(o.id, observationId);
      expect(o.serverVersion, 12);
    });

    test('an empty batch is still a valid round-trip', () async {
      client = makeClient((_) async => json({
            'resolved': [],
            'rejected': [],
            'server_now': '2026-09-02T12:00:00+00:00',
          }));
      final result = await SupabaseSyncTransport(client!).push(PushBatch());
      expect(result.resolved, isEmpty);
      expect(result.rejectedIds, isEmpty);
      expect(jsonDecode(requests.single.body),
          {'p_profiles': [], 'p_day_entries': [], 'p_observations': [],
            'p_profile_modes': [], 'p_cycle_overrides': [],
            'p_care_notes': [], 'p_visit_prep_items': [],
            'p_merge_events': []});
    });

    test('sends at most 500 rows per array', () async {
      client = makeClient((_) async => json({
            'resolved': [],
            'rejected': [],
            'server_now': '2026-09-02T12:00:00+00:00',
          }));
      final rows = List.generate(500, (i) => <String, Object?>{'id': '$i'});
      final batch = PushBatch(profiles: rows, dayEntries: rows);
      expect(batch.rowCount, 1000);
      await SupabaseSyncTransport(client!).push(batch);
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['p_profiles'], hasLength(500));
      expect(body['p_day_entries'], hasLength(500));

      final tooMany = List.generate(501, (i) => <String, Object?>{'id': '$i'});
      expect(() => PushBatch(profiles: tooMany), throwsArgumentError);
      expect(() => PushBatch(dayEntries: tooMany), throwsArgumentError);
      expect(PushBatch.maxRows, 500);
    });

    test('a malformed resolved row is `other`, never a codec exception',
        () async {
      client = makeClient((_) async => json({
            'resolved': [
              {...entryJson(flow: 'torrential'), 'table': 'day_entries'},
            ],
            'rejected': [],
            'server_now': '2026-09-02T12:00:00+00:00',
          }));
      expect(
        () => SupabaseSyncTransport(client!).push(PushBatch()),
        throwsA(isA<SyncTransportOtherError>()),
      );
    });

    test('a response that is not the RPC shape is `other`', () async {
      client = makeClient((_) async => json([1, 2, 3]));
      expect(
        () => SupabaseSyncTransport(client!).push(PushBatch()),
        throwsA(isA<SyncTransportOtherError>()),
      );
    });
  });

  group('pullPage', () {
    test('GETs the table with after_version, order and limit', () async {
      client = makeClient((_) async => json([
            profileJson(version: 43),
            profileJson(version: 44),
          ]));
      final rows = await SupabaseSyncTransport(client!).pullPage(
        table: SyncTable.profiles,
        afterVersion: 42,
        limit: 500,
      );

      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/rest/v1/profiles');
      expect(request.url.queryParameters, {
        'select': '*',
        'server_version': 'gt.42',
        // postgrest appends the default null ordering; the column is NOT
        // NULL so it never applies.
        'order': 'server_version.asc.nullslast',
        'limit': '500',
      });
      expect(request.headers['Authorization'], 'Bearer anon-key');
      expect(rows, hasLength(2));
      expect(rows.every((r) => r is RemoteProfileRow), isTrue);
      expect(rows.map((r) => r.serverVersion), [43, 44]);
    });

    test('day entries use the day_entries table', () async {
      client = makeClient((_) async => json([entryJson(version: 9)]));
      final rows = await SupabaseSyncTransport(client!).pullPage(
        table: SyncTable.dayEntries,
        afterVersion: 0,
        limit: 100,
      );
      final request = requests.single;
      expect(request.url.path, '/rest/v1/day_entries');
      expect(request.url.queryParameters['server_version'], 'gt.0');
      expect(request.url.queryParameters['limit'], '100');
      final row = rows.single as RemoteDayEntryRow;
      expect(row.id, entryId);
      expect(row.tags, ['cramps']);
      expect(row.serverVersion, 9);
      expect(row.updatedAt, DateTime.utc(2026, 9, 1, 10, 0, 0, 500));
    });

    test('profile guardians use the profile_guardians table', () async {
      client = makeClient((_) async => json([
            {
              'id': '00000000-0000-0000-0000-000000000001',
              'profile_id': profileId,
              'user_id': '00000000-0000-0000-0000-000000000002',
              'role': 'co_parent',
              'status': 'accepted',
              'display_name': 'Dad',
              'invited_by': null,
              'created_at': '2026-03-01T12:00:00.000Z',
              'updated_at': '2026-03-01T12:00:00.000Z',
              'server_version': 5,
            }
          ]));
      final rows = await SupabaseSyncTransport(client!).pullPage(
        table: SyncTable.profileGuardians,
        afterVersion: 0,
        limit: 100,
      );
      final request = requests.single;
      expect(request.url.path, '/rest/v1/profile_guardians');
      expect(request.url.queryParameters['server_version'], 'gt.0');
      expect(request.url.queryParameters['limit'], '100');
      final row = rows.single as RemoteProfileGuardianRow;
      expect(row.id, '00000000-0000-0000-0000-000000000001');
      expect(row.profileId, profileId);
      expect(row.role, 'co_parent');
      expect(row.displayName, 'Dad');
      expect(row.serverVersion, 5);
    });

    test('observations use the observations table (Issue #240)', () async {
      client = makeClient((_) async => json([observationJson(version: 11)]));
      final rows = await SupabaseSyncTransport(client!).pullPage(
        table: SyncTable.observations,
        afterVersion: 0,
        limit: 100,
      );
      final request = requests.single;
      expect(request.url.path, '/rest/v1/observations');
      expect(request.url.queryParameters['server_version'], 'gt.0');
      final row = rows.single as RemoteObservationRow;
      expect(row.id, observationId);
      expect(row.dayEntryId, entryId);
      expect(row.category, 'pain');
      expect(row.code, 'migraine');
      expect(row.intensity, 3);
      expect(row.serverVersion, 11);
    });

    test('deleted profiles use the deleted_profiles table (Issue #522)',
        () async {
      client = makeClient((_) async => json([
            {
              'profile_id': profileId,
              'deleted_at': '2026-09-01T10:00:00+00:00',
              'server_version': 9,
            }
          ]));
      final rows = await SupabaseSyncTransport(client!).pullPage(
        table: SyncTable.deletedProfiles,
        afterVersion: 0,
        limit: 100,
      );
      final request = requests.single;
      expect(request.url.path, '/rest/v1/deleted_profiles');
      final row = rows.single as RemoteDeletedProfileRow;
      expect(row.profileId, profileId);
      expect(row.deletedAt, DateTime.utc(2026, 9, 1, 10));
      expect(row.serverVersion, 9);
    });

    test('deleted_profiles falls back to an empty page — never a cycle '
        'failure — when the server has not run the migration adding it yet '
        '(issue #522)', () async {
      client = makeClient((_) async => json(
            {
              'message': 'Could not find the table \'public.deleted_profiles\'',
              'code': 'PGRST205',
            },
            status: 404,
          ));
      final rows = await SupabaseSyncTransport(client!).pullPage(
        table: SyncTable.deletedProfiles,
        afterVersion: 0,
        limit: 100,
      );
      expect(rows, isEmpty);
    });

    test('a "table not found" response for any OTHER table still throws — '
        'the leniency above is scoped to deleted_profiles only', () async {
      client = makeClient((_) async => json(
            {'message': 'Could not find the table', 'code': 'PGRST205'},
            status: 404,
          ));
      await expectLater(
        SupabaseSyncTransport(client!).pullPage(
          table: SyncTable.profiles,
          afterVersion: 0,
          limit: 100,
        ),
        throwsA(isA<SyncTransportOtherError>()),
      );
    });

    test('an empty page decodes to an empty list', () async {
      client = makeClient((_) async => json([]));
      final rows = await SupabaseSyncTransport(client!).pullPage(
        table: SyncTable.profiles,
        afterVersion: 10,
        limit: 500,
      );
      expect(rows, isEmpty);
    });

    test('rejects a non-positive limit before any request', () async {
      client = makeClient((_) async => json([]));
      expect(
        () => SupabaseSyncTransport(client!).pullPage(
          table: SyncTable.profiles,
          afterVersion: 0,
          limit: 0,
        ),
        throwsArgumentError,
      );
      expect(requests, isEmpty);
    });

    test('a malformed row fails the pull instead of being silently skipped',
        () async {
      client = makeClient((_) async => json([
            {...entryJson(version: 45), 'tags': [1, 2]},
            entryJson(version: 46),
          ]));
      await expectLater(
        SupabaseSyncTransport(client!).pullPage(
          table: SyncTable.dayEntries,
          afterVersion: 0,
          limit: 500,
        ),
        throwsA(isA<SyncTransportOtherError>()),
      );
    });
  });

  group('primePullCycle / pullPage RPC caching (issue #598)', () {
    test('primePullCycle POSTs once to /rpc/sync_pull with p_cursors built '
        'from the given map, and pullPage then answers every one of those '
        'tables from the cache with no further request (multi-table cursor '
        'advancement in one round trip)', () async {
      client = makeClient((_) async => json({
            'profiles': [profileJson(version: 43), profileJson(version: 44)],
            'day_entries': [entryJson(version: 9)],
          }));
      final transport = SupabaseSyncTransport(client!);

      await transport.primePullCycle({
        SyncTable.profiles: 42,
        SyncTable.dayEntries: 0,
      });
      final profiles = await transport.pullPage(
        table: SyncTable.profiles, afterVersion: 42, limit: 500);
      final entries = await transport.pullPage(
        table: SyncTable.dayEntries, afterVersion: 0, limit: 500);

      expect(requests, hasLength(1),
          reason: 'one sync_pull call served both tables\' first page');
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), '$baseUrl/rest/v1/rpc/sync_pull');
      expect(jsonDecode(request.body), {
        'p_cursors': {'profiles': 42, 'day_entries': 0},
      });
      expect(profiles.map((r) => r.serverVersion), [43, 44]);
      expect(entries.single.serverVersion, 9);
    });

    test('a table not named in primePullCycle\'s cursors is unaffected — '
        'pullPage falls back to its own select for it', () async {
      client = makeClient((request) async {
        if (request.url.path.endsWith('/rpc/sync_pull')) {
          return json({'profiles': []});
        }
        return json([entryJson(version: 5)]);
      });
      final transport = SupabaseSyncTransport(client!);

      await transport.primePullCycle({SyncTable.profiles: 0});
      final rows = await transport.pullPage(
        table: SyncTable.dayEntries, afterVersion: 0, limit: 500);

      expect(rows, hasLength(1));
      expect(requests, hasLength(2));
      expect(requests.last.url.path, '/rest/v1/day_entries');
    });

    test('pullPage falls back to the per-table select when sync_pull was '
        'never primed at all (every pre-#598 caller)', () async {
      client = makeClient((_) async => json([profileJson(version: 7)]));
      final rows = await SupabaseSyncTransport(client!).pullPage(
        table: SyncTable.profiles, afterVersion: 0, limit: 500);
      expect(rows, hasLength(1));
      expect(requests.single.url.path, '/rest/v1/profiles');
    });

    test('a PGRST202 "function not found" response to sync_pull leaves the '
        'cache empty, so pullPage falls back to the per-table select — the '
        'graceful degradation for a server predating the migration that '
        'adds sync_pull', () async {
      client = makeClient((request) async {
        if (request.url.path.endsWith('/rpc/sync_pull')) {
          return json(
            {'message': 'Could not find the function', 'code': 'PGRST202'},
            status: 404,
          );
        }
        return json([profileJson(version: 8)]);
      });
      final transport = SupabaseSyncTransport(client!);

      await transport.primePullCycle({SyncTable.profiles: 0});
      final rows = await transport.pullPage(
        table: SyncTable.profiles, afterVersion: 0, limit: 500);

      expect(rows, hasLength(1));
      expect(requests, hasLength(2));
      expect(requests.first.url.toString(), '$baseUrl/rest/v1/rpc/sync_pull');
      expect(requests.last.url.path, '/rest/v1/profiles');
    });

    test('a raw Postgres 42883 undefined_function response to sync_pull '
        'also falls back cleanly (a stale PostgREST schema cache can '
        'surface the SQLSTATE directly instead of PGRST202)', () async {
      client = makeClient((request) async {
        if (request.url.path.endsWith('/rpc/sync_pull')) {
          return json(
            {'message': 'function does not exist', 'code': '42883'},
            status: 404,
          );
        }
        return json([profileJson(version: 8)]);
      });
      final transport = SupabaseSyncTransport(client!);

      await transport.primePullCycle({SyncTable.profiles: 0});
      final rows = await transport.pullPage(
        table: SyncTable.profiles, afterVersion: 0, limit: 500);

      expect(rows, hasLength(1));
      expect(requests, hasLength(2));
    });

    test('any other sync_pull failure (network, malformed shape) also '
        'degrades to the select fallback rather than failing the pull',
        () async {
      client = makeClient((request) async {
        if (request.url.path.endsWith('/rpc/sync_pull')) {
          return json([1, 2, 3]); // not the expected object shape
        }
        return json([profileJson(version: 8)]);
      });
      final transport = SupabaseSyncTransport(client!);

      await transport.primePullCycle({SyncTable.profiles: 0});
      final rows = await transport.pullPage(
        table: SyncTable.profiles, afterVersion: 0, limit: 500);

      expect(rows, hasLength(1));
      expect(requests, hasLength(2));
    });

    test('deletedProfiles always uses the select path, even when primed — '
        'sync_pull does not cover it', () async {
      client = makeClient((request) async {
        if (request.url.path.endsWith('/rpc/sync_pull')) {
          return json({'profiles': []});
        }
        return json([
          {
            'profile_id': profileId,
            'deleted_at': '2026-09-01T10:00:00+00:00',
            'server_version': 9,
          }
        ]);
      });
      final transport = SupabaseSyncTransport(client!);

      await transport.primePullCycle({SyncTable.profiles: 0});
      final rows = await transport.pullPage(
        table: SyncTable.deletedProfiles, afterVersion: 0, limit: 100);

      expect(rows, hasLength(1));
      expect(requests, hasLength(2));
      expect(requests.last.url.path, '/rest/v1/deleted_profiles');
    });

    test('a cached page capped at sync_pull\'s 500-row page size cannot '
        'fill a full page from what remains cached, so pullPage falls back '
        'to a fresh select for the rest rather than reporting a false '
        'short/final page', () async {
      final full500 = List.generate(500, (i) => profileJson(version: i + 1));
      client = makeClient((request) async {
        if (request.url.path.endsWith('/rpc/sync_pull')) {
          return json({'profiles': full500});
        }
        // The fallback select for the remainder beyond the cached window.
        return json([profileJson(version: 998), profileJson(version: 999)]);
      });
      final transport = SupabaseSyncTransport(client!);

      await transport.primePullCycle({SyncTable.profiles: 0});
      // Only 3 cached rows remain unconsumed past version 497, far short of
      // the requested limit — with the raw cache at the 500-row cap, this
      // must not be trusted as the final page.
      final rows = await transport.pullPage(
        table: SyncTable.profiles, afterVersion: 497, limit: 500);

      expect(requests, hasLength(2),
          reason: 'the short remainder forces a fresh select instead of '
              'trusting the capped cache');
      expect(rows.map((r) => r.serverVersion), [998, 999]);
    });

    test('a cached page shorter than the 500-row cap is trusted as final, '
        'even when the slice comes up short of the caller\'s limit',
        () async {
      client = makeClient((_) async => json({
            'profiles': [profileJson(version: 1), profileJson(version: 2)],
          }));
      final transport = SupabaseSyncTransport(client!);

      await transport.primePullCycle({SyncTable.profiles: 0});
      final rows = await transport.pullPage(
        table: SyncTable.profiles, afterVersion: 0, limit: 500);

      expect(requests, hasLength(1),
          reason: 'a genuinely short (uncapped) cached page is trusted '
              'without a fallback call');
      expect(rows.map((r) => r.serverVersion), [1, 2]);
    });

    test('a malformed row inside sync_pull\'s response is not silently '
        'skipped — it is treated as a decode failure and falls back to '
        'the select path instead', () async {
      client = makeClient((request) async {
        if (request.url.path.endsWith('/rpc/sync_pull')) {
          return json({
            'day_entries': [
              {...entryJson(version: 45), 'tags': [1, 2]},
            ],
          });
        }
        return json([entryJson(version: 46)]);
      });
      final transport = SupabaseSyncTransport(client!);

      await transport.primePullCycle({SyncTable.dayEntries: 0});
      final rows = await transport.pullPage(
        table: SyncTable.dayEntries, afterVersion: 0, limit: 500);

      expect(rows.single.serverVersion, 46);
      expect(requests, hasLength(2));
    });
  });

  group('fetchWatermark (issue #521)', () {
    test('POSTs to /rpc/sync_watermark and returns the decoded value',
        () async {
      client = makeClient((_) async => json(12345));
      final watermark = await SupabaseSyncTransport(client!).fetchWatermark();

      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(requests.single.url.toString(),
          '$baseUrl/rest/v1/rpc/sync_watermark');
      expect(watermark, 12345);
    });

    test('a PGRST202 "function not found" response falls back to null — '
        'the server has not run the paired migration yet', () async {
      client = makeClient((_) async => json(
            {'message': 'Could not find the function', 'code': 'PGRST202'},
            status: 404,
          ));
      final watermark = await SupabaseSyncTransport(client!).fetchWatermark();
      expect(watermark, isNull);
    });

    test('any other transport failure also falls back to null — the '
        'watermark is an optimization, never a correctness requirement',
        () async {
      client = makeClient((_) async => http.Response('bad gateway', 502));
      expect(await SupabaseSyncTransport(client!).fetchWatermark(), isNull);
      await client!.dispose();

      client = makeClient((_) async => throw const SocketException('down'));
      expect(await SupabaseSyncTransport(client!).fetchWatermark(), isNull);
    });

    test('a malformed (non-numeric) response falls back to null', () async {
      client = makeClient((_) async => json({'not': 'a number'}));
      expect(await SupabaseSyncTransport(client!).fetchWatermark(), isNull);
    });

    test('a quoted-string bigint (PR #582\'s public.sync_watermark() '
        'returns `bigint`, which some renderers quote to avoid precision '
        'loss) still decodes', () async {
      client = makeClient((_) async => json('12345'));
      expect(await SupabaseSyncTransport(client!).fetchWatermark(), 12345);
    });

    test('a non-numeric string falls back to null', () async {
      client = makeClient((_) async => json('not-a-number'));
      expect(await SupabaseSyncTransport(client!).fetchWatermark(), isNull);
    });
  });

  group('error mapping over HTTP', () {
    test('401 maps to auth on push and pull', () async {
      client = makeClient((_) async => json(
            {'message': 'JWT expired', 'code': 'PGRST301'},
            status: 401,
          ));
      final transport = SupabaseSyncTransport(client!);
      expect(
        () => transport.push(PushBatch()),
        throwsA(isA<SyncTransportAuthError>()),
      );
      expect(
        () => transport.pullPage(
            table: SyncTable.profiles, afterVersion: 0, limit: 10),
        throwsA(isA<SyncTransportAuthError>()),
      );
    });

    test('AuthException maps to auth', () async {
      client = makeClient((_) async => throw const AuthException('refresh'));
      expect(
        () => SupabaseSyncTransport(client!).push(PushBatch()),
        throwsA(isA<SyncTransportAuthError>()),
      );
    });

    test('5xx maps to network', () async {
      client = makeClient(
          (_) async => http.Response('<html>bad gateway</html>', 502));
      final transport = SupabaseSyncTransport(client!);
      expect(
        () => transport.push(PushBatch()),
        throwsA(isA<SyncTransportNetworkError>()),
      );
      expect(
        () => transport.pullPage(
            table: SyncTable.dayEntries, afterVersion: 0, limit: 10),
        throwsA(isA<SyncTransportNetworkError>()),
      );
    });

    test('socket and client exceptions map to network', () async {
      client = makeClient((_) async => throw const SocketException('down'));
      expect(
        () => SupabaseSyncTransport(client!).push(PushBatch()),
        throwsA(isA<SyncTransportNetworkError>()),
      );
      await client!.dispose();

      client = makeClient(
          (_) async => throw http.ClientException('connection closed'));
      expect(
        () => SupabaseSyncTransport(client!).pullPage(
            table: SyncTable.profiles, afterVersion: 0, limit: 10),
        throwsA(isA<SyncTransportNetworkError>()),
      );
    });

    test('a 400 with the batch-size SQLSTATE is `other`', () async {
      client = makeClient((_) async => json(
            {'message': 'p_profiles exceeds 500 rows', 'code': '22023'},
            status: 400,
          ));
      expect(
        () => SupabaseSyncTransport(client!).push(PushBatch()),
        throwsA(isA<SyncTransportOtherError>()),
      );
    });

    test('a deadlock SQLSTATE is `network`, for a prompt backoff retry '
        '(issue #95)', () async {
      client = makeClient((_) async => json(
            {'message': 'deadlock detected', 'code': '40P01'},
            status: 500,
          ));
      expect(
        () => SupabaseSyncTransport(client!).push(PushBatch()),
        throwsA(isA<SyncTransportNetworkError>()),
      );
    });

    test('typed errors never expose provider text', () async {
      client = makeClient((_) async => json(
            {'message': 'secret provider detail', 'code': 'PGRST301'},
            status: 401,
          ));
      try {
        await SupabaseSyncTransport(client!).push(PushBatch());
        fail('expected a transport error');
      } on SyncTransportError catch (e) {
        expect(e.toString(), isNot(contains('secret')));
        expect(e.toString(), isNot(contains('PGRST')));
      }
    });
  });

  group('mapSyncTransportError', () {
    test('classifies every known failure', () {
      expect(
          mapSyncTransportError(AuthRetryableFetchException()),
          isA<SyncTransportNetworkError>());
      expect(mapSyncTransportError(const AuthException('x')),
          isA<SyncTransportAuthError>());
      expect(
          mapSyncTransportError(
              const PostgrestException(message: 'x', code: '401')),
          isA<SyncTransportAuthError>());
      expect(
          mapSyncTransportError(
              const PostgrestException(message: 'x', code: '403')),
          isA<SyncTransportAuthError>());
      expect(
          mapSyncTransportError(
              const PostgrestException(message: 'x', code: 'PGRST303')),
          isA<SyncTransportAuthError>());
      expect(
          mapSyncTransportError(
              const PostgrestException(message: 'x', code: '42501')),
          isA<SyncTransportAuthError>());
      expect(
          mapSyncTransportError(
              const PostgrestException(message: 'x', code: '500')),
          isA<SyncTransportNetworkError>());
      expect(
          mapSyncTransportError(
              const PostgrestException(message: 'x', code: '503')),
          isA<SyncTransportNetworkError>());
      expect(
          mapSyncTransportError(
              const PostgrestException(message: 'x', code: '429')),
          isA<SyncTransportNetworkError>());
      expect(mapSyncTransportError(const SocketException('x')),
          isA<SyncTransportNetworkError>());
      expect(mapSyncTransportError(TimeoutException('x')),
          isA<SyncTransportNetworkError>());
      expect(mapSyncTransportError(http.ClientException('x')),
          isA<SyncTransportNetworkError>());
      expect(
          mapSyncTransportError(
              const PostgrestException(message: 'x', code: '22023')),
          isA<SyncTransportOtherError>());
      expect(
          mapSyncTransportError(
              const PostgrestException(message: 'x', code: '40P01')),
          isA<SyncTransportNetworkError>());
      expect(
          mapSyncTransportError(
              const PostgrestException(message: 'x', code: '40001')),
          isA<SyncTransportNetworkError>());
      expect(
          mapSyncTransportError(
              const PostgrestException(message: 'x', code: '55P03')),
          isA<SyncTransportNetworkError>());
      expect(
          mapSyncTransportError(
              const PostgrestException(message: 'x', code: '400')),
          isA<SyncTransportOtherError>());
      expect(mapSyncTransportError(StateError('x')),
          isA<SyncTransportOtherError>());
    });

    test('an already-typed error passes through unchanged', () {
      const rejected = SyncTransportError.rejected(['a']);
      expect(identical(mapSyncTransportError(rejected), rejected), isTrue);
    });
  });

  group('SyncTransportError', () {
    test('fieldless kinds are value-equal; rejected carries only ids', () {
      expect(const SyncTransportError.auth(), const SyncTransportError.auth());
      expect(const SyncTransportError.network(),
          isNot(const SyncTransportError.other()));
      const rejected = SyncTransportError.rejected(['a', 'b']);
      expect(rejected, const SyncTransportError.rejected(['a', 'b']));
      expect((rejected as SyncTransportRejectedError).ids, ['a', 'b']);
      expect(rejected.toString(), contains('2'));
    });
  });
}
