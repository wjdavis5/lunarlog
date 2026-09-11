/// Storage-level persistence API for the drift database (the domain
/// repositories and the sync engine build on this).
///
/// Invariants enforced here (settled data model, KTD4, KTD5):
/// * `updated_at` strictly increases on local edits: a local write stamps
///   the clock when it is later than the stored value, otherwise the stored
///   value plus one millisecond — never equal, because the server declines
///   an edit stamped equal to the copy it already holds (the remote wins
///   ties) and would revert it. Remote applies compare *before* writing
///   (LWW per id; the remote copy wins ties) and only ever write a
///   timestamp that is at least the stored one, so `updated_at` never
///   regresses for them by construction.
/// * Payload limits mirror the server's CHECK constraints
///   (`lib/domain/limits.dart`): a local write past them throws rather than
///   persisting a row the server would reject forever.
/// * The storage clock is the injected clock plus [clockOffset]
///   (`server_now - device_now`, learned by the sync engine), so a device
///   whose clock trails the server does not lose every LWW race.
/// * Every local write sets `dirty = true` and bumps `local_rev`; remote
///   applies write `dirty = false` and leave `local_rev` alone.
/// * Deletes are tombstones: `deleted_at` is set, `updated_at` bumped, the
///   payload cleared (`flow = none`, `note = null`, `tags = []`,
///   `display_name = ''`); rows are never removed.
/// * At most one *live* day entry per (profile, date): local writes update
///   the live row in place, remote applies run the same-date rule and
///   tombstone the loser with the winner's timestamp.
/// * Observations (Issue #240) are keyed by id alone, like profiles — there
///   is no same-date uniqueness to resolve: multiple live rows per
///   (profile, date, category) are the whole point of this child table.
///   Their tombstone clears every payload column, `category` included —
///   only `local_date`/`tz`/`source`/`source_id`/`import_id` survive a
///   delete (Issue #159: provenance is not health content, and a deleted
///   row must stay recognisable to a future re-import; see
///   `supabase/migrations/20260908170000_import_provenance.sql`'s
///   `observations_tombstone_payload_check`). `day_entries.source`/
///   `source_id`/`import_id` (Issue #159) get the same treatment.
/// * Profile modes (Issue #188) are one row per profile keyed by
///   `profile_id`, with NO tombstone (the server table has none either) —
///   an absent row means `tracking`, and rows are created lazily on first
///   write. Cycle overrides (Issue #188) tombstone like day entries:
///   `excluded_from_average`/`manual_start` reset to false and `note_id`
///   clears, while `cycle_start_date` (identity) survives — mirroring the
///   server's `cycle_overrides_tombstone_payload_check` exactly.
/// * Care notes and visit-prep items (Issue #128) are per-profile,
///   non-date-bound rows keyed by id alone, with per-id LWW and no
///   same-date resolver (see `domain/models/visit_prep_item.dart`'s
///   resolution rule: the checklist converges as a set; a care-note edit
///   races only against another write to the same note id). Both
///   tombstone like day entries: `body` clears (prep items additionally
///   reset `is_checked` and clear `checked_by`/`checked_at`), mirroring
///   the server's `care_notes_tombstone_payload_check` /
///   `visit_prep_items_tombstone_payload_check` exactly.
/// * UI reads filter tombstones; full-fidelity reads (tombstones included)
///   exist for sync.
///
/// Split (#434): the members documented above now live in three `part`
/// files, each mixed back into [LunarLogStorage] —
/// `storage_local_writes.dart` (local writes plus their validation
/// helpers), `storage_remote_apply.dart` (remote applies plus conflict
/// resolution), and `storage_queries.dart` (local reads, dirty scans, and
/// the private query/row helpers) — while `storage.dart` stays the single
/// import path. One library, one private namespace: no importer changes,
/// no signature changes.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lunarlog/domain/activity/merge_events.dart';
import 'package:lunarlog/domain/limits.dart';
import 'package:lunarlog/domain/sync/local_row_counts.dart';

import '../sync/conflict_rules.dart';
import '../sync/remote_rows.dart';
import 'db.dart';
import 'tables.dart';
import 'ulid.dart';

export 'package:lunarlog/domain/sync/local_row_counts.dart' show LocalRowCounts;

export '../sync/remote_rows.dart'
    show
        RemoteCareNoteRow,
        RemoteCycleOverrideRow,
        RemoteDayEntryRow,
        RemoteObservationRow,
        RemoteProfileModeRow,
        RemoteProfileRow,
        RemoteRow,
        RemoteVisitPrepItemRow,
        RetryableSyncApplyError,
        SyncTable;

part 'storage_local_writes.dart';
part 'storage_queries.dart';
part 'storage_remote_apply.dart';

class LunarLogStorage with LunarLogStorageQueries, LunarLogStorageLocalWrites, LunarLogStorageRemoteApply {
  LunarLogStorage(this.db, {DateTime Function()? clock, UlidGenerator? ulid})
      : _clock = clock ?? (() => DateTime.now().toUtc()),
        _generator = ulid ?? _ulid;

  @override
  final LunarLogDatabase db;
  final DateTime Function() _clock;
  @override
  final UlidGenerator _generator;
  Duration _clockOffset = Duration.zero;

  /// `server_now - device_now`, added to the clock when stamping local
  /// writes (KTD4). Zero until the sync engine learns it.
  Duration get clockOffset => _clockOffset;

  /// Sets [clockOffset]. In-memory only; the engine persists the learned
  /// value in `sync_state.server_clock_offset_ms` and restores it on open.
  void setClockOffset(Duration offset) {
    _clockOffset = offset;
  }

  /// The instant a local write is stamped with: injected clock + offset.
  @override
  DateTime _now() => _clock().toUtc().add(_clockOffset);
}
