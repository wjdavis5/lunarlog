/// Issue #264/#472/#883/#905 coverage for [SupabaseProfileErasureService]:
/// the RPC call shapes (`delete_profile_data`, with and without `p_source`),
/// typed failure mapping (unauthorized, invalid source, network), the local
/// wipe only runs AFTER the RPC has already succeeded when signed in (never
/// on a failed or offline call, Issue #905), and device-only profiles purge
/// locally without an RPC (Issue #883). Mirrors
/// supabase_sharing_service_test.dart's MockClient + MockSyncEngine
/// harness.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunarlog/data/db/db.dart' hide Profile;
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart' show FlowLevel;
import 'package:lunarlog/data/profiles/supabase_profile_erasure_service.dart';
import 'package:lunarlog/data/repositories/drift_imported_data_purge_repository.dart';
import 'package:lunarlog/domain/logging/tracking_preferences.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/measurement_unit.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/models/profile_relationship.dart';
import 'package:lunarlog/domain/profiles/profile_erasure_service.dart';
import 'package:lunarlog/domain/repositories/imported_data_purge_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSyncEngine implements SyncEngine {
  int syncRequestCount = 0;

  @override
  void requestSync() {
    syncRequestCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records every [applyServerPurge] call — never actually asked to
/// create/update/list/etc. in these tests, so those throw rather than
/// silently no-op.
class FakeProfilesRepository implements ProfilesRepository {
  final List<String> purgedIds = [];
  Object? purgeError;

  @override
  Future<void> applyServerPurge(String id) async {
    final error = purgeError;
    if (error != null) throw error;
    purgedIds.add(id);
  }

  @override
  Future<Profile> create({
    required String displayName,
    required bool isMinor,
    int sortOrder = 0,
    ProfileMode mode = ProfileMode.standard,
    int? birthYear,
    ProfileRelationship? relationship,
    LocalDate? lastPeriodStart,
    int? typicalCycleLengthDays,
    int? typicalPeriodLengthDays,
    BbtUnit bbtUnit = BbtUnit.celsius,
    WeightUnit weightUnit = WeightUnit.kg,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String id) => throw UnimplementedError();

  @override
  Future<Profile?> findById(String id) => throw UnimplementedError();

  @override
  Future<List<Profile>> list() => throw UnimplementedError();

  @override
  Future<void> setArchived(String id, bool archived) =>
      throw UnimplementedError();

  @override
  Future<Profile?> setTrackingPreferences(
          String id, TrackingPreferences? preferences) =>
      throw UnimplementedError();

  @override
  Future<Profile> update(Profile profile) => throw UnimplementedError();

  @override
  Stream<List<Profile>> watch() => throw UnimplementedError();
}

/// Records the local, source-scoped purge calls and serves canned
/// per-source counts — never touches drift.
class FakeImportedDataPurgeRepository implements ImportedDataPurgeRepository {
  final List<(String, String)> purges = [];
  Map<String, int> counts = const {};
  Object? purgeError;

  @override
  Future<void> applyLocalPurge({
    required String profileId,
    required String source,
  }) async {
    final error = purgeError;
    if (error != null) throw error;
    purges.add((profileId, source));
  }

  @override
  Future<Map<String, int>> liveSourceCounts(String profileId) async => counts;
}

/// A base64url JWT-shaped string whose payload decodes to `{sub, exp, iat}`
/// — enough for `GoTrueClient.recoverSession` to accept it as a live session
/// with no network call, so `client.auth.currentUser?.id` resolves locally
/// (the `supabase_sharing_service_test.dart` helper).
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
  late FakeProfilesRepository profiles;
  late FakeImportedDataPurgeRepository purge;
  late MockSyncEngine syncEngine;

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

  setUp(() {
    profiles = FakeProfilesRepository();
    purge = FakeImportedDataPurgeRepository();
    syncEngine = MockSyncEngine();
  });

  group('deleteProfile', () {
    test('calls delete_profile_data with only p_profile_id, applies the '
        'local wipe after success, and requests a sync', () async {
      final client = makeClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(req.url.path, '/rest/v1/rpc/delete_profile_data');
        expect(body['p_profile_id'], 'profile-1');
        expect(body.containsKey('p_source'), isFalse);
        return http.Response(jsonEncode({'profiles': 1}), 200);
      });

      final service = SupabaseProfileErasureService(
        client: client,
        profiles: profiles,
        importedDataPurge: purge,
        syncEngine: syncEngine,
      );
      await service.deleteProfile(profileId: 'profile-1');

      expect(profiles.purgedIds, ['profile-1']);
      expect(syncEngine.syncRequestCount, 1);
    });

    test('never applies the local wipe when the RPC fails (never delete '
        'locally on a failed call)', () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({
            'message':
                'profile not found or caller is not its accepted primary_guardian',
            'code': '42501',
          }),
          400,
        );
      });
      // Issue #883: this mapping is now auth-state dependent, so sign in to
      // keep this a genuine "signed in but lacks the role" (unauthorized)
      // case; the no-session equivalent is pinned separately below.
      await signIn(client, 'u1');

      final service = SupabaseProfileErasureService(
        client: client,
        profiles: profiles,
        importedDataPurge: purge,
        syncEngine: syncEngine,
      );
      await expectLater(
        service.deleteProfile(profileId: 'profile-1'),
        throwsA(const ProfileErasureFailure.unauthorized()),
      );

      expect(profiles.purgedIds, isEmpty);
      expect(syncEngine.syncRequestCount, 0);
    });

    test('an offline call maps to network and never touches local storage',
        () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          throw const SocketException('no network');
        }),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      );

      final service = SupabaseProfileErasureService(
        client: client,
        profiles: profiles,
        importedDataPurge: purge,
        syncEngine: syncEngine,
      );
      await expectLater(
        service.deleteProfile(profileId: 'profile-1'),
        throwsA(const ProfileErasureFailure.network()),
      );

      expect(profiles.purgedIds, isEmpty);
    });

    test('a failed local wipe after a successful RPC still propagates as '
        'an error, without a fabricated typed failure', () async {
      profiles.purgeError = StateError('local db closed');
      final client = makeClient((req) async {
        return http.Response(jsonEncode({'profiles': 1}), 200);
      });

      final service = SupabaseProfileErasureService(
        client: client,
        profiles: profiles,
        importedDataPurge: purge,
        syncEngine: syncEngine,
      );
      await expectLater(
        service.deleteProfile(profileId: 'profile-1'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('purgeImportedData', () {
    test('signed in: tombstones locally AND calls delete_profile_data with '
        'p_source, then requests a sync', () async {
      var rpcCalled = false;
      final client = makeClient((req) async {
        rpcCalled = true;
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(req.url.path, '/rest/v1/rpc/delete_profile_data');
        expect(body['p_profile_id'], 'profile-1');
        expect(body['p_source'], 'clue_import');
        return http.Response(
          jsonEncode({'day_entries': 3, 'observations': 5, 'import_jobs': 1}),
          200,
        );
      });
      await signIn(client, 'u1');

      final service = SupabaseProfileErasureService(
        client: client,
        profiles: profiles,
        importedDataPurge: purge,
        syncEngine: syncEngine,
      );
      await service.purgeImportedData(
        profileId: 'profile-1',
        source: PurgeableImportSource.clueImport,
      );

      expect(
        purge.purges,
        [('profile-1', 'clue_import')],
        reason: 'the local Drift tombstone always runs',
      );
      expect(rpcCalled, isTrue, reason: 'a session means the RPC runs');
      expect(syncEngine.syncRequestCount, 1);
      expect(
        profiles.purgedIds,
        isEmpty,
        reason: 'purgeImportedData never runs the full-profile wipe',
      );
    });

    test('signed out: tombstones the matching local rows, makes NO RPC call '
        'at all, and reports success on the strength of the local purge',
        () async {
      var rpcCalled = false;
      final client = makeClient((req) async {
        rpcCalled = true;
        return http.Response(jsonEncode({'error': 'should not be called'}), 500);
      });

      final service = SupabaseProfileErasureService(
        client: client,
        profiles: profiles,
        importedDataPurge: purge,
        syncEngine: syncEngine,
      );
      // No throw: the whole point of #883 is that a device-only profile can
      // purge without a session.
      await service.purgeImportedData(
        profileId: 'profile-1',
        source: PurgeableImportSource.fileImport,
      );

      expect(purge.purges, [('profile-1', 'file_import')]);
      expect(rpcCalled, isFalse, reason: 'no session: the RPC is skipped');
      expect(
        syncEngine.syncRequestCount,
        0,
        reason: 'nothing to reconcile with no session',
      );
    });

    test('a signed-in caller who genuinely lacks the primary-guardian role '
        'maps to unauthorized (the primary-guardian copy)', () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({
            'message':
                'profile not found or caller is not its accepted primary_guardian',
            'code': '42501',
          }),
          400,
        );
      });
      await signIn(client, 'not-primary');

      final service = SupabaseProfileErasureService(
        client: client,
        profiles: profiles,
        importedDataPurge: purge,
        syncEngine: syncEngine,
      );
      await expectLater(
        service.purgeImportedData(
          profileId: 'profile-1',
          source: PurgeableImportSource.fileImport,
        ),
        throwsA(const ProfileErasureFailure.unauthorized()),
      );
      // Issue #905: local purge must NOT run when the server refuses.
      expect(purge.purges, isEmpty);
      expect(syncEngine.syncRequestCount, 0);
    });

    test('a network/socket failure maps to network and leaves local state untouched (issue #905)',
        () async {
      final client = makeClient((req) async {
        throw const SocketException('offline');
      });
      await signIn(client, 'u1');

      final service = SupabaseProfileErasureService(
        client: client,
        profiles: profiles,
        importedDataPurge: purge,
        syncEngine: syncEngine,
      );
      await expectLater(
        service.purgeImportedData(
          profileId: 'profile-1',
          source: PurgeableImportSource.fileImport,
        ),
        throwsA(const ProfileErasureFailure.network()),
      );
      expect(purge.purges, isEmpty);
      expect(syncEngine.syncRequestCount, 0);
    });

    test('a no-session refusal never maps to unauthorized — it is '
        'notSignedIn (issue #883)', () async {
      // deleteProfile does not skip the RPC, so this is where a no-session
      // Postgrest refusal can still be observed directly.
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({
            'message': 'JWT expired',
            'code': 'PGRST301',
          }),
          401,
        );
      });

      final service = SupabaseProfileErasureService(
        client: client,
        profiles: profiles,
        importedDataPurge: purge,
        syncEngine: syncEngine,
      );
      await expectLater(
        service.deleteProfile(profileId: 'profile-1'),
        throwsA(const ProfileErasureFailure.notSignedIn()),
      );
      expect(profiles.purgedIds, isEmpty);
    });

    test('an unknown-source refusal maps to invalidSource', () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({
            'message': 'unknown source: bogus',
            'code': '22023',
          }),
          400,
        );
      });
      await signIn(client, 'u1');

      final service = SupabaseProfileErasureService(
        client: client,
        profiles: profiles,
        importedDataPurge: purge,
        syncEngine: syncEngine,
      );
      await expectLater(
        service.purgeImportedData(
          profileId: 'profile-1',
          source: PurgeableImportSource.fileImport,
        ),
        throwsA(const ProfileErasureFailure.invalidSource()),
      );
      expect(purge.purges, isEmpty);
      expect(syncEngine.syncRequestCount, 0);
    });

    test('a numeric 5xx code maps to network (a transient server error, '
        'not a client-side refusal)', () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({'message': 'internal error', 'code': '503'}),
          503,
        );
      });
      await signIn(client, 'u1');

      final service = SupabaseProfileErasureService(
        client: client,
        profiles: profiles,
        importedDataPurge: purge,
        syncEngine: syncEngine,
      );
      await expectLater(
        service.purgeImportedData(
          profileId: 'profile-1',
          source: PurgeableImportSource.fileImport,
        ),
        throwsA(const ProfileErasureFailure.network()),
      );
      expect(purge.purges, isEmpty);
      expect(syncEngine.syncRequestCount, 0);
    });

    test('an unrecognized, non-numeric code/message falls through to other',
        () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({'message': 'something unexpected', 'code': 'P0001'}),
          400,
        );
      });
      await signIn(client, 'u1');

      final service = SupabaseProfileErasureService(
        client: client,
        profiles: profiles,
        importedDataPurge: purge,
        syncEngine: syncEngine,
      );
      await expectLater(
        service.purgeImportedData(
          profileId: 'profile-1',
          source: PurgeableImportSource.fileImport,
        ),
        throwsA(const ProfileErasureFailure.other()),
      );
      expect(purge.purges, isEmpty);
      expect(syncEngine.syncRequestCount, 0);
    });
  });

  group('importedDataCounts', () {
    test('maps the local per-source counts onto every closed-enum source, '
        'defaulting an absent one to zero', () async {
      purge.counts = {'clue_import': 4, 'healthkit': 2};
      final client = makeClient((req) async {
        fail('importedDataCounts must never touch the network');
      });

      final service = SupabaseProfileErasureService(
        client: client,
        profiles: profiles,
        importedDataPurge: purge,
        syncEngine: syncEngine,
      );
      final counts = await service.importedDataCounts('profile-1');

      expect(counts[PurgeableImportSource.clueImport], 4);
      expect(counts[PurgeableImportSource.healthkit], 2);
      expect(counts[PurgeableImportSource.fileImport], 0);
      expect(counts.length, PurgeableImportSource.values.length);
    });
  });

  group('SupabaseProfileErasureService with real storage (issue #905)', () {
    late LunarLogDatabase db;
    late LunarLogStorage storage;
    late DriftImportedDataPurgeRepository purgeRepo;
    late MockSyncEngine realSyncEngine;

    setUp(() {
      db = LunarLogDatabase(NativeDatabase.memory());
      storage = LunarLogStorage(db);
      purgeRepo = DriftImportedDataPurgeRepository(storage);
      realSyncEngine = MockSyncEngine();
    });

    tearDown(() async {
      await db.close();
    });

    test('when server RPC fails, local rows remain live and reconcile does not alter them', () async {
      final p = await storage.upsertProfile(displayName: 'Test', isMinor: false);
      final entry = await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.medium,
        source: 'clue_import',
      );
      await storage.upsertObservation(
        dayEntryId: entry.id,
        profileId: p.id,
        localDate: entry.localDate,
        tz: 'UTC',
        category: 'pain',
        source: 'clue_import',
      );

      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({
            'message': 'profile not found or caller is not its accepted primary_guardian',
            'code': '42501',
          }),
          400,
        );
      });
      await signIn(client, 'not-primary');

      final service = SupabaseProfileErasureService(
        client: client,
        profiles: FakeProfilesRepository(),
        importedDataPurge: purgeRepo,
        syncEngine: realSyncEngine,
      );

      await expectLater(
        service.purgeImportedData(
          profileId: p.id,
          source: PurgeableImportSource.clueImport,
        ),
        throwsA(const ProfileErasureFailure.unauthorized()),
      );

      // Local rows were NOT tombstoned.
      final liveEntries = await storage.getDayEntries(profileId: p.id);
      expect(liveEntries.map((e) => e.id), contains(entry.id));
      final counts = await service.importedDataCounts(p.id);
      expect(counts[PurgeableImportSource.clueImport], 2);

      // Subsequent reconcile / remote pull applies the server's existing row:
      // it remains live as well.
      final remote = RemoteDayEntryRow(
        id: entry.id,
        profileId: p.id,
        localDate: entry.localDate,
        tz: 'UTC',
        flow: FlowLevel.medium,
        tags: const [],
        note: null,
        updatedAt: entry.updatedAt,
        deletedAt: null,
        source: 'clue_import',
      );
      await storage.applyRemoteDayEntry(remote);

      final afterReconcile = await storage.getDayEntries(profileId: p.id);
      expect(afterReconcile.map((e) => e.id), contains(entry.id));
      expect(afterReconcile.first.deletedAt, isNull);
    });

    test('when server RPC succeeds, local rows are tombstoned and reconcile keeps them tombstoned', () async {
      final p = await storage.upsertProfile(displayName: 'Test', isMinor: false);
      await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.medium,
        source: 'clue_import',
      );

      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({'day_entries': 1, 'observations': 0, 'import_jobs': 0}),
          200,
        );
      });
      await signIn(client, 'primary');

      final service = SupabaseProfileErasureService(
        client: client,
        profiles: FakeProfilesRepository(),
        importedDataPurge: purgeRepo,
        syncEngine: realSyncEngine,
      );

      await service.purgeImportedData(
        profileId: p.id,
        source: PurgeableImportSource.clueImport,
      );

      // Local rows are tombstoned.
      final liveEntries = await storage.getDayEntries(profileId: p.id);
      expect(liveEntries, isEmpty);
      final counts = await service.importedDataCounts(p.id);
      expect(counts[PurgeableImportSource.clueImport], 0);
      expect(realSyncEngine.syncRequestCount, 1);
    });
  });
}
