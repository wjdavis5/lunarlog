/// [SyncTransport] over a `SupabaseClient` (U10; KTD2, KTD3).
///
/// Push is the `sync_push` RPC (`POST /rest/v1/rpc/sync_push`). Pull
/// (issue #598) is primed once per cycle by [primePullCycle], which calls
/// the `sync_pull(p_cursors)` RPC ONCE for every table it covers — the
/// tenant-scoped, cursor-filtered-before-`LIMIT` shape #525 added — and
/// caches the result; [pullPage] then answers each table's first page from
/// that cache instead of its own round trip. A table [sync_pull] does not
/// cover ([SyncTable.deletedProfiles]), a cache miss (never primed, the
/// cached page was itself capped and cannot fill a full page from here, or
/// priming failed for any reason including the RPC not existing on a
/// server predating its migration), or an unprimed call (no
/// [primePullCycle] before it, as every existing test predates issue #598)
/// all fall back to the original per-table `select … where server_version
/// > cursor … order by server_version … limit …` query. The client is
/// injected (the app passes `Supabase.instance.client` from `main.dart`;
/// tests pass one built over a mock `http.Client`), so nothing here
/// touches `Supabase.instance`.
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

  /// Issue #598: `sync_pull`'s per-table page cap
  /// (`c_page_size` in 20260913014000_sync_server_version_indexes_and_pull.sql).
  /// A cached page at exactly this length may not be the whole story — the
  /// table could have more rows past it — so [_cachedSlice] never trusts a
  /// slice shorter than the caller's own `limit` out of a cache this full;
  /// see its doc comment.
  static const int _pullRpcPageCap = 500;

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
        'p_merge_events': batch.mergeEvents,
        'p_tag_registry': batch.tagRegistry,
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

  /// Issue #598: [primePullCycle]'s cached `sync_pull` pages, keyed by
  /// table — `null` until primed (or after a prime that found nothing to
  /// cache), always fully replaced (never merged) by the next successful
  /// prime.
  Map<SyncTable, _PulledPage>? _pullCache;

  @override
  Future<List<RemoteRow>> pullPage({
    required SyncTable table,
    required int afterVersion,
    required int limit,
  }) async {
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'must be at least 1');
    }
    if (table != SyncTable.deletedProfiles) {
      final cached = _cachedSlice(table, afterVersion: afterVersion, limit: limit);
      if (cached != null) return cached;
    }
    return _pullPageViaSelect(table: table, afterVersion: afterVersion, limit: limit);
  }

  /// The migration-gated tables whose absence on an older server must read
  /// as "nothing to pull yet" rather than a cycle-failing error: issue
  /// #522's `deleted_profiles` (the original carve-out) and issue #170's
  /// `day_entry_history` (pull-only — a server predating its migration
  /// never wrote a row this client could miss). Every other table is
  /// expected to exist unconditionally.
  static const Set<SyncTable> _migrationGatedTables = {
    SyncTable.deletedProfiles,
    SyncTable.dayEntryHistory,
  };

  /// The original per-table select, unchanged (issue #598's fallback path):
  /// used directly for [SyncTable.deletedProfiles] (never covered by
  /// `sync_pull`), and for every other table whenever [_cachedSlice] has
  /// nothing to answer from.
  Future<List<RemoteRow>> _pullPageViaSelect({
    required SyncTable table,
    required int afterVersion,
    required int limit,
  }) async {
    final List<Map<String, dynamic>> data;
    try {
      data = await _client
          .from(syncTableName(table))
          .select()
          .gt(_versionColumn, afterVersion)
          .order(_versionColumn, ascending: true)
          .limit(limit);
    } catch (error) {
      // Issue #522: `deletedProfiles` is a new table added by a migration
      // this PR does not include — a server predating it answers with
      // PostgREST's "relation not found" shape. Every other table is
      // expected to exist unconditionally, so this leniency is deliberately
      // scoped to the migration-gated tables (see [_migrationGatedTables]):
      // an empty page (the caller reads exactly like "nothing to pull
      // yet") rather than a cycle-failing error. Issue #170 extends the
      // same carve-out to the pull-only day_entry_history.
      if (_migrationGatedTables.contains(table) &&
          _isRelationNotFound(error)) {
        return const [];
      }
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

  /// A page sliced from [_pullCache], or `null` when there is none — the
  /// table was never cached, the caller's [afterVersion] is behind what the
  /// cached page was fetched from (stale relative to it), or the cache
  /// cannot honestly answer a full [limit]-sized page (see below) — in
  /// which case [pullPage] falls back to [_pullPageViaSelect].
  ///
  /// The cached page was capped at [_pullRpcPageCap] server-side rows, so a
  /// table with more than that many rows pending needs a follow-up beyond
  /// what this one cached response holds. Serving a SHORT slice from a
  /// capped cache would falsely read like "this table is exhausted" to the
  /// caller (whose own contract is "a page shorter than `limit` is the
  /// last one") when more rows may genuinely be waiting past the cache's
  /// own cutoff — so any time the cached page was itself capped, this
  /// returns `null` rather than a too-short slice, and the caller re-fetches
  /// the remainder via the ordinary select path instead.
  List<RemoteRow>? _cachedSlice(
    SyncTable table, {
    required int afterVersion,
    required int limit,
  }) {
    final cached = _pullCache?[table];
    if (cached == null || afterVersion < cached.lowerBound) return null;
    final rows = [
      for (final row in cached.rows)
        if (row.serverVersion > afterVersion) row,
    ];
    final slice = rows.length > limit ? rows.sublist(0, limit) : rows;
    final mayHaveMore =
        cached.rows.length >= _pullRpcPageCap && slice.length < limit;
    return mayHaveMore ? null : slice;
  }

  static const String _pullRpc = 'sync_pull';

  /// Issue #42: [SyncTransport.fetchMaxVersion] over a plain PostgREST
  /// select — the newest visible row's `server_version`, via
  /// `order by server_version desc limit 1` (one index-ordered lookup, no
  /// aggregate support required). Answers `0` for a table with nothing
  /// visible and `null` on any failure, per the interface contract.
  @override
  Future<int?> fetchMaxVersion(SyncTable table) async {
    final List<Map<String, dynamic>> data;
    try {
      data = await _client
          .from(syncTableName(table))
          .select(_versionColumn)
          .order(_versionColumn, ascending: false)
          .limit(1);
    } catch (_) {
      // The probe is an optimization for the scheduled daily reconcile
      // only: any failure means "unknown", and the caller falls back to
      // the full re-pull rather than silently skipping sync.
      return null;
    }
    if (data.isEmpty) return 0;
    final value = data.first[_versionColumn];
    if (value is int) return value;
    if (value is num) return value.toInt();
    // A bigint's wire representation is not guaranteed never to be a
    // quoted string (the same leniency fetchWatermark applies).
    if (value is String) return int.tryParse(value);
    return null;
  }

  @override
  Future<void> primePullCycle(Map<SyncTable, int> cursors) async {
    _pullCache = null;
    final Object? data;
    try {
      data = await _client.rpc<dynamic>(_pullRpc, params: {
        'p_cursors': {
          for (final entry in cursors.entries) syncTableName(entry.key): entry.value,
        },
      });
    } catch (_) {
      // Issue #598: sync_pull is purely an optimization — a server
      // predating the migration that adds it (PostgREST "function not
      // found": PGRST202, or the raw Postgres 42883 undefined_function if
      // the schema cache is stale) or any other failure while priming
      // leaves the cache empty, so every pullPage call this cycle falls
      // back to its own per-table select — correct, just without this
      // RPC's single-round-trip benefit. See the interface doc comment:
      // this must never throw.
      return;
    }
    _pullCache = _decodePullResponse(data, cursors);
  }

  /// Decodes `sync_pull`'s response into one [_PulledPage] per key in
  /// [cursors], or `null` on any shape mismatch (a malformed response is
  /// treated exactly like an RPC failure — [primePullCycle] leaves the
  /// cache empty rather than throwing).
  Map<SyncTable, _PulledPage>? _decodePullResponse(
    Object? data,
    Map<SyncTable, int> cursors,
  ) {
    if (data is! Map) return null;
    final result = <SyncTable, _PulledPage>{};
    for (final entry in cursors.entries) {
      final rowsJson = data[syncTableName(entry.key)];
      if (rowsJson is! List) return null;
      final rows = <RemoteRow>[];
      for (final row in rowsJson) {
        if (row is! Map) return null;
        try {
          rows.add(decodeRemoteRow(entry.key, row.cast<String, Object?>()));
        } on RowCodecError {
          return null;
        }
      }
      result[entry.key] = _PulledPage(entry.value, rows);
    }
    return result;
  }

  static const String _watermarkRpc = 'sync_watermark';

  /// PostgREST "function not found in the schema cache" — a server that
  /// has not yet run the migration adding `sync_watermark()` (issue #521's
  /// graceful-fallback contract: this transport's half of the fix must not
  /// depend on that migration having landed).
  static const String _functionNotFoundCode = 'PGRST202';

  /// PostgREST "table not found in the schema cache" — the same
  /// graceful-fallback shape as [_functionNotFoundCode], for
  /// `deleted_profiles` (issue #522).
  static const String _tableNotFoundCode = 'PGRST205';

  /// Postgres `undefined_table` (SQLSTATE `42P01`): the same "does not
  /// exist yet" outcome, reached if a table genuinely absent from the
  /// database (rather than merely absent from PostgREST's schema cache)
  /// surfaces as a raw SQL error instead.
  static const String _undefinedTableSqlState = '42P01';

  bool _isRelationNotFound(Object error) =>
      error is PostgrestException &&
      (error.code == _tableNotFoundCode ||
          error.code == _undefinedTableSqlState);

  @override
  Future<int?> fetchWatermark() async {
    try {
      final data = await _client.rpc<dynamic>(_watermarkRpc);
      if (data is int) return data;
      if (data is num) return data.toInt();
      // public.sync_watermark() returns `bigint` (PR #582): PostgREST
      // renders it as a JSON number in practice, but a bigint's wire
      // representation is not guaranteed never to be a quoted string (some
      // Postgres/PostgREST configurations render bigint that way to avoid
      // silent precision loss past 2^53) — accept either shape rather than
      // fail a perfectly good watermark on a representation detail.
      if (data is String) return int.tryParse(data);
      return null;
    } on PostgrestException catch (error) {
      if (error.code == _functionNotFoundCode) return null;
      // Any other failure (network, auth, an unexpected shape) is treated
      // the same way: the watermark is an optimization, never a
      // correctness requirement (the caller's lookback fallback is always
      // safe), so a hiccup fetching it must never fail the whole pull
      // cycle.
      return null;
    } catch (_) {
      return null;
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

/// Issue #598: one table's slice of a single `sync_pull` response, cached by
/// [SupabaseSyncTransport._pullCache].
class _PulledPage {
  const _PulledPage(this.lowerBound, this.rows);

  /// The `server_version` cursor this page was fetched from (exclusive) —
  /// every row in [rows] has `serverVersion > lowerBound`. A [pullPage] call
  /// is only answerable from this cache when its own `afterVersion` is at
  /// least this value; a lower `afterVersion` needs rows this page never
  /// requested and was never asked to include.
  final int lowerBound;

  /// Rows ascending by `server_version`, exactly as `sync_pull` returned
  /// them (already capped server-side at [SupabaseSyncTransport._pullRpcPageCap]).
  final List<RemoteRow> rows;
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
