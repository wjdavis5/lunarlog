/// Drift table definitions for the lunarlog data model.
///
/// Every domain row carries the hand-modeled sync metadata settled in the
/// data model: client-generated ULID id, `updated_at` (UTC, never regresses
/// on-device), and `deleted_at` (tombstone soft-delete; rows are retained
/// for sync until swept by the bounded tombstone sweep — Issue #203). Schema
/// v2 (KTD4) adds device-local sync bookkeeping to the two synced tables —
/// `dirty` (needs pushing) and `local_rev` (bumped on every local write,
/// never synced) — plus the `sync_state` singleton.
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
  /// Issue #853: the `irregular` value is a legacy wire value only — never
  /// stored by this client (the v28 migration converts any stored copy to
  /// `standard` + [irregularFraming], and `decodeProfile` maps any that an
  /// old client re-pushes), though the server CHECK still accepts it.
  TextColumn get mode => text().withDefault(const Constant('standard'))();

  /// Irregular-cycles framing (Issue #853), mirrored by
  /// `domain.Profile.irregularFraming` and the server's nullable
  /// `profiles.irregular_framing` boolean. Nullable tri-state BY DESIGN —
  /// null means "never explicitly chosen; the engine default applies"
  /// (`irregularFramingInEffect` in `lib/domain/care_modes.dart`: true for
  /// a `teen`-mode profile until `CycleConfidence.high`, false otherwise),
  /// while `true`/`false` are the operator's explicit override. Nullable
  /// (not non-null-with-default, the [unitsUnconfirmed] precedent) so every
  /// existing direct `Profile(...)` test fixture keeps compiling without
  /// passing the field. Presentation only — never consulted by any
  /// authorization path. Never synced as a null: `encodeProfile` emits the
  /// key only when non-null, so a never-chosen device can't clobber a
  /// co-guardian's explicit choice (the server's `?` containment guard
  /// backstops it).
  BoolColumn get irregularFraming =>
      boolean().named('irregular_framing').nullable()();

  /// Instant this profile's ownership last moved via
  /// `accept_ownership_transfer`, or null if it never has (R5). Never
  /// client-writable — server-owned, pulled but never pushed (see
  /// `encodeProfile` in `row_codec.dart`).
  DateTimeColumn get transferredAt =>
      dateTime().named('transferred_at').nullable()();

  /// The account that accepted this profile's last ownership transfer, or
  /// null if it never has (Issue #296). Same server-owned, pulled-never-
  /// pushed treatment as [transferredAt]: the health-sync minor gate
  /// requires this to equal the signed-in user id before a transferred
  /// minor profile may bind, and null fails closed.
  TextColumn get transferredToUserId =>
      text().named('transferred_to_user_id').nullable()();

  /// Onboarding-collected cycle facts (Issue #218), mirrored by the
  /// server's `profiles` columns added in
  /// `20260909120000_provisional_cycle_facts.sql`. ISO calendar date
  /// `yyyy-MM-dd` of the supplied last-period start, like
  /// `profile_modes.mode_started_on`'s text-date shape. Optional and
  /// editable later from profile settings; feeds the provisional
  /// prediction seed — never a `day_entries` row (a supplied answer is
  /// not an observation).
  TextColumn get lastPeriodStart =>
      text().named('last_period_start').nullable()();

  /// The supplied "typical cycle length" answer in days (Issue #218).
  /// Stored as supplied; `CycleFacts.canSeed` in the prediction domain is
  /// the semantic bound on which values can seed an estimate.
  IntColumn get typicalCycleLengthDays =>
      integer().named('typical_cycle_length_days').nullable()();

  /// The supplied "typical period length" answer in days (Issue #218).
  IntColumn get typicalPeriodLengthDays =>
      integer().named('typical_period_length_days').nullable()();

  /// The profile's curated tracking categories (Issue #259), as the JSON
  /// text `TrackingPreferences.toJsonText` produces — the same partial
  /// `{category: {enabled, sort_order}}` document the server's
  /// `profiles.tracking_preferences` jsonb carries (mirroring
  /// [Observations.raw]'s wire-JSON/local-text precedent). Null means
  /// never customized: every category resolves to its default (enabled,
  /// taxonomy order) except the minor-hidden set on an [isMinor] profile.
  /// Presentation curation only — never consulted by any authorization
  /// path, and hiding a category never touches already-logged entries.
  /// Synced like any other profile column; `row_codec.dart` carries it on
  /// the wire as a JSON object and only ever emits the key when locally
  /// non-null, so this client never clears a co-guardian's document by
  /// accident (the server's `?` containment guard is the backstop).
  TextColumn get trackingPreferences =>
      text().named('tracking_preferences').nullable()();

  /// Per-profile BBT display unit (Issue #255), mirrored by
  /// `domain.BbtUnit` and the server's `profiles_bbt_unit_check` CHECK
  /// (`celsius|fahrenheit`). Non-null, defaulting to `celsius`; an
  /// unrecognised value decodes to `celsius` rather than throwing (see
  /// `row_codec.dart`). Presentation only — a stored `observations`
  /// temperature always keeps the unit it was entered/imported in
  /// (`observations.unit`); this decides only how it renders.
  TextColumn get bbtUnit =>
      text().named('bbt_unit').withDefault(const Constant('celsius'))();

  /// Per-profile weight display unit (Issue #255), mirrored by
  /// `domain.WeightUnit` and the server's `profiles_weight_unit_check`
  /// CHECK (`kg|lb`). Same contract as [bbtUnit].
  TextColumn get weightUnit =>
      text().named('weight_unit').withDefault(const Constant('kg'))();

  /// Device-local, never synced (LLA-041): the instant
  /// `_tombstoneRevokedSharedProfile` last wiped this row for a guardian
  /// revocation (or a server-side hard purge), or null if it has never
  /// been evicted this way. Marks the local copy's `updated_at` as a
  /// cache-eviction artifact rather than a genuine LWW competitor: the
  /// wipe deliberately leaves `updated_at` untouched (so an unrevoked
  /// re-share carrying the profile's original, never-bumped timestamp can
  /// still tie/win normally), but that same choice means a row that was
  /// *dirty* with an unpushed, clock-ahead edit at wipe time keeps an
  /// `updated_at` no future authoritative delivery can ever beat under the
  /// ordinary per-id rule. [_applyProfile] bypasses that rule entirely
  /// while this is non-null — any remote delivery of the row wins
  /// unconditionally — and clears it back to null the moment one lands, so
  /// normal per-id LWW resumes from the restored value.
  DateTimeColumn get accessRevokedAt =>
      dateTime().named('access_revoked_at').nullable()();

  /// Device-local, never synced (Issue #637, LLA-039). Nullable, like
  /// [accessRevokedAt] just above, specifically so every existing direct
  /// `Profile(...)` test fixture keeps compiling without passing this
  /// field (a non-nullable-with-default `BoolColumn` still generates a
  /// *required* Dart constructor parameter — nullable is the column shape
  /// that does not). Null or `false` for a row this device has confirmed
  /// against a real server value at least once — a fresh local row (never
  /// set, so implicitly null) and every remote apply of this row
  /// (`_applyProfile` always clears it back to null on write, win or
  /// lose). `true` for every row the v20 migration found already on the
  /// device: [bbtUnit]/[weightUnit] were added at v16 with a local
  /// default (`celsius`/`kg`), so an old client upgrading through that
  /// version backfills every existing profile with that default whether
  /// or not the server already held a real, different preference — and
  /// since a migration never marks a row `dirty`, the row's own
  /// `updated_at` is untouched, so the two values silently diverge with
  /// nothing to say so. If the row later becomes dirty for an unrelated
  /// edit before the next pull ever delivers the server's real value, an
  /// ordinary push would carry the still-default `bbt_unit`/`weight_unit`
  /// as if it were real data and clobber the server's stored preference.
  /// `row_codec.dart`'s `encodeProfile` omits both keys while this is
  /// `true` — safe, since `sync_push`'s update path already applies a
  /// `? 'bbt_unit'`/`? 'weight_unit'` containment guard for an absent key
  /// (the same guard [trackingPreferences] already relies on) — so an
  /// otherwise-legitimate push of the rest of the row never touches
  /// either preference until this device has actually seen the server's
  /// value for them.
  BoolColumn get unitsUnconfirmed =>
      boolean().named('units_unconfirmed').nullable()();

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

  /// First-class PMS marker (Issue #220): the day was premenstrual,
  /// deliberately distinct from the tag taxonomy (a day can be PMS without
  /// also being tagged for every symptom present). Cleared on a tombstone
  /// like every other payload column (the server's
  /// `day_entries_tombstone_pms_check` is the structural backstop); the
  /// `sync_push` update path applies a `v_row ? 'pms'` containment guard so
  /// an old client's payload that omits the key entirely never clears an
  /// already-stored marker. Logged PMS days feed the 6-cycle PMS averages
  /// and the predicted PMS band (`lib/domain/prediction/pms.dart`).
  BoolColumn get pms => boolean().withDefault(const Constant(false))();

  /// Device-local, never synced (Issue #637, LLA-039) — the same
  /// unconfirmed-default guard as [Profiles.unitsUnconfirmed] (see its
  /// doc comment for why this is nullable rather than
  /// non-nullable-with-default), for [pms]: `pms` was added at v12 with a
  /// local default (`false`), so an old client upgrading through that
  /// version backfills every existing day entry with `false` whether or
  /// not the server already held `true` for it, and a migration never
  /// marks a row dirty, so nothing about the row's own `updated_at`
  /// reveals the divergence. Null or `false` for a row this device has
  /// confirmed against a real server value at least once (never set on a
  /// fresh local row, and cleared back to null on every remote apply of
  /// this row); `true` for every row the v20 migration found already on
  /// the device. `row_codec.dart`'s `encodeDayEntry` omits the `pms` key
  /// while this is `true` — safe, since `sync_push`'s update path already
  /// applies a `? 'pms'` containment guard for an absent key.
  BoolColumn get pmsUnconfirmed =>
      boolean().named('pms_unconfirmed').nullable()();

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

  /// Server-owned, monotonic version stamped by the server's
  /// `set_server_version` trigger on every insert/update (LLA-035): unlike
  /// every other per-id table, this table's `updated_at` is directly
  /// client-writable (`grant update (display_name, updated_at)` in
  /// `20260904010000_multi_guardian_schema.sql`, needed so a guardian can
  /// edit its own `display_name`), so an accepted guardian can stamp its
  /// own membership row's `updated_at` arbitrarily far in the future and
  /// permanently outrank a later, authoritative revocation under the
  /// ordinary per-id rule. Membership convergence is ordered by this
  /// column instead — see `conflict_rules.dart`'s `remoteWinsByVersion`.
  IntColumn get serverVersion =>
      integer().named('server_version').withDefault(const Constant(0))();

  /// Issue #802: this member is the person the profile is about (the
  /// subject). Server-stamped by the subject invitation path or
  /// `accept_ownership_transfer` only — never client-writable on either
  /// side — and synced with the row (durable, unlike #518's client-side
  /// flag). Membership identity, orthogonal to both [role] (the only
  /// capability model) and the profile's own `is_minor`/`birth_year`
  /// (#295). NOT NULL DEFAULT FALSE locally so the v29 `addColumn`
  /// backfills every pre-#802 row as a plain helper membership in one
  /// catalog-only step; a pulled null (a server row never re-stamped since
  /// the column landed) decodes to false before it reaches storage.
  BoolColumn get isSubject =>
      boolean().named('is_subject').withDefault(const Constant(false))();

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

  /// Issue #186 (sync mechanics): the UTC instant this row's content was
  /// last written to a health platform (HealthKit/Health Connect), so a
  /// round-trip write is detectable when the same row comes back through a
  /// future import (#217/#228). Client-stamped at export time and synced
  /// like any other observations column (the migration applies the
  /// established `v_row ? 'key'` containment guard so an old client's
  /// payload never clears an already-stored value). Null until the export
  /// flow writes it — inert until #217/#228 own that flow.
  DateTimeColumn get exportedToPlatformAt =>
      dateTime().named('exported_to_platform_at').nullable()();

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

  /// Estimated due date (Issue #192), as an ISO calendar date
  /// `yyyy-MM-dd` — derived on entry from the last recorded period start
  /// + 280 days (Naegele's rule) or manually supplied when that start is
  /// unknown/imported, stored here (NOT client-local: it must sync) and
  /// consumed by the Pregnancy-mode week counter. Kept on exit rather
  /// than cleared — the mode column says whether a pregnancy is current;
  /// this stays as the record of the one that was (and is overwritten on
  /// any later re-entry).
  TextColumn get estimatedDueDate =>
      text().named('estimated_due_date').nullable()();

  /// Postpartum-mode birth date (Issue #861), as an ISO calendar date
  /// `yyyy-MM-dd` — optionally supplied when the operator switches to
  /// Postpartum, stored here (synced like every other `profile_modes`
  /// column) and used by the Postpartum day counter. Null when not
  /// supplied: the counter falls back to `modeStartedOn` (today's
  /// existing surrogate). Kept on exit rather than cleared, like
  /// `estimatedDueDate` — the mode column says whether the mode is
  /// current; this stays as the record of the postpartum that was.
  TextColumn get postpartumBirthDate =>
      text().named('postpartum_birth_date').nullable()();

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

