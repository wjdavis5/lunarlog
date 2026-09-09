/// The bulk-import seam between an importer pipeline (#172/#140 build the
/// Clue-file-to-[BulkImportRow] mapping and any UI on top of this) and the
/// server's `bulk_import_entries` RPC (Issue #167).
///
/// [BulkImporter] is the interface; `SupabaseBulkImporter`
/// (`lib/data/import/supabase_bulk_importer.dart`) is the only
/// implementation, chunking a run into `bulk_import_entries` calls of at
/// most [kBulkImportMaxRowsPerChunk] rows each — mirroring
/// `PushBatch.maxRows`'s role for `sync_push`
/// (`lib/data/sync/sync_transport.dart`), except an import run does **not**
/// go through `SyncTransport`/`sync_push` at all (the RPC bypasses it
/// entirely — see the migration's header).
///
/// Pure Dart, no drift/Flutter imports (R14/R16).
library;

import 'package:meta/meta.dart';

/// The RPC's own per-call row cap (`c_max_rows` in
/// `supabase/migrations/20260908190000_bulk_import.sql`).
const int kBulkImportMaxRowsPerChunk = 2000;

/// One `day_entries` row ready for `bulk_import_entries` — exactly the
/// allowlisted shape the RPC accepts (the migration's `c_row_keys`):
/// `id`, `profile_id`, `local_date`, `tz`, `flow`, `tags`, `note`,
/// `source_id`, `updated_at`, `deleted_at`. `source`/`import_id` are
/// deliberately not fields here — one import run carries exactly one
/// source and one job id, supplied once for the whole run
/// ([BulkImporter.importEntries]'s own parameters), never per row.
@immutable
class BulkImportRow {
  const BulkImportRow({
    required this.id,
    required this.profileId,
    required this.localDate,
    this.tz = 'UTC',
    this.flow = 'none',
    this.tags = const [],
    this.note,
    required this.sourceId,
    required this.updatedAt,
    this.deletedAt,
  });

  /// A day-entry ULID (see `lib/domain/models/`'s id generator).
  final String id;
  final String profileId;

  /// ISO calendar date, e.g. `'2015-03-04'`.
  final String localDate;
  final String tz;
  final String flow;
  final List<String> tags;
  final String? note;

  /// The source's own row identifier (e.g. Clue's export id for this day).
  /// Required, not optional (review fix, Issue #167): `bulk_import_entries`
  /// rejects a null `source_id` outright for a row whose `id` isn't already
  /// on `day_entries` (`'source_id is required for idempotent import'`,
  /// `supabase/migrations/20260908190000_bulk_import.sql`) — without one,
  /// a retry of a chunk that already landed would have no idempotent write
  /// path (a bare insert collides on `id`), aborting the whole chunk on
  /// every retry after the first success. Every importer feeding this type
  /// (#172/#140) must therefore mint a stable per-row source identifier
  /// (Clue's own export row id, or a deterministic hash of the row's
  /// content) even when the source system has no natural one.
  final String sourceId;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// The RPC's `p_rows` element shape — omits an absent optional field
  /// entirely rather than sending an explicit `null`, matching every other
  /// row codec in this codebase (`lib/data/sync/row_codec.dart`).
  Map<String, Object?> toJson() => {
        'id': id,
        'profile_id': profileId,
        'local_date': localDate,
        'tz': tz,
        'flow': flow,
        'tags': tags,
        if (note != null) 'note': note,
        'source_id': sourceId,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        if (deletedAt != null) 'deleted_at': deletedAt!.toUtc().toIso8601String(),
      };
}

/// One row `bulk_import_entries` declined, with its 0-based position in
/// the chunk that carried it and the server's plain-text reason.
@immutable
class BulkImportRejectedRow {
  const BulkImportRejectedRow({required this.rowIndex, required this.reason});

  final int rowIndex;
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is BulkImportRejectedRow &&
      other.rowIndex == rowIndex &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(rowIndex, reason);

