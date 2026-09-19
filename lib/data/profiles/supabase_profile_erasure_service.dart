/// [ProfileErasureService] implementation over the `delete_profile_data`
/// Supabase RPC (Issue #264/#472) plus the local Drift half (Issue #883).
/// Mirrors the error-mapping shape of
/// [SupabaseAccountDeletionService][account_deletion_service_link] and
/// [SupabasePredictionConnectionService][prediction_connection_service_link]
/// so the seam family stays consistent.
///
/// [account_deletion_service_link]: ../account/supabase_account_deletion_service.dart
/// [prediction_connection_service_link]: ../sharing/supabase_prediction_connection_service.dart
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/profiles/profile_erasure_service.dart';
import '../../domain/repositories/imported_data_purge_repository.dart';
import '../../domain/repositories/profiles_repository.dart';
import '../../domain/sync/sync_engine.dart';

class SupabaseProfileErasureService implements ProfileErasureService {
  SupabaseProfileErasureService({
    required this.client,
    required this.profiles,
    required this.importedDataPurge,
    this.syncEngine,
  });

  final SupabaseClient client;

  /// The local half of a full-purge delete (Issue #472): only ever called
  /// AFTER the server RPC below has already succeeded, and only for
  /// [deleteProfile] — [purgeImportedData] reuses
  /// [ImportedDataPurgeRepository.applyLocalPurge] instead, which also
  /// runs with no session at all (Issue #883).
  final ProfilesRepository profiles;

  /// Issue #883: the local, source-scoped tombstone behind
  /// [purgeImportedData], and the live per-source counts behind
  /// [importedDataCounts]. Storage-only and always available — this is
  /// what lets a device-only profile (never near an account) purge.
  final ImportedDataPurgeRepository importedDataPurge;

  /// Nudges a pull right after a successful call, matching every sibling
  /// RPC-backed service (`SupabaseSharingService.revokeGuardian`, etc.) —
  /// belt-and-suspenders alongside [deleteProfile]'s immediate local wipe,
  /// and, for the session-bearing [purgeImportedData] path, the
  /// propagation mechanism for the server-side delete. Null on a
  /// build with no sync engine wired (the R26 null-gating posture); the
  /// RPC calls themselves still work without it.
  final SyncEngine? syncEngine;

  @override
  Future<void> deleteProfile({required String profileId}) async {
    try {
      await client.rpc<dynamic>(
        'delete_profile_data',
        params: {'p_profile_id': profileId},
      );
    } catch (e) {
      throw _mapError(e);
    }
    // The server call has already succeeded past this point — apply the
    // local half unconditionally rather than let a later local failure
    // read as "the delete failed" when the server has, in fact, already
    // erased the data.
    await profiles.applyServerPurge(profileId);
    syncEngine?.requestSync();
  }

  @override
  Future<void> purgeImportedData({
    required String profileId,
    required PurgeableImportSource source,
  }) async {
    // Issue #883: the local Drift tombstone always runs FIRST, so this
    // works with no session and no network. Reuses the app's tombstone
    // cascade rather than a raw delete, scoped to this one profile and
    // this one source.
    await importedDataPurge.applyLocalPurge(
      profileId: profileId,
      source: source.wireValue,
    );
    // No session: the RPC could only be refused — skip it entirely and
    // succeed on the strength of the local purge, instead of surfacing a
    // false "not primary guardian" failure on a device-only profile.
    if (client.auth.currentUser == null) return;
    try {
      await client.rpc<dynamic>(
        'delete_profile_data',
        params: {
          'p_profile_id': profileId,
          'p_source': source.wireValue,
        },
      );
    } catch (e) {
      throw _mapError(e);
    }
    syncEngine?.requestSync();
  }

  @override
  Future<Map<PurgeableImportSource, int>> importedDataCounts(
      String profileId) async {
    final raw = await importedDataPurge.liveSourceCounts(profileId);
    return {
      for (final source in PurgeableImportSource.values)
        source: raw[source.wireValue] ?? 0,
    };
  }

  ProfileErasureFailure _mapError(Object error) {
    if (error is ProfileErasureFailure) return error;
    if (error is SocketException || error is http.ClientException) {
      return const ProfileErasureFailure.network();
    }
    if (error is PostgrestException) {
      return _mapPostgrestError(error);
    }
    return const ProfileErasureFailure.other();
  }

  ProfileErasureFailure _mapPostgrestError(PostgrestException error) {
    final code = error.code ?? '';
    final msg = error.message.toLowerCase();
    if (code == 'PGRST301' || code == '42501' || msg.contains('permission')) {
      // Issue #883: mirror SupabaseSharingService's Issue #885 distinction —
      // the server refuses no-session and under-privileged callers the same
      // way, but only a session fixes the former, so the copy must say
      // "sign in", never "not primary guardian".
      if (client.auth.currentUser == null) {
        return const ProfileErasureFailure.notSignedIn();
      }
      return const ProfileErasureFailure.unauthorized();
    }
    if (code == '22023' || msg.contains('unknown source')) {
      return const ProfileErasureFailure.invalidSource();
    }
    final status = int.tryParse(code);
    if (status != null && status >= 500) {
      return const ProfileErasureFailure.network();
    }
    return const ProfileErasureFailure.other();
  }
}
