/// [ProfileErasureService] implementation over the `delete_profile_data`
/// Supabase RPC (Issue #264/#472). Mirrors the error-mapping shape of
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
import '../../domain/repositories/profiles_repository.dart';
import '../../domain/sync/sync_engine.dart';

class SupabaseProfileErasureService implements ProfileErasureService {
  SupabaseProfileErasureService({
    required this.client,
    required this.profiles,
    this.syncEngine,
  });

  final SupabaseClient client;

  /// The local half of a full-purge delete (Issue #472): only ever called
  /// AFTER the server RPC below has already succeeded, and only for
  /// [deleteProfile] — [purgeImportedData]'s per-row tombstones already
  /// propagate through the ordinary incremental pull (the server RPC
  /// bumps `server_version` on every row it touches), the same as any
  /// other tombstone-producing RPC in this app (`revokeGuardian`,
  /// `updateGuardianRole`), so no immediate local write is needed there.
  final ProfilesRepository profiles;

  /// Nudges a pull right after a successful call, matching every sibling
  /// RPC-backed service (`SupabaseSharingService.revokeGuardian`, etc.) —
  /// belt-and-suspenders alongside [deleteProfile]'s immediate local wipe,
  /// and the only propagation mechanism for [purgeImportedData]. Null on a
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
