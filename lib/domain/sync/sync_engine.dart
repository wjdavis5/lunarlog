/// Cloud sync contract (U10; KTD6, R10–R15). Pure Dart: no Flutter, no
/// Supabase, no drift types cross this boundary, exactly like the
/// repository and auth interfaces beside it. The implementation
/// (`SupabaseSyncEngine`) lives in `lib/data/sync/`; the UI notifier
/// (`SyncStatusController`) in `lib/ui/account/`.
///
/// Nothing here carries health content: counts, phases, an error *kind*,
/// timestamps and the bound account id are all a crash report or a status
/// line may see (R18).
library;

import 'package:meta/meta.dart';

/// Where the engine is in its lifecycle. Exactly one phase at a time.
enum SyncPhase {
  /// Nothing to do right now: signed out, not yet started, between cycles,
  /// or waiting for a session to be confirmed.
  idle,

  /// First bind on an empty device: the bind-time full pull is running and
  /// the UI should show "restoring your data" rather than an empty app.
  restoring,

  /// A cycle is pushing dirty rows through `sync_push`.
  pushing,

  /// A cycle is pulling remote pages (incremental or full reconcile).
  pulling,

  /// The device gate is locked or the database is closed: the engine
  /// finished its current batch/page and will not start another (KTD10).
  paused,

  /// A confirmed session exists but this non-empty database is not bound
  /// to any account: waiting for [SyncEngine.confirmUpload] (R14).
  awaitingUploadConsent,

  /// The database is bound to a different account than the session's:
  /// nothing runs and nothing is touched until the operator switches
  /// account or removes this device's data (AE5, R15).
  accountMismatch,

  /// The last cycle failed; see [SyncSnapshot.lastError]. Local use is
  /// unaffected (AE9).
  error,
}

/// Why the last cycle failed, if it did. Kinds only — never a message.
enum SyncErrorKind {
  none,

  /// The session is gone or could not be refreshed: sync needs a sign-in.
  auth,

  /// The server was unreachable or unavailable; the engine backs off.
  network,

  /// Anything else (a malformed payload, a local apply failure).
  other,
}

/// A point-in-time view of the engine for the UI.
@immutable
class SyncSnapshot {
  const SyncSnapshot({
    required this.phase,
    this.dirtyCount = 0,
    this.rejectedCount = 0,
    this.lastSyncAt,
    this.lastError = SyncErrorKind.none,
    this.boundUserId,
  });

  /// The engine before [SyncEngine.start] has observed anything.
  static const SyncSnapshot initial = SyncSnapshot(phase: SyncPhase.idle);

  final SyncPhase phase;

  /// Rows (live and tombstoned, both tables) still waiting to be pushed.
  final int dirtyCount;

  /// Rows the server rejected on the last push; they stay dirty and are
  /// not retried in a tight loop ("some entries could not be uploaded").
  final int rejectedCount;

  /// When the last cycle completed without error (UTC), if ever.
  final DateTime? lastSyncAt;

  /// Meaningful only while [phase] is [SyncPhase.error].
  final SyncErrorKind lastError;

  /// The account this database is bound to, if any (`sync_state
  /// .bound_user_id`).
  final String? boundUserId;

  SyncSnapshot copyWith({
    SyncPhase? phase,
    int? dirtyCount,
    int? rejectedCount,
    DateTime? lastSyncAt,
    SyncErrorKind? lastError,
    String? boundUserId,
  }) =>
      SyncSnapshot(
        phase: phase ?? this.phase,
        dirtyCount: dirtyCount ?? this.dirtyCount,
        rejectedCount: rejectedCount ?? this.rejectedCount,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        lastError: lastError ?? this.lastError,
        boundUserId: boundUserId ?? this.boundUserId,
      );

  @override
  bool operator ==(Object other) =>
      other is SyncSnapshot &&
      other.phase == phase &&
      other.dirtyCount == dirtyCount &&
      other.rejectedCount == rejectedCount &&
      other.lastSyncAt == lastSyncAt &&
      other.lastError == lastError &&
      other.boundUserId == boundUserId;

  @override
  int get hashCode => Object.hash(
      phase, dirtyCount, rejectedCount, lastSyncAt, lastError, boundUserId);

  @override
  String toString() => 'SyncSnapshot(${phase.name}, dirty: $dirtyCount, '
      'rejected: $rejectedCount, lastError: ${lastError.name})';
}

/// The sync seam. Built by `LunarLogRoot` after the database opens and
/// only when the build has both an `AuthService` and a `SyncTransport`
/// (KTD11); `null` otherwise — there is no no-op implementation.
abstract interface class SyncEngine {
  /// Subscribes to its triggers (gate, auth state, local writes, resume,
  /// periodic timer). Idempotent. Runs nothing until the gating conditions
  /// hold (KTD10).
  void start();

  /// Cancels every timer and subscription and lets an in-flight batch or
  /// page finish, so the database can be closed safely afterwards.
  Future<void> dispose();

  /// Asks for a cycle now ("Sync now"). Coalesces while one is running:
  /// at most one follow-up cycle is queued.
  void requestSync();

  /// Forces a full reconciliation pull on the next cycle, clearing pull
  /// cursors so newly joined profiles or guardians are pulled completely (Issue #8).
  void triggerFullReconcile();

  /// Answers [SyncPhase.awaitingUploadConsent]: marks every local row for
  /// upload, binds the device to the session's account and runs a cycle
  /// (R14). A no-op in any other phase.
  Future<void> confirmUpload();

  /// Every snapshot change after subscription; see [snapshot] for the
  /// current value so a late subscriber starts from truth.
  Stream<SyncSnapshot> get snapshots;

  SyncSnapshot get snapshot;
}