  @override
  String toString() => 'BulkImportRejectedRow($rowIndex, $reason)';
}

/// The outcome of a full [BulkImporter.importEntries] run: the created
/// job's id plus every chunk's `{inserted, updated, revived, rejected}`
/// summed together.
@immutable
class BulkImportRunResult {
  BulkImportRunResult({
    required this.jobId,
    required this.inserted,
    required this.updated,
    required this.revived,
    required List<BulkImportRejectedRow> rejected,
  }) : rejected = List.unmodifiable(rejected);

  final String jobId;
  final int inserted;
  final int updated;
  final int revived;
  final List<BulkImportRejectedRow> rejected;

  /// Rows the server actually wrote (inserted, updated, or revived from a
  /// tombstone).
  int get written => inserted + updated + revived;

  @override
  String toString() => 'BulkImportRunResult(jobId: $jobId, written: $written, '
      'rejected: ${rejected.length})';
}

/// `processedRows` out of `totalRows` completed so far, reported after
/// each chunk (so the caller can drive a progress bar or persist a resume
/// point) — never mid-chunk.
typedef BulkImportProgress = void Function(int processedRows, int totalRows);

/// Typed bulk-import failure — never the provider's message, code or body
/// (R18), mirroring `SyncTransportError`
/// (`lib/data/sync/sync_transport.dart`). Fieldless: unlike
/// `SyncTransportError.rejected`, a per-row rejection from
/// `bulk_import_entries` is not a failure at all — it is reported in
/// [BulkImportRunResult.rejected] on an otherwise-successful call.
@immutable
sealed class BulkImportError implements Exception {
  const BulkImportError();

  /// No usable session, or the caller is not a guardian with a writing
  /// role on the job's profile.
  const factory BulkImportError.auth() = BulkImportAuthError;

  /// The server could not be reached or was unavailable. `processedRows`
  /// at the point of failure is durable in `import_jobs`, but
  /// [BulkImporter.importEntries] itself does not read it back — calling
  /// it again after this error creates a brand-new `import_jobs` row and
  /// restarts from row 0, it does not resume the failed job. Resuming
  /// from the durable `processedRows` would need a dedicated entry point
  /// (e.g. `resumeJob(jobId, rows)`) that this interface does not yet
  /// have; retry with backoff in the meantime.
  const factory BulkImportError.network() = BulkImportNetworkError;

  /// Everything else: a malformed response, a rejected job (already
  /// completed/failed, row-count cap, malformed `p_import_id`), or an
  /// unexpected status.
  const factory BulkImportError.other() = BulkImportOtherError;

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class BulkImportAuthError extends BulkImportError {
  const BulkImportAuthError();

  @override
  String toString() => 'BulkImportError.auth';
}

final class BulkImportNetworkError extends BulkImportError {
  const BulkImportNetworkError();

  @override
  String toString() => 'BulkImportError.network';
}

final class BulkImportOtherError extends BulkImportError {
  const BulkImportOtherError();

  @override
  String toString() => 'BulkImportError.other';
}

/// Runs a large import directly against `bulk_import_entries`, never
/// through `SyncTransport`/`sync_push` (see the migration header's
/// rationale — `sync_push`'s per-row cost and 8s timeout cannot survive a
/// multi-thousand-row Clue import).
abstract interface class BulkImporter {
  /// Creates one `import_jobs` row for [profileId]/[source], then pushes
  /// [rows] through `bulk_import_entries` in chunks of at most
  /// [kBulkImportMaxRowsPerChunk], calling [onProgress] after each chunk
  /// and marking the job `completed` on success or `failed` on error
  /// before rethrowing a [BulkImportError].
  ///
  /// [source] is one of `day_entries`' closed source set other than
  /// `'manual'` (e.g. `'clue_import'`) — validated server-side by
  /// `import_jobs_source_check`.
  Future<BulkImportRunResult> importEntries({
    required String profileId,
    required String source,
    required List<BulkImportRow> rows,
    BulkImportProgress? onProgress,
  });
}
