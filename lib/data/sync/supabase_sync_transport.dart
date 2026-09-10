/// [SyncTransport] over a `SupabaseClient` (U10; KTD2, KTD3).
///
/// Push is the `sync_push` RPC (`POST /rest/v1/rpc/sync_push`); pull is a
/// PostgREST select filtered and ordered by `server_version` with a row
/// limit. The client is injected (the app passes `Supabase.instance.client`
/// from `main.dart`; tests pass one built over a mock `http.Client`), so
/// nothing here touches `Supabase.instance`.
///
/// Every failure is mapped to a [SyncTransportError] kind by
/// [mapSyncTransportError]; the provider's message, code and body stop
/// here (R18).
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'remote_rows.dart';
import 'row_codec.dart';
import 'sync_transport.dart';

class SupabaseSyncTransport implements SyncTransport {
  SupabaseSyncTransport(this._client);

  final SupabaseClient _client;

  static const String _rpc = 'sync_push';
  static const String _versionColumn = 'server_version';

  @override
  Future<PushResult> push(PushBatch batch) async {
    final Object? data;
    try {
      data = await _client.rpc<dynamic>(_rpc, params: {
        'p_profiles': batch.profiles,
        'p_day_entries': batch.dayEntries,
        'p_observations': batch.observations,
        'p_profile_modes': batch.profileModes,
        'p_cycle_overrides': batch.cycleOverrides,
        'p_care_notes': batch.careNotes,
        'p_visit_prep_items': batch.visitPrepItems,
      });
    } catch (error) {
      throw mapSyncTransportError(error);
    }
    try {
      return _decodePushResult(data);
    } on RowCodecError {
      throw const SyncTransportError.other();
    }
  }

  @override
  Future<List<RemoteRow>> pullPage({
    required SyncTable table,
    required int afterVersion,
    required int limit,
  }) async {
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'must be at least 1');
    }
    final List<Map<String, dynamic>> data;
    try {
      data = await _client
          .from(syncTableName(table))
          .select()
          .gt(_versionColumn, afterVersion)
          .order(_versionColumn, ascending: true)
          .limit(limit);
    } catch (error) {
      throw mapSyncTransportError(error);
    }
    try {
      return [for (final row in data) decodeRemoteRow(table, row)];
    } on RowCodecError {
      // Do not advance a cursor past data this client could not preserve.
      // The engine surfaces a durable error and retries after repair.
      throw const SyncTransportError.other();
    }
  }

  PushResult _decodePushResult(Object? data) {
    if (data is! Map) throw const SyncTransportError.other();
    final resolvedJson = data['resolved'];
    final rejectedJson = data['rejected'];
    final serverNow = data['server_now'];
    if (resolvedJson is! List ||
        rejectedJson is! List ||
        serverNow is! String) {
      throw const SyncTransportError.other();
    }
    final resolved = <RemoteRow>[];
    for (final item in resolvedJson) {
      if (item is! Map) throw const SyncTransportError.other();
      resolved.add(decodeResolvedRow(item.cast<String, Object?>()));
    }
    // A rejected entry echoes the payload's `id` verbatim; one that was not
    // a string could never match a local row, so it is dropped.
    final rejectedIds = <String>[
      for (final item in rejectedJson)
        if (item is Map && item['id'] is String) item['id'] as String,
    ];
    return PushResult(
      resolved: resolved,
      rejectedIds: rejectedIds,
      serverNow: decodeTimestamp(serverNow, field: 'server_now'),
    );
  }
}

/// HTTP statuses PostgREST answers with when the request is fine but the
/// service is not: retry later.
const Set<int> _transientStatuses = {408, 425, 429};

/// Classifies [error] as a [SyncTransportError] kind. Already-typed errors
/// pass through unchanged.
///
/// * `AuthException` (the client could not refresh the session) and a
///   `PostgrestException` whose code is HTTP 401/403, a `PGRST3xx` JWT
///   error, or SQLSTATE `42501` (insufficient privilege — the RPC is not
///   executable without a session) → [SyncTransportError.auth].
/// * `SocketException`, any other `IOException`, `http.ClientException`,
///   `TimeoutException`, and HTTP 5xx / 408 / 425 / 429 →
///   [SyncTransportError.network].
/// * SQLSTATE `40P01` (deadlock detected), `40001` (serialization failure)
///   and `55P03` (lock timeout) — transient concurrency errors the server
///   deliberately re-raises out of `sync_push`'s per-row handlers instead of
///   swallowing them as rejected rows (issue #95) →
///   [SyncTransportError.network], so the engine's exponential backoff
///   retries the batch instead of waiting for the periodic tick.
/// * Everything else, including SQLSTATE `22023` (batch over 500 rows — a
///   client bug) → [SyncTransportError.other].
SyncTransportError mapSyncTransportError(Object error) {
  if (error is SyncTransportError) return error;
  if (error is AuthRetryableFetchException) {
    return const SyncTransportError.network();
  }
  if (error is AuthException) return const SyncTransportError.auth();
  if (error is PostgrestException) return _mapPostgrest(error);
  if (error is IOException ||
      error is http.ClientException ||
      error is TimeoutException) {
    return const SyncTransportError.network();
  }
  return const SyncTransportError.other();
}

/// SQLSTATEs for transient concurrency failures the server deliberately
/// re-raises out of `sync_push`'s per-row handlers instead of swallowing
/// them as rejected rows (issue #95): deadlock detected, serialization
/// failure, lock timeout. A push that dies on one of these means "retry the
/// batch", not "the payload is bad".
const Set<String> _transientConcurrencyCodes = {'40P01', '40001', '55P03'};

/// Maps a PostgREST code that is a SQLSTATE (or a `PGRST3xx` JWT error) to
/// its [SyncTransportError], or `null` when the code is an HTTP status (or
/// unrecognized) and the caller should fall through to status mapping.
/// Split out of [_mapPostgrest] so each half stays under the CRAP gate.
SyncTransportError? _mapSqlState(String code) {
  if (code.startsWith('PGRST3') || code == '42501') {
    return const SyncTransportError.auth();
  }
  if (_transientConcurrencyCodes.contains(code)) {
    return const SyncTransportError.network();
  }
  return null;
}

SyncTransportError _mapPostgrest(PostgrestException error) {
  final code = error.code ?? '';
  final sqlState = _mapSqlState(code);
  if (sqlState != null) return sqlState;
  // postgrest stores the HTTP status as the code when the body carries no
  // SQLSTATE; a SQLSTATE is five characters (`22023`), a status three.
  final status = code.length == 3 ? int.tryParse(code) : null;
  if (status != null) {
    if (status == 401 || status == 403) return const SyncTransportError.auth();
    if (status >= 500 || _transientStatuses.contains(status)) {
      return const SyncTransportError.network();
    }
  }
  return const SyncTransportError.other();
}