@DataClassName('CareNoteData')
class CareNotes extends Table {
  /// Client-generated ULID (stable across devices/sync).
  TextColumn get id => text()();

  /// The profile this note belongs to (notes are per-profile, never
  /// per-date).
  TextColumn get profileId =>
      text().named('profile_id').references(Profiles, #id)();

  /// Free-text standing note (health content; bounded by
  /// `kMaxCareNoteLength`, cleared on a tombstone like every other payload
  /// column).
  TextColumn get body => text()();

  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  DateTimeColumn get deletedAt => dateTime().named('deleted_at').nullable()();

  /// See [Profiles.dirty].
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  /// See [Profiles.localRev].
  IntColumn get localRev =>
      integer().named('local_rev').withDefault(const Constant(0))();

  /// Supabase auth user who created this note (stamped by server).
  TextColumn get loggedByUserId =>
      text().named('logged_by_user_id').nullable()();

  /// Supabase auth user who last edited this note (stamped by server).
  TextColumn get lastModifiedByUserId =>
      text().named('last_modified_by_user_id').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One guardian's dated note on a profile's day (Issue #801): the
/// date-bound, author-scoped sibling of [CareNotes]. Distinct ULIDs per
/// author per date, per-id last-writer-wins, never merged across authors.
/// Tombstones clear `body` (the server's
/// `guardian_notes_tombstone_payload_check`), keeping `local_date`/`tz` as
/// identity/provenance.
@DataClassName('GuardianNoteData')
class GuardianNotes extends Table {
  /// Client-generated ULID (stable across devices/sync).
  TextColumn get id => text()();

  /// The profile this note belongs to.
  TextColumn get profileId =>
      text().named('profile_id').references(Profiles, #id)();

  /// The civil date the note is about (`yyyy-MM-dd`).
  TextColumn get localDate => text().named('local_date')();

  /// IANA time zone name the author's day was measured in.
  TextColumn get tz => text()();

  /// Free-text note (health content; bounded by `kMaxCareNoteLength`,
  /// cleared on a tombstone like every other payload column).
  TextColumn get body => text()();

  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  DateTimeColumn get deletedAt => dateTime().named('deleted_at').nullable()();

  /// See [Profiles.dirty].
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  /// See [Profiles.localRev].
  IntColumn get localRev =>
      integer().named('local_rev').withDefault(const Constant(0))();

  /// Supabase auth user who created this note (stamped by server). Also the
  /// author-ownership key: only this user may edit or tombstone the row.
  TextColumn get loggedByUserId =>
      text().named('logged_by_user_id').nullable()();

  /// Supabase auth user who last edited this note (stamped by server).
  TextColumn get lastModifiedByUserId =>
      text().named('last_modified_by_user_id').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One item on a profile's visit-prep checklist (Issue #128): a
/// question or to-bring for an upcoming appointment. Each item is an
/// independent row converging as a set (see
/// `domain/models/visit_prep_item.dart`'s resolution rule); checked items
/// stay visible until explicitly cleared.
@DataClassName('VisitPrepItemData')
class VisitPrepItems extends Table {
  /// Client-generated ULID (stable across devices/sync).
  TextColumn get id => text()();

  /// The profile this item belongs to.
  TextColumn get profileId =>
      text().named('profile_id').references(Profiles, #id)();

  /// The item/question text (health content; bounded by
  /// `kMaxVisitPrepItemLength`, cleared on a tombstone).
  TextColumn get body => text()();

  /// Whether the item has been checked off. Checking never deletes.
  BoolColumn get isChecked =>
      boolean().named('is_checked').withDefault(const Constant(false))();

  /// The auth user who checked the item (AC3), null while unchecked.
  /// Cleared (alongside [checkedAt]) when the item is unchecked or
  /// tombstoned.
  TextColumn get checkedByUserId =>
      text().named('checked_by_user_id').nullable()();

  /// UTC instant the item was checked, null while unchecked.
  DateTimeColumn get checkedAt =>
      dateTime().named('checked_at').nullable()();

  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  DateTimeColumn get deletedAt => dateTime().named('deleted_at').nullable()();

  /// See [Profiles.dirty].
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  /// See [Profiles.localRev].
  IntColumn get localRev =>
      integer().named('local_rev').withDefault(const Constant(0))();

  /// Supabase auth user who added this item (stamped by server).
  TextColumn get loggedByUserId =>
      text().named('logged_by_user_id').nullable()();

  /// Supabase auth user who last edited this item (stamped by server).
  TextColumn get lastModifiedByUserId =>
      text().named('last_modified_by_user_id').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One recorded same-date merge discard (Issue #130), mirroring
/// `public.day_entry_merge_events` column-for-column: the disclosure record
/// `LunarLogStorage._resolveSameDateConflicts` writes when a same-date
/// resolution actually discarded a `flow` or `note` value (never for a
/// tags-only merge — a set union loses nothing). Machine-written rows, never
/// user-composed content. NO `deleted_at`: nothing ever soft-deletes a merge
/// event — dismissal is device-local (an `app_settings` key), and the only
/// removals are the local profile wipe and display-window aging (the server
/// hard-purges after 30 days; [createdAt] drives the same window locally).
/// Deduplicated by the natural key (profileId, losingRowId, field), matching
/// the server's `day_entry_merge_events_discard_uq` — a discard recorded by
/// this device and the server's own emission of the same event collapse to
/// one local row, so the day sheet never shows two notices for one merge.
@DataClassName('DayEntryMergeEventData')
class DayEntryMergeEvents extends Table {
  /// Client-generated ULID (stable across devices/sync).
  TextColumn get id => text()();

  TextColumn get profileId =>
      text().named('profile_id').references(Profiles, #id)();

  /// ISO calendar date `yyyy-MM-dd` the colliding entries were both for.
  TextColumn get localDate => text().named('local_date')();

  /// The surviving row's id at merge time.
  TextColumn get winningRowId => text().named('winning_row_id')();

  /// The tombstoned row's id at merge time (half of the natural key: a
  /// losing row is tombstoned by the very merge being disclosed, so it can
  /// lose at most one value per field).
  TextColumn get losingRowId => text().named('losing_row_id')();

  /// 'flow' | 'note' — which value kind was discarded.
  TextColumn get field => text()();

  /// The discarded value itself: the losing note's text, or the losing flow
  /// level's wire string. Health content — bounded (the server CHECKs
  /// 2000), never in a notification, kept out of crash reports.
  TextColumn get losingValueText => text().named('losing_value_text')();

  /// Display attribution only: whose value was discarded / survived.
  TextColumn get losingAuthorUserId =>
      text().named('losing_author_user_id').nullable()();

  TextColumn get winningAuthorUserId =>
      text().named('winning_author_user_id').nullable()();

  /// The UTC instant the merge was recorded (the resolution stamp for a
  /// locally-emitted row; the server's `created_at` for a pulled one).
  /// Drives the 30-day display/recovery window, in lockstep with the
  /// server-side retention purge.
  DateTimeColumn get createdAt => dateTime().named('created_at')();

  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  /// See [Profiles.dirty].
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  /// See [Profiles.localRev].
  IntColumn get localRev =>
      integer().named('local_rev').withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// One row of the per-profile custom-tag registry (Issue #257), mirroring
/// `public.profile_tag_registry` column-for-column; see
/// `supabase/migrations/20260917000000_profile_tag_registry.sql` for the
/// server shape, its RLS/grants, and the retirement-not-deletion rule.
/// `hiddenAt` is retirement (removed from the picker; stored rows keep
/// rendering); `deletedAt` is the ordinary synced-table tombstone, payload
/// cleared per the server's `profile_tag_registry_tombstone_payload_check`
/// except `code`, which survives (the #159 provenance precedent).
@DataClassName('ProfileTagRegistryEntry')
class ProfileTagRegistry extends Table {
  /// Client-generated ULID (stable across devices/sync).
  TextColumn get id => text()();

  TextColumn get profileId =>
      text().named('profile_id').references(Profiles, #id)();

  /// The stable snake_case identifier persisted on day entries; immutable
  /// once created (a rename rewrites displayName only). Bounded to
  /// `kMaxTagLength` (64) by the storage layer, mirroring the server's
  /// CHECK. Survives a tombstone.
  TextColumn get code => text()();

  /// The user's own label (bounded to `kMaxCustomTagLabelLength`, 40).
  /// Empty on a tombstone.
  TextColumn get displayName => text().named('display_name')();

  /// Free text, client-owned ('custom' for in-app creations). Empty on a
  /// tombstone.
  TextColumn get category => text()();

  /// Reserved for per-tag intensity affordances; false today.
  BoolColumn get intensityEnabled =>
      boolean().named('intensity_enabled').withDefault(const Constant(false))();

  /// RETIREMENT, not deletion: non-null removes the code from the
  /// day-sheet picker while stored rows referencing it keep rendering.
  /// Null on a tombstone.
  DateTimeColumn get hiddenAt => dateTime().named('hidden_at').nullable()();

  IntColumn get sortOrder => integer().named('sort_order').nullable()();

  /// Server-stamped from the caller on INSERT; never pushed.
  TextColumn get createdBy => text().named('created_by').nullable()();

  /// Server-stamped; never pushed (rides the row for display only).
  DateTimeColumn get createdAt => dateTime().named('created_at')();

  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  DateTimeColumn get deletedAt => dateTime().named('deleted_at').nullable()();

  /// See [Profiles.dirty].
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  /// See [Profiles.localRev].
  IntColumn get localRev =>
      integer().named('local_rev').withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// One row of `public.day_entry_history` (Issue #170): a machine-written,
/// content-free audit record of one day-entry change. Mirrors the server
/// table column-for-column EXCEPT the local store deliberately carries no
/// FK from [entryId] to day entries (the server does; locally, the
/// tombstone sweep may remove an old day-entry row while its 90-day
/// history is still inside the feed window — see the domain model's doc
/// comment) and no `dirty`/`localRev` (PULL-ONLY: rows are never pushed,
/// the [ProfileGuardians] precedent).
@DataClassName('DayEntryHistoryData')
class DayEntryHistory extends Table {
  /// Server-generated ULID (random identity; rows are keyed by event, never
  /// ordered by id).
  TextColumn get id => text()();

  /// The day_entries row the change happened to (a plain text reference
  /// locally — see the class doc comment).
  TextColumn get entryId => text().named('entry_id')();

  TextColumn get profileId =>
      text().named('profile_id').references(Profiles, #id)();

  /// Display attribution only: who made the change.
  TextColumn get changedByUserId =>
      text().named('changed_by_user_id')();

  DateTimeColumn get changedAt => dateTime().named('changed_at')();

  /// Raw `change_kind` wire string ('logged' | 'updated' | 'tombstoned' |
  /// 'merged_discard'); `DayEntryChangeKind.fromDb` normalises on the way
  /// to the domain model.
  TextColumn get changeKind => text().named('change_kind')();

  /// day_entries COLUMN NAMES only, never values — the table's whole
  /// contract (content-free, enforced server-side by CHECK). Stored as a
  /// JSON array via [TagsConverter] (the same List&lt;String&gt; mapping the
  /// day-entry `tags` column uses).
  TextColumn get changedFields =>
      text().named('changed_fields').map(const TagsConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AppSetting')
class AppSettings extends Table {  TextColumn get key => text()();
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

  /// Issue #128: the `care_notes` pull cursor, same shape as
  /// [cursorDayEntries].
  IntColumn get cursorCareNotes =>
      integer().named('cursor_care_notes').withDefault(const Constant(0))();

  /// Issue #128: the `visit_prep_items` pull cursor, same shape as
  /// [cursorDayEntries].
  IntColumn get cursorVisitPrepItems =>
      integer().named('cursor_visit_prep_items').withDefault(const Constant(0))();

  /// Issue #525: the `profile_guardians` pull cursor, same shape as
  /// [cursorDayEntries]. Before this column existed, `profileGuardians`
  /// paged from version 0 every cycle (see the sync engine's
  /// `_startingCursor`, pre-#525) — every 15-minute tick forced a full
  /// sequential scan of the global `profile_guardians` table plus one
  /// `is_profile_guardian()` RLS check per scanned row.
  IntColumn get cursorProfileGuardians =>
      integer().named('cursor_profile_guardians').withDefault(const Constant(0))();

  /// Issue #597: the `deleted_profiles` pull cursor, same shape as
  /// [cursorProfileGuardians] — same fix, same table shape (pull-only, a
  /// server-owned `server_version` already exists and is already indexed
  /// server-side). Before this column existed, `deletedProfiles` paged
  /// from version 0 every cycle (see the sync engine's `_startingCursor`,
  /// pre-#597), same tradeoff #525 closed for `profileGuardians` — this
  /// table stayed small enough for a full scan to be cheap at the time,
  /// but the same per-cycle full-scan cost applies as it grows.
  IntColumn get cursorDeletedProfiles =>
      integer().named('cursor_deleted_profiles').withDefault(const Constant(0))();

  /// Issue #130: the `day_entry_merge_events` pull cursor, same shape as
  /// [cursorDayEntries].
  IntColumn get cursorDayEntryMergeEvents =>
      integer().named('cursor_day_entry_merge_events')
          .withDefault(const Constant(0))();

  /// Issue #257: the `profile_tag_registry` pull cursor, same shape as
  /// [cursorDayEntries].
  IntColumn get cursorProfileTagRegistry =>
      integer().named('cursor_profile_tag_registry')
          .withDefault(const Constant(0))();

  /// Issue #170: the `day_entry_history` pull cursor, same shape as
  /// [cursorDayEntries] (the table is pull-only, so this cursor plus the
  /// apply path are its entire sync surface).
  IntColumn get cursorDayEntryHistory =>
      integer().named('cursor_day_entry_history')
          .withDefault(const Constant(0))();

  /// Issue #801: the `guardian_notes` pull cursor, same shape as
  /// [cursorDayEntries].
  IntColumn get cursorGuardianNotes =>
      integer().named('cursor_guardian_notes')
          .withDefault(const Constant(0))();

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

/// Per-device, per-platform sync anchors for health-store reads (Issue
/// #186, sync mechanics): one row per OS health platform (`healthkit` /
/// `health_connect`), recording the change anchor and the last sync
/// instant. **Deliberately never synced to the server** — anchors are
/// device-specific and the platform stores are local (never server state),
/// exactly the rationale `sync_state`'s cursor columns already document for
/// lunarlog's own sync. Also deliberately not bound to a profile: like
/// `sync_state`, the whole local database belongs to at most one account,
/// and the platform anchor advances regardless of which bound profile (at
/// most one at a time) is being synced.
@DataClassName('HealthSyncStateRow')
class HealthSyncState extends Table {
  /// The OS health platform this anchor belongs to: `healthkit` |
  /// `health_connect`.
  TextColumn get platform => text()();

  /// The platform's opaque change anchor: Health Connect's
  /// `getChangesToken` token, or HealthKit's anchor UUID / last-read
  /// instant as a string. Null before the first successful read; clearing
  /// it signals "no anchor — do a full time-range read" (the
  /// `ChangesTokenExpiredException` fallback of issue #186).
  TextColumn get anchor => text().nullable()();

  /// The UTC instant this anchor was last persisted at.
  DateTimeColumn get lastSyncedAt =>
      dateTime().named('last_synced_at').nullable()();

  @override
  Set<Column> get primaryKey => {platform};
}

/// The device-local health-store export ledger (Issue #936): one row per
/// health-store sample this device actually wrote, so a tombstone or an
/// edit made in a later app session can still reconcile the sample away.
/// **Deliberately never synced to the server** — exactly
/// [HealthSyncState]'s rationale: what this device exported to its own
/// health store is per-device state, not account state. It is not a member
/// of the remote `SyncTable` set, so `sync_push`/`remote_rows.dart`/
/// `row_codec.dart` cannot see it, and the account export never reads it.
///
/// Ids and provenance only ([recordId]/[sourceRowId]/[kind]/[localDate]) —
/// no flow level, tag, note, or measurement ever reaches this table.
/// Rows are removed once their record is deleted from the store, and
/// cleared per profile on profile/account deletion or outright on unbind.
@DataClassName('HealthExportLedgerRowData')
class HealthExportLedger extends Table {
  /// The platform external id this device wrote (Health Connect
  /// `clientRecordId` / HealthKit `HKMetadataKeyExternalUUID`); the key.
  TextColumn get recordId => text().named('record_id')();

  /// The bound profile this export belonged to.
  TextColumn get profileId => text().named('profile_id')();

  /// The source day-entry or observation id the record was derived from
  /// (one record id can embed it, but this preserves the grouping key the
  /// deletion paths diff against).
  TextColumn get sourceRowId => text().named('source_row_id')();

  /// `entry` | `spotting` | `bbt` — mirrors
  /// `domain.HealthExportLedgerKind`.
  TextColumn get kind => text()();

  /// ISO calendar date `yyyy-MM-dd` the export was for (provenance only).
  TextColumn get localDate => text().named('local_date')();

  /// The UTC instant the record was exported.
  DateTimeColumn get exportedAt => dateTime().named('exported_at')();

  @override
  Set<Column> get primaryKey => {recordId};
}
