/// Drift table definitions for the lunarlog data model.
///
/// Every domain row carries the hand-modeled sync metadata settled in the
/// data model: client-generated ULID id, `updated_at` (UTC, never regresses
/// on-device), and `deleted_at` (tombstone soft-delete; rows are never
/// removed). `app_settings` is device-local key-value state and intentionally
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
