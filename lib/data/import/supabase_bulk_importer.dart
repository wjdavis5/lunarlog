/// [BulkImporter] over a `SupabaseClient` (Issue #167): creates one
/// `import_jobs` row (`status: 'pending'`), marks it `'running'` before
/// the first chunk, then calls `bulk_import_entries`
/// (`POST /rest/v1/rpc/bulk_import_entries`) once per
/// [kBulkImportMaxRowsPerChunk]-row chunk, updating `import_jobs`'s
/// `processed_rows` after each chunk and its final `status`/`completed_at`
/// at the end (`'completed'` on success -- not best-effort, see
/// [importEntries]'s own doc comment on that PATCH -- or `'failed'` with
/// `error_kind` on error, best-effort). Deliberately does **not** go through
/// `SyncTransport`/
/// `sync_push` (see the migration's header) — this class talks to the
/// `SupabaseClient` directly, exactly like `SupabaseSyncTransport`
/// (`lib/data/sync/supabase_sync_transport.dart`), which it mirrors for
/// error mapping.
///
/// The client is injected (the app passes `Supabase.instance.client`;
/// tests pass one built over a mock `http.Client`), so nothing here
/// touches `Supabase.instance`.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/import/bulk_importer.dart';

class SupabaseBulkImporter implements BulkImporter {
  SupabaseBulkImporter(this._client);

  final SupabaseClient _client;

  static const String _jobsTable = 'import_jobs';
  static const String _rpc = 'bulk_import_entries';

