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

/// Menstrual flow levels (cycle/flow-only logging; fertility-signal
/// logging fields arrive with #144). Issue #247 adds `superHeavy` (a
/// fourth bleed level) and `notBleeding` (an explicit "not bleeding
/// today" assertion, distinct from `none`/unlogged); `spotting` stays as
/// a deprecated alias for already-stored data -- see the domain mirror's
/// doc comment, `lib/domain/models/flow_level.dart`, for the full
/// rationale. Member names here are local-storage-only (this converter's
/// `toSql`/`fromSql` use `.name` directly, opaque to SQLite) and need not
/// match the server wire string -- [toDb]/[fromDb] below are what
/// `lib/data/sync/row_codec.dart` uses for that.
enum FlowLevel {
  none,
  spotting,
  notBleeding,
  light,
  medium,
  heavy,
  superHeavy;

  /// Server wire string -- mirrors the domain enum's `toDb()`
  /// (`lib/domain/models/flow_level.dart`), duplicated here rather than
  /// shared since `lib/data/` and `lib/domain/` deliberately keep
  /// separate `FlowLevel` types (R14/R16).
  String toDb() => switch (this) {
        FlowLevel.none => 'none',
        FlowLevel.spotting => 'spotting',
        FlowLevel.notBleeding => 'not_bleeding',
        FlowLevel.light => 'light',
        FlowLevel.medium => 'medium',
        FlowLevel.heavy => 'heavy',
        FlowLevel.superHeavy => 'super_heavy',
      };

  static FlowLevel fromDb(String value) => switch (value) {
        'spotting' => FlowLevel.spotting,
        'not_bleeding' => FlowLevel.notBleeding,
        'light' => FlowLevel.light,
        'medium' => FlowLevel.medium,
        'heavy' => FlowLevel.heavy,
        'super_heavy' => FlowLevel.superHeavy,
        _ => FlowLevel.none,
      };
}

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

  /// Optional birth year of the profile subject (Issue #4 R1). Display and
  /// context only — never gates, forces, or auto-schedules an ownership
  /// transfer (R2).
  IntColumn get birthYear => integer().named('birth_year').nullable()();

  /// Optional closed-set relationship of the subject to the profile creator
  /// (R3), mirrored by [domain.ProfileRelationship]. Stored as the raw
  /// `toDb()` string; an unrecognised value decodes to null rather than
  /// throwing (see `row_codec.dart`).
  TextColumn get relationship => text().nullable()();

  /// Care mode (Issue #131, R12), mirrored by [domain.ProfileMode] and the
  /// server's `profiles_mode_check` CHECK (`standard|teen|caregiver|
  /// irregular`). Non-null, defaulting to `standard`; an unrecognised value
  /// decodes to `standard` rather than throwing (see `row_codec.dart`).
  /// Presentation only — never consulted by any authorization path.
  TextColumn get mode => text().withDefault(const Constant('standard'))();

  /// Instant this profile's ownership last moved via
  /// `accept_ownership_transfer`, or null if it never has (R5). Never
  /// client-writable — server-owned, pulled but never pushed (see
  /// `encodeProfile` in `row_codec.dart`).
  DateTimeColumn get transferredAt =>
      dateTime().named('transferred_at').nullable()();

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

  /// Supabase auth user who created this entry (stamped by server).
  TextColumn get loggedByUserId =>
      text().named('logged_by_user_id').nullable()();

  /// Supabase auth user who last edited this entry (stamped by server).
  TextColumn get lastModifiedByUserId =>
      text().named('last_modified_by_user_id').nullable()();

  /// Import/device provenance (Issue #159), mirroring `public.day_entries`'
  /// `day_entries_source_check` (`manual`/`clue_import`/`healthkit`/
  /// `health_connect`/`file_import` — a different closed set from
  /// [Observations.source]'s, see `domain.DayEntrySource`'s doc comment).
  /// Never cleared on a tombstone (see `sync_push`'s doc comment in
  /// `supabase/migrations/20260908170000_import_provenance.sql`).
  TextColumn get source =>
      text().withDefault(const Constant('manual'))();

  /// Import/device provenance key, for idempotent re-import; paired with
  /// [source] in the server's partial unique index.
  TextColumn get sourceId => text().named('source_id').nullable()();

  /// Placeholder FK to a future `import_jobs(id)` row (Issue #159,
  /// unconstrained server-side until #167 adds that table).
  TextColumn get importId => text().named('import_id').nullable()();

  @override
  Set<Column> get primaryKey => {id};

  // NOTE: uniqueness of (profile_id, local_date) is enforced only among live
  // rows, via the partial index created in LunarLogDatabase's migration
  // (uq_day_entries_profile_date_live). A plain UNIQUE constraint would make
  // re-creating an entry for a tombstoned date impossible, breaking sync.
}

