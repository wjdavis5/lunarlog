/// Drift table definitions for the lunarlog data model.
///
/// Every domain row carries the hand-modeled sync metadata settled in the
/// data model: client-generated ULID id, `updated_at` (UTC, never regresses
/// on-device), and `deleted_at` (tombstone soft-delete; rows are never
/// removed). Schema v2 (KTD4) adds device-local sync bookkeeping to the two
/// synced tables — `dirty` (needs pushing) and `local_rev` (bumped on every
/// local write, never synced) — plus the `sync_state` singleton.
/// `app_settings` is device-local key-value state and intentionally
/// carries only `updated_at` (flagged as an open design question).
library;

import 'dart:convert';

import 'package:drift/drift.dart';

/// Menstrual flow levels (no fertility features — v1 scope).
enum FlowLevel { none, spotting, light, medium, heavy }

class FlowLevelConverter extends TypeConverter<FlowLevel, String> {
  const FlowLevelConverter();

  @override
  FlowLevel fromSql(String fromDb) => FlowLevel.values.byName(fromDb);

  @override
  String toSql(FlowLevel value) => value.name;
}

class TagsConverter extends TypeConverter<List<String>, String> {
  const TagsConverter();

  @override
  List<String> fromSql(String fromDb) =>
      (jsonDecode(fromDb) as List<dynamic>).cast<String>();

  @override
  String toSql(List<String> value) => jsonEncode(value);
}

@DataClassName('Profile')
class Profiles extends Table {
  /// Client-generated ULID (stable across devices/sync).
  TextColumn get id => text()();

  TextColumn get displayName => text().named('display_name')();

  BoolColumn get isMinor => boolean().named('is_minor')();

  IntColumn get sortOrder => integer().named('sort_order').withDefault(const Constant(0))();

  DateTimeColumn get archivedAt => dateTime().named('archived_at').nullable()();

  DateTimeColumn get createdAt => dateTime().named('created_at')();

  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  DateTimeColumn get deletedAt => dateTime().named('deleted_at').nullable()();

  /// Device-local: true while this row has a local change not yet pushed.
  /// Set by every local write; cleared by `markPushed` and remote applies.
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  /// Device-local revision counter, bumped on every local write and never
  /// synced. `markPushed` clears `dirty` only when it still matches the
  /// value read at push time (KTD4, AE11).
  IntColumn get localRev =>
      integer().named('local_rev').withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DayEntry')
class DayEntries extends Table {
  /// Client-generated ULID (stable across devices/sync).
  TextColumn get id => text()();

  TextColumn get profileId => text().named('profile_id').references(Profiles, #id)();

  /// ISO calendar date `yyyy-MM-dd` in the profile's local zone.
  TextColumn get localDate => text().named('local_date')();

  /// IANA time zone name the [localDate] was recorded in.
  TextColumn get tz => text()();

  TextColumn get flow => text().map(const FlowLevelConverter())();

  /// JSON array of tag codes.
  TextColumn get tags =>
      text().map(const TagsConverter()).withDefault(const Constant('[]'))();

  TextColumn get note => text().nullable()();

  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  DateTimeColumn get deletedAt => dateTime().named('deleted_at').nullable()();

  /// See [Profiles.dirty].
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  /// See [Profiles.localRev].
  IntColumn get localRev =>
      integer().named('local_rev').withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};

  // NOTE: uniqueness of (profile_id, local_date) is enforced only among live
  // rows, via the partial index created in LunarLogDatabase's migration
  // (uq_day_entries_profile_date_live). A plain UNIQUE constraint would make
  // re-creating an entry for a tombstoned date impossible, breaking sync.
}

@DataClassName('AppSetting')
class AppSettings extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  @override
  Set<Column> get primaryKey => {key};
}

/// Device-level sync bookkeeping (KTD4): exactly one row (`id = 1`,
/// enforced by a CHECK), absent until the first sync write. The whole local
/// database belongs to at most one account (R15), so the binding is a
/// device-level fact, not a per-row `user_id`.
@DataClassName('SyncStateRow')
class SyncState extends Table {
  // The documented drift form for a self-referencing CHECK.
  // ignore: recursive_getters
  IntColumn get id => integer().check(id.equals(1))();

  /// The Supabase user this database is bound to; null while signed out
  /// or never bound.
  TextColumn get boundUserId => text().named('bound_user_id').nullable()();

  /// Stable per-install identifier minted by the sync engine. Defaults to
  /// the empty string so the row can be created by a cursor write before
  /// the engine has bound the device.
  TextColumn get deviceId =>
      text().named('device_id').withDefault(const Constant(''))();

  /// Per-table pull cursors (`server_version` high-water marks, KTD2).
  IntColumn get cursorProfiles =>
      integer().named('cursor_profiles').withDefault(const Constant(0))();

  IntColumn get cursorDayEntries =>
      integer().named('cursor_day_entries').withDefault(const Constant(0))();

  DateTimeColumn get lastFullPullAt =>
      dateTime().named('last_full_pull_at').nullable()();

  DateTimeColumn get lastSyncAt => dateTime().named('last_sync_at').nullable()();

  /// Last sync failure, as a type name or short code — never health content.
  TextColumn get lastError => text().named('last_error').nullable()();

  /// `server_now - device_now` in milliseconds, learned from the push RPC;
  /// the storage clock adds it when stamping local writes.
  IntColumn get serverClockOffsetMs =>
      integer().named('server_clock_offset_ms').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