  @override
  Future<BulkImportRunResult> importEntries({
    required String profileId,
    required String source,
    required List<BulkImportRow> rows,
    BulkImportProgress? onProgress,
  }) async {
    final jobId = await _createJob(profileId: profileId, source: source, totalRows: rows.length);
    final BulkImportRunResult result;
    try {
      // Review fix: previously the job sat at 'running' by convention only
      // (import_jobs.status's own doc comment named it, but nothing ever
      // wrote it) -- it stayed 'pending' for the entire run, indistinguishable
      // from a job that had not started yet.
      await _setStatus(jobId, status: 'running');
      result = await _runChunks(jobId, rows, onProgress);
    } catch (error) {
      final mapped = mapBulkImportError(error);
      await _markFailedBestEffort(jobId, mapped);
      throw mapped;
    }
    // Review fix (round 2): this PATCH used to be routed through the same
    // catch block as the data run above, so a failure here alone -- every
    // row already durably written, only this last status write failing --
    // marked the job 'failed', which is wrong: the rows are in. Its own
    // try/catch now surfaces a typed BulkImportError without touching the
    // job's status, leaving it 'running' -- a later retry of this same
    // PATCH, or a fresh bulk_import_entries re-import of the same rows
    // (now idempotent by (source, source_id) regardless of import_id, see
    // the migration's review-fix header), is safe either way.
    try {
      await _client.from(_jobsTable).update({
        'status': 'completed',
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', jobId);
    } catch (error) {
      throw mapBulkImportError(error);
    }
    return result;
  }

  /// Pushes every row through [_rpc] in [kBulkImportMaxRowsPerChunk]-row
  /// chunks, updating `processed_rows` and calling [onProgress] after
  /// each, and summing every chunk's `{inserted, updated, revived,
  /// rejected}` into one [BulkImportRunResult].
  Future<BulkImportRunResult> _runChunks(
    String jobId,
    List<BulkImportRow> rows,
    BulkImportProgress? onProgress,
  ) async {
    var inserted = 0, updated = 0, revived = 0, processed = 0;
    final rejected = <BulkImportRejectedRow>[];
    for (var offset = 0; offset < rows.length; offset += kBulkImportMaxRowsPerChunk) {
      final chunkEnd = math.min(offset + kBulkImportMaxRowsPerChunk, rows.length);
      final chunk = rows.sublist(offset, chunkEnd);
      final chunkResult = await _importChunk(jobId, chunk);
      inserted += chunkResult.inserted;
      updated += chunkResult.updated;
      revived += chunkResult.revived;
      rejected.addAll(chunkResult.rejected);
      processed += chunk.length;
      await _updateProcessedRows(jobId, processed);
      onProgress?.call(processed, rows.length);
    }
    return BulkImportRunResult(
      jobId: jobId,
      inserted: inserted,
      updated: updated,
      revived: revived,
      rejected: rejected,
    );
  }

  Future<String> _createJob({
    required String profileId,
    required String source,
    required int totalRows,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const BulkImportError.auth();
    try {
      final row = await _client.from(_jobsTable).insert({
        'profile_id': profileId,
        'source': source,
        'status': 'pending',
        'total_rows': totalRows,
        'created_by': uid,
      }).select('id').single();
      return row['id'] as String;
    } catch (error) {
      throw mapBulkImportError(error);
    }
  }

  Future<BulkImportRunResult> _importChunk(String jobId, List<BulkImportRow> chunk) async {
    final Object? data;
    try {
      data = await _client.rpc<dynamic>(_rpc, params: {
        'p_import_id': jobId,
        'p_rows': [for (final row in chunk) row.toJson()],
      });
    } catch (error) {
      throw mapBulkImportError(error);
    }
    return _decodeChunkResult(jobId, data);
  }

  BulkImportRunResult _decodeChunkResult(String jobId, Object? data) {
    try {
      final map = data as Map;
      return BulkImportRunResult(
        jobId: jobId,
        inserted: map['inserted'] as int,
        updated: map['updated'] as int,
        revived: map['revived'] as int,
        rejected: [
          for (final item in map['rejected'] as List) _decodeRejectedRow(item)
        ],
      );
    } catch (error) {
      throw mapBulkImportError(error);
    }
  }

  BulkImportRejectedRow _decodeRejectedRow(Object? item) {
    try {
      final map = item as Map;
      return BulkImportRejectedRow(
        rowIndex: map['row_index'] as int,
        reason: map['reason'] as String,
      );
    } catch (error) {
      throw mapBulkImportError(error);
    }
  }

  Future<void> _updateProcessedRows(String jobId, int processedRows) async {
    try {
      await _client.from(_jobsTable).update({'processed_rows': processedRows}).eq('id', jobId);
    } catch (error) {
      throw mapBulkImportError(error);
    }
  }

  /// Best-effort: swallows its own failure (e.g. the network dropping a
  /// second time) rather than masking [error]'s caller — the caller
  /// already has, and is about to (re)throw, the real error. Unlike the
  /// final `completed` PATCH in [importEntries] (review fix: that one no
  /// longer swallows), a failure to *record* that the job already failed
  /// is not itself worth surfacing as a second, different error.
  Future<void> _markFailedBestEffort(String jobId, BulkImportError error) async {
    try {
      await _client.from(_jobsTable).update({
        'status': 'failed',
        'completed_at': DateTime.now().toUtc().toIso8601String(),
        'error_kind': _errorKind(error),
      }).eq('id', jobId);
    } catch (_) {
      // See doc comment: deliberately swallowed.
    }
  }

  /// Best-effort: a failure here does not abort the run -- the job simply
  /// stays visible at 'pending' instead of 'running' until the next status
  /// write (`processed_rows`, or the final `completed`/`failed`), which is
  /// a progress-visibility gap, not a correctness one.
  Future<void> _setStatus(String jobId, {required String status}) async {
    try {
      await _client.from(_jobsTable).update({'status': status}).eq('id', jobId);
    } catch (_) {
      // See doc comment: deliberately swallowed.
    }
  }

  /// `'BulkImportError.auth'` -> `'auth'` (well under
  /// `import_jobs_error_kind_length_check`'s 64-character bound).
  static String _errorKind(BulkImportError error) => error.toString().split('.').last;
}

/// HTTP statuses PostgREST answers with when the request is fine but the
/// service is not: retry later (mirrors
/// `lib/data/sync/supabase_sync_transport.dart`'s identical set).
const Set<int> _transientStatuses = {408, 425, 429};

/// Classifies [error] as a [BulkImportError] kind, the same taxonomy
/// `mapSyncTransportError` applies for `sync_push`/pull. Already-typed
/// errors pass through unchanged.
BulkImportError mapBulkImportError(Object error) {
  if (error is BulkImportError) return error;
  if (error is AuthRetryableFetchException) {
    return const BulkImportError.network();
  }
  if (error is AuthException) return const BulkImportError.auth();
  if (error is PostgrestException) return _mapPostgrest(error);
  if (error is IOException ||
      error is http.ClientException ||
      error is TimeoutException) {
    return const BulkImportError.network();
  }
  return const BulkImportError.other();
}

BulkImportError _mapPostgrest(PostgrestException error) {
  final code = error.code ?? '';
  if (code.startsWith('PGRST3') || code == '42501') {
    return const BulkImportError.auth();
  }
  // postgrest stores the HTTP status as the code when the body carries no
  // SQLSTATE; a SQLSTATE is five characters (`22023`), a status three.
  final status = code.length == 3 ? int.tryParse(code) : null;
  if (status != null) {
    if (status == 401 || status == 403) return const BulkImportError.auth();
    if (status >= 500 || _transientStatuses.contains(status)) {
      return const BulkImportError.network();
    }
  }
  return const BulkImportError.other();
}
