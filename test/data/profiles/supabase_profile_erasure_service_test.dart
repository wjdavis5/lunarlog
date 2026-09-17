/// Issue #264/#472 coverage for [SupabaseProfileErasureService]: the RPC
/// call shapes (`delete_profile_data`, with and without `p_source`), typed
/// failure mapping (unauthorized, invalid source, network), the local
/// wipe only runs for [ProfileErasureService.deleteProfile] and only AFTER
/// the RPC has already succeeded (never on a failed or offline call), and
/// [ProfileErasureService.purgeImportedData] never touches local storage
/// at all (its tombstones propagate through the ordinary sync pull, like
/// every other RPC-backed service in this app). Mirrors
/// supabase_sharing_service_test.dart's MockClient + MockSyncEngine
/// harness.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunarlog/data/profiles/supabase_profile_erasure_service.dart';
import 'package:lunarlog/domain/logging/tracking_preferences.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/measurement_unit.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/models/profile_relationship.dart';
import 'package:lunarlog/domain/profiles/profile_erasure_service.dart';
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

void main() {
  late FakeProfilesRepository profiles;
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

      final service = SupabaseProfileErasureService(
        client: client,
        profiles: profiles,
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
        syncEngine: syncEngine,
      );
      await expectLater(
        service.deleteProfile(profileId: 'profile-1'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('purgeImportedData', () {
    test('calls delete_profile_data with p_source and requests a sync, '
        'without touching local storage (the tombstones propagate through '
        'the ordinary pull)', () async {
      final client = makeClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(req.url.path, '/rest/v1/rpc/delete_profile_data');
        expect(body['p_profile_id'], 'profile-1');
        expect(body['p_source'], 'clue_import');
        return http.Response(
          jsonEncode({'day_entries': 3, 'observations': 5, 'import_jobs': 1}),
          200,
        );
      });

      final service = SupabaseProfileErasureService(
        client: client,
        profiles: profiles,
        syncEngine: syncEngine,
      );
      await service.purgeImportedData(
        profileId: 'profile-1',
        source: PurgeableImportSource.clueImport,
      );

      expect(profiles.purgedIds, isEmpty);
      expect(syncEngine.syncRequestCount, 1);
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

      final service = SupabaseProfileErasureService(
        client: client,
        profiles: profiles,
        syncEngine: syncEngine,
      );
      await expectLater(
        service.purgeImportedData(
          profileId: 'profile-1',
          source: PurgeableImportSource.fileImport,
        ),
        throwsA(const ProfileErasureFailure.invalidSource()),
      );
    });

    test('a numeric 5xx code maps to network (a transient server error, '
        'not a client-side refusal)', () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({'message': 'internal error', 'code': '503'}),
          503,
        );
      });

      final service = SupabaseProfileErasureService(
        client: client,
        profiles: profiles,
        syncEngine: syncEngine,
      );
      await expectLater(
        service.purgeImportedData(
          profileId: 'profile-1',
          source: PurgeableImportSource.fileImport,
        ),
        throwsA(const ProfileErasureFailure.network()),
      );
    });

    test('an unrecognized, non-numeric code/message falls through to other',
        () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({'message': 'something unexpected', 'code': 'P0001'}),
          400,
        );
      });

      final service = SupabaseProfileErasureService(
        client: client,
        profiles: profiles,
        syncEngine: syncEngine,
      );
      await expectLater(
        service.purgeImportedData(
          profileId: 'profile-1',
          source: PurgeableImportSource.fileImport,
        ),
        throwsA(const ProfileErasureFailure.other()),
      );
    });
  });
}
