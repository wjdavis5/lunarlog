/// Storage-level persistence API for the drift database (U3's domain
/// repositories build on this).
///
/// Invariants enforced here (settled data model):
/// * `updated_at` never regresses on-device: every write clamps the new
///   timestamp to `max(incoming, stored)`. A future sync importer should
///   additionally compare timestamps *before* writing (LWW, delete wins
///   ties); the clamp is the storage-level backstop either way.
/// * Deletes are tombstones: `deleted_at` is set and `updated_at` bumped;
///   rows are never removed.
/// * UI reads filter tombstones; full-fidelity reads (tombstones included)
///   exist for future sync.
library;

import 'package:drift/drift.dart';

import 'db.dart';
import 'tables.dart';
import 'ulid.dart';

/// Default ULID generator for new records (per-isolate monotonic).
final UlidGenerator _ulid = UlidGenerator();

final RegExp _isoLocalDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

void _validateLocalDate(String localDate) {
  if (!_isoLocalDate.hasMatch(localDate)) {
    throw ArgumentError.value(
        localDate, 'localDate', 'must be an ISO yyyy-MM-dd string');
  }
  final parsed = DateTime.tryParse('${localDate}T00:00:00Z');
  if (parsed == null ||
      parsed.year.toString().padLeft(4, '0') != localDate.substring(0, 4) ||
      parsed.month.toString().padLeft(2, '0') != localDate.substring(5, 7) ||
      parsed.day.toString().padLeft(2, '0') != localDate.substring(8, 10)) {
    throw ArgumentError.value(localDate, 'localDate', 'not a valid calendar date');
  }
}

/// Returns [next] clamped so it is never earlier than [floor].
DateTime _notBefore(DateTime next, DateTime floor) =>
    next.toUtc().isBefore(floor.toUtc()) ? floor.toUtc() : next.toUtc();

class LunarLogStorage {
  LunarLogStorage(this.db, {DateTime Function()? clock, UlidGenerator? ulid})
      : _clock = clock ?? (() => DateTime.now().toUtc()),
        _generator = ulid ?? _ulid;

  final LunarLogDatabase db;
  final DateTime Function() _clock;
  final UlidGenerator _generator;

  // ---------------------------------------------------------------- profiles