@DataClassName('ProfileGuardianData')
class ProfileGuardians extends Table {
  TextColumn get id => text()();

  TextColumn get profileId =>
      text().named('profile_id').references(Profiles, #id)();

  TextColumn get userId => text().named('user_id')();

  /// 'primary_guardian' | 'co_parent' | 'caregiver' | 'viewer'
  TextColumn get role => text()();

  /// 'pending' | 'accepted' | 'revoked'
  TextColumn get status =>
      text().withDefault(const Constant('accepted'))();

  TextColumn get displayName => text().named('display_name').nullable()();

  TextColumn get invitedBy => text().named('invited_by').nullable()();

  DateTimeColumn get createdAt => dateTime().named('created_at')();

  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

/// One logged option (Issue #240, the Clue tracking model's `observations`
/// child table): a `day_entry_id`-scoped row per (category, code), with
/// numeric/text value, unit, intensity, exclusion, and source provenance.
/// Mirrors `public.observations` column-for-column; see
/// `supabase/migrations/20260908160000_observations.sql` for the server
/// shape and its RLS/grants. `category`/`code` are free text — never
/// validated client-side against a closed set (issue #240 D-10 companion
/// note: unlike `flow`, the ~200 option codes are stored, never rejected,
/// so a newer client's or an importer's not-yet-locally-known code always
/// round-trips).
@DataClassName('Observation')
class Observations extends Table {
  /// Client-generated ULID (stable across devices/sync).
  TextColumn get id => text()();

  /// The day entry this observation is attached to; cascades with its
  /// tombstone. Immutable once set (enforced server-side by `sync_push`).
  TextColumn get dayEntryId =>
      text().named('day_entry_id').references(DayEntries, #id)();

  /// Denormalized for query and parity with the server's RLS predicates
  /// (matches `day_entries.profile_id`).
  TextColumn get profileId => text().named('profile_id').references(Profiles, #id)();

  /// ISO calendar date `yyyy-MM-dd` in the profile's local zone.
  TextColumn get localDate => text().named('local_date')();

  /// Optional exact time-of-day; unused by the Clue importer (A1-40).
  DateTimeColumn get observedAt => dateTime().named('observed_at').nullable()();

  /// IANA time zone name the entry was logged in.
  TextColumn get tz => text()();

  /// e.g. `pain`, `energy`, `bbt`. Free text, never a closed set. Nullable
  /// (review finding: no longer required on a tombstone -- see
  /// `supabase/migrations/20260908160000_observations.sql`'s
  /// `observations_category_required_unless_tombstoned_check`); still
  /// required on every live row, enforced in the storage layer (see
  /// `LunarLogStorage.upsertObservation`'s `_validateObservation` call and
  /// `softDeleteObservation`, which clears it alongside every other
  /// payload column).
  TextColumn get category => text().nullable()();

  /// The selected option within [category] (e.g. `migraine`); nullable
  /// only for a purely-numeric category. Free text, never a closed set.
  TextColumn get code => text().nullable()();

  RealColumn get valueNum => real().named('value_num').nullable()();

  TextColumn get valueText => text().named('value_text').nullable()();

  /// `celsius` / `fahrenheit` / `kg` / `lb`.
  TextColumn get unit => text().nullable()();

  /// 1-5; nullable for legacy/ungraded rows.
  IntColumn get intensity => integer().nullable()();

  /// BBT's per-point exclusion flag (A1-44).
  BoolColumn get excluded => boolean().withDefault(const Constant(false))();

  /// `manual` / `apple_health` / `health_connect` / `wearable` / `clue_import`.
  TextColumn get source =>
      text().withDefault(const Constant('manual'))();

  /// Import/device provenance key, for idempotent re-import.
  TextColumn get sourceId => text().named('source_id').nullable()();

  /// Placeholder FK to a future `import_jobs(id)` row (Issue #159,
  /// unconstrained server-side until #167 adds that table).
  TextColumn get importId => text().named('import_id').nullable()();

  /// Escape hatch for an unrecognised type/value shape (A1-45); the entire
  /// original datapoint as JSON text.
  TextColumn get raw => text().nullable()();

  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  DateTimeColumn get deletedAt => dateTime().named('deleted_at').nullable()();

  /// See [Profiles.dirty].
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  /// See [Profiles.localRev].
  IntColumn get localRev =>
      integer().named('local_rev').withDefault(const Constant(0))();

  /// Supabase auth user who created this observation (stamped by server).
  TextColumn get loggedByUserId =>
      text().named('logged_by_user_id').nullable()();

  /// Supabase auth user who last edited this observation (stamped by server).
  TextColumn get lastModifiedByUserId =>
      text().named('last_modified_by_user_id').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One row per profile: the life-stage mode axis (Issue #188), mirroring
/// `public.profile_modes` column-for-column; see
/// `supabase/migrations/20260909000000_profile_modes_and_cycle_overrides.sql`
/// for the server shape and its RLS/grants. ORTHOGONAL to [Profiles.mode]
/// (Issue #131's care modes) — the two enums are never merged; see
/// `domain/models/lifecycle_mode.dart`'s doc comment.
///
/// Unlike every other synced table there is NO `deleted_at`: the server
/// table has none either — a mode row is created lazily on first write and
/// dies with its profile. An absent row means `tracking` (the column
/// default, matching the server's lazy-default contract).
@DataClassName('ProfileModeData')
class ProfileModes extends Table {
  /// The profile this row belongs to (also the primary key — exactly one
  /// row per profile, enforced by the key itself).
  TextColumn get profileId =>
      text().named('profile_id').references(Profiles, #id)();

  /// Raw `LifecycleMode` `toDb()` string
  /// (`tracking`/`conceive`/`pregnancy`/`perimenopause`/`postpartum`), the
  /// server's `profile_modes_mode_check` set. Not validated here (the
  /// domain enum and the server CHECK are the enforcement points); an
  /// unrecognised value decodes to `tracking` on pull (see `row_codec.dart`).
  TextColumn get mode => text().withDefault(const Constant('tracking'))();

  /// ISO calendar date `yyyy-MM-dd` the current mode took effect, or null.
  TextColumn get modeStartedOn =>
      text().named('mode_started_on').nullable()();

  /// Current birth-control method (free text, #260 owns the vocabulary) or
  /// null when none is recorded.
  TextColumn get birthControlMethod =>
      text().named('birth_control_method').nullable()();

  TextColumn get birthControlStartedOn =>
      text().named('birth_control_started_on').nullable()();

  TextColumn get birthControlStoppedOn =>
      text().named('birth_control_stopped_on').nullable()();

  /// D-29: per-profile opt-in for health-platform writes — a distinct
  /// consent from cycle sharing/guardian consent, recorded server-side.
  BoolColumn get healthSyncConsent =>
      boolean().named('health_sync_consent').withDefault(const Constant(false))();

  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  /// See [Profiles.dirty]. (No `deleted_at` — this table has no tombstone.)
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  /// See [Profiles.localRev].
  IntColumn get localRev =>
      integer().named('local_rev').withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {profileId};
}

/// One row per manually-flagged or manually-started cycle (Issue #188,
/// consumed by #132's omit-from-average and manual cycle-boundary
/// correction), mirroring `public.cycle_overrides` column-for-column.
/// Tombstones (`deletedAt` set) carry no payload — `excludedFromAverage`/
/// `manualStart` reset to false and `noteId` cleared, mirroring the
/// server's `cycle_overrides_tombstone_payload_check` exactly.
@DataClassName('CycleOverrideData')
class CycleOverrides extends Table {
  /// Client-generated ULID (stable across devices/sync).
  TextColumn get id => text()();

  TextColumn get profileId =>
      text().named('profile_id').references(Profiles, #id)();

  /// ISO calendar date `yyyy-MM-dd` of the manual boundary.
  TextColumn get cycleStartDate =>
      text().named('cycle_start_date')();

  /// True when this interval is left out of cycle-length averages (#132).
  BoolColumn get excludedFromAverage =>
      boolean().named('excluded_from_average').withDefault(const Constant(false))();

  /// True when the user started this cycle by hand.
  BoolColumn get manualStart =>
      boolean().named('manual_start').withDefault(const Constant(false))();

  /// Placeholder id of a future notes-table row (#132); null when unset.
  TextColumn get noteId => text().named('note_id').nullable()();

  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  DateTimeColumn get deletedAt => dateTime().named('deleted_at').nullable()();

  /// See [Profiles.dirty].
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  /// See [Profiles.localRev].
  IntColumn get localRev =>
      integer().named('local_rev').withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id, profileId};
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

  /// Issue #240: the `observations` pull cursor, same shape as
  /// [cursorDayEntries].
  IntColumn get cursorObservations =>
      integer().named('cursor_observations').withDefault(const Constant(0))();

  /// Issue #188: the `profile_modes` pull cursor, same shape as
  /// [cursorProfiles].
  IntColumn get cursorProfileModes =>
      integer().named('cursor_profile_modes').withDefault(const Constant(0))();

  /// Issue #188: the `cycle_overrides` pull cursor, same shape as
  /// [cursorDayEntries].
  IntColumn get cursorCycleOverrides =>
      integer().named('cursor_cycle_overrides').withDefault(const Constant(0))();

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