  /// Creates or updates a profile keyed by [id] (a fresh ULID is generated
  /// when omitted). A newer write to a tombstoned profile revives it
  /// (`deleted_at` cleared) — under LWW a newer non-delete must win.
  Future<Profile> upsertProfile({
    String? id,
    required String displayName,
    required bool isMinor,
    int sortOrder = 0,
    DateTime? archivedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return db.transaction(() async {
      final now = (updatedAt ?? _clock()).toUtc();
      Profile? existing;
      if (id != null) {
        existing = await (db.select(db.profiles)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
      }
      if (existing == null) {
        final rowId = id ?? _generator.next();
        await db.into(db.profiles).insert(ProfilesCompanion.insert(
              id: rowId,
              displayName: displayName,
              isMinor: isMinor,
              sortOrder: Value(sortOrder),
              archivedAt: Value(archivedAt),
              createdAt: createdAt ?? now,
              updatedAt: now,
            ));
        return _profileById(rowId);
      }
      final rowId = existing.id;
      await (db.update(db.profiles)..where((t) => t.id.equals(rowId))).write(
        ProfilesCompanion(
          displayName: Value(displayName),
          isMinor: Value(isMinor),
          sortOrder: Value(sortOrder),
          archivedAt: Value(archivedAt),
          updatedAt: Value(_notBefore(now, existing.updatedAt)),
          deletedAt: const Value(null),
        ),
      );
      return _profileById(rowId);
    });
  }

  /// Tombstones a profile: sets `deleted_at` (and bumps `updated_at`);
  /// the row is never removed. Idempotent: re-deleting a tombstone does not
  /// bump `updated_at` again.
  Future<void> softDeleteProfile(String id) async {
    await db.transaction(() async {
      final existing = await (db.select(db.profiles)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (existing == null || existing.deletedAt != null) return;
      final at = _notBefore(_clock(), existing.updatedAt);
      await (db.update(db.profiles)..where((t) => t.id.equals(id))).write(
          ProfilesCompanion(updatedAt: Value(at), deletedAt: Value(at)));
    });
  }

  /// Profiles for UI reads ([includeTombstones] false, default) or for sync
  /// (true), ordered by [Profiles.sortOrder] then id for stable lists.
  Future<List<Profile>> getProfiles({bool includeTombstones = false}) {
    final query = db.select(db.profiles)
      ..orderBy([
        (t) => OrderingTerm(expression: t.sortOrder),
        (t) => OrderingTerm(expression: t.id),
      ]);
    if (!includeTombstones) {
      query.where((t) => t.deletedAt.isNull());
    }
    return query.get();
  }

  /// Stream variant of [getProfiles] for reactive UI.
  Stream<List<Profile>> watchProfiles({bool includeTombstones = false}) {
    final query = db.select(db.profiles)
      ..orderBy([
        (t) => OrderingTerm(expression: t.sortOrder),
        (t) => OrderingTerm(expression: t.id),
      ]);
    if (!includeTombstones) {
      query.where((t) => t.deletedAt.isNull());
    }
    return query.watch();
  }

  // ------------------------------------------------------------- day entries

  /// Creates or updates the *live* day entry for (profileId, localDate).
  ///
  /// * If a live entry exists, it is updated in place (same ULID) with
  ///   `updated_at = max(now, stored)` (monotonic).
  /// * If none exists (including when only a tombstone exists for that date),
  ///   a new row with a fresh ULID is inserted. The old tombstone remains in
  ///   full-fidelity reads for sync; the new ULID row wins UI reads.
  Future<DayEntry> upsertDayEntry({
    required String profileId,
    required String localDate,
    required String tz,
    required FlowLevel flow,
    List<String> tags = const [],
    String? note,
    DateTime? updatedAt,
  }) async {
    // Async so validation failures surface as failed futures, not sync
    // throws, for callers awaiting the result.
    _validateLocalDate(localDate);
    return db.transaction(() async {
      final now = (updatedAt ?? _clock()).toUtc();
      final live = await _liveDayEntry(profileId, localDate);
      if (live == null) {
        await db.into(db.dayEntries).insert(DayEntriesCompanion.insert(
              id: _generator.next(),
              profileId: profileId,
              localDate: localDate,
              tz: tz,
              flow: flow,
              tags: Value(tags),
              note: Value(note),
              updatedAt: now,
            ));
      } else {
        final rowId = live.id;
        await (db.update(db.dayEntries)..where((t) => t.id.equals(rowId)))
            .write(DayEntriesCompanion(
          tz: Value(tz),
          flow: Value(flow),
          tags: Value(tags),
          note: Value(note),
          updatedAt: Value(_notBefore(now, live.updatedAt)),
          deletedAt: const Value(null),
        ));
      }
      final rows = await (db.select(db.dayEntries)
            ..where((t) =>
                t.profileId.equals(profileId) &
                t.localDate.equals(localDate) &
                t.deletedAt.isNull()))
          .get();
      if (rows.isEmpty) {
        throw StateError('day entry disappeared: $profileId $localDate');
      }
      return rows.last;
    });
  }

  /// Tombstones the live entry for (profileId, localDate), if any. Does
  /// nothing when there is no live entry (idempotent; never bumps
  /// `updated_at` without a change).
  Future<void> softDeleteDayEntry({
    required String profileId,
    required String localDate,
  }) async {
    await db.transaction(() async {
      final live = await _liveDayEntry(profileId, localDate);
      if (live == null) return;
      final at = _notBefore(_clock(), live.updatedAt);
      final rowId = live.id;
      await (db.update(db.dayEntries)..where((t) => t.id.equals(rowId))).write(
          DayEntriesCompanion(updatedAt: Value(at), deletedAt: Value(at)));
    });
  }

  /// Day entries for one profile — UI reads (default) filter tombstones;
  /// `includeTombstones: true` gives full-fidelity reads for sync.
  /// [updatedAfter] narrows to rows changed after that instant
  /// (incremental-sync support). Per-profile isolation (R3) is structural:
  /// every query is scoped to exactly one profileId.
  Future<List<DayEntry>> getDayEntries({
    required String profileId,
    bool includeTombstones = false,
    DateTime? updatedAfter,
  }) {
    return _dayEntryQuery(
      profileId: profileId,
      includeTombstones: includeTombstones,
      updatedAfter: updatedAfter,
    ).get();
  }

  /// Stream variant of [getDayEntries] for reactive UI.
  Stream<List<DayEntry>> watchDayEntries({
    required String profileId,
    bool includeTombstones = false,
    DateTime? updatedAfter,
  }) {
    return _dayEntryQuery(
      profileId: profileId,
      includeTombstones: includeTombstones,
      updatedAfter: updatedAfter,
    ).watch();
  }

  // ------------------------------------------------------------- app settings

  /// Device-local key-value state. Not part of the sync model (open design
  /// question); `updated_at` kept for uniform change tracking.
  Future<void> setSetting({
    required String key,
    required String value,
    DateTime? updatedAt,
  }) async {
    await db.transaction(() async {
      final now = (updatedAt ?? _clock()).toUtc();
      final existing = await (db.select(db.appSettings)
            ..where((t) => t.key.equals(key)))
          .getSingleOrNull();
      await db.into(db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: key,
              value: value,
              updatedAt:
                  existing == null ? now : _notBefore(now, existing.updatedAt),
            ),
          );
    });
  }

  Future<String?> getSetting(String key) async {
    final row = await (db.select(db.appSettings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Stream<String?> watchSetting(String key) {
    final query = db.select(db.appSettings)..where((t) => t.key.equals(key));
    return query.watchSingleOrNull().map((row) => row?.value);
  }

  // ---------------------------------------------------------------- internal

  Selectable<DayEntry> _dayEntryQuery({
    required String profileId,
    required bool includeTombstones,
    DateTime? updatedAfter,
  }) {
    final query = db.select(db.dayEntries)
      ..where((row) {
        var condition = row.profileId.equals(profileId);
        if (!includeTombstones) {
          condition = condition & row.deletedAt.isNull();
        }
        if (updatedAfter != null) {
          condition = condition & row.updatedAt.isBiggerThanValue(updatedAfter);
        }
        return condition;
      })
      ..orderBy([(row) => OrderingTerm(expression: row.localDate)]);
    return query;
  }

  Future<DayEntry?> _liveDayEntry(String profileId, String localDate) {
    final query = db.select(db.dayEntries)
      ..where((t) =>
          t.profileId.equals(profileId) &
          t.localDate.equals(localDate) &
          t.deletedAt.isNull());
    return query.getSingleOrNull();
  }

  Future<Profile> _profileById(String id) async {
    final row = await (db.select(db.profiles)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) throw StateError('profile disappeared: $id');
    return row;
  }
}
