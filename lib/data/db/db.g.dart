// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'db.dart';

// ignore_for_file: type=lint
class $ProfilesTable extends Profiles with TableInfo<$ProfilesTable, Profile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isMinorMeta = const VerificationMeta(
    'isMinor',
  );
  @override
  late final GeneratedColumn<bool> isMinor = GeneratedColumn<bool>(
    'is_minor',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_minor" IN (0, 1))',
    ),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> archivedAt = GeneratedColumn<DateTime>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _localRevMeta = const VerificationMeta(
    'localRev',
  );
  @override
  late final GeneratedColumn<int> localRev = GeneratedColumn<int>(
    'local_rev',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _birthYearMeta = const VerificationMeta(
    'birthYear',
  );
  @override
  late final GeneratedColumn<int> birthYear = GeneratedColumn<int>(
    'birth_year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _relationshipMeta = const VerificationMeta(
    'relationship',
  );
  @override
  late final GeneratedColumn<String> relationship = GeneratedColumn<String>(
    'relationship',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('standard'),
  );
  static const VerificationMeta _transferredAtMeta = const VerificationMeta(
    'transferredAt',
  );
  @override
  late final GeneratedColumn<DateTime> transferredAt =
      GeneratedColumn<DateTime>(
        'transferred_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _transferredToUserIdMeta =
      const VerificationMeta('transferredToUserId');
  @override
  late final GeneratedColumn<String> transferredToUserId =
      GeneratedColumn<String>(
        'transferred_to_user_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastPeriodStartMeta = const VerificationMeta(
    'lastPeriodStart',
  );
  @override
  late final GeneratedColumn<String> lastPeriodStart = GeneratedColumn<String>(
    'last_period_start',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _typicalCycleLengthDaysMeta =
      const VerificationMeta('typicalCycleLengthDays');
  @override
  late final GeneratedColumn<int> typicalCycleLengthDays = GeneratedColumn<int>(
    'typical_cycle_length_days',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _typicalPeriodLengthDaysMeta =
      const VerificationMeta('typicalPeriodLengthDays');
  @override
  late final GeneratedColumn<int> typicalPeriodLengthDays =
      GeneratedColumn<int>(
        'typical_period_length_days',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _trackingPreferencesMeta =
      const VerificationMeta('trackingPreferences');
  @override
  late final GeneratedColumn<String> trackingPreferences =
      GeneratedColumn<String>(
        'tracking_preferences',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _bbtUnitMeta = const VerificationMeta(
    'bbtUnit',
  );
  @override
  late final GeneratedColumn<String> bbtUnit = GeneratedColumn<String>(
    'bbt_unit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('celsius'),
  );
  static const VerificationMeta _weightUnitMeta = const VerificationMeta(
    'weightUnit',
  );
  @override
  late final GeneratedColumn<String> weightUnit = GeneratedColumn<String>(
    'weight_unit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('kg'),
  );
  static const VerificationMeta _accessRevokedAtMeta = const VerificationMeta(
    'accessRevokedAt',
  );
  @override
  late final GeneratedColumn<DateTime> accessRevokedAt =
      GeneratedColumn<DateTime>(
        'access_revoked_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _unitsUnconfirmedMeta = const VerificationMeta(
    'unitsUnconfirmed',
  );
  @override
  late final GeneratedColumn<bool> unitsUnconfirmed = GeneratedColumn<bool>(
    'units_unconfirmed',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("units_unconfirmed" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    displayName,
    isMinor,
    sortOrder,
    archivedAt,
    createdAt,
    updatedAt,
    deletedAt,
    dirty,
    localRev,
    birthYear,
    relationship,
    mode,
    transferredAt,
    transferredToUserId,
    lastPeriodStart,
    typicalCycleLengthDays,
    typicalPeriodLengthDays,
    trackingPreferences,
    bbtUnit,
    weightUnit,
    accessRevokedAt,
    unitsUnconfirmed,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<Profile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('is_minor')) {
      context.handle(
        _isMinorMeta,
        isMinor.isAcceptableOrUnknown(data['is_minor']!, _isMinorMeta),
      );
    } else if (isInserting) {
      context.missing(_isMinorMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('local_rev')) {
      context.handle(
        _localRevMeta,
        localRev.isAcceptableOrUnknown(data['local_rev']!, _localRevMeta),
      );
    }
    if (data.containsKey('birth_year')) {
      context.handle(
        _birthYearMeta,
        birthYear.isAcceptableOrUnknown(data['birth_year']!, _birthYearMeta),
      );
    }
    if (data.containsKey('relationship')) {
      context.handle(
        _relationshipMeta,
        relationship.isAcceptableOrUnknown(
          data['relationship']!,
          _relationshipMeta,
        ),
      );
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    }
    if (data.containsKey('transferred_at')) {
      context.handle(
        _transferredAtMeta,
        transferredAt.isAcceptableOrUnknown(
          data['transferred_at']!,
          _transferredAtMeta,
        ),
      );
    }
    if (data.containsKey('transferred_to_user_id')) {
      context.handle(
        _transferredToUserIdMeta,
        transferredToUserId.isAcceptableOrUnknown(
          data['transferred_to_user_id']!,
          _transferredToUserIdMeta,
        ),
      );
    }
    if (data.containsKey('last_period_start')) {
      context.handle(
        _lastPeriodStartMeta,
        lastPeriodStart.isAcceptableOrUnknown(
          data['last_period_start']!,
          _lastPeriodStartMeta,
        ),
      );
    }
    if (data.containsKey('typical_cycle_length_days')) {
      context.handle(
        _typicalCycleLengthDaysMeta,
        typicalCycleLengthDays.isAcceptableOrUnknown(
          data['typical_cycle_length_days']!,
          _typicalCycleLengthDaysMeta,
        ),
      );
    }
    if (data.containsKey('typical_period_length_days')) {
      context.handle(
        _typicalPeriodLengthDaysMeta,
        typicalPeriodLengthDays.isAcceptableOrUnknown(
          data['typical_period_length_days']!,
          _typicalPeriodLengthDaysMeta,
        ),
      );
    }
    if (data.containsKey('tracking_preferences')) {
      context.handle(
        _trackingPreferencesMeta,
        trackingPreferences.isAcceptableOrUnknown(
          data['tracking_preferences']!,
          _trackingPreferencesMeta,
        ),
      );
    }
    if (data.containsKey('bbt_unit')) {
      context.handle(
        _bbtUnitMeta,
        bbtUnit.isAcceptableOrUnknown(data['bbt_unit']!, _bbtUnitMeta),
      );
    }
    if (data.containsKey('weight_unit')) {
      context.handle(
        _weightUnitMeta,
        weightUnit.isAcceptableOrUnknown(data['weight_unit']!, _weightUnitMeta),
      );
    }
    if (data.containsKey('access_revoked_at')) {
      context.handle(
        _accessRevokedAtMeta,
        accessRevokedAt.isAcceptableOrUnknown(
          data['access_revoked_at']!,
          _accessRevokedAtMeta,
        ),
      );
    }
    if (data.containsKey('units_unconfirmed')) {
      context.handle(
        _unitsUnconfirmedMeta,
        unitsUnconfirmed.isAcceptableOrUnknown(
          data['units_unconfirmed']!,
          _unitsUnconfirmedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Profile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Profile(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      isMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_minor'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      localRev: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_rev'],
      )!,
      birthYear: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}birth_year'],
      ),
      relationship: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relationship'],
      ),
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      transferredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}transferred_at'],
      ),
      transferredToUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transferred_to_user_id'],
      ),
      lastPeriodStart: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_period_start'],
      ),
      typicalCycleLengthDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}typical_cycle_length_days'],
      ),
      typicalPeriodLengthDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}typical_period_length_days'],
      ),
      trackingPreferences: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tracking_preferences'],
      ),
      bbtUnit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bbt_unit'],
      )!,
      weightUnit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}weight_unit'],
      )!,
      accessRevokedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}access_revoked_at'],
      ),
      unitsUnconfirmed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}units_unconfirmed'],
      ),
    );
  }

  @override
  $ProfilesTable createAlias(String alias) {
    return $ProfilesTable(attachedDatabase, alias);
  }
}

class Profile extends DataClass implements Insertable<Profile> {
  /// Client-generated ULID (stable across devices/sync).
  final String id;
  final String displayName;
  final bool isMinor;
  final int sortOrder;
  final DateTime? archivedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// Device-local: true while this row has a local change not yet pushed.
  /// Set by every local write; cleared by `markPushed` and remote applies.
  final bool dirty;

  /// Device-local revision counter, bumped on every local write and never
  /// synced. `markPushed` clears `dirty` only when it still matches the
  /// value read at push time (KTD4, AE11).
  final int localRev;

  /// Optional birth year of the profile subject (Issue #4 R1). Display and
  /// context only — never gates, forces, or auto-schedules an ownership
  /// transfer (R2).
  final int? birthYear;

  /// Optional closed-set relationship of the subject to the profile creator
  /// (R3), mirrored by [domain.ProfileRelationship]. Stored as the raw
  /// `toDb()` string; an unrecognised value decodes to null rather than
  /// throwing (see `row_codec.dart`).
  final String? relationship;

  /// Care mode (Issue #131, R12), mirrored by [domain.ProfileMode] and the
  /// server's `profiles_mode_check` CHECK (`standard|teen|caregiver|
  /// irregular`). Non-null, defaulting to `standard`; an unrecognised value
  /// decodes to `standard` rather than throwing (see `row_codec.dart`).
  /// Presentation only — never consulted by any authorization path.
  final String mode;

  /// Instant this profile's ownership last moved via
  /// `accept_ownership_transfer`, or null if it never has (R5). Never
  /// client-writable — server-owned, pulled but never pushed (see
  /// `encodeProfile` in `row_codec.dart`).
  final DateTime? transferredAt;

  /// The account that accepted this profile's last ownership transfer, or
  /// null if it never has (Issue #296). Same server-owned, pulled-never-
  /// pushed treatment as [transferredAt]: the health-sync minor gate
  /// requires this to equal the signed-in user id before a transferred
  /// minor profile may bind, and null fails closed.
  final String? transferredToUserId;

  /// Onboarding-collected cycle facts (Issue #218), mirrored by the
  /// server's `profiles` columns added in
  /// `20260909120000_provisional_cycle_facts.sql`. ISO calendar date
  /// `yyyy-MM-dd` of the supplied last-period start, like
  /// `profile_modes.mode_started_on`'s text-date shape. Optional and
  /// editable later from profile settings; feeds the provisional
  /// prediction seed — never a `day_entries` row (a supplied answer is
  /// not an observation).
  final String? lastPeriodStart;

  /// The supplied "typical cycle length" answer in days (Issue #218).
  /// Stored as supplied; `CycleFacts.canSeed` in the prediction domain is
  /// the semantic bound on which values can seed an estimate.
  final int? typicalCycleLengthDays;

  /// The supplied "typical period length" answer in days (Issue #218).
  final int? typicalPeriodLengthDays;

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
  final String? trackingPreferences;

  /// Per-profile BBT display unit (Issue #255), mirrored by
  /// `domain.BbtUnit` and the server's `profiles_bbt_unit_check` CHECK
  /// (`celsius|fahrenheit`). Non-null, defaulting to `celsius`; an
  /// unrecognised value decodes to `celsius` rather than throwing (see
  /// `row_codec.dart`). Presentation only — a stored `observations`
  /// temperature always keeps the unit it was entered/imported in
  /// (`observations.unit`); this decides only how it renders.
  final String bbtUnit;

  /// Per-profile weight display unit (Issue #255), mirrored by
  /// `domain.WeightUnit` and the server's `profiles_weight_unit_check`
  /// CHECK (`kg|lb`). Same contract as [bbtUnit].
  final String weightUnit;

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
  final DateTime? accessRevokedAt;

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
  final bool? unitsUnconfirmed;
  const Profile({
    required this.id,
    required this.displayName,
    required this.isMinor,
    required this.sortOrder,
    this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.dirty,
    required this.localRev,
    this.birthYear,
    this.relationship,
    required this.mode,
    this.transferredAt,
    this.transferredToUserId,
    this.lastPeriodStart,
    this.typicalCycleLengthDays,
    this.typicalPeriodLengthDays,
    this.trackingPreferences,
    required this.bbtUnit,
    required this.weightUnit,
    this.accessRevokedAt,
    this.unitsUnconfirmed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['display_name'] = Variable<String>(displayName);
    map['is_minor'] = Variable<bool>(isMinor);
    map['sort_order'] = Variable<int>(sortOrder);
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['dirty'] = Variable<bool>(dirty);
    map['local_rev'] = Variable<int>(localRev);
    if (!nullToAbsent || birthYear != null) {
      map['birth_year'] = Variable<int>(birthYear);
    }
    if (!nullToAbsent || relationship != null) {
      map['relationship'] = Variable<String>(relationship);
    }
    map['mode'] = Variable<String>(mode);
    if (!nullToAbsent || transferredAt != null) {
      map['transferred_at'] = Variable<DateTime>(transferredAt);
    }
    if (!nullToAbsent || transferredToUserId != null) {
      map['transferred_to_user_id'] = Variable<String>(transferredToUserId);
    }
    if (!nullToAbsent || lastPeriodStart != null) {
      map['last_period_start'] = Variable<String>(lastPeriodStart);
    }
    if (!nullToAbsent || typicalCycleLengthDays != null) {
      map['typical_cycle_length_days'] = Variable<int>(typicalCycleLengthDays);
    }
    if (!nullToAbsent || typicalPeriodLengthDays != null) {
      map['typical_period_length_days'] = Variable<int>(
        typicalPeriodLengthDays,
      );
    }
    if (!nullToAbsent || trackingPreferences != null) {
      map['tracking_preferences'] = Variable<String>(trackingPreferences);
    }
    map['bbt_unit'] = Variable<String>(bbtUnit);
    map['weight_unit'] = Variable<String>(weightUnit);
    if (!nullToAbsent || accessRevokedAt != null) {
      map['access_revoked_at'] = Variable<DateTime>(accessRevokedAt);
    }
    if (!nullToAbsent || unitsUnconfirmed != null) {
      map['units_unconfirmed'] = Variable<bool>(unitsUnconfirmed);
    }
    return map;
  }

  ProfilesCompanion toCompanion(bool nullToAbsent) {
    return ProfilesCompanion(
      id: Value(id),
      displayName: Value(displayName),
      isMinor: Value(isMinor),
      sortOrder: Value(sortOrder),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      dirty: Value(dirty),
      localRev: Value(localRev),
      birthYear: birthYear == null && nullToAbsent
          ? const Value.absent()
          : Value(birthYear),
      relationship: relationship == null && nullToAbsent
          ? const Value.absent()
          : Value(relationship),
      mode: Value(mode),
      transferredAt: transferredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(transferredAt),
      transferredToUserId: transferredToUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(transferredToUserId),
      lastPeriodStart: lastPeriodStart == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPeriodStart),
      typicalCycleLengthDays: typicalCycleLengthDays == null && nullToAbsent
          ? const Value.absent()
          : Value(typicalCycleLengthDays),
      typicalPeriodLengthDays: typicalPeriodLengthDays == null && nullToAbsent
          ? const Value.absent()
          : Value(typicalPeriodLengthDays),
      trackingPreferences: trackingPreferences == null && nullToAbsent
          ? const Value.absent()
          : Value(trackingPreferences),
      bbtUnit: Value(bbtUnit),
      weightUnit: Value(weightUnit),
      accessRevokedAt: accessRevokedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(accessRevokedAt),
      unitsUnconfirmed: unitsUnconfirmed == null && nullToAbsent
          ? const Value.absent()
          : Value(unitsUnconfirmed),
    );
  }

  factory Profile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Profile(
      id: serializer.fromJson<String>(json['id']),
      displayName: serializer.fromJson<String>(json['displayName']),
      isMinor: serializer.fromJson<bool>(json['isMinor']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      localRev: serializer.fromJson<int>(json['localRev']),
      birthYear: serializer.fromJson<int?>(json['birthYear']),
      relationship: serializer.fromJson<String?>(json['relationship']),
      mode: serializer.fromJson<String>(json['mode']),
      transferredAt: serializer.fromJson<DateTime?>(json['transferredAt']),
      transferredToUserId: serializer.fromJson<String?>(
        json['transferredToUserId'],
      ),
      lastPeriodStart: serializer.fromJson<String?>(json['lastPeriodStart']),
      typicalCycleLengthDays: serializer.fromJson<int?>(
        json['typicalCycleLengthDays'],
      ),
      typicalPeriodLengthDays: serializer.fromJson<int?>(
        json['typicalPeriodLengthDays'],
      ),
      trackingPreferences: serializer.fromJson<String?>(
        json['trackingPreferences'],
      ),
      bbtUnit: serializer.fromJson<String>(json['bbtUnit']),
      weightUnit: serializer.fromJson<String>(json['weightUnit']),
      accessRevokedAt: serializer.fromJson<DateTime?>(json['accessRevokedAt']),
      unitsUnconfirmed: serializer.fromJson<bool?>(json['unitsUnconfirmed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'displayName': serializer.toJson<String>(displayName),
      'isMinor': serializer.toJson<bool>(isMinor),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'localRev': serializer.toJson<int>(localRev),
      'birthYear': serializer.toJson<int?>(birthYear),
      'relationship': serializer.toJson<String?>(relationship),
      'mode': serializer.toJson<String>(mode),
      'transferredAt': serializer.toJson<DateTime?>(transferredAt),
      'transferredToUserId': serializer.toJson<String?>(transferredToUserId),
      'lastPeriodStart': serializer.toJson<String?>(lastPeriodStart),
      'typicalCycleLengthDays': serializer.toJson<int?>(typicalCycleLengthDays),
      'typicalPeriodLengthDays': serializer.toJson<int?>(
        typicalPeriodLengthDays,
      ),
      'trackingPreferences': serializer.toJson<String?>(trackingPreferences),
      'bbtUnit': serializer.toJson<String>(bbtUnit),
      'weightUnit': serializer.toJson<String>(weightUnit),
      'accessRevokedAt': serializer.toJson<DateTime?>(accessRevokedAt),
      'unitsUnconfirmed': serializer.toJson<bool?>(unitsUnconfirmed),
    };
  }

  Profile copyWith({
    String? id,
    String? displayName,
    bool? isMinor,
    int? sortOrder,
    Value<DateTime?> archivedAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    bool? dirty,
    int? localRev,
    Value<int?> birthYear = const Value.absent(),
    Value<String?> relationship = const Value.absent(),
    String? mode,
    Value<DateTime?> transferredAt = const Value.absent(),
    Value<String?> transferredToUserId = const Value.absent(),
    Value<String?> lastPeriodStart = const Value.absent(),
    Value<int?> typicalCycleLengthDays = const Value.absent(),
    Value<int?> typicalPeriodLengthDays = const Value.absent(),
    Value<String?> trackingPreferences = const Value.absent(),
    String? bbtUnit,
    String? weightUnit,
    Value<DateTime?> accessRevokedAt = const Value.absent(),
    Value<bool?> unitsUnconfirmed = const Value.absent(),
  }) => Profile(
    id: id ?? this.id,
    displayName: displayName ?? this.displayName,
    isMinor: isMinor ?? this.isMinor,
    sortOrder: sortOrder ?? this.sortOrder,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    dirty: dirty ?? this.dirty,
    localRev: localRev ?? this.localRev,
    birthYear: birthYear.present ? birthYear.value : this.birthYear,
    relationship: relationship.present ? relationship.value : this.relationship,
    mode: mode ?? this.mode,
    transferredAt: transferredAt.present
        ? transferredAt.value
        : this.transferredAt,
    transferredToUserId: transferredToUserId.present
        ? transferredToUserId.value
        : this.transferredToUserId,
    lastPeriodStart: lastPeriodStart.present
        ? lastPeriodStart.value
        : this.lastPeriodStart,
    typicalCycleLengthDays: typicalCycleLengthDays.present
        ? typicalCycleLengthDays.value
        : this.typicalCycleLengthDays,
    typicalPeriodLengthDays: typicalPeriodLengthDays.present
        ? typicalPeriodLengthDays.value
        : this.typicalPeriodLengthDays,
    trackingPreferences: trackingPreferences.present
        ? trackingPreferences.value
        : this.trackingPreferences,
    bbtUnit: bbtUnit ?? this.bbtUnit,
    weightUnit: weightUnit ?? this.weightUnit,
    accessRevokedAt: accessRevokedAt.present
        ? accessRevokedAt.value
        : this.accessRevokedAt,
    unitsUnconfirmed: unitsUnconfirmed.present
        ? unitsUnconfirmed.value
        : this.unitsUnconfirmed,
  );
  Profile copyWithCompanion(ProfilesCompanion data) {
    return Profile(
      id: data.id.present ? data.id.value : this.id,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      isMinor: data.isMinor.present ? data.isMinor.value : this.isMinor,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      localRev: data.localRev.present ? data.localRev.value : this.localRev,
      birthYear: data.birthYear.present ? data.birthYear.value : this.birthYear,
      relationship: data.relationship.present
          ? data.relationship.value
          : this.relationship,
      mode: data.mode.present ? data.mode.value : this.mode,
      transferredAt: data.transferredAt.present
          ? data.transferredAt.value
          : this.transferredAt,
      transferredToUserId: data.transferredToUserId.present
          ? data.transferredToUserId.value
          : this.transferredToUserId,
      lastPeriodStart: data.lastPeriodStart.present
          ? data.lastPeriodStart.value
          : this.lastPeriodStart,
      typicalCycleLengthDays: data.typicalCycleLengthDays.present
          ? data.typicalCycleLengthDays.value
          : this.typicalCycleLengthDays,
      typicalPeriodLengthDays: data.typicalPeriodLengthDays.present
          ? data.typicalPeriodLengthDays.value
          : this.typicalPeriodLengthDays,
      trackingPreferences: data.trackingPreferences.present
          ? data.trackingPreferences.value
          : this.trackingPreferences,
      bbtUnit: data.bbtUnit.present ? data.bbtUnit.value : this.bbtUnit,
      weightUnit: data.weightUnit.present
          ? data.weightUnit.value
          : this.weightUnit,
      accessRevokedAt: data.accessRevokedAt.present
          ? data.accessRevokedAt.value
          : this.accessRevokedAt,
      unitsUnconfirmed: data.unitsUnconfirmed.present
          ? data.unitsUnconfirmed.value
          : this.unitsUnconfirmed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Profile(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('isMinor: $isMinor, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('dirty: $dirty, ')
          ..write('localRev: $localRev, ')
          ..write('birthYear: $birthYear, ')
          ..write('relationship: $relationship, ')
          ..write('mode: $mode, ')
          ..write('transferredAt: $transferredAt, ')
          ..write('transferredToUserId: $transferredToUserId, ')
          ..write('lastPeriodStart: $lastPeriodStart, ')
          ..write('typicalCycleLengthDays: $typicalCycleLengthDays, ')
          ..write('typicalPeriodLengthDays: $typicalPeriodLengthDays, ')
          ..write('trackingPreferences: $trackingPreferences, ')
          ..write('bbtUnit: $bbtUnit, ')
          ..write('weightUnit: $weightUnit, ')
          ..write('accessRevokedAt: $accessRevokedAt, ')
          ..write('unitsUnconfirmed: $unitsUnconfirmed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    displayName,
    isMinor,
    sortOrder,
    archivedAt,
    createdAt,
    updatedAt,
    deletedAt,
    dirty,
    localRev,
    birthYear,
    relationship,
    mode,
    transferredAt,
    transferredToUserId,
    lastPeriodStart,
    typicalCycleLengthDays,
    typicalPeriodLengthDays,
    trackingPreferences,
    bbtUnit,
    weightUnit,
    accessRevokedAt,
    unitsUnconfirmed,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Profile &&
          other.id == this.id &&
          other.displayName == this.displayName &&
          other.isMinor == this.isMinor &&
          other.sortOrder == this.sortOrder &&
          other.archivedAt == this.archivedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.dirty == this.dirty &&
          other.localRev == this.localRev &&
          other.birthYear == this.birthYear &&
          other.relationship == this.relationship &&
          other.mode == this.mode &&
          other.transferredAt == this.transferredAt &&
          other.transferredToUserId == this.transferredToUserId &&
          other.lastPeriodStart == this.lastPeriodStart &&
          other.typicalCycleLengthDays == this.typicalCycleLengthDays &&
          other.typicalPeriodLengthDays == this.typicalPeriodLengthDays &&
          other.trackingPreferences == this.trackingPreferences &&
          other.bbtUnit == this.bbtUnit &&
          other.weightUnit == this.weightUnit &&
          other.accessRevokedAt == this.accessRevokedAt &&
          other.unitsUnconfirmed == this.unitsUnconfirmed);
}

class ProfilesCompanion extends UpdateCompanion<Profile> {
  final Value<String> id;
  final Value<String> displayName;
  final Value<bool> isMinor;
  final Value<int> sortOrder;
  final Value<DateTime?> archivedAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<bool> dirty;
  final Value<int> localRev;
  final Value<int?> birthYear;
  final Value<String?> relationship;
  final Value<String> mode;
  final Value<DateTime?> transferredAt;
  final Value<String?> transferredToUserId;
  final Value<String?> lastPeriodStart;
  final Value<int?> typicalCycleLengthDays;
  final Value<int?> typicalPeriodLengthDays;
  final Value<String?> trackingPreferences;
  final Value<String> bbtUnit;
  final Value<String> weightUnit;
  final Value<DateTime?> accessRevokedAt;
  final Value<bool?> unitsUnconfirmed;
  final Value<int> rowid;
  const ProfilesCompanion({
    this.id = const Value.absent(),
    this.displayName = const Value.absent(),
    this.isMinor = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.localRev = const Value.absent(),
    this.birthYear = const Value.absent(),
    this.relationship = const Value.absent(),
    this.mode = const Value.absent(),
    this.transferredAt = const Value.absent(),
    this.transferredToUserId = const Value.absent(),
    this.lastPeriodStart = const Value.absent(),
    this.typicalCycleLengthDays = const Value.absent(),
    this.typicalPeriodLengthDays = const Value.absent(),
    this.trackingPreferences = const Value.absent(),
    this.bbtUnit = const Value.absent(),
    this.weightUnit = const Value.absent(),
    this.accessRevokedAt = const Value.absent(),
    this.unitsUnconfirmed = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProfilesCompanion.insert({
    required String id,
    required String displayName,
    required bool isMinor,
    this.sortOrder = const Value.absent(),
    this.archivedAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.localRev = const Value.absent(),
    this.birthYear = const Value.absent(),
    this.relationship = const Value.absent(),
    this.mode = const Value.absent(),
    this.transferredAt = const Value.absent(),
    this.transferredToUserId = const Value.absent(),
    this.lastPeriodStart = const Value.absent(),
    this.typicalCycleLengthDays = const Value.absent(),
    this.typicalPeriodLengthDays = const Value.absent(),
    this.trackingPreferences = const Value.absent(),
    this.bbtUnit = const Value.absent(),
    this.weightUnit = const Value.absent(),
    this.accessRevokedAt = const Value.absent(),
    this.unitsUnconfirmed = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       displayName = Value(displayName),
       isMinor = Value(isMinor),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Profile> custom({
    Expression<String>? id,
    Expression<String>? displayName,
    Expression<bool>? isMinor,
    Expression<int>? sortOrder,
    Expression<DateTime>? archivedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<bool>? dirty,
    Expression<int>? localRev,
    Expression<int>? birthYear,
    Expression<String>? relationship,
    Expression<String>? mode,
    Expression<DateTime>? transferredAt,
    Expression<String>? transferredToUserId,
    Expression<String>? lastPeriodStart,
    Expression<int>? typicalCycleLengthDays,
    Expression<int>? typicalPeriodLengthDays,
    Expression<String>? trackingPreferences,
    Expression<String>? bbtUnit,
    Expression<String>? weightUnit,
    Expression<DateTime>? accessRevokedAt,
    Expression<bool>? unitsUnconfirmed,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (displayName != null) 'display_name': displayName,
      if (isMinor != null) 'is_minor': isMinor,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (dirty != null) 'dirty': dirty,
      if (localRev != null) 'local_rev': localRev,
      if (birthYear != null) 'birth_year': birthYear,
      if (relationship != null) 'relationship': relationship,
      if (mode != null) 'mode': mode,
      if (transferredAt != null) 'transferred_at': transferredAt,
      if (transferredToUserId != null)
        'transferred_to_user_id': transferredToUserId,
      if (lastPeriodStart != null) 'last_period_start': lastPeriodStart,
      if (typicalCycleLengthDays != null)
        'typical_cycle_length_days': typicalCycleLengthDays,
      if (typicalPeriodLengthDays != null)
        'typical_period_length_days': typicalPeriodLengthDays,
      if (trackingPreferences != null)
        'tracking_preferences': trackingPreferences,
      if (bbtUnit != null) 'bbt_unit': bbtUnit,
      if (weightUnit != null) 'weight_unit': weightUnit,
      if (accessRevokedAt != null) 'access_revoked_at': accessRevokedAt,
      if (unitsUnconfirmed != null) 'units_unconfirmed': unitsUnconfirmed,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProfilesCompanion copyWith({
    Value<String>? id,
    Value<String>? displayName,
    Value<bool>? isMinor,
    Value<int>? sortOrder,
    Value<DateTime?>? archivedAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<bool>? dirty,
    Value<int>? localRev,
    Value<int?>? birthYear,
    Value<String?>? relationship,
    Value<String>? mode,
    Value<DateTime?>? transferredAt,
    Value<String?>? transferredToUserId,
    Value<String?>? lastPeriodStart,
    Value<int?>? typicalCycleLengthDays,
    Value<int?>? typicalPeriodLengthDays,
    Value<String?>? trackingPreferences,
    Value<String>? bbtUnit,
    Value<String>? weightUnit,
    Value<DateTime?>? accessRevokedAt,
    Value<bool?>? unitsUnconfirmed,
    Value<int>? rowid,
  }) {
    return ProfilesCompanion(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      isMinor: isMinor ?? this.isMinor,
      sortOrder: sortOrder ?? this.sortOrder,
      archivedAt: archivedAt ?? this.archivedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      dirty: dirty ?? this.dirty,
      localRev: localRev ?? this.localRev,
      birthYear: birthYear ?? this.birthYear,
      relationship: relationship ?? this.relationship,
      mode: mode ?? this.mode,
      transferredAt: transferredAt ?? this.transferredAt,
      transferredToUserId: transferredToUserId ?? this.transferredToUserId,
      lastPeriodStart: lastPeriodStart ?? this.lastPeriodStart,
      typicalCycleLengthDays:
          typicalCycleLengthDays ?? this.typicalCycleLengthDays,
      typicalPeriodLengthDays:
          typicalPeriodLengthDays ?? this.typicalPeriodLengthDays,
      trackingPreferences: trackingPreferences ?? this.trackingPreferences,
      bbtUnit: bbtUnit ?? this.bbtUnit,
      weightUnit: weightUnit ?? this.weightUnit,
      accessRevokedAt: accessRevokedAt ?? this.accessRevokedAt,
      unitsUnconfirmed: unitsUnconfirmed ?? this.unitsUnconfirmed,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (isMinor.present) {
      map['is_minor'] = Variable<bool>(isMinor.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (localRev.present) {
      map['local_rev'] = Variable<int>(localRev.value);
    }
    if (birthYear.present) {
      map['birth_year'] = Variable<int>(birthYear.value);
    }
    if (relationship.present) {
      map['relationship'] = Variable<String>(relationship.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (transferredAt.present) {
      map['transferred_at'] = Variable<DateTime>(transferredAt.value);
    }
    if (transferredToUserId.present) {
      map['transferred_to_user_id'] = Variable<String>(
        transferredToUserId.value,
      );
    }
    if (lastPeriodStart.present) {
      map['last_period_start'] = Variable<String>(lastPeriodStart.value);
    }
    if (typicalCycleLengthDays.present) {
      map['typical_cycle_length_days'] = Variable<int>(
        typicalCycleLengthDays.value,
      );
    }
    if (typicalPeriodLengthDays.present) {
      map['typical_period_length_days'] = Variable<int>(
        typicalPeriodLengthDays.value,
      );
    }
    if (trackingPreferences.present) {
      map['tracking_preferences'] = Variable<String>(trackingPreferences.value);
    }
    if (bbtUnit.present) {
      map['bbt_unit'] = Variable<String>(bbtUnit.value);
    }
    if (weightUnit.present) {
      map['weight_unit'] = Variable<String>(weightUnit.value);
    }
    if (accessRevokedAt.present) {
      map['access_revoked_at'] = Variable<DateTime>(accessRevokedAt.value);
    }
    if (unitsUnconfirmed.present) {
      map['units_unconfirmed'] = Variable<bool>(unitsUnconfirmed.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfilesCompanion(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('isMinor: $isMinor, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('dirty: $dirty, ')
          ..write('localRev: $localRev, ')
          ..write('birthYear: $birthYear, ')
          ..write('relationship: $relationship, ')
          ..write('mode: $mode, ')
          ..write('transferredAt: $transferredAt, ')
          ..write('transferredToUserId: $transferredToUserId, ')
          ..write('lastPeriodStart: $lastPeriodStart, ')
          ..write('typicalCycleLengthDays: $typicalCycleLengthDays, ')
          ..write('typicalPeriodLengthDays: $typicalPeriodLengthDays, ')
          ..write('trackingPreferences: $trackingPreferences, ')
          ..write('bbtUnit: $bbtUnit, ')
          ..write('weightUnit: $weightUnit, ')
          ..write('accessRevokedAt: $accessRevokedAt, ')
          ..write('unitsUnconfirmed: $unitsUnconfirmed, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DayEntriesTable extends DayEntries
    with TableInfo<$DayEntriesTable, DayEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DayEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES profiles (id)',
    ),
  );
  static const VerificationMeta _localDateMeta = const VerificationMeta(
    'localDate',
  );
  @override
  late final GeneratedColumn<String> localDate = GeneratedColumn<String>(
    'local_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tzMeta = const VerificationMeta('tz');
  @override
  late final GeneratedColumn<String> tz = GeneratedColumn<String>(
    'tz',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<FlowLevel, String> flow =
      GeneratedColumn<String>(
        'flow',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<FlowLevel>($DayEntriesTable.$converterflow);
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String> tags =
      GeneratedColumn<String>(
        'tags',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      ).withConverter<List<String>>($DayEntriesTable.$convertertags);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pmsMeta = const VerificationMeta('pms');
  @override
  late final GeneratedColumn<bool> pms = GeneratedColumn<bool>(
    'pms',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pms" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _pmsUnconfirmedMeta = const VerificationMeta(
    'pmsUnconfirmed',
  );
  @override
  late final GeneratedColumn<bool> pmsUnconfirmed = GeneratedColumn<bool>(
    'pms_unconfirmed',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pms_unconfirmed" IN (0, 1))',
    ),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _localRevMeta = const VerificationMeta(
    'localRev',
  );
  @override
  late final GeneratedColumn<int> localRev = GeneratedColumn<int>(
    'local_rev',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _loggedByUserIdMeta = const VerificationMeta(
    'loggedByUserId',
  );
  @override
  late final GeneratedColumn<String> loggedByUserId = GeneratedColumn<String>(
    'logged_by_user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastModifiedByUserIdMeta =
      const VerificationMeta('lastModifiedByUserId');
  @override
  late final GeneratedColumn<String> lastModifiedByUserId =
      GeneratedColumn<String>(
        'last_modified_by_user_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('manual'),
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _importIdMeta = const VerificationMeta(
    'importId',
  );
  @override
  late final GeneratedColumn<String> importId = GeneratedColumn<String>(
    'import_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    profileId,
    localDate,
    tz,
    flow,
    tags,
    note,
    pms,
    pmsUnconfirmed,
    updatedAt,
    deletedAt,
    dirty,
    localRev,
    loggedByUserId,
    lastModifiedByUserId,
    source,
    sourceId,
    importId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'day_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<DayEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('local_date')) {
      context.handle(
        _localDateMeta,
        localDate.isAcceptableOrUnknown(data['local_date']!, _localDateMeta),
      );
    } else if (isInserting) {
      context.missing(_localDateMeta);
    }
    if (data.containsKey('tz')) {
      context.handle(_tzMeta, tz.isAcceptableOrUnknown(data['tz']!, _tzMeta));
    } else if (isInserting) {
      context.missing(_tzMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('pms')) {
      context.handle(
        _pmsMeta,
        pms.isAcceptableOrUnknown(data['pms']!, _pmsMeta),
      );
    }
    if (data.containsKey('pms_unconfirmed')) {
      context.handle(
        _pmsUnconfirmedMeta,
        pmsUnconfirmed.isAcceptableOrUnknown(
          data['pms_unconfirmed']!,
          _pmsUnconfirmedMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('local_rev')) {
      context.handle(
        _localRevMeta,
        localRev.isAcceptableOrUnknown(data['local_rev']!, _localRevMeta),
      );
    }
    if (data.containsKey('logged_by_user_id')) {
      context.handle(
        _loggedByUserIdMeta,
        loggedByUserId.isAcceptableOrUnknown(
          data['logged_by_user_id']!,
          _loggedByUserIdMeta,
        ),
      );
    }
    if (data.containsKey('last_modified_by_user_id')) {
      context.handle(
        _lastModifiedByUserIdMeta,
        lastModifiedByUserId.isAcceptableOrUnknown(
          data['last_modified_by_user_id']!,
          _lastModifiedByUserIdMeta,
        ),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    }
    if (data.containsKey('import_id')) {
      context.handle(
        _importIdMeta,
        importId.isAcceptableOrUnknown(data['import_id']!, _importIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DayEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DayEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      localDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_date'],
      )!,
      tz: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tz'],
      )!,
      flow: $DayEntriesTable.$converterflow.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}flow'],
        )!,
      ),
      tags: $DayEntriesTable.$convertertags.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}tags'],
        )!,
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      pms: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pms'],
      )!,
      pmsUnconfirmed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pms_unconfirmed'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      localRev: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_rev'],
      )!,
      loggedByUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}logged_by_user_id'],
      ),
      lastModifiedByUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_modified_by_user_id'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      ),
      importId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}import_id'],
      ),
    );
  }

  @override
  $DayEntriesTable createAlias(String alias) {
    return $DayEntriesTable(attachedDatabase, alias);
  }

  static TypeConverter<FlowLevel, String> $converterflow =
      const FlowLevelConverter();
  static TypeConverter<List<String>, String> $convertertags =
      const TagsConverter();
}

class DayEntry extends DataClass implements Insertable<DayEntry> {
  /// Client-generated ULID (stable across devices/sync).
  final String id;
  final String profileId;

  /// ISO calendar date `yyyy-MM-dd` in the profile's local zone.
  final String localDate;

  /// IANA time zone name the [localDate] was recorded in.
  final String tz;
  final FlowLevel flow;

  /// JSON array of tag codes.
  final List<String> tags;
  final String? note;

  /// First-class PMS marker (Issue #220): the day was premenstrual,
  /// deliberately distinct from the tag taxonomy (a day can be PMS without
  /// also being tagged for every symptom present). Cleared on a tombstone
  /// like every other payload column (the server's
  /// `day_entries_tombstone_pms_check` is the structural backstop); the
  /// `sync_push` update path applies a `v_row ? 'pms'` containment guard so
  /// an old client's payload that omits the key entirely never clears an
  /// already-stored marker. Logged PMS days feed the 6-cycle PMS averages
  /// and the predicted PMS band (`lib/domain/prediction/pms.dart`).
  final bool pms;

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
  final bool? pmsUnconfirmed;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// See [Profiles.dirty].
  final bool dirty;

  /// See [Profiles.localRev].
  final int localRev;

  /// Supabase auth user who created this entry (stamped by server).
  final String? loggedByUserId;

  /// Supabase auth user who last edited this entry (stamped by server).
  final String? lastModifiedByUserId;

  /// Import/device provenance (Issue #159), mirroring `public.day_entries`'
  /// `day_entries_source_check` (`manual`/`clue_import`/`healthkit`/
  /// `health_connect`/`file_import` — a different closed set from
  /// [Observations.source]'s, see `domain.DayEntrySource`'s doc comment).
  /// Never cleared on a tombstone (see `sync_push`'s doc comment in
  /// `supabase/migrations/20260908170000_import_provenance.sql`).
  final String source;

  /// Import/device provenance key, for idempotent re-import; paired with
  /// [source] in the server's partial unique index.
  final String? sourceId;

  /// Placeholder FK to a future `import_jobs(id)` row (Issue #159,
  /// unconstrained server-side until #167 adds that table).
  final String? importId;
  const DayEntry({
    required this.id,
    required this.profileId,
    required this.localDate,
    required this.tz,
    required this.flow,
    required this.tags,
    this.note,
    required this.pms,
    this.pmsUnconfirmed,
    required this.updatedAt,
    this.deletedAt,
    required this.dirty,
    required this.localRev,
    this.loggedByUserId,
    this.lastModifiedByUserId,
    required this.source,
    this.sourceId,
    this.importId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['profile_id'] = Variable<String>(profileId);
    map['local_date'] = Variable<String>(localDate);
    map['tz'] = Variable<String>(tz);
    {
      map['flow'] = Variable<String>(
        $DayEntriesTable.$converterflow.toSql(flow),
      );
    }
    {
      map['tags'] = Variable<String>(
        $DayEntriesTable.$convertertags.toSql(tags),
      );
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['pms'] = Variable<bool>(pms);
    if (!nullToAbsent || pmsUnconfirmed != null) {
      map['pms_unconfirmed'] = Variable<bool>(pmsUnconfirmed);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['dirty'] = Variable<bool>(dirty);
    map['local_rev'] = Variable<int>(localRev);
    if (!nullToAbsent || loggedByUserId != null) {
      map['logged_by_user_id'] = Variable<String>(loggedByUserId);
    }
    if (!nullToAbsent || lastModifiedByUserId != null) {
      map['last_modified_by_user_id'] = Variable<String>(lastModifiedByUserId);
    }
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || sourceId != null) {
      map['source_id'] = Variable<String>(sourceId);
    }
    if (!nullToAbsent || importId != null) {
      map['import_id'] = Variable<String>(importId);
    }
    return map;
  }

  DayEntriesCompanion toCompanion(bool nullToAbsent) {
    return DayEntriesCompanion(
      id: Value(id),
      profileId: Value(profileId),
      localDate: Value(localDate),
      tz: Value(tz),
      flow: Value(flow),
      tags: Value(tags),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      pms: Value(pms),
      pmsUnconfirmed: pmsUnconfirmed == null && nullToAbsent
          ? const Value.absent()
          : Value(pmsUnconfirmed),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      dirty: Value(dirty),
      localRev: Value(localRev),
      loggedByUserId: loggedByUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(loggedByUserId),
      lastModifiedByUserId: lastModifiedByUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastModifiedByUserId),
      source: Value(source),
      sourceId: sourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceId),
      importId: importId == null && nullToAbsent
          ? const Value.absent()
          : Value(importId),
    );
  }

  factory DayEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DayEntry(
      id: serializer.fromJson<String>(json['id']),
      profileId: serializer.fromJson<String>(json['profileId']),
      localDate: serializer.fromJson<String>(json['localDate']),
      tz: serializer.fromJson<String>(json['tz']),
      flow: serializer.fromJson<FlowLevel>(json['flow']),
      tags: serializer.fromJson<List<String>>(json['tags']),
      note: serializer.fromJson<String?>(json['note']),
      pms: serializer.fromJson<bool>(json['pms']),
      pmsUnconfirmed: serializer.fromJson<bool?>(json['pmsUnconfirmed']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      localRev: serializer.fromJson<int>(json['localRev']),
      loggedByUserId: serializer.fromJson<String?>(json['loggedByUserId']),
      lastModifiedByUserId: serializer.fromJson<String?>(
        json['lastModifiedByUserId'],
      ),
      source: serializer.fromJson<String>(json['source']),
      sourceId: serializer.fromJson<String?>(json['sourceId']),
      importId: serializer.fromJson<String?>(json['importId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'profileId': serializer.toJson<String>(profileId),
      'localDate': serializer.toJson<String>(localDate),
      'tz': serializer.toJson<String>(tz),
      'flow': serializer.toJson<FlowLevel>(flow),
      'tags': serializer.toJson<List<String>>(tags),
      'note': serializer.toJson<String?>(note),
      'pms': serializer.toJson<bool>(pms),
      'pmsUnconfirmed': serializer.toJson<bool?>(pmsUnconfirmed),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'localRev': serializer.toJson<int>(localRev),
      'loggedByUserId': serializer.toJson<String?>(loggedByUserId),
      'lastModifiedByUserId': serializer.toJson<String?>(lastModifiedByUserId),
      'source': serializer.toJson<String>(source),
      'sourceId': serializer.toJson<String?>(sourceId),
      'importId': serializer.toJson<String?>(importId),
    };
  }

  DayEntry copyWith({
    String? id,
    String? profileId,
    String? localDate,
    String? tz,
    FlowLevel? flow,
    List<String>? tags,
    Value<String?> note = const Value.absent(),
    bool? pms,
    Value<bool?> pmsUnconfirmed = const Value.absent(),
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    bool? dirty,
    int? localRev,
    Value<String?> loggedByUserId = const Value.absent(),
    Value<String?> lastModifiedByUserId = const Value.absent(),
    String? source,
    Value<String?> sourceId = const Value.absent(),
    Value<String?> importId = const Value.absent(),
  }) => DayEntry(
    id: id ?? this.id,
    profileId: profileId ?? this.profileId,
    localDate: localDate ?? this.localDate,
    tz: tz ?? this.tz,
    flow: flow ?? this.flow,
    tags: tags ?? this.tags,
    note: note.present ? note.value : this.note,
    pms: pms ?? this.pms,
    pmsUnconfirmed: pmsUnconfirmed.present
        ? pmsUnconfirmed.value
        : this.pmsUnconfirmed,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    dirty: dirty ?? this.dirty,
    localRev: localRev ?? this.localRev,
    loggedByUserId: loggedByUserId.present
        ? loggedByUserId.value
        : this.loggedByUserId,
    lastModifiedByUserId: lastModifiedByUserId.present
        ? lastModifiedByUserId.value
        : this.lastModifiedByUserId,
    source: source ?? this.source,
    sourceId: sourceId.present ? sourceId.value : this.sourceId,
    importId: importId.present ? importId.value : this.importId,
  );
  DayEntry copyWithCompanion(DayEntriesCompanion data) {
    return DayEntry(
      id: data.id.present ? data.id.value : this.id,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      localDate: data.localDate.present ? data.localDate.value : this.localDate,
      tz: data.tz.present ? data.tz.value : this.tz,
      flow: data.flow.present ? data.flow.value : this.flow,
      tags: data.tags.present ? data.tags.value : this.tags,
      note: data.note.present ? data.note.value : this.note,
      pms: data.pms.present ? data.pms.value : this.pms,
      pmsUnconfirmed: data.pmsUnconfirmed.present
          ? data.pmsUnconfirmed.value
          : this.pmsUnconfirmed,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      localRev: data.localRev.present ? data.localRev.value : this.localRev,
      loggedByUserId: data.loggedByUserId.present
          ? data.loggedByUserId.value
          : this.loggedByUserId,
      lastModifiedByUserId: data.lastModifiedByUserId.present
          ? data.lastModifiedByUserId.value
          : this.lastModifiedByUserId,
      source: data.source.present ? data.source.value : this.source,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      importId: data.importId.present ? data.importId.value : this.importId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DayEntry(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('localDate: $localDate, ')
          ..write('tz: $tz, ')
          ..write('flow: $flow, ')
          ..write('tags: $tags, ')
          ..write('note: $note, ')
          ..write('pms: $pms, ')
          ..write('pmsUnconfirmed: $pmsUnconfirmed, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('dirty: $dirty, ')
          ..write('localRev: $localRev, ')
          ..write('loggedByUserId: $loggedByUserId, ')
          ..write('lastModifiedByUserId: $lastModifiedByUserId, ')
          ..write('source: $source, ')
          ..write('sourceId: $sourceId, ')
          ..write('importId: $importId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    profileId,
    localDate,
    tz,
    flow,
    tags,
    note,
    pms,
    pmsUnconfirmed,
    updatedAt,
    deletedAt,
    dirty,
    localRev,
    loggedByUserId,
    lastModifiedByUserId,
    source,
    sourceId,
    importId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DayEntry &&
          other.id == this.id &&
          other.profileId == this.profileId &&
          other.localDate == this.localDate &&
          other.tz == this.tz &&
          other.flow == this.flow &&
          other.tags == this.tags &&
          other.note == this.note &&
          other.pms == this.pms &&
          other.pmsUnconfirmed == this.pmsUnconfirmed &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.dirty == this.dirty &&
          other.localRev == this.localRev &&
          other.loggedByUserId == this.loggedByUserId &&
          other.lastModifiedByUserId == this.lastModifiedByUserId &&
          other.source == this.source &&
          other.sourceId == this.sourceId &&
          other.importId == this.importId);
}

class DayEntriesCompanion extends UpdateCompanion<DayEntry> {
  final Value<String> id;
  final Value<String> profileId;
  final Value<String> localDate;
  final Value<String> tz;
  final Value<FlowLevel> flow;
  final Value<List<String>> tags;
  final Value<String?> note;
  final Value<bool> pms;
  final Value<bool?> pmsUnconfirmed;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<bool> dirty;
  final Value<int> localRev;
  final Value<String?> loggedByUserId;
  final Value<String?> lastModifiedByUserId;
  final Value<String> source;
  final Value<String?> sourceId;
  final Value<String?> importId;
  final Value<int> rowid;
  const DayEntriesCompanion({
    this.id = const Value.absent(),
    this.profileId = const Value.absent(),
    this.localDate = const Value.absent(),
    this.tz = const Value.absent(),
    this.flow = const Value.absent(),
    this.tags = const Value.absent(),
    this.note = const Value.absent(),
    this.pms = const Value.absent(),
    this.pmsUnconfirmed = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.localRev = const Value.absent(),
    this.loggedByUserId = const Value.absent(),
    this.lastModifiedByUserId = const Value.absent(),
    this.source = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.importId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DayEntriesCompanion.insert({
    required String id,
    required String profileId,
    required String localDate,
    required String tz,
    required FlowLevel flow,
    this.tags = const Value.absent(),
    this.note = const Value.absent(),
    this.pms = const Value.absent(),
    this.pmsUnconfirmed = const Value.absent(),
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.localRev = const Value.absent(),
    this.loggedByUserId = const Value.absent(),
    this.lastModifiedByUserId = const Value.absent(),
    this.source = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.importId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       profileId = Value(profileId),
       localDate = Value(localDate),
       tz = Value(tz),
       flow = Value(flow),
       updatedAt = Value(updatedAt);
  static Insertable<DayEntry> custom({
    Expression<String>? id,
    Expression<String>? profileId,
    Expression<String>? localDate,
    Expression<String>? tz,
    Expression<String>? flow,
    Expression<String>? tags,
    Expression<String>? note,
    Expression<bool>? pms,
    Expression<bool>? pmsUnconfirmed,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<bool>? dirty,
    Expression<int>? localRev,
    Expression<String>? loggedByUserId,
    Expression<String>? lastModifiedByUserId,
    Expression<String>? source,
    Expression<String>? sourceId,
    Expression<String>? importId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (profileId != null) 'profile_id': profileId,
      if (localDate != null) 'local_date': localDate,
      if (tz != null) 'tz': tz,
      if (flow != null) 'flow': flow,
      if (tags != null) 'tags': tags,
      if (note != null) 'note': note,
      if (pms != null) 'pms': pms,
      if (pmsUnconfirmed != null) 'pms_unconfirmed': pmsUnconfirmed,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (dirty != null) 'dirty': dirty,
      if (localRev != null) 'local_rev': localRev,
      if (loggedByUserId != null) 'logged_by_user_id': loggedByUserId,
      if (lastModifiedByUserId != null)
        'last_modified_by_user_id': lastModifiedByUserId,
      if (source != null) 'source': source,
      if (sourceId != null) 'source_id': sourceId,
      if (importId != null) 'import_id': importId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DayEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? profileId,
    Value<String>? localDate,
    Value<String>? tz,
    Value<FlowLevel>? flow,
    Value<List<String>>? tags,
    Value<String?>? note,
    Value<bool>? pms,
    Value<bool?>? pmsUnconfirmed,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<bool>? dirty,
    Value<int>? localRev,
    Value<String?>? loggedByUserId,
    Value<String?>? lastModifiedByUserId,
    Value<String>? source,
    Value<String?>? sourceId,
    Value<String?>? importId,
    Value<int>? rowid,
  }) {
    return DayEntriesCompanion(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      localDate: localDate ?? this.localDate,
      tz: tz ?? this.tz,
      flow: flow ?? this.flow,
      tags: tags ?? this.tags,
      note: note ?? this.note,
      pms: pms ?? this.pms,
      pmsUnconfirmed: pmsUnconfirmed ?? this.pmsUnconfirmed,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      dirty: dirty ?? this.dirty,
      localRev: localRev ?? this.localRev,
      loggedByUserId: loggedByUserId ?? this.loggedByUserId,
      lastModifiedByUserId: lastModifiedByUserId ?? this.lastModifiedByUserId,
      source: source ?? this.source,
      sourceId: sourceId ?? this.sourceId,
      importId: importId ?? this.importId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (localDate.present) {
      map['local_date'] = Variable<String>(localDate.value);
    }
    if (tz.present) {
      map['tz'] = Variable<String>(tz.value);
    }
    if (flow.present) {
      map['flow'] = Variable<String>(
        $DayEntriesTable.$converterflow.toSql(flow.value),
      );
    }
    if (tags.present) {
      map['tags'] = Variable<String>(
        $DayEntriesTable.$convertertags.toSql(tags.value),
      );
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (pms.present) {
      map['pms'] = Variable<bool>(pms.value);
    }
    if (pmsUnconfirmed.present) {
      map['pms_unconfirmed'] = Variable<bool>(pmsUnconfirmed.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (localRev.present) {
      map['local_rev'] = Variable<int>(localRev.value);
    }
    if (loggedByUserId.present) {
      map['logged_by_user_id'] = Variable<String>(loggedByUserId.value);
    }
    if (lastModifiedByUserId.present) {
      map['last_modified_by_user_id'] = Variable<String>(
        lastModifiedByUserId.value,
      );
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (importId.present) {
      map['import_id'] = Variable<String>(importId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DayEntriesCompanion(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('localDate: $localDate, ')
          ..write('tz: $tz, ')
          ..write('flow: $flow, ')
          ..write('tags: $tags, ')
          ..write('note: $note, ')
          ..write('pms: $pms, ')
          ..write('pmsUnconfirmed: $pmsUnconfirmed, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('dirty: $dirty, ')
          ..write('localRev: $localRev, ')
          ..write('loggedByUserId: $loggedByUserId, ')
          ..write('lastModifiedByUserId: $lastModifiedByUserId, ')
          ..write('source: $source, ')
          ..write('sourceId: $sourceId, ')
          ..write('importId: $importId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProfileGuardiansTable extends ProfileGuardians
    with TableInfo<$ProfileGuardiansTable, ProfileGuardianData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfileGuardiansTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES profiles (id)',
    ),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('accepted'),
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _invitedByMeta = const VerificationMeta(
    'invitedBy',
  );
  @override
  late final GeneratedColumn<String> invitedBy = GeneratedColumn<String>(
    'invited_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    profileId,
    userId,
    role,
    status,
    displayName,
    invitedBy,
    createdAt,
    updatedAt,
    serverVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profile_guardians';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProfileGuardianData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    }
    if (data.containsKey('invited_by')) {
      context.handle(
        _invitedByMeta,
        invitedBy.isAcceptableOrUnknown(data['invited_by']!, _invitedByMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProfileGuardianData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProfileGuardianData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      ),
      invitedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}invited_by'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      )!,
    );
  }

  @override
  $ProfileGuardiansTable createAlias(String alias) {
    return $ProfileGuardiansTable(attachedDatabase, alias);
  }
}

class ProfileGuardianData extends DataClass
    implements Insertable<ProfileGuardianData> {
  final String id;
  final String profileId;
  final String userId;

  /// 'primary_guardian' | 'co_parent' | 'caregiver' | 'viewer'
  final String role;

  /// 'pending' | 'accepted' | 'revoked'
  final String status;
  final String? displayName;
  final String? invitedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

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
  final int serverVersion;
  const ProfileGuardianData({
    required this.id,
    required this.profileId,
    required this.userId,
    required this.role,
    required this.status,
    this.displayName,
    this.invitedBy,
    required this.createdAt,
    required this.updatedAt,
    required this.serverVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['profile_id'] = Variable<String>(profileId);
    map['user_id'] = Variable<String>(userId);
    map['role'] = Variable<String>(role);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    if (!nullToAbsent || invitedBy != null) {
      map['invited_by'] = Variable<String>(invitedBy);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['server_version'] = Variable<int>(serverVersion);
    return map;
  }

  ProfileGuardiansCompanion toCompanion(bool nullToAbsent) {
    return ProfileGuardiansCompanion(
      id: Value(id),
      profileId: Value(profileId),
      userId: Value(userId),
      role: Value(role),
      status: Value(status),
      displayName: displayName == null && nullToAbsent
          ? const Value.absent()
          : Value(displayName),
      invitedBy: invitedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(invitedBy),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      serverVersion: Value(serverVersion),
    );
  }

  factory ProfileGuardianData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProfileGuardianData(
      id: serializer.fromJson<String>(json['id']),
      profileId: serializer.fromJson<String>(json['profileId']),
      userId: serializer.fromJson<String>(json['userId']),
      role: serializer.fromJson<String>(json['role']),
      status: serializer.fromJson<String>(json['status']),
      displayName: serializer.fromJson<String?>(json['displayName']),
      invitedBy: serializer.fromJson<String?>(json['invitedBy']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      serverVersion: serializer.fromJson<int>(json['serverVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'profileId': serializer.toJson<String>(profileId),
      'userId': serializer.toJson<String>(userId),
      'role': serializer.toJson<String>(role),
      'status': serializer.toJson<String>(status),
      'displayName': serializer.toJson<String?>(displayName),
      'invitedBy': serializer.toJson<String?>(invitedBy),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'serverVersion': serializer.toJson<int>(serverVersion),
    };
  }

  ProfileGuardianData copyWith({
    String? id,
    String? profileId,
    String? userId,
    String? role,
    String? status,
    Value<String?> displayName = const Value.absent(),
    Value<String?> invitedBy = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    int? serverVersion,
  }) => ProfileGuardianData(
    id: id ?? this.id,
    profileId: profileId ?? this.profileId,
    userId: userId ?? this.userId,
    role: role ?? this.role,
    status: status ?? this.status,
    displayName: displayName.present ? displayName.value : this.displayName,
    invitedBy: invitedBy.present ? invitedBy.value : this.invitedBy,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    serverVersion: serverVersion ?? this.serverVersion,
  );
  ProfileGuardianData copyWithCompanion(ProfileGuardiansCompanion data) {
    return ProfileGuardianData(
      id: data.id.present ? data.id.value : this.id,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      userId: data.userId.present ? data.userId.value : this.userId,
      role: data.role.present ? data.role.value : this.role,
      status: data.status.present ? data.status.value : this.status,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      invitedBy: data.invitedBy.present ? data.invitedBy.value : this.invitedBy,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProfileGuardianData(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('userId: $userId, ')
          ..write('role: $role, ')
          ..write('status: $status, ')
          ..write('displayName: $displayName, ')
          ..write('invitedBy: $invitedBy, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('serverVersion: $serverVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    profileId,
    userId,
    role,
    status,
    displayName,
    invitedBy,
    createdAt,
    updatedAt,
    serverVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProfileGuardianData &&
          other.id == this.id &&
          other.profileId == this.profileId &&
          other.userId == this.userId &&
          other.role == this.role &&
          other.status == this.status &&
          other.displayName == this.displayName &&
          other.invitedBy == this.invitedBy &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.serverVersion == this.serverVersion);
}

class ProfileGuardiansCompanion extends UpdateCompanion<ProfileGuardianData> {
  final Value<String> id;
  final Value<String> profileId;
  final Value<String> userId;
  final Value<String> role;
  final Value<String> status;
  final Value<String?> displayName;
  final Value<String?> invitedBy;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> serverVersion;
  final Value<int> rowid;
  const ProfileGuardiansCompanion({
    this.id = const Value.absent(),
    this.profileId = const Value.absent(),
    this.userId = const Value.absent(),
    this.role = const Value.absent(),
    this.status = const Value.absent(),
    this.displayName = const Value.absent(),
    this.invitedBy = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProfileGuardiansCompanion.insert({
    required String id,
    required String profileId,
    required String userId,
    required String role,
    this.status = const Value.absent(),
    this.displayName = const Value.absent(),
    this.invitedBy = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       profileId = Value(profileId),
       userId = Value(userId),
       role = Value(role),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ProfileGuardianData> custom({
    Expression<String>? id,
    Expression<String>? profileId,
    Expression<String>? userId,
    Expression<String>? role,
    Expression<String>? status,
    Expression<String>? displayName,
    Expression<String>? invitedBy,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? serverVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (profileId != null) 'profile_id': profileId,
      if (userId != null) 'user_id': userId,
      if (role != null) 'role': role,
      if (status != null) 'status': status,
      if (displayName != null) 'display_name': displayName,
      if (invitedBy != null) 'invited_by': invitedBy,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (serverVersion != null) 'server_version': serverVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProfileGuardiansCompanion copyWith({
    Value<String>? id,
    Value<String>? profileId,
    Value<String>? userId,
    Value<String>? role,
    Value<String>? status,
    Value<String?>? displayName,
    Value<String?>? invitedBy,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? serverVersion,
    Value<int>? rowid,
  }) {
    return ProfileGuardiansCompanion(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      status: status ?? this.status,
      displayName: displayName ?? this.displayName,
      invitedBy: invitedBy ?? this.invitedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      serverVersion: serverVersion ?? this.serverVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (invitedBy.present) {
      map['invited_by'] = Variable<String>(invitedBy.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfileGuardiansCompanion(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('userId: $userId, ')
          ..write('role: $role, ')
          ..write('status: $status, ')
          ..write('displayName: $displayName, ')
          ..write('invitedBy: $invitedBy, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ObservationsTable extends Observations
    with TableInfo<$ObservationsTable, Observation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ObservationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dayEntryIdMeta = const VerificationMeta(
    'dayEntryId',
  );
  @override
  late final GeneratedColumn<String> dayEntryId = GeneratedColumn<String>(
    'day_entry_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES day_entries (id)',
    ),
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES profiles (id)',
    ),
  );
  static const VerificationMeta _localDateMeta = const VerificationMeta(
    'localDate',
  );
  @override
  late final GeneratedColumn<String> localDate = GeneratedColumn<String>(
    'local_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _observedAtMeta = const VerificationMeta(
    'observedAt',
  );
  @override
  late final GeneratedColumn<DateTime> observedAt = GeneratedColumn<DateTime>(
    'observed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tzMeta = const VerificationMeta('tz');
  @override
  late final GeneratedColumn<String> tz = GeneratedColumn<String>(
    'tz',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _valueNumMeta = const VerificationMeta(
    'valueNum',
  );
  @override
  late final GeneratedColumn<double> valueNum = GeneratedColumn<double>(
    'value_num',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _valueTextMeta = const VerificationMeta(
    'valueText',
  );
  @override
  late final GeneratedColumn<String> valueText = GeneratedColumn<String>(
    'value_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _intensityMeta = const VerificationMeta(
    'intensity',
  );
  @override
  late final GeneratedColumn<int> intensity = GeneratedColumn<int>(
    'intensity',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _excludedMeta = const VerificationMeta(
    'excluded',
  );
  @override
  late final GeneratedColumn<bool> excluded = GeneratedColumn<bool>(
    'excluded',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("excluded" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('manual'),
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _importIdMeta = const VerificationMeta(
    'importId',
  );
  @override
  late final GeneratedColumn<String> importId = GeneratedColumn<String>(
    'import_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _exportedToPlatformAtMeta =
      const VerificationMeta('exportedToPlatformAt');
  @override
  late final GeneratedColumn<DateTime> exportedToPlatformAt =
      GeneratedColumn<DateTime>(
        'exported_to_platform_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _rawMeta = const VerificationMeta('raw');
  @override
  late final GeneratedColumn<String> raw = GeneratedColumn<String>(
    'raw',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _localRevMeta = const VerificationMeta(
    'localRev',
  );
  @override
  late final GeneratedColumn<int> localRev = GeneratedColumn<int>(
    'local_rev',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _loggedByUserIdMeta = const VerificationMeta(
    'loggedByUserId',
  );
  @override
  late final GeneratedColumn<String> loggedByUserId = GeneratedColumn<String>(
    'logged_by_user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastModifiedByUserIdMeta =
      const VerificationMeta('lastModifiedByUserId');
  @override
  late final GeneratedColumn<String> lastModifiedByUserId =
      GeneratedColumn<String>(
        'last_modified_by_user_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    dayEntryId,
    profileId,
    localDate,
    observedAt,
    tz,
    category,
    code,
    valueNum,
    valueText,
    unit,
    intensity,
    excluded,
    source,
    sourceId,
    importId,
    exportedToPlatformAt,
    raw,
    updatedAt,
    deletedAt,
    dirty,
    localRev,
    loggedByUserId,
    lastModifiedByUserId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'observations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Observation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('day_entry_id')) {
      context.handle(
        _dayEntryIdMeta,
        dayEntryId.isAcceptableOrUnknown(
          data['day_entry_id']!,
          _dayEntryIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dayEntryIdMeta);
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('local_date')) {
      context.handle(
        _localDateMeta,
        localDate.isAcceptableOrUnknown(data['local_date']!, _localDateMeta),
      );
    } else if (isInserting) {
      context.missing(_localDateMeta);
    }
    if (data.containsKey('observed_at')) {
      context.handle(
        _observedAtMeta,
        observedAt.isAcceptableOrUnknown(data['observed_at']!, _observedAtMeta),
      );
    }
    if (data.containsKey('tz')) {
      context.handle(_tzMeta, tz.isAcceptableOrUnknown(data['tz']!, _tzMeta));
    } else if (isInserting) {
      context.missing(_tzMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    }
    if (data.containsKey('value_num')) {
      context.handle(
        _valueNumMeta,
        valueNum.isAcceptableOrUnknown(data['value_num']!, _valueNumMeta),
      );
    }
    if (data.containsKey('value_text')) {
      context.handle(
        _valueTextMeta,
        valueText.isAcceptableOrUnknown(data['value_text']!, _valueTextMeta),
      );
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    }
    if (data.containsKey('intensity')) {
      context.handle(
        _intensityMeta,
        intensity.isAcceptableOrUnknown(data['intensity']!, _intensityMeta),
      );
    }
    if (data.containsKey('excluded')) {
      context.handle(
        _excludedMeta,
        excluded.isAcceptableOrUnknown(data['excluded']!, _excludedMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    }
    if (data.containsKey('import_id')) {
      context.handle(
        _importIdMeta,
        importId.isAcceptableOrUnknown(data['import_id']!, _importIdMeta),
      );
    }
    if (data.containsKey('exported_to_platform_at')) {
      context.handle(
        _exportedToPlatformAtMeta,
        exportedToPlatformAt.isAcceptableOrUnknown(
          data['exported_to_platform_at']!,
          _exportedToPlatformAtMeta,
        ),
      );
    }
    if (data.containsKey('raw')) {
      context.handle(
        _rawMeta,
        raw.isAcceptableOrUnknown(data['raw']!, _rawMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('local_rev')) {
      context.handle(
        _localRevMeta,
        localRev.isAcceptableOrUnknown(data['local_rev']!, _localRevMeta),
      );
    }
    if (data.containsKey('logged_by_user_id')) {
      context.handle(
        _loggedByUserIdMeta,
        loggedByUserId.isAcceptableOrUnknown(
          data['logged_by_user_id']!,
          _loggedByUserIdMeta,
        ),
      );
    }
    if (data.containsKey('last_modified_by_user_id')) {
      context.handle(
        _lastModifiedByUserIdMeta,
        lastModifiedByUserId.isAcceptableOrUnknown(
          data['last_modified_by_user_id']!,
          _lastModifiedByUserIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Observation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Observation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      dayEntryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day_entry_id'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      localDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_date'],
      )!,
      observedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}observed_at'],
      ),
      tz: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tz'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      ),
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      ),
      valueNum: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}value_num'],
      ),
      valueText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_text'],
      ),
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      ),
      intensity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}intensity'],
      ),
      excluded: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}excluded'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      ),
      importId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}import_id'],
      ),
      exportedToPlatformAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}exported_to_platform_at'],
      ),
      raw: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      localRev: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_rev'],
      )!,
      loggedByUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}logged_by_user_id'],
      ),
      lastModifiedByUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_modified_by_user_id'],
      ),
    );
  }

  @override
  $ObservationsTable createAlias(String alias) {
    return $ObservationsTable(attachedDatabase, alias);
  }
}

class Observation extends DataClass implements Insertable<Observation> {
  /// Client-generated ULID (stable across devices/sync).
  final String id;

  /// The day entry this observation is attached to; cascades with its
  /// tombstone. Immutable once set (enforced server-side by `sync_push`).
  final String dayEntryId;

  /// Denormalized for query and parity with the server's RLS predicates
  /// (matches `day_entries.profile_id`).
  final String profileId;

  /// ISO calendar date `yyyy-MM-dd` in the profile's local zone.
  final String localDate;

  /// Optional exact time-of-day; unused by the Clue importer (A1-40).
  final DateTime? observedAt;

  /// IANA time zone name the entry was logged in.
  final String tz;

  /// e.g. `pain`, `energy`, `bbt`. Free text, never a closed set. Nullable
  /// (review finding: no longer required on a tombstone -- see
  /// `supabase/migrations/20260908160000_observations.sql`'s
  /// `observations_category_required_unless_tombstoned_check`); still
  /// required on every live row, enforced in the storage layer (see
  /// `LunarLogStorage.upsertObservation`'s `_validateObservation` call and
  /// `softDeleteObservation`, which clears it alongside every other
  /// payload column).
  final String? category;

  /// The selected option within [category] (e.g. `migraine`); nullable
  /// only for a purely-numeric category. Free text, never a closed set.
  final String? code;
  final double? valueNum;
  final String? valueText;

  /// `celsius` / `fahrenheit` / `kg` / `lb`.
  final String? unit;

  /// 1-5; nullable for legacy/ungraded rows.
  final int? intensity;

  /// BBT's per-point exclusion flag (A1-44).
  final bool excluded;

  /// `manual` / `apple_health` / `health_connect` / `wearable` / `clue_import`.
  final String source;

  /// Import/device provenance key, for idempotent re-import.
  final String? sourceId;

  /// Placeholder FK to a future `import_jobs(id)` row (Issue #159,
  /// unconstrained server-side until #167 adds that table).
  final String? importId;

  /// Issue #186 (sync mechanics): the UTC instant this row's content was
  /// last written to a health platform (HealthKit/Health Connect), so a
  /// round-trip write is detectable when the same row comes back through a
  /// future import (#217/#228). Client-stamped at export time and synced
  /// like any other observations column (the migration applies the
  /// established `v_row ? 'key'` containment guard so an old client's
  /// payload never clears an already-stored value). Null until the export
  /// flow writes it — inert until #217/#228 own that flow.
  final DateTime? exportedToPlatformAt;

  /// Escape hatch for an unrecognised type/value shape (A1-45); the entire
  /// original datapoint as JSON text.
  final String? raw;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// See [Profiles.dirty].
  final bool dirty;

  /// See [Profiles.localRev].
  final int localRev;

  /// Supabase auth user who created this observation (stamped by server).
  final String? loggedByUserId;

  /// Supabase auth user who last edited this observation (stamped by server).
  final String? lastModifiedByUserId;
  const Observation({
    required this.id,
    required this.dayEntryId,
    required this.profileId,
    required this.localDate,
    this.observedAt,
    required this.tz,
    this.category,
    this.code,
    this.valueNum,
    this.valueText,
    this.unit,
    this.intensity,
    required this.excluded,
    required this.source,
    this.sourceId,
    this.importId,
    this.exportedToPlatformAt,
    this.raw,
    required this.updatedAt,
    this.deletedAt,
    required this.dirty,
    required this.localRev,
    this.loggedByUserId,
    this.lastModifiedByUserId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['day_entry_id'] = Variable<String>(dayEntryId);
    map['profile_id'] = Variable<String>(profileId);
    map['local_date'] = Variable<String>(localDate);
    if (!nullToAbsent || observedAt != null) {
      map['observed_at'] = Variable<DateTime>(observedAt);
    }
    map['tz'] = Variable<String>(tz);
    if (!nullToAbsent || category != null) {
      map['category'] = Variable<String>(category);
    }
    if (!nullToAbsent || code != null) {
      map['code'] = Variable<String>(code);
    }
    if (!nullToAbsent || valueNum != null) {
      map['value_num'] = Variable<double>(valueNum);
    }
    if (!nullToAbsent || valueText != null) {
      map['value_text'] = Variable<String>(valueText);
    }
    if (!nullToAbsent || unit != null) {
      map['unit'] = Variable<String>(unit);
    }
    if (!nullToAbsent || intensity != null) {
      map['intensity'] = Variable<int>(intensity);
    }
    map['excluded'] = Variable<bool>(excluded);
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || sourceId != null) {
      map['source_id'] = Variable<String>(sourceId);
    }
    if (!nullToAbsent || importId != null) {
      map['import_id'] = Variable<String>(importId);
    }
    if (!nullToAbsent || exportedToPlatformAt != null) {
      map['exported_to_platform_at'] = Variable<DateTime>(exportedToPlatformAt);
    }
    if (!nullToAbsent || raw != null) {
      map['raw'] = Variable<String>(raw);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['dirty'] = Variable<bool>(dirty);
    map['local_rev'] = Variable<int>(localRev);
    if (!nullToAbsent || loggedByUserId != null) {
      map['logged_by_user_id'] = Variable<String>(loggedByUserId);
    }
    if (!nullToAbsent || lastModifiedByUserId != null) {
      map['last_modified_by_user_id'] = Variable<String>(lastModifiedByUserId);
    }
    return map;
  }

  ObservationsCompanion toCompanion(bool nullToAbsent) {
    return ObservationsCompanion(
      id: Value(id),
      dayEntryId: Value(dayEntryId),
      profileId: Value(profileId),
      localDate: Value(localDate),
      observedAt: observedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(observedAt),
      tz: Value(tz),
      category: category == null && nullToAbsent
          ? const Value.absent()
          : Value(category),
      code: code == null && nullToAbsent ? const Value.absent() : Value(code),
      valueNum: valueNum == null && nullToAbsent
          ? const Value.absent()
          : Value(valueNum),
      valueText: valueText == null && nullToAbsent
          ? const Value.absent()
          : Value(valueText),
      unit: unit == null && nullToAbsent ? const Value.absent() : Value(unit),
      intensity: intensity == null && nullToAbsent
          ? const Value.absent()
          : Value(intensity),
      excluded: Value(excluded),
      source: Value(source),
      sourceId: sourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceId),
      importId: importId == null && nullToAbsent
          ? const Value.absent()
          : Value(importId),
      exportedToPlatformAt: exportedToPlatformAt == null && nullToAbsent
          ? const Value.absent()
          : Value(exportedToPlatformAt),
      raw: raw == null && nullToAbsent ? const Value.absent() : Value(raw),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      dirty: Value(dirty),
      localRev: Value(localRev),
      loggedByUserId: loggedByUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(loggedByUserId),
      lastModifiedByUserId: lastModifiedByUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastModifiedByUserId),
    );
  }

  factory Observation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Observation(
      id: serializer.fromJson<String>(json['id']),
      dayEntryId: serializer.fromJson<String>(json['dayEntryId']),
      profileId: serializer.fromJson<String>(json['profileId']),
      localDate: serializer.fromJson<String>(json['localDate']),
      observedAt: serializer.fromJson<DateTime?>(json['observedAt']),
      tz: serializer.fromJson<String>(json['tz']),
      category: serializer.fromJson<String?>(json['category']),
      code: serializer.fromJson<String?>(json['code']),
      valueNum: serializer.fromJson<double?>(json['valueNum']),
      valueText: serializer.fromJson<String?>(json['valueText']),
      unit: serializer.fromJson<String?>(json['unit']),
      intensity: serializer.fromJson<int?>(json['intensity']),
      excluded: serializer.fromJson<bool>(json['excluded']),
      source: serializer.fromJson<String>(json['source']),
      sourceId: serializer.fromJson<String?>(json['sourceId']),
      importId: serializer.fromJson<String?>(json['importId']),
      exportedToPlatformAt: serializer.fromJson<DateTime?>(
        json['exportedToPlatformAt'],
      ),
      raw: serializer.fromJson<String?>(json['raw']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      localRev: serializer.fromJson<int>(json['localRev']),
      loggedByUserId: serializer.fromJson<String?>(json['loggedByUserId']),
      lastModifiedByUserId: serializer.fromJson<String?>(
        json['lastModifiedByUserId'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'dayEntryId': serializer.toJson<String>(dayEntryId),
      'profileId': serializer.toJson<String>(profileId),
      'localDate': serializer.toJson<String>(localDate),
      'observedAt': serializer.toJson<DateTime?>(observedAt),
      'tz': serializer.toJson<String>(tz),
      'category': serializer.toJson<String?>(category),
      'code': serializer.toJson<String?>(code),
      'valueNum': serializer.toJson<double?>(valueNum),
      'valueText': serializer.toJson<String?>(valueText),
      'unit': serializer.toJson<String?>(unit),
      'intensity': serializer.toJson<int?>(intensity),
      'excluded': serializer.toJson<bool>(excluded),
      'source': serializer.toJson<String>(source),
      'sourceId': serializer.toJson<String?>(sourceId),
      'importId': serializer.toJson<String?>(importId),
      'exportedToPlatformAt': serializer.toJson<DateTime?>(
        exportedToPlatformAt,
      ),
      'raw': serializer.toJson<String?>(raw),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'localRev': serializer.toJson<int>(localRev),
      'loggedByUserId': serializer.toJson<String?>(loggedByUserId),
      'lastModifiedByUserId': serializer.toJson<String?>(lastModifiedByUserId),
    };
  }

  Observation copyWith({
    String? id,
    String? dayEntryId,
    String? profileId,
    String? localDate,
    Value<DateTime?> observedAt = const Value.absent(),
    String? tz,
    Value<String?> category = const Value.absent(),
    Value<String?> code = const Value.absent(),
    Value<double?> valueNum = const Value.absent(),
    Value<String?> valueText = const Value.absent(),
    Value<String?> unit = const Value.absent(),
    Value<int?> intensity = const Value.absent(),
    bool? excluded,
    String? source,
    Value<String?> sourceId = const Value.absent(),
    Value<String?> importId = const Value.absent(),
    Value<DateTime?> exportedToPlatformAt = const Value.absent(),
    Value<String?> raw = const Value.absent(),
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    bool? dirty,
    int? localRev,
    Value<String?> loggedByUserId = const Value.absent(),
    Value<String?> lastModifiedByUserId = const Value.absent(),
  }) => Observation(
    id: id ?? this.id,
    dayEntryId: dayEntryId ?? this.dayEntryId,
    profileId: profileId ?? this.profileId,
    localDate: localDate ?? this.localDate,
    observedAt: observedAt.present ? observedAt.value : this.observedAt,
    tz: tz ?? this.tz,
    category: category.present ? category.value : this.category,
    code: code.present ? code.value : this.code,
    valueNum: valueNum.present ? valueNum.value : this.valueNum,
    valueText: valueText.present ? valueText.value : this.valueText,
    unit: unit.present ? unit.value : this.unit,
    intensity: intensity.present ? intensity.value : this.intensity,
    excluded: excluded ?? this.excluded,
    source: source ?? this.source,
    sourceId: sourceId.present ? sourceId.value : this.sourceId,
    importId: importId.present ? importId.value : this.importId,
    exportedToPlatformAt: exportedToPlatformAt.present
        ? exportedToPlatformAt.value
        : this.exportedToPlatformAt,
    raw: raw.present ? raw.value : this.raw,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    dirty: dirty ?? this.dirty,
    localRev: localRev ?? this.localRev,
    loggedByUserId: loggedByUserId.present
        ? loggedByUserId.value
        : this.loggedByUserId,
    lastModifiedByUserId: lastModifiedByUserId.present
        ? lastModifiedByUserId.value
        : this.lastModifiedByUserId,
  );
  Observation copyWithCompanion(ObservationsCompanion data) {
    return Observation(
      id: data.id.present ? data.id.value : this.id,
      dayEntryId: data.dayEntryId.present
          ? data.dayEntryId.value
          : this.dayEntryId,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      localDate: data.localDate.present ? data.localDate.value : this.localDate,
      observedAt: data.observedAt.present
          ? data.observedAt.value
          : this.observedAt,
      tz: data.tz.present ? data.tz.value : this.tz,
      category: data.category.present ? data.category.value : this.category,
      code: data.code.present ? data.code.value : this.code,
      valueNum: data.valueNum.present ? data.valueNum.value : this.valueNum,
      valueText: data.valueText.present ? data.valueText.value : this.valueText,
      unit: data.unit.present ? data.unit.value : this.unit,
      intensity: data.intensity.present ? data.intensity.value : this.intensity,
      excluded: data.excluded.present ? data.excluded.value : this.excluded,
      source: data.source.present ? data.source.value : this.source,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      importId: data.importId.present ? data.importId.value : this.importId,
      exportedToPlatformAt: data.exportedToPlatformAt.present
          ? data.exportedToPlatformAt.value
          : this.exportedToPlatformAt,
      raw: data.raw.present ? data.raw.value : this.raw,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      localRev: data.localRev.present ? data.localRev.value : this.localRev,
      loggedByUserId: data.loggedByUserId.present
          ? data.loggedByUserId.value
          : this.loggedByUserId,
      lastModifiedByUserId: data.lastModifiedByUserId.present
          ? data.lastModifiedByUserId.value
          : this.lastModifiedByUserId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Observation(')
          ..write('id: $id, ')
          ..write('dayEntryId: $dayEntryId, ')
          ..write('profileId: $profileId, ')
          ..write('localDate: $localDate, ')
          ..write('observedAt: $observedAt, ')
          ..write('tz: $tz, ')
          ..write('category: $category, ')
          ..write('code: $code, ')
          ..write('valueNum: $valueNum, ')
          ..write('valueText: $valueText, ')
          ..write('unit: $unit, ')
          ..write('intensity: $intensity, ')
          ..write('excluded: $excluded, ')
          ..write('source: $source, ')
          ..write('sourceId: $sourceId, ')
          ..write('importId: $importId, ')
          ..write('exportedToPlatformAt: $exportedToPlatformAt, ')
          ..write('raw: $raw, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('dirty: $dirty, ')
          ..write('localRev: $localRev, ')
          ..write('loggedByUserId: $loggedByUserId, ')
          ..write('lastModifiedByUserId: $lastModifiedByUserId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    dayEntryId,
    profileId,
    localDate,
    observedAt,
    tz,
    category,
    code,
    valueNum,
    valueText,
    unit,
    intensity,
    excluded,
    source,
    sourceId,
    importId,
    exportedToPlatformAt,
    raw,
    updatedAt,
    deletedAt,
    dirty,
    localRev,
    loggedByUserId,
    lastModifiedByUserId,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Observation &&
          other.id == this.id &&
          other.dayEntryId == this.dayEntryId &&
          other.profileId == this.profileId &&
          other.localDate == this.localDate &&
          other.observedAt == this.observedAt &&
          other.tz == this.tz &&
          other.category == this.category &&
          other.code == this.code &&
          other.valueNum == this.valueNum &&
          other.valueText == this.valueText &&
          other.unit == this.unit &&
          other.intensity == this.intensity &&
          other.excluded == this.excluded &&
          other.source == this.source &&
          other.sourceId == this.sourceId &&
          other.importId == this.importId &&
          other.exportedToPlatformAt == this.exportedToPlatformAt &&
          other.raw == this.raw &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.dirty == this.dirty &&
          other.localRev == this.localRev &&
          other.loggedByUserId == this.loggedByUserId &&
          other.lastModifiedByUserId == this.lastModifiedByUserId);
}

class ObservationsCompanion extends UpdateCompanion<Observation> {
  final Value<String> id;
  final Value<String> dayEntryId;
  final Value<String> profileId;
  final Value<String> localDate;
  final Value<DateTime?> observedAt;
  final Value<String> tz;
  final Value<String?> category;
  final Value<String?> code;
  final Value<double?> valueNum;
  final Value<String?> valueText;
  final Value<String?> unit;
  final Value<int?> intensity;
  final Value<bool> excluded;
  final Value<String> source;
  final Value<String?> sourceId;
  final Value<String?> importId;
  final Value<DateTime?> exportedToPlatformAt;
  final Value<String?> raw;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<bool> dirty;
  final Value<int> localRev;
  final Value<String?> loggedByUserId;
  final Value<String?> lastModifiedByUserId;
  final Value<int> rowid;
  const ObservationsCompanion({
    this.id = const Value.absent(),
    this.dayEntryId = const Value.absent(),
    this.profileId = const Value.absent(),
    this.localDate = const Value.absent(),
    this.observedAt = const Value.absent(),
    this.tz = const Value.absent(),
    this.category = const Value.absent(),
    this.code = const Value.absent(),
    this.valueNum = const Value.absent(),
    this.valueText = const Value.absent(),
    this.unit = const Value.absent(),
    this.intensity = const Value.absent(),
    this.excluded = const Value.absent(),
    this.source = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.importId = const Value.absent(),
    this.exportedToPlatformAt = const Value.absent(),
    this.raw = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.localRev = const Value.absent(),
    this.loggedByUserId = const Value.absent(),
    this.lastModifiedByUserId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ObservationsCompanion.insert({
    required String id,
    required String dayEntryId,
    required String profileId,
    required String localDate,
    this.observedAt = const Value.absent(),
    required String tz,
    this.category = const Value.absent(),
    this.code = const Value.absent(),
    this.valueNum = const Value.absent(),
    this.valueText = const Value.absent(),
    this.unit = const Value.absent(),
    this.intensity = const Value.absent(),
    this.excluded = const Value.absent(),
    this.source = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.importId = const Value.absent(),
    this.exportedToPlatformAt = const Value.absent(),
    this.raw = const Value.absent(),
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.localRev = const Value.absent(),
    this.loggedByUserId = const Value.absent(),
    this.lastModifiedByUserId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       dayEntryId = Value(dayEntryId),
       profileId = Value(profileId),
       localDate = Value(localDate),
       tz = Value(tz),
       updatedAt = Value(updatedAt);
  static Insertable<Observation> custom({
    Expression<String>? id,
    Expression<String>? dayEntryId,
    Expression<String>? profileId,
    Expression<String>? localDate,
    Expression<DateTime>? observedAt,
    Expression<String>? tz,
    Expression<String>? category,
    Expression<String>? code,
    Expression<double>? valueNum,
    Expression<String>? valueText,
    Expression<String>? unit,
    Expression<int>? intensity,
    Expression<bool>? excluded,
    Expression<String>? source,
    Expression<String>? sourceId,
    Expression<String>? importId,
    Expression<DateTime>? exportedToPlatformAt,
    Expression<String>? raw,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<bool>? dirty,
    Expression<int>? localRev,
    Expression<String>? loggedByUserId,
    Expression<String>? lastModifiedByUserId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (dayEntryId != null) 'day_entry_id': dayEntryId,
      if (profileId != null) 'profile_id': profileId,
      if (localDate != null) 'local_date': localDate,
      if (observedAt != null) 'observed_at': observedAt,
      if (tz != null) 'tz': tz,
      if (category != null) 'category': category,
      if (code != null) 'code': code,
      if (valueNum != null) 'value_num': valueNum,
      if (valueText != null) 'value_text': valueText,
      if (unit != null) 'unit': unit,
      if (intensity != null) 'intensity': intensity,
      if (excluded != null) 'excluded': excluded,
      if (source != null) 'source': source,
      if (sourceId != null) 'source_id': sourceId,
      if (importId != null) 'import_id': importId,
      if (exportedToPlatformAt != null)
        'exported_to_platform_at': exportedToPlatformAt,
      if (raw != null) 'raw': raw,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (dirty != null) 'dirty': dirty,
      if (localRev != null) 'local_rev': localRev,
      if (loggedByUserId != null) 'logged_by_user_id': loggedByUserId,
      if (lastModifiedByUserId != null)
        'last_modified_by_user_id': lastModifiedByUserId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ObservationsCompanion copyWith({
    Value<String>? id,
    Value<String>? dayEntryId,
    Value<String>? profileId,
    Value<String>? localDate,
    Value<DateTime?>? observedAt,
    Value<String>? tz,
    Value<String?>? category,
    Value<String?>? code,
    Value<double?>? valueNum,
    Value<String?>? valueText,
    Value<String?>? unit,
    Value<int?>? intensity,
    Value<bool>? excluded,
    Value<String>? source,
    Value<String?>? sourceId,
    Value<String?>? importId,
    Value<DateTime?>? exportedToPlatformAt,
    Value<String?>? raw,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<bool>? dirty,
    Value<int>? localRev,
    Value<String?>? loggedByUserId,
    Value<String?>? lastModifiedByUserId,
    Value<int>? rowid,
  }) {
    return ObservationsCompanion(
      id: id ?? this.id,
      dayEntryId: dayEntryId ?? this.dayEntryId,
      profileId: profileId ?? this.profileId,
      localDate: localDate ?? this.localDate,
      observedAt: observedAt ?? this.observedAt,
      tz: tz ?? this.tz,
      category: category ?? this.category,
      code: code ?? this.code,
      valueNum: valueNum ?? this.valueNum,
      valueText: valueText ?? this.valueText,
      unit: unit ?? this.unit,
      intensity: intensity ?? this.intensity,
      excluded: excluded ?? this.excluded,
      source: source ?? this.source,
      sourceId: sourceId ?? this.sourceId,
      importId: importId ?? this.importId,
      exportedToPlatformAt: exportedToPlatformAt ?? this.exportedToPlatformAt,
      raw: raw ?? this.raw,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      dirty: dirty ?? this.dirty,
      localRev: localRev ?? this.localRev,
      loggedByUserId: loggedByUserId ?? this.loggedByUserId,
      lastModifiedByUserId: lastModifiedByUserId ?? this.lastModifiedByUserId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (dayEntryId.present) {
      map['day_entry_id'] = Variable<String>(dayEntryId.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (localDate.present) {
      map['local_date'] = Variable<String>(localDate.value);
    }
    if (observedAt.present) {
      map['observed_at'] = Variable<DateTime>(observedAt.value);
    }
    if (tz.present) {
      map['tz'] = Variable<String>(tz.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (valueNum.present) {
      map['value_num'] = Variable<double>(valueNum.value);
    }
    if (valueText.present) {
      map['value_text'] = Variable<String>(valueText.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (intensity.present) {
      map['intensity'] = Variable<int>(intensity.value);
    }
    if (excluded.present) {
      map['excluded'] = Variable<bool>(excluded.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (importId.present) {
      map['import_id'] = Variable<String>(importId.value);
    }
    if (exportedToPlatformAt.present) {
      map['exported_to_platform_at'] = Variable<DateTime>(
        exportedToPlatformAt.value,
      );
    }
    if (raw.present) {
      map['raw'] = Variable<String>(raw.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (localRev.present) {
      map['local_rev'] = Variable<int>(localRev.value);
    }
    if (loggedByUserId.present) {
      map['logged_by_user_id'] = Variable<String>(loggedByUserId.value);
    }
    if (lastModifiedByUserId.present) {
      map['last_modified_by_user_id'] = Variable<String>(
        lastModifiedByUserId.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ObservationsCompanion(')
          ..write('id: $id, ')
          ..write('dayEntryId: $dayEntryId, ')
          ..write('profileId: $profileId, ')
          ..write('localDate: $localDate, ')
          ..write('observedAt: $observedAt, ')
          ..write('tz: $tz, ')
          ..write('category: $category, ')
          ..write('code: $code, ')
          ..write('valueNum: $valueNum, ')
          ..write('valueText: $valueText, ')
          ..write('unit: $unit, ')
          ..write('intensity: $intensity, ')
          ..write('excluded: $excluded, ')
          ..write('source: $source, ')
          ..write('sourceId: $sourceId, ')
          ..write('importId: $importId, ')
          ..write('exportedToPlatformAt: $exportedToPlatformAt, ')
          ..write('raw: $raw, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('dirty: $dirty, ')
          ..write('localRev: $localRev, ')
          ..write('loggedByUserId: $loggedByUserId, ')
          ..write('lastModifiedByUserId: $lastModifiedByUserId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProfileModesTable extends ProfileModes
    with TableInfo<$ProfileModesTable, ProfileModeData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfileModesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES profiles (id)',
    ),
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('tracking'),
  );
  static const VerificationMeta _modeStartedOnMeta = const VerificationMeta(
    'modeStartedOn',
  );
  @override
  late final GeneratedColumn<String> modeStartedOn = GeneratedColumn<String>(
    'mode_started_on',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _estimatedDueDateMeta = const VerificationMeta(
    'estimatedDueDate',
  );
  @override
  late final GeneratedColumn<String> estimatedDueDate = GeneratedColumn<String>(
    'estimated_due_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _birthControlMethodMeta =
      const VerificationMeta('birthControlMethod');
  @override
  late final GeneratedColumn<String> birthControlMethod =
      GeneratedColumn<String>(
        'birth_control_method',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _birthControlStartedOnMeta =
      const VerificationMeta('birthControlStartedOn');
  @override
  late final GeneratedColumn<String> birthControlStartedOn =
      GeneratedColumn<String>(
        'birth_control_started_on',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _birthControlStoppedOnMeta =
      const VerificationMeta('birthControlStoppedOn');
  @override
  late final GeneratedColumn<String> birthControlStoppedOn =
      GeneratedColumn<String>(
        'birth_control_stopped_on',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _healthSyncConsentMeta = const VerificationMeta(
    'healthSyncConsent',
  );
  @override
  late final GeneratedColumn<bool> healthSyncConsent = GeneratedColumn<bool>(
    'health_sync_consent',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("health_sync_consent" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _localRevMeta = const VerificationMeta(
    'localRev',
  );
  @override
  late final GeneratedColumn<int> localRev = GeneratedColumn<int>(
    'local_rev',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    profileId,
    mode,
    modeStartedOn,
    estimatedDueDate,
    birthControlMethod,
    birthControlStartedOn,
    birthControlStoppedOn,
    healthSyncConsent,
    updatedAt,
    dirty,
    localRev,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profile_modes';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProfileModeData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    }
    if (data.containsKey('mode_started_on')) {
      context.handle(
        _modeStartedOnMeta,
        modeStartedOn.isAcceptableOrUnknown(
          data['mode_started_on']!,
          _modeStartedOnMeta,
        ),
      );
    }
    if (data.containsKey('estimated_due_date')) {
      context.handle(
        _estimatedDueDateMeta,
        estimatedDueDate.isAcceptableOrUnknown(
          data['estimated_due_date']!,
          _estimatedDueDateMeta,
        ),
      );
    }
    if (data.containsKey('birth_control_method')) {
      context.handle(
        _birthControlMethodMeta,
        birthControlMethod.isAcceptableOrUnknown(
          data['birth_control_method']!,
          _birthControlMethodMeta,
        ),
      );
    }
    if (data.containsKey('birth_control_started_on')) {
      context.handle(
        _birthControlStartedOnMeta,
        birthControlStartedOn.isAcceptableOrUnknown(
          data['birth_control_started_on']!,
          _birthControlStartedOnMeta,
        ),
      );
    }
    if (data.containsKey('birth_control_stopped_on')) {
      context.handle(
        _birthControlStoppedOnMeta,
        birthControlStoppedOn.isAcceptableOrUnknown(
          data['birth_control_stopped_on']!,
          _birthControlStoppedOnMeta,
        ),
      );
    }
    if (data.containsKey('health_sync_consent')) {
      context.handle(
        _healthSyncConsentMeta,
        healthSyncConsent.isAcceptableOrUnknown(
          data['health_sync_consent']!,
          _healthSyncConsentMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('local_rev')) {
      context.handle(
        _localRevMeta,
        localRev.isAcceptableOrUnknown(data['local_rev']!, _localRevMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {profileId};
  @override
  ProfileModeData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProfileModeData(
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      modeStartedOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode_started_on'],
      ),
      estimatedDueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}estimated_due_date'],
      ),
      birthControlMethod: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}birth_control_method'],
      ),
      birthControlStartedOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}birth_control_started_on'],
      ),
      birthControlStoppedOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}birth_control_stopped_on'],
      ),
      healthSyncConsent: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}health_sync_consent'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      localRev: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_rev'],
      )!,
    );
  }

  @override
  $ProfileModesTable createAlias(String alias) {
    return $ProfileModesTable(attachedDatabase, alias);
  }
}

class ProfileModeData extends DataClass implements Insertable<ProfileModeData> {
  /// The profile this row belongs to (also the primary key — exactly one
  /// row per profile, enforced by the key itself).
  final String profileId;

  /// Raw `LifecycleMode` `toDb()` string
  /// (`tracking`/`conceive`/`pregnancy`/`perimenopause`/`postpartum`), the
  /// server's `profile_modes_mode_check` set. Not validated here (the
  /// domain enum and the server CHECK are the enforcement points); an
  /// unrecognised value decodes to `tracking` on pull (see `row_codec.dart`).
  final String mode;

  /// ISO calendar date `yyyy-MM-dd` the current mode took effect, or null.
  final String? modeStartedOn;

  /// Estimated due date (Issue #192), as an ISO calendar date
  /// `yyyy-MM-dd` — derived on entry from the last recorded period start
  /// + 280 days (Naegele's rule) or manually supplied when that start is
  /// unknown/imported, stored here (NOT client-local: it must sync) and
  /// consumed by the Pregnancy-mode week counter. Kept on exit rather
  /// than cleared — the mode column says whether a pregnancy is current;
  /// this stays as the record of the one that was (and is overwritten on
  /// any later re-entry).
  final String? estimatedDueDate;

  /// Current birth-control method (free text, #260 owns the vocabulary) or
  /// null when none is recorded.
  final String? birthControlMethod;
  final String? birthControlStartedOn;
  final String? birthControlStoppedOn;

  /// D-29: per-profile opt-in for health-platform writes — a distinct
  /// consent from cycle sharing/guardian consent, recorded server-side.
  final bool healthSyncConsent;
  final DateTime updatedAt;

  /// See [Profiles.dirty]. (No `deleted_at` — this table has no tombstone.)
  final bool dirty;

  /// See [Profiles.localRev].
  final int localRev;
  const ProfileModeData({
    required this.profileId,
    required this.mode,
    this.modeStartedOn,
    this.estimatedDueDate,
    this.birthControlMethod,
    this.birthControlStartedOn,
    this.birthControlStoppedOn,
    required this.healthSyncConsent,
    required this.updatedAt,
    required this.dirty,
    required this.localRev,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['profile_id'] = Variable<String>(profileId);
    map['mode'] = Variable<String>(mode);
    if (!nullToAbsent || modeStartedOn != null) {
      map['mode_started_on'] = Variable<String>(modeStartedOn);
    }
    if (!nullToAbsent || estimatedDueDate != null) {
      map['estimated_due_date'] = Variable<String>(estimatedDueDate);
    }
    if (!nullToAbsent || birthControlMethod != null) {
      map['birth_control_method'] = Variable<String>(birthControlMethod);
    }
    if (!nullToAbsent || birthControlStartedOn != null) {
      map['birth_control_started_on'] = Variable<String>(birthControlStartedOn);
    }
    if (!nullToAbsent || birthControlStoppedOn != null) {
      map['birth_control_stopped_on'] = Variable<String>(birthControlStoppedOn);
    }
    map['health_sync_consent'] = Variable<bool>(healthSyncConsent);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['dirty'] = Variable<bool>(dirty);
    map['local_rev'] = Variable<int>(localRev);
    return map;
  }

  ProfileModesCompanion toCompanion(bool nullToAbsent) {
    return ProfileModesCompanion(
      profileId: Value(profileId),
      mode: Value(mode),
      modeStartedOn: modeStartedOn == null && nullToAbsent
          ? const Value.absent()
          : Value(modeStartedOn),
      estimatedDueDate: estimatedDueDate == null && nullToAbsent
          ? const Value.absent()
          : Value(estimatedDueDate),
      birthControlMethod: birthControlMethod == null && nullToAbsent
          ? const Value.absent()
          : Value(birthControlMethod),
      birthControlStartedOn: birthControlStartedOn == null && nullToAbsent
          ? const Value.absent()
          : Value(birthControlStartedOn),
      birthControlStoppedOn: birthControlStoppedOn == null && nullToAbsent
          ? const Value.absent()
          : Value(birthControlStoppedOn),
      healthSyncConsent: Value(healthSyncConsent),
      updatedAt: Value(updatedAt),
      dirty: Value(dirty),
      localRev: Value(localRev),
    );
  }

  factory ProfileModeData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProfileModeData(
      profileId: serializer.fromJson<String>(json['profileId']),
      mode: serializer.fromJson<String>(json['mode']),
      modeStartedOn: serializer.fromJson<String?>(json['modeStartedOn']),
      estimatedDueDate: serializer.fromJson<String?>(json['estimatedDueDate']),
      birthControlMethod: serializer.fromJson<String?>(
        json['birthControlMethod'],
      ),
      birthControlStartedOn: serializer.fromJson<String?>(
        json['birthControlStartedOn'],
      ),
      birthControlStoppedOn: serializer.fromJson<String?>(
        json['birthControlStoppedOn'],
      ),
      healthSyncConsent: serializer.fromJson<bool>(json['healthSyncConsent']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      localRev: serializer.fromJson<int>(json['localRev']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'profileId': serializer.toJson<String>(profileId),
      'mode': serializer.toJson<String>(mode),
      'modeStartedOn': serializer.toJson<String?>(modeStartedOn),
      'estimatedDueDate': serializer.toJson<String?>(estimatedDueDate),
      'birthControlMethod': serializer.toJson<String?>(birthControlMethod),
      'birthControlStartedOn': serializer.toJson<String?>(
        birthControlStartedOn,
      ),
      'birthControlStoppedOn': serializer.toJson<String?>(
        birthControlStoppedOn,
      ),
      'healthSyncConsent': serializer.toJson<bool>(healthSyncConsent),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'localRev': serializer.toJson<int>(localRev),
    };
  }

  ProfileModeData copyWith({
    String? profileId,
    String? mode,
    Value<String?> modeStartedOn = const Value.absent(),
    Value<String?> estimatedDueDate = const Value.absent(),
    Value<String?> birthControlMethod = const Value.absent(),
    Value<String?> birthControlStartedOn = const Value.absent(),
    Value<String?> birthControlStoppedOn = const Value.absent(),
    bool? healthSyncConsent,
    DateTime? updatedAt,
    bool? dirty,
    int? localRev,
  }) => ProfileModeData(
    profileId: profileId ?? this.profileId,
    mode: mode ?? this.mode,
    modeStartedOn: modeStartedOn.present
        ? modeStartedOn.value
        : this.modeStartedOn,
    estimatedDueDate: estimatedDueDate.present
        ? estimatedDueDate.value
        : this.estimatedDueDate,
    birthControlMethod: birthControlMethod.present
        ? birthControlMethod.value
        : this.birthControlMethod,
    birthControlStartedOn: birthControlStartedOn.present
        ? birthControlStartedOn.value
        : this.birthControlStartedOn,
    birthControlStoppedOn: birthControlStoppedOn.present
        ? birthControlStoppedOn.value
        : this.birthControlStoppedOn,
    healthSyncConsent: healthSyncConsent ?? this.healthSyncConsent,
    updatedAt: updatedAt ?? this.updatedAt,
    dirty: dirty ?? this.dirty,
    localRev: localRev ?? this.localRev,
  );
  ProfileModeData copyWithCompanion(ProfileModesCompanion data) {
    return ProfileModeData(
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      mode: data.mode.present ? data.mode.value : this.mode,
      modeStartedOn: data.modeStartedOn.present
          ? data.modeStartedOn.value
          : this.modeStartedOn,
      estimatedDueDate: data.estimatedDueDate.present
          ? data.estimatedDueDate.value
          : this.estimatedDueDate,
      birthControlMethod: data.birthControlMethod.present
          ? data.birthControlMethod.value
          : this.birthControlMethod,
      birthControlStartedOn: data.birthControlStartedOn.present
          ? data.birthControlStartedOn.value
          : this.birthControlStartedOn,
      birthControlStoppedOn: data.birthControlStoppedOn.present
          ? data.birthControlStoppedOn.value
          : this.birthControlStoppedOn,
      healthSyncConsent: data.healthSyncConsent.present
          ? data.healthSyncConsent.value
          : this.healthSyncConsent,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      localRev: data.localRev.present ? data.localRev.value : this.localRev,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProfileModeData(')
          ..write('profileId: $profileId, ')
          ..write('mode: $mode, ')
          ..write('modeStartedOn: $modeStartedOn, ')
          ..write('estimatedDueDate: $estimatedDueDate, ')
          ..write('birthControlMethod: $birthControlMethod, ')
          ..write('birthControlStartedOn: $birthControlStartedOn, ')
          ..write('birthControlStoppedOn: $birthControlStoppedOn, ')
          ..write('healthSyncConsent: $healthSyncConsent, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('localRev: $localRev')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    profileId,
    mode,
    modeStartedOn,
    estimatedDueDate,
    birthControlMethod,
    birthControlStartedOn,
    birthControlStoppedOn,
    healthSyncConsent,
    updatedAt,
    dirty,
    localRev,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProfileModeData &&
          other.profileId == this.profileId &&
          other.mode == this.mode &&
          other.modeStartedOn == this.modeStartedOn &&
          other.estimatedDueDate == this.estimatedDueDate &&
          other.birthControlMethod == this.birthControlMethod &&
          other.birthControlStartedOn == this.birthControlStartedOn &&
          other.birthControlStoppedOn == this.birthControlStoppedOn &&
          other.healthSyncConsent == this.healthSyncConsent &&
          other.updatedAt == this.updatedAt &&
          other.dirty == this.dirty &&
          other.localRev == this.localRev);
}

class ProfileModesCompanion extends UpdateCompanion<ProfileModeData> {
  final Value<String> profileId;
  final Value<String> mode;
  final Value<String?> modeStartedOn;
  final Value<String?> estimatedDueDate;
  final Value<String?> birthControlMethod;
  final Value<String?> birthControlStartedOn;
  final Value<String?> birthControlStoppedOn;
  final Value<bool> healthSyncConsent;
  final Value<DateTime> updatedAt;
  final Value<bool> dirty;
  final Value<int> localRev;
  final Value<int> rowid;
  const ProfileModesCompanion({
    this.profileId = const Value.absent(),
    this.mode = const Value.absent(),
    this.modeStartedOn = const Value.absent(),
    this.estimatedDueDate = const Value.absent(),
    this.birthControlMethod = const Value.absent(),
    this.birthControlStartedOn = const Value.absent(),
    this.birthControlStoppedOn = const Value.absent(),
    this.healthSyncConsent = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.localRev = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProfileModesCompanion.insert({
    required String profileId,
    this.mode = const Value.absent(),
    this.modeStartedOn = const Value.absent(),
    this.estimatedDueDate = const Value.absent(),
    this.birthControlMethod = const Value.absent(),
    this.birthControlStartedOn = const Value.absent(),
    this.birthControlStoppedOn = const Value.absent(),
    this.healthSyncConsent = const Value.absent(),
    required DateTime updatedAt,
    this.dirty = const Value.absent(),
    this.localRev = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : profileId = Value(profileId),
       updatedAt = Value(updatedAt);
  static Insertable<ProfileModeData> custom({
    Expression<String>? profileId,
    Expression<String>? mode,
    Expression<String>? modeStartedOn,
    Expression<String>? estimatedDueDate,
    Expression<String>? birthControlMethod,
    Expression<String>? birthControlStartedOn,
    Expression<String>? birthControlStoppedOn,
    Expression<bool>? healthSyncConsent,
    Expression<DateTime>? updatedAt,
    Expression<bool>? dirty,
    Expression<int>? localRev,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (profileId != null) 'profile_id': profileId,
      if (mode != null) 'mode': mode,
      if (modeStartedOn != null) 'mode_started_on': modeStartedOn,
      if (estimatedDueDate != null) 'estimated_due_date': estimatedDueDate,
      if (birthControlMethod != null)
        'birth_control_method': birthControlMethod,
      if (birthControlStartedOn != null)
        'birth_control_started_on': birthControlStartedOn,
      if (birthControlStoppedOn != null)
        'birth_control_stopped_on': birthControlStoppedOn,
      if (healthSyncConsent != null) 'health_sync_consent': healthSyncConsent,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (dirty != null) 'dirty': dirty,
      if (localRev != null) 'local_rev': localRev,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProfileModesCompanion copyWith({
    Value<String>? profileId,
    Value<String>? mode,
    Value<String?>? modeStartedOn,
    Value<String?>? estimatedDueDate,
    Value<String?>? birthControlMethod,
    Value<String?>? birthControlStartedOn,
    Value<String?>? birthControlStoppedOn,
    Value<bool>? healthSyncConsent,
    Value<DateTime>? updatedAt,
    Value<bool>? dirty,
    Value<int>? localRev,
    Value<int>? rowid,
  }) {
    return ProfileModesCompanion(
      profileId: profileId ?? this.profileId,
      mode: mode ?? this.mode,
      modeStartedOn: modeStartedOn ?? this.modeStartedOn,
      estimatedDueDate: estimatedDueDate ?? this.estimatedDueDate,
      birthControlMethod: birthControlMethod ?? this.birthControlMethod,
      birthControlStartedOn:
          birthControlStartedOn ?? this.birthControlStartedOn,
      birthControlStoppedOn:
          birthControlStoppedOn ?? this.birthControlStoppedOn,
      healthSyncConsent: healthSyncConsent ?? this.healthSyncConsent,
      updatedAt: updatedAt ?? this.updatedAt,
      dirty: dirty ?? this.dirty,
      localRev: localRev ?? this.localRev,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (modeStartedOn.present) {
      map['mode_started_on'] = Variable<String>(modeStartedOn.value);
    }
    if (estimatedDueDate.present) {
      map['estimated_due_date'] = Variable<String>(estimatedDueDate.value);
    }
    if (birthControlMethod.present) {
      map['birth_control_method'] = Variable<String>(birthControlMethod.value);
    }
    if (birthControlStartedOn.present) {
      map['birth_control_started_on'] = Variable<String>(
        birthControlStartedOn.value,
      );
    }
    if (birthControlStoppedOn.present) {
      map['birth_control_stopped_on'] = Variable<String>(
        birthControlStoppedOn.value,
      );
    }
    if (healthSyncConsent.present) {
      map['health_sync_consent'] = Variable<bool>(healthSyncConsent.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (localRev.present) {
      map['local_rev'] = Variable<int>(localRev.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfileModesCompanion(')
          ..write('profileId: $profileId, ')
          ..write('mode: $mode, ')
          ..write('modeStartedOn: $modeStartedOn, ')
          ..write('estimatedDueDate: $estimatedDueDate, ')
          ..write('birthControlMethod: $birthControlMethod, ')
          ..write('birthControlStartedOn: $birthControlStartedOn, ')
          ..write('birthControlStoppedOn: $birthControlStoppedOn, ')
          ..write('healthSyncConsent: $healthSyncConsent, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('localRev: $localRev, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CycleOverridesTable extends CycleOverrides
    with TableInfo<$CycleOverridesTable, CycleOverrideData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CycleOverridesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES profiles (id)',
    ),
  );
  static const VerificationMeta _cycleStartDateMeta = const VerificationMeta(
    'cycleStartDate',
  );
  @override
  late final GeneratedColumn<String> cycleStartDate = GeneratedColumn<String>(
    'cycle_start_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _excludedFromAverageMeta =
      const VerificationMeta('excludedFromAverage');
  @override
  late final GeneratedColumn<bool> excludedFromAverage = GeneratedColumn<bool>(
    'excluded_from_average',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("excluded_from_average" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _manualStartMeta = const VerificationMeta(
    'manualStart',
  );
  @override
  late final GeneratedColumn<bool> manualStart = GeneratedColumn<bool>(
    'manual_start',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("manual_start" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _localRevMeta = const VerificationMeta(
    'localRev',
  );
  @override
  late final GeneratedColumn<int> localRev = GeneratedColumn<int>(
    'local_rev',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    profileId,
    cycleStartDate,
    excludedFromAverage,
    manualStart,
    noteId,
    updatedAt,
    deletedAt,
    dirty,
    localRev,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cycle_overrides';
  @override
  VerificationContext validateIntegrity(
    Insertable<CycleOverrideData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('cycle_start_date')) {
      context.handle(
        _cycleStartDateMeta,
        cycleStartDate.isAcceptableOrUnknown(
          data['cycle_start_date']!,
          _cycleStartDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cycleStartDateMeta);
    }
    if (data.containsKey('excluded_from_average')) {
      context.handle(
        _excludedFromAverageMeta,
        excludedFromAverage.isAcceptableOrUnknown(
          data['excluded_from_average']!,
          _excludedFromAverageMeta,
        ),
      );
    }
    if (data.containsKey('manual_start')) {
      context.handle(
        _manualStartMeta,
        manualStart.isAcceptableOrUnknown(
          data['manual_start']!,
          _manualStartMeta,
        ),
      );
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('local_rev')) {
      context.handle(
        _localRevMeta,
        localRev.isAcceptableOrUnknown(data['local_rev']!, _localRevMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, profileId};
  @override
  CycleOverrideData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CycleOverrideData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      cycleStartDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cycle_start_date'],
      )!,
      excludedFromAverage: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}excluded_from_average'],
      )!,
      manualStart: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}manual_start'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      localRev: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_rev'],
      )!,
    );
  }

  @override
  $CycleOverridesTable createAlias(String alias) {
    return $CycleOverridesTable(attachedDatabase, alias);
  }
}

class CycleOverrideData extends DataClass
    implements Insertable<CycleOverrideData> {
  /// Client-generated ULID (stable across devices/sync).
  final String id;
  final String profileId;

  /// ISO calendar date `yyyy-MM-dd` of the manual boundary.
  final String cycleStartDate;

  /// True when this interval is left out of cycle-length averages (#132).
  final bool excludedFromAverage;

  /// True when the user started this cycle by hand.
  final bool manualStart;

  /// Placeholder id of a future notes-table row (#132); null when unset.
  final String? noteId;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// See [Profiles.dirty].
  final bool dirty;

  /// See [Profiles.localRev].
  final int localRev;
  const CycleOverrideData({
    required this.id,
    required this.profileId,
    required this.cycleStartDate,
    required this.excludedFromAverage,
    required this.manualStart,
    this.noteId,
    required this.updatedAt,
    this.deletedAt,
    required this.dirty,
    required this.localRev,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['profile_id'] = Variable<String>(profileId);
    map['cycle_start_date'] = Variable<String>(cycleStartDate);
    map['excluded_from_average'] = Variable<bool>(excludedFromAverage);
    map['manual_start'] = Variable<bool>(manualStart);
    if (!nullToAbsent || noteId != null) {
      map['note_id'] = Variable<String>(noteId);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['dirty'] = Variable<bool>(dirty);
    map['local_rev'] = Variable<int>(localRev);
    return map;
  }

  CycleOverridesCompanion toCompanion(bool nullToAbsent) {
    return CycleOverridesCompanion(
      id: Value(id),
      profileId: Value(profileId),
      cycleStartDate: Value(cycleStartDate),
      excludedFromAverage: Value(excludedFromAverage),
      manualStart: Value(manualStart),
      noteId: noteId == null && nullToAbsent
          ? const Value.absent()
          : Value(noteId),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      dirty: Value(dirty),
      localRev: Value(localRev),
    );
  }

  factory CycleOverrideData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CycleOverrideData(
      id: serializer.fromJson<String>(json['id']),
      profileId: serializer.fromJson<String>(json['profileId']),
      cycleStartDate: serializer.fromJson<String>(json['cycleStartDate']),
      excludedFromAverage: serializer.fromJson<bool>(
        json['excludedFromAverage'],
      ),
      manualStart: serializer.fromJson<bool>(json['manualStart']),
      noteId: serializer.fromJson<String?>(json['noteId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      localRev: serializer.fromJson<int>(json['localRev']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'profileId': serializer.toJson<String>(profileId),
      'cycleStartDate': serializer.toJson<String>(cycleStartDate),
      'excludedFromAverage': serializer.toJson<bool>(excludedFromAverage),
      'manualStart': serializer.toJson<bool>(manualStart),
      'noteId': serializer.toJson<String?>(noteId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'localRev': serializer.toJson<int>(localRev),
    };
  }

  CycleOverrideData copyWith({
    String? id,
    String? profileId,
    String? cycleStartDate,
    bool? excludedFromAverage,
    bool? manualStart,
    Value<String?> noteId = const Value.absent(),
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    bool? dirty,
    int? localRev,
  }) => CycleOverrideData(
    id: id ?? this.id,
    profileId: profileId ?? this.profileId,
    cycleStartDate: cycleStartDate ?? this.cycleStartDate,
    excludedFromAverage: excludedFromAverage ?? this.excludedFromAverage,
    manualStart: manualStart ?? this.manualStart,
    noteId: noteId.present ? noteId.value : this.noteId,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    dirty: dirty ?? this.dirty,
    localRev: localRev ?? this.localRev,
  );
  CycleOverrideData copyWithCompanion(CycleOverridesCompanion data) {
    return CycleOverrideData(
      id: data.id.present ? data.id.value : this.id,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      cycleStartDate: data.cycleStartDate.present
          ? data.cycleStartDate.value
          : this.cycleStartDate,
      excludedFromAverage: data.excludedFromAverage.present
          ? data.excludedFromAverage.value
          : this.excludedFromAverage,
      manualStart: data.manualStart.present
          ? data.manualStart.value
          : this.manualStart,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      localRev: data.localRev.present ? data.localRev.value : this.localRev,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CycleOverrideData(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('cycleStartDate: $cycleStartDate, ')
          ..write('excludedFromAverage: $excludedFromAverage, ')
          ..write('manualStart: $manualStart, ')
          ..write('noteId: $noteId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('dirty: $dirty, ')
          ..write('localRev: $localRev')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    profileId,
    cycleStartDate,
    excludedFromAverage,
    manualStart,
    noteId,
    updatedAt,
    deletedAt,
    dirty,
    localRev,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CycleOverrideData &&
          other.id == this.id &&
          other.profileId == this.profileId &&
          other.cycleStartDate == this.cycleStartDate &&
          other.excludedFromAverage == this.excludedFromAverage &&
          other.manualStart == this.manualStart &&
          other.noteId == this.noteId &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.dirty == this.dirty &&
          other.localRev == this.localRev);
}

class CycleOverridesCompanion extends UpdateCompanion<CycleOverrideData> {
  final Value<String> id;
  final Value<String> profileId;
  final Value<String> cycleStartDate;
  final Value<bool> excludedFromAverage;
  final Value<bool> manualStart;
  final Value<String?> noteId;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<bool> dirty;
  final Value<int> localRev;
  final Value<int> rowid;
  const CycleOverridesCompanion({
    this.id = const Value.absent(),
    this.profileId = const Value.absent(),
    this.cycleStartDate = const Value.absent(),
    this.excludedFromAverage = const Value.absent(),
    this.manualStart = const Value.absent(),
    this.noteId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.localRev = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CycleOverridesCompanion.insert({
    required String id,
    required String profileId,
    required String cycleStartDate,
    this.excludedFromAverage = const Value.absent(),
    this.manualStart = const Value.absent(),
    this.noteId = const Value.absent(),
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.localRev = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       profileId = Value(profileId),
       cycleStartDate = Value(cycleStartDate),
       updatedAt = Value(updatedAt);
  static Insertable<CycleOverrideData> custom({
    Expression<String>? id,
    Expression<String>? profileId,
    Expression<String>? cycleStartDate,
    Expression<bool>? excludedFromAverage,
    Expression<bool>? manualStart,
    Expression<String>? noteId,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<bool>? dirty,
    Expression<int>? localRev,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (profileId != null) 'profile_id': profileId,
      if (cycleStartDate != null) 'cycle_start_date': cycleStartDate,
      if (excludedFromAverage != null)
        'excluded_from_average': excludedFromAverage,
      if (manualStart != null) 'manual_start': manualStart,
      if (noteId != null) 'note_id': noteId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (dirty != null) 'dirty': dirty,
      if (localRev != null) 'local_rev': localRev,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CycleOverridesCompanion copyWith({
    Value<String>? id,
    Value<String>? profileId,
    Value<String>? cycleStartDate,
    Value<bool>? excludedFromAverage,
    Value<bool>? manualStart,
    Value<String?>? noteId,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<bool>? dirty,
    Value<int>? localRev,
    Value<int>? rowid,
  }) {
    return CycleOverridesCompanion(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      cycleStartDate: cycleStartDate ?? this.cycleStartDate,
      excludedFromAverage: excludedFromAverage ?? this.excludedFromAverage,
      manualStart: manualStart ?? this.manualStart,
      noteId: noteId ?? this.noteId,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      dirty: dirty ?? this.dirty,
      localRev: localRev ?? this.localRev,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (cycleStartDate.present) {
      map['cycle_start_date'] = Variable<String>(cycleStartDate.value);
    }
    if (excludedFromAverage.present) {
      map['excluded_from_average'] = Variable<bool>(excludedFromAverage.value);
    }
    if (manualStart.present) {
      map['manual_start'] = Variable<bool>(manualStart.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (localRev.present) {
      map['local_rev'] = Variable<int>(localRev.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CycleOverridesCompanion(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('cycleStartDate: $cycleStartDate, ')
          ..write('excludedFromAverage: $excludedFromAverage, ')
          ..write('manualStart: $manualStart, ')
          ..write('noteId: $noteId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('dirty: $dirty, ')
          ..write('localRev: $localRev, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CareNotesTable extends CareNotes
    with TableInfo<$CareNotesTable, CareNoteData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CareNotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES profiles (id)',
    ),
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _localRevMeta = const VerificationMeta(
    'localRev',
  );
  @override
  late final GeneratedColumn<int> localRev = GeneratedColumn<int>(
    'local_rev',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _loggedByUserIdMeta = const VerificationMeta(
    'loggedByUserId',
  );
  @override
  late final GeneratedColumn<String> loggedByUserId = GeneratedColumn<String>(
    'logged_by_user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastModifiedByUserIdMeta =
      const VerificationMeta('lastModifiedByUserId');
  @override
  late final GeneratedColumn<String> lastModifiedByUserId =
      GeneratedColumn<String>(
        'last_modified_by_user_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    profileId,
    body,
    updatedAt,
    deletedAt,
    dirty,
    localRev,
    loggedByUserId,
    lastModifiedByUserId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'care_notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<CareNoteData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('local_rev')) {
      context.handle(
        _localRevMeta,
        localRev.isAcceptableOrUnknown(data['local_rev']!, _localRevMeta),
      );
    }
    if (data.containsKey('logged_by_user_id')) {
      context.handle(
        _loggedByUserIdMeta,
        loggedByUserId.isAcceptableOrUnknown(
          data['logged_by_user_id']!,
          _loggedByUserIdMeta,
        ),
      );
    }
    if (data.containsKey('last_modified_by_user_id')) {
      context.handle(
        _lastModifiedByUserIdMeta,
        lastModifiedByUserId.isAcceptableOrUnknown(
          data['last_modified_by_user_id']!,
          _lastModifiedByUserIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CareNoteData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CareNoteData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      localRev: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_rev'],
      )!,
      loggedByUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}logged_by_user_id'],
      ),
      lastModifiedByUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_modified_by_user_id'],
      ),
    );
  }

  @override
  $CareNotesTable createAlias(String alias) {
    return $CareNotesTable(attachedDatabase, alias);
  }
}

class CareNoteData extends DataClass implements Insertable<CareNoteData> {
  /// Client-generated ULID (stable across devices/sync).
  final String id;

  /// The profile this note belongs to (notes are per-profile, never
  /// per-date).
  final String profileId;

  /// Free-text standing note (health content; bounded by
  /// `kMaxCareNoteLength`, cleared on a tombstone like every other payload
  /// column).
  final String body;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// See [Profiles.dirty].
  final bool dirty;

  /// See [Profiles.localRev].
  final int localRev;

  /// Supabase auth user who created this note (stamped by server).
  final String? loggedByUserId;

  /// Supabase auth user who last edited this note (stamped by server).
  final String? lastModifiedByUserId;
  const CareNoteData({
    required this.id,
    required this.profileId,
    required this.body,
    required this.updatedAt,
    this.deletedAt,
    required this.dirty,
    required this.localRev,
    this.loggedByUserId,
    this.lastModifiedByUserId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['profile_id'] = Variable<String>(profileId);
    map['body'] = Variable<String>(body);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['dirty'] = Variable<bool>(dirty);
    map['local_rev'] = Variable<int>(localRev);
    if (!nullToAbsent || loggedByUserId != null) {
      map['logged_by_user_id'] = Variable<String>(loggedByUserId);
    }
    if (!nullToAbsent || lastModifiedByUserId != null) {
      map['last_modified_by_user_id'] = Variable<String>(lastModifiedByUserId);
    }
    return map;
  }

  CareNotesCompanion toCompanion(bool nullToAbsent) {
    return CareNotesCompanion(
      id: Value(id),
      profileId: Value(profileId),
      body: Value(body),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      dirty: Value(dirty),
      localRev: Value(localRev),
      loggedByUserId: loggedByUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(loggedByUserId),
      lastModifiedByUserId: lastModifiedByUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastModifiedByUserId),
    );
  }

  factory CareNoteData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CareNoteData(
      id: serializer.fromJson<String>(json['id']),
      profileId: serializer.fromJson<String>(json['profileId']),
      body: serializer.fromJson<String>(json['body']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      localRev: serializer.fromJson<int>(json['localRev']),
      loggedByUserId: serializer.fromJson<String?>(json['loggedByUserId']),
      lastModifiedByUserId: serializer.fromJson<String?>(
        json['lastModifiedByUserId'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'profileId': serializer.toJson<String>(profileId),
      'body': serializer.toJson<String>(body),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'localRev': serializer.toJson<int>(localRev),
      'loggedByUserId': serializer.toJson<String?>(loggedByUserId),
      'lastModifiedByUserId': serializer.toJson<String?>(lastModifiedByUserId),
    };
  }

  CareNoteData copyWith({
    String? id,
    String? profileId,
    String? body,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    bool? dirty,
    int? localRev,
    Value<String?> loggedByUserId = const Value.absent(),
    Value<String?> lastModifiedByUserId = const Value.absent(),
  }) => CareNoteData(
    id: id ?? this.id,
    profileId: profileId ?? this.profileId,
    body: body ?? this.body,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    dirty: dirty ?? this.dirty,
    localRev: localRev ?? this.localRev,
    loggedByUserId: loggedByUserId.present
        ? loggedByUserId.value
        : this.loggedByUserId,
    lastModifiedByUserId: lastModifiedByUserId.present
        ? lastModifiedByUserId.value
        : this.lastModifiedByUserId,
  );
  CareNoteData copyWithCompanion(CareNotesCompanion data) {
    return CareNoteData(
      id: data.id.present ? data.id.value : this.id,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      body: data.body.present ? data.body.value : this.body,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      localRev: data.localRev.present ? data.localRev.value : this.localRev,
      loggedByUserId: data.loggedByUserId.present
          ? data.loggedByUserId.value
          : this.loggedByUserId,
      lastModifiedByUserId: data.lastModifiedByUserId.present
          ? data.lastModifiedByUserId.value
          : this.lastModifiedByUserId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CareNoteData(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('body: $body, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('dirty: $dirty, ')
          ..write('localRev: $localRev, ')
          ..write('loggedByUserId: $loggedByUserId, ')
          ..write('lastModifiedByUserId: $lastModifiedByUserId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    profileId,
    body,
    updatedAt,
    deletedAt,
    dirty,
    localRev,
    loggedByUserId,
    lastModifiedByUserId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CareNoteData &&
          other.id == this.id &&
          other.profileId == this.profileId &&
          other.body == this.body &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.dirty == this.dirty &&
          other.localRev == this.localRev &&
          other.loggedByUserId == this.loggedByUserId &&
          other.lastModifiedByUserId == this.lastModifiedByUserId);
}

class CareNotesCompanion extends UpdateCompanion<CareNoteData> {
  final Value<String> id;
  final Value<String> profileId;
  final Value<String> body;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<bool> dirty;
  final Value<int> localRev;
  final Value<String?> loggedByUserId;
  final Value<String?> lastModifiedByUserId;
  final Value<int> rowid;
  const CareNotesCompanion({
    this.id = const Value.absent(),
    this.profileId = const Value.absent(),
    this.body = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.localRev = const Value.absent(),
    this.loggedByUserId = const Value.absent(),
    this.lastModifiedByUserId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CareNotesCompanion.insert({
    required String id,
    required String profileId,
    required String body,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.localRev = const Value.absent(),
    this.loggedByUserId = const Value.absent(),
    this.lastModifiedByUserId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       profileId = Value(profileId),
       body = Value(body),
       updatedAt = Value(updatedAt);
  static Insertable<CareNoteData> custom({
    Expression<String>? id,
    Expression<String>? profileId,
    Expression<String>? body,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<bool>? dirty,
    Expression<int>? localRev,
    Expression<String>? loggedByUserId,
    Expression<String>? lastModifiedByUserId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (profileId != null) 'profile_id': profileId,
      if (body != null) 'body': body,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (dirty != null) 'dirty': dirty,
      if (localRev != null) 'local_rev': localRev,
      if (loggedByUserId != null) 'logged_by_user_id': loggedByUserId,
      if (lastModifiedByUserId != null)
        'last_modified_by_user_id': lastModifiedByUserId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CareNotesCompanion copyWith({
    Value<String>? id,
    Value<String>? profileId,
    Value<String>? body,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<bool>? dirty,
    Value<int>? localRev,
    Value<String?>? loggedByUserId,
    Value<String?>? lastModifiedByUserId,
    Value<int>? rowid,
  }) {
    return CareNotesCompanion(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      body: body ?? this.body,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      dirty: dirty ?? this.dirty,
      localRev: localRev ?? this.localRev,
      loggedByUserId: loggedByUserId ?? this.loggedByUserId,
      lastModifiedByUserId: lastModifiedByUserId ?? this.lastModifiedByUserId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (localRev.present) {
      map['local_rev'] = Variable<int>(localRev.value);
    }
    if (loggedByUserId.present) {
      map['logged_by_user_id'] = Variable<String>(loggedByUserId.value);
    }
    if (lastModifiedByUserId.present) {
      map['last_modified_by_user_id'] = Variable<String>(
        lastModifiedByUserId.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CareNotesCompanion(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('body: $body, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('dirty: $dirty, ')
          ..write('localRev: $localRev, ')
          ..write('loggedByUserId: $loggedByUserId, ')
          ..write('lastModifiedByUserId: $lastModifiedByUserId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VisitPrepItemsTable extends VisitPrepItems
    with TableInfo<$VisitPrepItemsTable, VisitPrepItemData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VisitPrepItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES profiles (id)',
    ),
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isCheckedMeta = const VerificationMeta(
    'isChecked',
  );
  @override
  late final GeneratedColumn<bool> isChecked = GeneratedColumn<bool>(
    'is_checked',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_checked" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _checkedByUserIdMeta = const VerificationMeta(
    'checkedByUserId',
  );
  @override
  late final GeneratedColumn<String> checkedByUserId = GeneratedColumn<String>(
    'checked_by_user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _checkedAtMeta = const VerificationMeta(
    'checkedAt',
  );
  @override
  late final GeneratedColumn<DateTime> checkedAt = GeneratedColumn<DateTime>(
    'checked_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _localRevMeta = const VerificationMeta(
    'localRev',
  );
  @override
  late final GeneratedColumn<int> localRev = GeneratedColumn<int>(
    'local_rev',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _loggedByUserIdMeta = const VerificationMeta(
    'loggedByUserId',
  );
  @override
  late final GeneratedColumn<String> loggedByUserId = GeneratedColumn<String>(
    'logged_by_user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastModifiedByUserIdMeta =
      const VerificationMeta('lastModifiedByUserId');
  @override
  late final GeneratedColumn<String> lastModifiedByUserId =
      GeneratedColumn<String>(
        'last_modified_by_user_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    profileId,
    body,
    isChecked,
    checkedByUserId,
    checkedAt,
    updatedAt,
    deletedAt,
    dirty,
    localRev,
    loggedByUserId,
    lastModifiedByUserId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'visit_prep_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<VisitPrepItemData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('is_checked')) {
      context.handle(
        _isCheckedMeta,
        isChecked.isAcceptableOrUnknown(data['is_checked']!, _isCheckedMeta),
      );
    }
    if (data.containsKey('checked_by_user_id')) {
      context.handle(
        _checkedByUserIdMeta,
        checkedByUserId.isAcceptableOrUnknown(
          data['checked_by_user_id']!,
          _checkedByUserIdMeta,
        ),
      );
    }
    if (data.containsKey('checked_at')) {
      context.handle(
        _checkedAtMeta,
        checkedAt.isAcceptableOrUnknown(data['checked_at']!, _checkedAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('local_rev')) {
      context.handle(
        _localRevMeta,
        localRev.isAcceptableOrUnknown(data['local_rev']!, _localRevMeta),
      );
    }
    if (data.containsKey('logged_by_user_id')) {
      context.handle(
        _loggedByUserIdMeta,
        loggedByUserId.isAcceptableOrUnknown(
          data['logged_by_user_id']!,
          _loggedByUserIdMeta,
        ),
      );
    }
    if (data.containsKey('last_modified_by_user_id')) {
      context.handle(
        _lastModifiedByUserIdMeta,
        lastModifiedByUserId.isAcceptableOrUnknown(
          data['last_modified_by_user_id']!,
          _lastModifiedByUserIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VisitPrepItemData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VisitPrepItemData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      isChecked: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_checked'],
      )!,
      checkedByUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}checked_by_user_id'],
      ),
      checkedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}checked_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      localRev: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_rev'],
      )!,
      loggedByUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}logged_by_user_id'],
      ),
      lastModifiedByUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_modified_by_user_id'],
      ),
    );
  }

  @override
  $VisitPrepItemsTable createAlias(String alias) {
    return $VisitPrepItemsTable(attachedDatabase, alias);
  }
}

class VisitPrepItemData extends DataClass
    implements Insertable<VisitPrepItemData> {
  /// Client-generated ULID (stable across devices/sync).
  final String id;

  /// The profile this item belongs to.
  final String profileId;

  /// The item/question text (health content; bounded by
  /// `kMaxVisitPrepItemLength`, cleared on a tombstone).
  final String body;

  /// Whether the item has been checked off. Checking never deletes.
  final bool isChecked;

  /// The auth user who checked the item (AC3), null while unchecked.
  /// Cleared (alongside [checkedAt]) when the item is unchecked or
  /// tombstoned.
  final String? checkedByUserId;

  /// UTC instant the item was checked, null while unchecked.
  final DateTime? checkedAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// See [Profiles.dirty].
  final bool dirty;

  /// See [Profiles.localRev].
  final int localRev;

  /// Supabase auth user who added this item (stamped by server).
  final String? loggedByUserId;

  /// Supabase auth user who last edited this item (stamped by server).
  final String? lastModifiedByUserId;
  const VisitPrepItemData({
    required this.id,
    required this.profileId,
    required this.body,
    required this.isChecked,
    this.checkedByUserId,
    this.checkedAt,
    required this.updatedAt,
    this.deletedAt,
    required this.dirty,
    required this.localRev,
    this.loggedByUserId,
    this.lastModifiedByUserId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['profile_id'] = Variable<String>(profileId);
    map['body'] = Variable<String>(body);
    map['is_checked'] = Variable<bool>(isChecked);
    if (!nullToAbsent || checkedByUserId != null) {
      map['checked_by_user_id'] = Variable<String>(checkedByUserId);
    }
    if (!nullToAbsent || checkedAt != null) {
      map['checked_at'] = Variable<DateTime>(checkedAt);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['dirty'] = Variable<bool>(dirty);
    map['local_rev'] = Variable<int>(localRev);
    if (!nullToAbsent || loggedByUserId != null) {
      map['logged_by_user_id'] = Variable<String>(loggedByUserId);
    }
    if (!nullToAbsent || lastModifiedByUserId != null) {
      map['last_modified_by_user_id'] = Variable<String>(lastModifiedByUserId);
    }
    return map;
  }

  VisitPrepItemsCompanion toCompanion(bool nullToAbsent) {
    return VisitPrepItemsCompanion(
      id: Value(id),
      profileId: Value(profileId),
      body: Value(body),
      isChecked: Value(isChecked),
      checkedByUserId: checkedByUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(checkedByUserId),
      checkedAt: checkedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(checkedAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      dirty: Value(dirty),
      localRev: Value(localRev),
      loggedByUserId: loggedByUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(loggedByUserId),
      lastModifiedByUserId: lastModifiedByUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastModifiedByUserId),
    );
  }

  factory VisitPrepItemData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VisitPrepItemData(
      id: serializer.fromJson<String>(json['id']),
      profileId: serializer.fromJson<String>(json['profileId']),
      body: serializer.fromJson<String>(json['body']),
      isChecked: serializer.fromJson<bool>(json['isChecked']),
      checkedByUserId: serializer.fromJson<String?>(json['checkedByUserId']),
      checkedAt: serializer.fromJson<DateTime?>(json['checkedAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      localRev: serializer.fromJson<int>(json['localRev']),
      loggedByUserId: serializer.fromJson<String?>(json['loggedByUserId']),
      lastModifiedByUserId: serializer.fromJson<String?>(
        json['lastModifiedByUserId'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'profileId': serializer.toJson<String>(profileId),
      'body': serializer.toJson<String>(body),
      'isChecked': serializer.toJson<bool>(isChecked),
      'checkedByUserId': serializer.toJson<String?>(checkedByUserId),
      'checkedAt': serializer.toJson<DateTime?>(checkedAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'localRev': serializer.toJson<int>(localRev),
      'loggedByUserId': serializer.toJson<String?>(loggedByUserId),
      'lastModifiedByUserId': serializer.toJson<String?>(lastModifiedByUserId),
    };
  }

  VisitPrepItemData copyWith({
    String? id,
    String? profileId,
    String? body,
    bool? isChecked,
    Value<String?> checkedByUserId = const Value.absent(),
    Value<DateTime?> checkedAt = const Value.absent(),
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    bool? dirty,
    int? localRev,
    Value<String?> loggedByUserId = const Value.absent(),
    Value<String?> lastModifiedByUserId = const Value.absent(),
  }) => VisitPrepItemData(
    id: id ?? this.id,
    profileId: profileId ?? this.profileId,
    body: body ?? this.body,
    isChecked: isChecked ?? this.isChecked,
    checkedByUserId: checkedByUserId.present
        ? checkedByUserId.value
        : this.checkedByUserId,
    checkedAt: checkedAt.present ? checkedAt.value : this.checkedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    dirty: dirty ?? this.dirty,
    localRev: localRev ?? this.localRev,
    loggedByUserId: loggedByUserId.present
        ? loggedByUserId.value
        : this.loggedByUserId,
    lastModifiedByUserId: lastModifiedByUserId.present
        ? lastModifiedByUserId.value
        : this.lastModifiedByUserId,
  );
  VisitPrepItemData copyWithCompanion(VisitPrepItemsCompanion data) {
    return VisitPrepItemData(
      id: data.id.present ? data.id.value : this.id,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      body: data.body.present ? data.body.value : this.body,
      isChecked: data.isChecked.present ? data.isChecked.value : this.isChecked,
      checkedByUserId: data.checkedByUserId.present
          ? data.checkedByUserId.value
          : this.checkedByUserId,
      checkedAt: data.checkedAt.present ? data.checkedAt.value : this.checkedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      localRev: data.localRev.present ? data.localRev.value : this.localRev,
      loggedByUserId: data.loggedByUserId.present
          ? data.loggedByUserId.value
          : this.loggedByUserId,
      lastModifiedByUserId: data.lastModifiedByUserId.present
          ? data.lastModifiedByUserId.value
          : this.lastModifiedByUserId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VisitPrepItemData(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('body: $body, ')
          ..write('isChecked: $isChecked, ')
          ..write('checkedByUserId: $checkedByUserId, ')
          ..write('checkedAt: $checkedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('dirty: $dirty, ')
          ..write('localRev: $localRev, ')
          ..write('loggedByUserId: $loggedByUserId, ')
          ..write('lastModifiedByUserId: $lastModifiedByUserId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    profileId,
    body,
    isChecked,
    checkedByUserId,
    checkedAt,
    updatedAt,
    deletedAt,
    dirty,
    localRev,
    loggedByUserId,
    lastModifiedByUserId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VisitPrepItemData &&
          other.id == this.id &&
          other.profileId == this.profileId &&
          other.body == this.body &&
          other.isChecked == this.isChecked &&
          other.checkedByUserId == this.checkedByUserId &&
          other.checkedAt == this.checkedAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.dirty == this.dirty &&
          other.localRev == this.localRev &&
          other.loggedByUserId == this.loggedByUserId &&
          other.lastModifiedByUserId == this.lastModifiedByUserId);
}

class VisitPrepItemsCompanion extends UpdateCompanion<VisitPrepItemData> {
  final Value<String> id;
  final Value<String> profileId;
  final Value<String> body;
  final Value<bool> isChecked;
  final Value<String?> checkedByUserId;
  final Value<DateTime?> checkedAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<bool> dirty;
  final Value<int> localRev;
  final Value<String?> loggedByUserId;
  final Value<String?> lastModifiedByUserId;
  final Value<int> rowid;
  const VisitPrepItemsCompanion({
    this.id = const Value.absent(),
    this.profileId = const Value.absent(),
    this.body = const Value.absent(),
    this.isChecked = const Value.absent(),
    this.checkedByUserId = const Value.absent(),
    this.checkedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.localRev = const Value.absent(),
    this.loggedByUserId = const Value.absent(),
    this.lastModifiedByUserId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VisitPrepItemsCompanion.insert({
    required String id,
    required String profileId,
    required String body,
    this.isChecked = const Value.absent(),
    this.checkedByUserId = const Value.absent(),
    this.checkedAt = const Value.absent(),
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.localRev = const Value.absent(),
    this.loggedByUserId = const Value.absent(),
    this.lastModifiedByUserId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       profileId = Value(profileId),
       body = Value(body),
       updatedAt = Value(updatedAt);
  static Insertable<VisitPrepItemData> custom({
    Expression<String>? id,
    Expression<String>? profileId,
    Expression<String>? body,
    Expression<bool>? isChecked,
    Expression<String>? checkedByUserId,
    Expression<DateTime>? checkedAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<bool>? dirty,
    Expression<int>? localRev,
    Expression<String>? loggedByUserId,
    Expression<String>? lastModifiedByUserId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (profileId != null) 'profile_id': profileId,
      if (body != null) 'body': body,
      if (isChecked != null) 'is_checked': isChecked,
      if (checkedByUserId != null) 'checked_by_user_id': checkedByUserId,
      if (checkedAt != null) 'checked_at': checkedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (dirty != null) 'dirty': dirty,
      if (localRev != null) 'local_rev': localRev,
      if (loggedByUserId != null) 'logged_by_user_id': loggedByUserId,
      if (lastModifiedByUserId != null)
        'last_modified_by_user_id': lastModifiedByUserId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VisitPrepItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? profileId,
    Value<String>? body,
    Value<bool>? isChecked,
    Value<String?>? checkedByUserId,
    Value<DateTime?>? checkedAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<bool>? dirty,
    Value<int>? localRev,
    Value<String?>? loggedByUserId,
    Value<String?>? lastModifiedByUserId,
    Value<int>? rowid,
  }) {
    return VisitPrepItemsCompanion(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      body: body ?? this.body,
      isChecked: isChecked ?? this.isChecked,
      checkedByUserId: checkedByUserId ?? this.checkedByUserId,
      checkedAt: checkedAt ?? this.checkedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      dirty: dirty ?? this.dirty,
      localRev: localRev ?? this.localRev,
      loggedByUserId: loggedByUserId ?? this.loggedByUserId,
      lastModifiedByUserId: lastModifiedByUserId ?? this.lastModifiedByUserId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (isChecked.present) {
      map['is_checked'] = Variable<bool>(isChecked.value);
    }
    if (checkedByUserId.present) {
      map['checked_by_user_id'] = Variable<String>(checkedByUserId.value);
    }
    if (checkedAt.present) {
      map['checked_at'] = Variable<DateTime>(checkedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (localRev.present) {
      map['local_rev'] = Variable<int>(localRev.value);
    }
    if (loggedByUserId.present) {
      map['logged_by_user_id'] = Variable<String>(loggedByUserId.value);
    }
    if (lastModifiedByUserId.present) {
      map['last_modified_by_user_id'] = Variable<String>(
        lastModifiedByUserId.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VisitPrepItemsCompanion(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('body: $body, ')
          ..write('isChecked: $isChecked, ')
          ..write('checkedByUserId: $checkedByUserId, ')
          ..write('checkedAt: $checkedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('dirty: $dirty, ')
          ..write('localRev: $localRev, ')
          ..write('loggedByUserId: $loggedByUserId, ')
          ..write('lastModifiedByUserId: $lastModifiedByUserId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DayEntryMergeEventsTable extends DayEntryMergeEvents
    with TableInfo<$DayEntryMergeEventsTable, DayEntryMergeEventData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DayEntryMergeEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES profiles (id)',
    ),
  );
  static const VerificationMeta _localDateMeta = const VerificationMeta(
    'localDate',
  );
  @override
  late final GeneratedColumn<String> localDate = GeneratedColumn<String>(
    'local_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _winningRowIdMeta = const VerificationMeta(
    'winningRowId',
  );
  @override
  late final GeneratedColumn<String> winningRowId = GeneratedColumn<String>(
    'winning_row_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _losingRowIdMeta = const VerificationMeta(
    'losingRowId',
  );
  @override
  late final GeneratedColumn<String> losingRowId = GeneratedColumn<String>(
    'losing_row_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldMeta = const VerificationMeta('field');
  @override
  late final GeneratedColumn<String> field = GeneratedColumn<String>(
    'field',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _losingValueTextMeta = const VerificationMeta(
    'losingValueText',
  );
  @override
  late final GeneratedColumn<String> losingValueText = GeneratedColumn<String>(
    'losing_value_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _losingAuthorUserIdMeta =
      const VerificationMeta('losingAuthorUserId');
  @override
  late final GeneratedColumn<String> losingAuthorUserId =
      GeneratedColumn<String>(
        'losing_author_user_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _winningAuthorUserIdMeta =
      const VerificationMeta('winningAuthorUserId');
  @override
  late final GeneratedColumn<String> winningAuthorUserId =
      GeneratedColumn<String>(
        'winning_author_user_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _localRevMeta = const VerificationMeta(
    'localRev',
  );
  @override
  late final GeneratedColumn<int> localRev = GeneratedColumn<int>(
    'local_rev',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    profileId,
    localDate,
    winningRowId,
    losingRowId,
    field,
    losingValueText,
    losingAuthorUserId,
    winningAuthorUserId,
    createdAt,
    updatedAt,
    dirty,
    localRev,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'day_entry_merge_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<DayEntryMergeEventData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('local_date')) {
      context.handle(
        _localDateMeta,
        localDate.isAcceptableOrUnknown(data['local_date']!, _localDateMeta),
      );
    } else if (isInserting) {
      context.missing(_localDateMeta);
    }
    if (data.containsKey('winning_row_id')) {
      context.handle(
        _winningRowIdMeta,
        winningRowId.isAcceptableOrUnknown(
          data['winning_row_id']!,
          _winningRowIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_winningRowIdMeta);
    }
    if (data.containsKey('losing_row_id')) {
      context.handle(
        _losingRowIdMeta,
        losingRowId.isAcceptableOrUnknown(
          data['losing_row_id']!,
          _losingRowIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_losingRowIdMeta);
    }
    if (data.containsKey('field')) {
      context.handle(
        _fieldMeta,
        field.isAcceptableOrUnknown(data['field']!, _fieldMeta),
      );
    } else if (isInserting) {
      context.missing(_fieldMeta);
    }
    if (data.containsKey('losing_value_text')) {
      context.handle(
        _losingValueTextMeta,
        losingValueText.isAcceptableOrUnknown(
          data['losing_value_text']!,
          _losingValueTextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_losingValueTextMeta);
    }
    if (data.containsKey('losing_author_user_id')) {
      context.handle(
        _losingAuthorUserIdMeta,
        losingAuthorUserId.isAcceptableOrUnknown(
          data['losing_author_user_id']!,
          _losingAuthorUserIdMeta,
        ),
      );
    }
    if (data.containsKey('winning_author_user_id')) {
      context.handle(
        _winningAuthorUserIdMeta,
        winningAuthorUserId.isAcceptableOrUnknown(
          data['winning_author_user_id']!,
          _winningAuthorUserIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('local_rev')) {
      context.handle(
        _localRevMeta,
        localRev.isAcceptableOrUnknown(data['local_rev']!, _localRevMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DayEntryMergeEventData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DayEntryMergeEventData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      localDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_date'],
      )!,
      winningRowId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}winning_row_id'],
      )!,
      losingRowId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}losing_row_id'],
      )!,
      field: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field'],
      )!,
      losingValueText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}losing_value_text'],
      )!,
      losingAuthorUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}losing_author_user_id'],
      ),
      winningAuthorUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}winning_author_user_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      localRev: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_rev'],
      )!,
    );
  }

  @override
  $DayEntryMergeEventsTable createAlias(String alias) {
    return $DayEntryMergeEventsTable(attachedDatabase, alias);
  }
}

class DayEntryMergeEventData extends DataClass
    implements Insertable<DayEntryMergeEventData> {
  /// Client-generated ULID (stable across devices/sync).
  final String id;
  final String profileId;

  /// ISO calendar date `yyyy-MM-dd` the colliding entries were both for.
  final String localDate;

  /// The surviving row's id at merge time.
  final String winningRowId;

  /// The tombstoned row's id at merge time (half of the natural key: a
  /// losing row is tombstoned by the very merge being disclosed, so it can
  /// lose at most one value per field).
  final String losingRowId;

  /// 'flow' | 'note' — which value kind was discarded.
  final String field;

  /// The discarded value itself: the losing note's text, or the losing flow
  /// level's wire string. Health content — bounded (the server CHECKs
  /// 2000), never in a notification, kept out of crash reports.
  final String losingValueText;

  /// Display attribution only: whose value was discarded / survived.
  final String? losingAuthorUserId;
  final String? winningAuthorUserId;

  /// The UTC instant the merge was recorded (the resolution stamp for a
  /// locally-emitted row; the server's `created_at` for a pulled one).
  /// Drives the 30-day display/recovery window, in lockstep with the
  /// server-side retention purge.
  final DateTime createdAt;
  final DateTime updatedAt;

  /// See [Profiles.dirty].
  final bool dirty;

  /// See [Profiles.localRev].
  final int localRev;
  const DayEntryMergeEventData({
    required this.id,
    required this.profileId,
    required this.localDate,
    required this.winningRowId,
    required this.losingRowId,
    required this.field,
    required this.losingValueText,
    this.losingAuthorUserId,
    this.winningAuthorUserId,
    required this.createdAt,
    required this.updatedAt,
    required this.dirty,
    required this.localRev,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['profile_id'] = Variable<String>(profileId);
    map['local_date'] = Variable<String>(localDate);
    map['winning_row_id'] = Variable<String>(winningRowId);
    map['losing_row_id'] = Variable<String>(losingRowId);
    map['field'] = Variable<String>(field);
    map['losing_value_text'] = Variable<String>(losingValueText);
    if (!nullToAbsent || losingAuthorUserId != null) {
      map['losing_author_user_id'] = Variable<String>(losingAuthorUserId);
    }
    if (!nullToAbsent || winningAuthorUserId != null) {
      map['winning_author_user_id'] = Variable<String>(winningAuthorUserId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['dirty'] = Variable<bool>(dirty);
    map['local_rev'] = Variable<int>(localRev);
    return map;
  }

  DayEntryMergeEventsCompanion toCompanion(bool nullToAbsent) {
    return DayEntryMergeEventsCompanion(
      id: Value(id),
      profileId: Value(profileId),
      localDate: Value(localDate),
      winningRowId: Value(winningRowId),
      losingRowId: Value(losingRowId),
      field: Value(field),
      losingValueText: Value(losingValueText),
      losingAuthorUserId: losingAuthorUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(losingAuthorUserId),
      winningAuthorUserId: winningAuthorUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(winningAuthorUserId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      dirty: Value(dirty),
      localRev: Value(localRev),
    );
  }

  factory DayEntryMergeEventData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DayEntryMergeEventData(
      id: serializer.fromJson<String>(json['id']),
      profileId: serializer.fromJson<String>(json['profileId']),
      localDate: serializer.fromJson<String>(json['localDate']),
      winningRowId: serializer.fromJson<String>(json['winningRowId']),
      losingRowId: serializer.fromJson<String>(json['losingRowId']),
      field: serializer.fromJson<String>(json['field']),
      losingValueText: serializer.fromJson<String>(json['losingValueText']),
      losingAuthorUserId: serializer.fromJson<String?>(
        json['losingAuthorUserId'],
      ),
      winningAuthorUserId: serializer.fromJson<String?>(
        json['winningAuthorUserId'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      localRev: serializer.fromJson<int>(json['localRev']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'profileId': serializer.toJson<String>(profileId),
      'localDate': serializer.toJson<String>(localDate),
      'winningRowId': serializer.toJson<String>(winningRowId),
      'losingRowId': serializer.toJson<String>(losingRowId),
      'field': serializer.toJson<String>(field),
      'losingValueText': serializer.toJson<String>(losingValueText),
      'losingAuthorUserId': serializer.toJson<String?>(losingAuthorUserId),
      'winningAuthorUserId': serializer.toJson<String?>(winningAuthorUserId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'localRev': serializer.toJson<int>(localRev),
    };
  }

  DayEntryMergeEventData copyWith({
    String? id,
    String? profileId,
    String? localDate,
    String? winningRowId,
    String? losingRowId,
    String? field,
    String? losingValueText,
    Value<String?> losingAuthorUserId = const Value.absent(),
    Value<String?> winningAuthorUserId = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? dirty,
    int? localRev,
  }) => DayEntryMergeEventData(
    id: id ?? this.id,
    profileId: profileId ?? this.profileId,
    localDate: localDate ?? this.localDate,
    winningRowId: winningRowId ?? this.winningRowId,
    losingRowId: losingRowId ?? this.losingRowId,
    field: field ?? this.field,
    losingValueText: losingValueText ?? this.losingValueText,
    losingAuthorUserId: losingAuthorUserId.present
        ? losingAuthorUserId.value
        : this.losingAuthorUserId,
    winningAuthorUserId: winningAuthorUserId.present
        ? winningAuthorUserId.value
        : this.winningAuthorUserId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    dirty: dirty ?? this.dirty,
    localRev: localRev ?? this.localRev,
  );
  DayEntryMergeEventData copyWithCompanion(DayEntryMergeEventsCompanion data) {
    return DayEntryMergeEventData(
      id: data.id.present ? data.id.value : this.id,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      localDate: data.localDate.present ? data.localDate.value : this.localDate,
      winningRowId: data.winningRowId.present
          ? data.winningRowId.value
          : this.winningRowId,
      losingRowId: data.losingRowId.present
          ? data.losingRowId.value
          : this.losingRowId,
      field: data.field.present ? data.field.value : this.field,
      losingValueText: data.losingValueText.present
          ? data.losingValueText.value
          : this.losingValueText,
      losingAuthorUserId: data.losingAuthorUserId.present
          ? data.losingAuthorUserId.value
          : this.losingAuthorUserId,
      winningAuthorUserId: data.winningAuthorUserId.present
          ? data.winningAuthorUserId.value
          : this.winningAuthorUserId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      localRev: data.localRev.present ? data.localRev.value : this.localRev,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DayEntryMergeEventData(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('localDate: $localDate, ')
          ..write('winningRowId: $winningRowId, ')
          ..write('losingRowId: $losingRowId, ')
          ..write('field: $field, ')
          ..write('losingValueText: $losingValueText, ')
          ..write('losingAuthorUserId: $losingAuthorUserId, ')
          ..write('winningAuthorUserId: $winningAuthorUserId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('localRev: $localRev')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    profileId,
    localDate,
    winningRowId,
    losingRowId,
    field,
    losingValueText,
    losingAuthorUserId,
    winningAuthorUserId,
    createdAt,
    updatedAt,
    dirty,
    localRev,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DayEntryMergeEventData &&
          other.id == this.id &&
          other.profileId == this.profileId &&
          other.localDate == this.localDate &&
          other.winningRowId == this.winningRowId &&
          other.losingRowId == this.losingRowId &&
          other.field == this.field &&
          other.losingValueText == this.losingValueText &&
          other.losingAuthorUserId == this.losingAuthorUserId &&
          other.winningAuthorUserId == this.winningAuthorUserId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.dirty == this.dirty &&
          other.localRev == this.localRev);
}

class DayEntryMergeEventsCompanion
    extends UpdateCompanion<DayEntryMergeEventData> {
  final Value<String> id;
  final Value<String> profileId;
  final Value<String> localDate;
  final Value<String> winningRowId;
  final Value<String> losingRowId;
  final Value<String> field;
  final Value<String> losingValueText;
  final Value<String?> losingAuthorUserId;
  final Value<String?> winningAuthorUserId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> dirty;
  final Value<int> localRev;
  final Value<int> rowid;
  const DayEntryMergeEventsCompanion({
    this.id = const Value.absent(),
    this.profileId = const Value.absent(),
    this.localDate = const Value.absent(),
    this.winningRowId = const Value.absent(),
    this.losingRowId = const Value.absent(),
    this.field = const Value.absent(),
    this.losingValueText = const Value.absent(),
    this.losingAuthorUserId = const Value.absent(),
    this.winningAuthorUserId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.localRev = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DayEntryMergeEventsCompanion.insert({
    required String id,
    required String profileId,
    required String localDate,
    required String winningRowId,
    required String losingRowId,
    required String field,
    required String losingValueText,
    this.losingAuthorUserId = const Value.absent(),
    this.winningAuthorUserId = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.dirty = const Value.absent(),
    this.localRev = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       profileId = Value(profileId),
       localDate = Value(localDate),
       winningRowId = Value(winningRowId),
       losingRowId = Value(losingRowId),
       field = Value(field),
       losingValueText = Value(losingValueText),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DayEntryMergeEventData> custom({
    Expression<String>? id,
    Expression<String>? profileId,
    Expression<String>? localDate,
    Expression<String>? winningRowId,
    Expression<String>? losingRowId,
    Expression<String>? field,
    Expression<String>? losingValueText,
    Expression<String>? losingAuthorUserId,
    Expression<String>? winningAuthorUserId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? dirty,
    Expression<int>? localRev,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (profileId != null) 'profile_id': profileId,
      if (localDate != null) 'local_date': localDate,
      if (winningRowId != null) 'winning_row_id': winningRowId,
      if (losingRowId != null) 'losing_row_id': losingRowId,
      if (field != null) 'field': field,
      if (losingValueText != null) 'losing_value_text': losingValueText,
      if (losingAuthorUserId != null)
        'losing_author_user_id': losingAuthorUserId,
      if (winningAuthorUserId != null)
        'winning_author_user_id': winningAuthorUserId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (dirty != null) 'dirty': dirty,
      if (localRev != null) 'local_rev': localRev,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DayEntryMergeEventsCompanion copyWith({
    Value<String>? id,
    Value<String>? profileId,
    Value<String>? localDate,
    Value<String>? winningRowId,
    Value<String>? losingRowId,
    Value<String>? field,
    Value<String>? losingValueText,
    Value<String?>? losingAuthorUserId,
    Value<String?>? winningAuthorUserId,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? dirty,
    Value<int>? localRev,
    Value<int>? rowid,
  }) {
    return DayEntryMergeEventsCompanion(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      localDate: localDate ?? this.localDate,
      winningRowId: winningRowId ?? this.winningRowId,
      losingRowId: losingRowId ?? this.losingRowId,
      field: field ?? this.field,
      losingValueText: losingValueText ?? this.losingValueText,
      losingAuthorUserId: losingAuthorUserId ?? this.losingAuthorUserId,
      winningAuthorUserId: winningAuthorUserId ?? this.winningAuthorUserId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      dirty: dirty ?? this.dirty,
      localRev: localRev ?? this.localRev,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (localDate.present) {
      map['local_date'] = Variable<String>(localDate.value);
    }
    if (winningRowId.present) {
      map['winning_row_id'] = Variable<String>(winningRowId.value);
    }
    if (losingRowId.present) {
      map['losing_row_id'] = Variable<String>(losingRowId.value);
    }
    if (field.present) {
      map['field'] = Variable<String>(field.value);
    }
    if (losingValueText.present) {
      map['losing_value_text'] = Variable<String>(losingValueText.value);
    }
    if (losingAuthorUserId.present) {
      map['losing_author_user_id'] = Variable<String>(losingAuthorUserId.value);
    }
    if (winningAuthorUserId.present) {
      map['winning_author_user_id'] = Variable<String>(
        winningAuthorUserId.value,
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (localRev.present) {
      map['local_rev'] = Variable<int>(localRev.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DayEntryMergeEventsCompanion(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('localDate: $localDate, ')
          ..write('winningRowId: $winningRowId, ')
          ..write('losingRowId: $losingRowId, ')
          ..write('field: $field, ')
          ..write('losingValueText: $losingValueText, ')
          ..write('losingAuthorUserId: $losingAuthorUserId, ')
          ..write('winningAuthorUserId: $winningAuthorUserId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('localRev: $localRev, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProfileTagRegistryTable extends ProfileTagRegistry
    with TableInfo<$ProfileTagRegistryTable, ProfileTagRegistryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfileTagRegistryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES profiles (id)',
    ),
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _intensityEnabledMeta = const VerificationMeta(
    'intensityEnabled',
  );
  @override
  late final GeneratedColumn<bool> intensityEnabled = GeneratedColumn<bool>(
    'intensity_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("intensity_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _hiddenAtMeta = const VerificationMeta(
    'hiddenAt',
  );
  @override
  late final GeneratedColumn<DateTime> hiddenAt = GeneratedColumn<DateTime>(
    'hidden_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdByMeta = const VerificationMeta(
    'createdBy',
  );
  @override
  late final GeneratedColumn<String> createdBy = GeneratedColumn<String>(
    'created_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _localRevMeta = const VerificationMeta(
    'localRev',
  );
  @override
  late final GeneratedColumn<int> localRev = GeneratedColumn<int>(
    'local_rev',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    profileId,
    code,
    displayName,
    category,
    intensityEnabled,
    hiddenAt,
    sortOrder,
    createdBy,
    createdAt,
    updatedAt,
    deletedAt,
    dirty,
    localRev,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profile_tag_registry';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProfileTagRegistryEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('intensity_enabled')) {
      context.handle(
        _intensityEnabledMeta,
        intensityEnabled.isAcceptableOrUnknown(
          data['intensity_enabled']!,
          _intensityEnabledMeta,
        ),
      );
    }
    if (data.containsKey('hidden_at')) {
      context.handle(
        _hiddenAtMeta,
        hiddenAt.isAcceptableOrUnknown(data['hidden_at']!, _hiddenAtMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('created_by')) {
      context.handle(
        _createdByMeta,
        createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('local_rev')) {
      context.handle(
        _localRevMeta,
        localRev.isAcceptableOrUnknown(data['local_rev']!, _localRevMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProfileTagRegistryEntry map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProfileTagRegistryEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      intensityEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}intensity_enabled'],
      )!,
      hiddenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}hidden_at'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      ),
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      localRev: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_rev'],
      )!,
    );
  }

  @override
  $ProfileTagRegistryTable createAlias(String alias) {
    return $ProfileTagRegistryTable(attachedDatabase, alias);
  }
}

class ProfileTagRegistryEntry extends DataClass
    implements Insertable<ProfileTagRegistryEntry> {
  /// Client-generated ULID (stable across devices/sync).
  final String id;
  final String profileId;

  /// The stable snake_case identifier persisted on day entries; immutable
  /// once created (a rename rewrites displayName only). Bounded to
  /// `kMaxTagLength` (64) by the storage layer, mirroring the server's
  /// CHECK. Survives a tombstone.
  final String code;

  /// The user's own label (bounded to `kMaxCustomTagLabelLength`, 40).
  /// Empty on a tombstone.
  final String displayName;

  /// Free text, client-owned ('custom' for in-app creations). Empty on a
  /// tombstone.
  final String category;

  /// Reserved for per-tag intensity affordances; false today.
  final bool intensityEnabled;

  /// RETIREMENT, not deletion: non-null removes the code from the
  /// day-sheet picker while stored rows referencing it keep rendering.
  /// Null on a tombstone.
  final DateTime? hiddenAt;
  final int? sortOrder;

  /// Server-stamped from the caller on INSERT; never pushed.
  final String? createdBy;

  /// Server-stamped; never pushed (rides the row for display only).
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// See [Profiles.dirty].
  final bool dirty;

  /// See [Profiles.localRev].
  final int localRev;
  const ProfileTagRegistryEntry({
    required this.id,
    required this.profileId,
    required this.code,
    required this.displayName,
    required this.category,
    required this.intensityEnabled,
    this.hiddenAt,
    this.sortOrder,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.dirty,
    required this.localRev,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['profile_id'] = Variable<String>(profileId);
    map['code'] = Variable<String>(code);
    map['display_name'] = Variable<String>(displayName);
    map['category'] = Variable<String>(category);
    map['intensity_enabled'] = Variable<bool>(intensityEnabled);
    if (!nullToAbsent || hiddenAt != null) {
      map['hidden_at'] = Variable<DateTime>(hiddenAt);
    }
    if (!nullToAbsent || sortOrder != null) {
      map['sort_order'] = Variable<int>(sortOrder);
    }
    if (!nullToAbsent || createdBy != null) {
      map['created_by'] = Variable<String>(createdBy);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['dirty'] = Variable<bool>(dirty);
    map['local_rev'] = Variable<int>(localRev);
    return map;
  }

  ProfileTagRegistryCompanion toCompanion(bool nullToAbsent) {
    return ProfileTagRegistryCompanion(
      id: Value(id),
      profileId: Value(profileId),
      code: Value(code),
      displayName: Value(displayName),
      category: Value(category),
      intensityEnabled: Value(intensityEnabled),
      hiddenAt: hiddenAt == null && nullToAbsent
          ? const Value.absent()
          : Value(hiddenAt),
      sortOrder: sortOrder == null && nullToAbsent
          ? const Value.absent()
          : Value(sortOrder),
      createdBy: createdBy == null && nullToAbsent
          ? const Value.absent()
          : Value(createdBy),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      dirty: Value(dirty),
      localRev: Value(localRev),
    );
  }

  factory ProfileTagRegistryEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProfileTagRegistryEntry(
      id: serializer.fromJson<String>(json['id']),
      profileId: serializer.fromJson<String>(json['profileId']),
      code: serializer.fromJson<String>(json['code']),
      displayName: serializer.fromJson<String>(json['displayName']),
      category: serializer.fromJson<String>(json['category']),
      intensityEnabled: serializer.fromJson<bool>(json['intensityEnabled']),
      hiddenAt: serializer.fromJson<DateTime?>(json['hiddenAt']),
      sortOrder: serializer.fromJson<int?>(json['sortOrder']),
      createdBy: serializer.fromJson<String?>(json['createdBy']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      localRev: serializer.fromJson<int>(json['localRev']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'profileId': serializer.toJson<String>(profileId),
      'code': serializer.toJson<String>(code),
      'displayName': serializer.toJson<String>(displayName),
      'category': serializer.toJson<String>(category),
      'intensityEnabled': serializer.toJson<bool>(intensityEnabled),
      'hiddenAt': serializer.toJson<DateTime?>(hiddenAt),
      'sortOrder': serializer.toJson<int?>(sortOrder),
      'createdBy': serializer.toJson<String?>(createdBy),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'localRev': serializer.toJson<int>(localRev),
    };
  }

  ProfileTagRegistryEntry copyWith({
    String? id,
    String? profileId,
    String? code,
    String? displayName,
    String? category,
    bool? intensityEnabled,
    Value<DateTime?> hiddenAt = const Value.absent(),
    Value<int?> sortOrder = const Value.absent(),
    Value<String?> createdBy = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    bool? dirty,
    int? localRev,
  }) => ProfileTagRegistryEntry(
    id: id ?? this.id,
    profileId: profileId ?? this.profileId,
    code: code ?? this.code,
    displayName: displayName ?? this.displayName,
    category: category ?? this.category,
    intensityEnabled: intensityEnabled ?? this.intensityEnabled,
    hiddenAt: hiddenAt.present ? hiddenAt.value : this.hiddenAt,
    sortOrder: sortOrder.present ? sortOrder.value : this.sortOrder,
    createdBy: createdBy.present ? createdBy.value : this.createdBy,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    dirty: dirty ?? this.dirty,
    localRev: localRev ?? this.localRev,
  );
  ProfileTagRegistryEntry copyWithCompanion(ProfileTagRegistryCompanion data) {
    return ProfileTagRegistryEntry(
      id: data.id.present ? data.id.value : this.id,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      code: data.code.present ? data.code.value : this.code,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      category: data.category.present ? data.category.value : this.category,
      intensityEnabled: data.intensityEnabled.present
          ? data.intensityEnabled.value
          : this.intensityEnabled,
      hiddenAt: data.hiddenAt.present ? data.hiddenAt.value : this.hiddenAt,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      localRev: data.localRev.present ? data.localRev.value : this.localRev,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProfileTagRegistryEntry(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('code: $code, ')
          ..write('displayName: $displayName, ')
          ..write('category: $category, ')
          ..write('intensityEnabled: $intensityEnabled, ')
          ..write('hiddenAt: $hiddenAt, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdBy: $createdBy, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('dirty: $dirty, ')
          ..write('localRev: $localRev')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    profileId,
    code,
    displayName,
    category,
    intensityEnabled,
    hiddenAt,
    sortOrder,
    createdBy,
    createdAt,
    updatedAt,
    deletedAt,
    dirty,
    localRev,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProfileTagRegistryEntry &&
          other.id == this.id &&
          other.profileId == this.profileId &&
          other.code == this.code &&
          other.displayName == this.displayName &&
          other.category == this.category &&
          other.intensityEnabled == this.intensityEnabled &&
          other.hiddenAt == this.hiddenAt &&
          other.sortOrder == this.sortOrder &&
          other.createdBy == this.createdBy &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.dirty == this.dirty &&
          other.localRev == this.localRev);
}

class ProfileTagRegistryCompanion
    extends UpdateCompanion<ProfileTagRegistryEntry> {
  final Value<String> id;
  final Value<String> profileId;
  final Value<String> code;
  final Value<String> displayName;
  final Value<String> category;
  final Value<bool> intensityEnabled;
  final Value<DateTime?> hiddenAt;
  final Value<int?> sortOrder;
  final Value<String?> createdBy;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<bool> dirty;
  final Value<int> localRev;
  final Value<int> rowid;
  const ProfileTagRegistryCompanion({
    this.id = const Value.absent(),
    this.profileId = const Value.absent(),
    this.code = const Value.absent(),
    this.displayName = const Value.absent(),
    this.category = const Value.absent(),
    this.intensityEnabled = const Value.absent(),
    this.hiddenAt = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.localRev = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProfileTagRegistryCompanion.insert({
    required String id,
    required String profileId,
    required String code,
    required String displayName,
    required String category,
    this.intensityEnabled = const Value.absent(),
    this.hiddenAt = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdBy = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.localRev = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       profileId = Value(profileId),
       code = Value(code),
       displayName = Value(displayName),
       category = Value(category),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ProfileTagRegistryEntry> custom({
    Expression<String>? id,
    Expression<String>? profileId,
    Expression<String>? code,
    Expression<String>? displayName,
    Expression<String>? category,
    Expression<bool>? intensityEnabled,
    Expression<DateTime>? hiddenAt,
    Expression<int>? sortOrder,
    Expression<String>? createdBy,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<bool>? dirty,
    Expression<int>? localRev,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (profileId != null) 'profile_id': profileId,
      if (code != null) 'code': code,
      if (displayName != null) 'display_name': displayName,
      if (category != null) 'category': category,
      if (intensityEnabled != null) 'intensity_enabled': intensityEnabled,
      if (hiddenAt != null) 'hidden_at': hiddenAt,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdBy != null) 'created_by': createdBy,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (dirty != null) 'dirty': dirty,
      if (localRev != null) 'local_rev': localRev,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProfileTagRegistryCompanion copyWith({
    Value<String>? id,
    Value<String>? profileId,
    Value<String>? code,
    Value<String>? displayName,
    Value<String>? category,
    Value<bool>? intensityEnabled,
    Value<DateTime?>? hiddenAt,
    Value<int?>? sortOrder,
    Value<String?>? createdBy,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<bool>? dirty,
    Value<int>? localRev,
    Value<int>? rowid,
  }) {
    return ProfileTagRegistryCompanion(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      code: code ?? this.code,
      displayName: displayName ?? this.displayName,
      category: category ?? this.category,
      intensityEnabled: intensityEnabled ?? this.intensityEnabled,
      hiddenAt: hiddenAt ?? this.hiddenAt,
      sortOrder: sortOrder ?? this.sortOrder,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      dirty: dirty ?? this.dirty,
      localRev: localRev ?? this.localRev,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (intensityEnabled.present) {
      map['intensity_enabled'] = Variable<bool>(intensityEnabled.value);
    }
    if (hiddenAt.present) {
      map['hidden_at'] = Variable<DateTime>(hiddenAt.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (localRev.present) {
      map['local_rev'] = Variable<int>(localRev.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfileTagRegistryCompanion(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('code: $code, ')
          ..write('displayName: $displayName, ')
          ..write('category: $category, ')
          ..write('intensityEnabled: $intensityEnabled, ')
          ..write('hiddenAt: $hiddenAt, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdBy: $createdBy, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('dirty: $dirty, ')
          ..write('localRev: $localRev, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DayEntryHistoryTable extends DayEntryHistory
    with TableInfo<$DayEntryHistoryTable, DayEntryHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DayEntryHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<String> entryId = GeneratedColumn<String>(
    'entry_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES profiles (id)',
    ),
  );
  static const VerificationMeta _changedByUserIdMeta = const VerificationMeta(
    'changedByUserId',
  );
  @override
  late final GeneratedColumn<String> changedByUserId = GeneratedColumn<String>(
    'changed_by_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _changedAtMeta = const VerificationMeta(
    'changedAt',
  );
  @override
  late final GeneratedColumn<DateTime> changedAt = GeneratedColumn<DateTime>(
    'changed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _changeKindMeta = const VerificationMeta(
    'changeKind',
  );
  @override
  late final GeneratedColumn<String> changeKind = GeneratedColumn<String>(
    'change_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String>
  changedFields = GeneratedColumn<String>(
    'changed_fields',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<List<String>>($DayEntryHistoryTable.$converterchangedFields);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entryId,
    profileId,
    changedByUserId,
    changedAt,
    changeKind,
    changedFields,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'day_entry_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<DayEntryHistoryData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entryIdMeta);
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('changed_by_user_id')) {
      context.handle(
        _changedByUserIdMeta,
        changedByUserId.isAcceptableOrUnknown(
          data['changed_by_user_id']!,
          _changedByUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_changedByUserIdMeta);
    }
    if (data.containsKey('changed_at')) {
      context.handle(
        _changedAtMeta,
        changedAt.isAcceptableOrUnknown(data['changed_at']!, _changedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_changedAtMeta);
    }
    if (data.containsKey('change_kind')) {
      context.handle(
        _changeKindMeta,
        changeKind.isAcceptableOrUnknown(data['change_kind']!, _changeKindMeta),
      );
    } else if (isInserting) {
      context.missing(_changeKindMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DayEntryHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DayEntryHistoryData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_id'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      changedByUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}changed_by_user_id'],
      )!,
      changedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}changed_at'],
      )!,
      changeKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}change_kind'],
      )!,
      changedFields: $DayEntryHistoryTable.$converterchangedFields.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}changed_fields'],
        )!,
      ),
    );
  }

  @override
  $DayEntryHistoryTable createAlias(String alias) {
    return $DayEntryHistoryTable(attachedDatabase, alias);
  }

  static TypeConverter<List<String>, String> $converterchangedFields =
      const TagsConverter();
}

class DayEntryHistoryData extends DataClass
    implements Insertable<DayEntryHistoryData> {
  /// Server-generated ULID (random identity; rows are keyed by event, never
  /// ordered by id).
  final String id;

  /// The day_entries row the change happened to (a plain text reference
  /// locally — see the class doc comment).
  final String entryId;
  final String profileId;

  /// Display attribution only: who made the change.
  final String changedByUserId;
  final DateTime changedAt;

  /// Raw `change_kind` wire string ('logged' | 'updated' | 'tombstoned' |
  /// 'merged_discard'); `DayEntryChangeKind.fromDb` normalises on the way
  /// to the domain model.
  final String changeKind;

  /// day_entries COLUMN NAMES only, never values — the table's whole
  /// contract (content-free, enforced server-side by CHECK). Stored as a
  /// JSON array via [TagsConverter] (the same List&lt;String&gt; mapping the
  /// day-entry `tags` column uses).
  final List<String> changedFields;
  const DayEntryHistoryData({
    required this.id,
    required this.entryId,
    required this.profileId,
    required this.changedByUserId,
    required this.changedAt,
    required this.changeKind,
    required this.changedFields,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['entry_id'] = Variable<String>(entryId);
    map['profile_id'] = Variable<String>(profileId);
    map['changed_by_user_id'] = Variable<String>(changedByUserId);
    map['changed_at'] = Variable<DateTime>(changedAt);
    map['change_kind'] = Variable<String>(changeKind);
    {
      map['changed_fields'] = Variable<String>(
        $DayEntryHistoryTable.$converterchangedFields.toSql(changedFields),
      );
    }
    return map;
  }

  DayEntryHistoryCompanion toCompanion(bool nullToAbsent) {
    return DayEntryHistoryCompanion(
      id: Value(id),
      entryId: Value(entryId),
      profileId: Value(profileId),
      changedByUserId: Value(changedByUserId),
      changedAt: Value(changedAt),
      changeKind: Value(changeKind),
      changedFields: Value(changedFields),
    );
  }

  factory DayEntryHistoryData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DayEntryHistoryData(
      id: serializer.fromJson<String>(json['id']),
      entryId: serializer.fromJson<String>(json['entryId']),
      profileId: serializer.fromJson<String>(json['profileId']),
      changedByUserId: serializer.fromJson<String>(json['changedByUserId']),
      changedAt: serializer.fromJson<DateTime>(json['changedAt']),
      changeKind: serializer.fromJson<String>(json['changeKind']),
      changedFields: serializer.fromJson<List<String>>(json['changedFields']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entryId': serializer.toJson<String>(entryId),
      'profileId': serializer.toJson<String>(profileId),
      'changedByUserId': serializer.toJson<String>(changedByUserId),
      'changedAt': serializer.toJson<DateTime>(changedAt),
      'changeKind': serializer.toJson<String>(changeKind),
      'changedFields': serializer.toJson<List<String>>(changedFields),
    };
  }

  DayEntryHistoryData copyWith({
    String? id,
    String? entryId,
    String? profileId,
    String? changedByUserId,
    DateTime? changedAt,
    String? changeKind,
    List<String>? changedFields,
  }) => DayEntryHistoryData(
    id: id ?? this.id,
    entryId: entryId ?? this.entryId,
    profileId: profileId ?? this.profileId,
    changedByUserId: changedByUserId ?? this.changedByUserId,
    changedAt: changedAt ?? this.changedAt,
    changeKind: changeKind ?? this.changeKind,
    changedFields: changedFields ?? this.changedFields,
  );
  DayEntryHistoryData copyWithCompanion(DayEntryHistoryCompanion data) {
    return DayEntryHistoryData(
      id: data.id.present ? data.id.value : this.id,
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      changedByUserId: data.changedByUserId.present
          ? data.changedByUserId.value
          : this.changedByUserId,
      changedAt: data.changedAt.present ? data.changedAt.value : this.changedAt,
      changeKind: data.changeKind.present
          ? data.changeKind.value
          : this.changeKind,
      changedFields: data.changedFields.present
          ? data.changedFields.value
          : this.changedFields,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DayEntryHistoryData(')
          ..write('id: $id, ')
          ..write('entryId: $entryId, ')
          ..write('profileId: $profileId, ')
          ..write('changedByUserId: $changedByUserId, ')
          ..write('changedAt: $changedAt, ')
          ..write('changeKind: $changeKind, ')
          ..write('changedFields: $changedFields')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    entryId,
    profileId,
    changedByUserId,
    changedAt,
    changeKind,
    changedFields,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DayEntryHistoryData &&
          other.id == this.id &&
          other.entryId == this.entryId &&
          other.profileId == this.profileId &&
          other.changedByUserId == this.changedByUserId &&
          other.changedAt == this.changedAt &&
          other.changeKind == this.changeKind &&
          other.changedFields == this.changedFields);
}

class DayEntryHistoryCompanion extends UpdateCompanion<DayEntryHistoryData> {
  final Value<String> id;
  final Value<String> entryId;
  final Value<String> profileId;
  final Value<String> changedByUserId;
  final Value<DateTime> changedAt;
  final Value<String> changeKind;
  final Value<List<String>> changedFields;
  final Value<int> rowid;
  const DayEntryHistoryCompanion({
    this.id = const Value.absent(),
    this.entryId = const Value.absent(),
    this.profileId = const Value.absent(),
    this.changedByUserId = const Value.absent(),
    this.changedAt = const Value.absent(),
    this.changeKind = const Value.absent(),
    this.changedFields = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DayEntryHistoryCompanion.insert({
    required String id,
    required String entryId,
    required String profileId,
    required String changedByUserId,
    required DateTime changedAt,
    required String changeKind,
    required List<String> changedFields,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       entryId = Value(entryId),
       profileId = Value(profileId),
       changedByUserId = Value(changedByUserId),
       changedAt = Value(changedAt),
       changeKind = Value(changeKind),
       changedFields = Value(changedFields);
  static Insertable<DayEntryHistoryData> custom({
    Expression<String>? id,
    Expression<String>? entryId,
    Expression<String>? profileId,
    Expression<String>? changedByUserId,
    Expression<DateTime>? changedAt,
    Expression<String>? changeKind,
    Expression<String>? changedFields,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entryId != null) 'entry_id': entryId,
      if (profileId != null) 'profile_id': profileId,
      if (changedByUserId != null) 'changed_by_user_id': changedByUserId,
      if (changedAt != null) 'changed_at': changedAt,
      if (changeKind != null) 'change_kind': changeKind,
      if (changedFields != null) 'changed_fields': changedFields,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DayEntryHistoryCompanion copyWith({
    Value<String>? id,
    Value<String>? entryId,
    Value<String>? profileId,
    Value<String>? changedByUserId,
    Value<DateTime>? changedAt,
    Value<String>? changeKind,
    Value<List<String>>? changedFields,
    Value<int>? rowid,
  }) {
    return DayEntryHistoryCompanion(
      id: id ?? this.id,
      entryId: entryId ?? this.entryId,
      profileId: profileId ?? this.profileId,
      changedByUserId: changedByUserId ?? this.changedByUserId,
      changedAt: changedAt ?? this.changedAt,
      changeKind: changeKind ?? this.changeKind,
      changedFields: changedFields ?? this.changedFields,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entryId.present) {
      map['entry_id'] = Variable<String>(entryId.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (changedByUserId.present) {
      map['changed_by_user_id'] = Variable<String>(changedByUserId.value);
    }
    if (changedAt.present) {
      map['changed_at'] = Variable<DateTime>(changedAt.value);
    }
    if (changeKind.present) {
      map['change_kind'] = Variable<String>(changeKind.value);
    }
    if (changedFields.present) {
      map['changed_fields'] = Variable<String>(
        $DayEntryHistoryTable.$converterchangedFields.toSql(
          changedFields.value,
        ),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DayEntryHistoryCompanion(')
          ..write('id: $id, ')
          ..write('entryId: $entryId, ')
          ..write('profileId: $profileId, ')
          ..write('changedByUserId: $changedByUserId, ')
          ..write('changedAt: $changedAt, ')
          ..write('changeKind: $changeKind, ')
          ..write('changedFields: $changedFields, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String value;
  final DateTime updatedAt;
  const AppSetting({
    required this.key,
    required this.value,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AppSetting copyWith({String? key, String? value, DateTime? updatedAt}) =>
      AppSetting(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       updatedAt = Value(updatedAt);
  static Insertable<AppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncStateTable extends SyncState
    with TableInfo<$SyncStateTable, SyncStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    check: () => id.equals(1),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _boundUserIdMeta = const VerificationMeta(
    'boundUserId',
  );
  @override
  late final GeneratedColumn<String> boundUserId = GeneratedColumn<String>(
    'bound_user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _cursorProfilesMeta = const VerificationMeta(
    'cursorProfiles',
  );
  @override
  late final GeneratedColumn<int> cursorProfiles = GeneratedColumn<int>(
    'cursor_profiles',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _cursorDayEntriesMeta = const VerificationMeta(
    'cursorDayEntries',
  );
  @override
  late final GeneratedColumn<int> cursorDayEntries = GeneratedColumn<int>(
    'cursor_day_entries',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _cursorObservationsMeta =
      const VerificationMeta('cursorObservations');
  @override
  late final GeneratedColumn<int> cursorObservations = GeneratedColumn<int>(
    'cursor_observations',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _cursorProfileModesMeta =
      const VerificationMeta('cursorProfileModes');
  @override
  late final GeneratedColumn<int> cursorProfileModes = GeneratedColumn<int>(
    'cursor_profile_modes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _cursorCycleOverridesMeta =
      const VerificationMeta('cursorCycleOverrides');
  @override
  late final GeneratedColumn<int> cursorCycleOverrides = GeneratedColumn<int>(
    'cursor_cycle_overrides',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _cursorCareNotesMeta = const VerificationMeta(
    'cursorCareNotes',
  );
  @override
  late final GeneratedColumn<int> cursorCareNotes = GeneratedColumn<int>(
    'cursor_care_notes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _cursorVisitPrepItemsMeta =
      const VerificationMeta('cursorVisitPrepItems');
  @override
  late final GeneratedColumn<int> cursorVisitPrepItems = GeneratedColumn<int>(
    'cursor_visit_prep_items',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _cursorProfileGuardiansMeta =
      const VerificationMeta('cursorProfileGuardians');
  @override
  late final GeneratedColumn<int> cursorProfileGuardians = GeneratedColumn<int>(
    'cursor_profile_guardians',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _cursorDeletedProfilesMeta =
      const VerificationMeta('cursorDeletedProfiles');
  @override
  late final GeneratedColumn<int> cursorDeletedProfiles = GeneratedColumn<int>(
    'cursor_deleted_profiles',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _cursorDayEntryMergeEventsMeta =
      const VerificationMeta('cursorDayEntryMergeEvents');
  @override
  late final GeneratedColumn<int> cursorDayEntryMergeEvents =
      GeneratedColumn<int>(
        'cursor_day_entry_merge_events',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
      );
  static const VerificationMeta _cursorProfileTagRegistryMeta =
      const VerificationMeta('cursorProfileTagRegistry');
  @override
  late final GeneratedColumn<int> cursorProfileTagRegistry =
      GeneratedColumn<int>(
        'cursor_profile_tag_registry',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
      );
  static const VerificationMeta _cursorDayEntryHistoryMeta =
      const VerificationMeta('cursorDayEntryHistory');
  @override
  late final GeneratedColumn<int> cursorDayEntryHistory = GeneratedColumn<int>(
    'cursor_day_entry_history',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastFullPullAtMeta = const VerificationMeta(
    'lastFullPullAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastFullPullAt =
      GeneratedColumn<DateTime>(
        'last_full_pull_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastSyncAtMeta = const VerificationMeta(
    'lastSyncAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncAt = GeneratedColumn<DateTime>(
    'last_sync_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverClockOffsetMsMeta =
      const VerificationMeta('serverClockOffsetMs');
  @override
  late final GeneratedColumn<int> serverClockOffsetMs = GeneratedColumn<int>(
    'server_clock_offset_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    boundUserId,
    deviceId,
    cursorProfiles,
    cursorDayEntries,
    cursorObservations,
    cursorProfileModes,
    cursorCycleOverrides,
    cursorCareNotes,
    cursorVisitPrepItems,
    cursorProfileGuardians,
    cursorDeletedProfiles,
    cursorDayEntryMergeEvents,
    cursorProfileTagRegistry,
    cursorDayEntryHistory,
    lastFullPullAt,
    lastSyncAt,
    lastError,
    serverClockOffsetMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('bound_user_id')) {
      context.handle(
        _boundUserIdMeta,
        boundUserId.isAcceptableOrUnknown(
          data['bound_user_id']!,
          _boundUserIdMeta,
        ),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    }
    if (data.containsKey('cursor_profiles')) {
      context.handle(
        _cursorProfilesMeta,
        cursorProfiles.isAcceptableOrUnknown(
          data['cursor_profiles']!,
          _cursorProfilesMeta,
        ),
      );
    }
    if (data.containsKey('cursor_day_entries')) {
      context.handle(
        _cursorDayEntriesMeta,
        cursorDayEntries.isAcceptableOrUnknown(
          data['cursor_day_entries']!,
          _cursorDayEntriesMeta,
        ),
      );
    }
    if (data.containsKey('cursor_observations')) {
      context.handle(
        _cursorObservationsMeta,
        cursorObservations.isAcceptableOrUnknown(
          data['cursor_observations']!,
          _cursorObservationsMeta,
        ),
      );
    }
    if (data.containsKey('cursor_profile_modes')) {
      context.handle(
        _cursorProfileModesMeta,
        cursorProfileModes.isAcceptableOrUnknown(
          data['cursor_profile_modes']!,
          _cursorProfileModesMeta,
        ),
      );
    }
    if (data.containsKey('cursor_cycle_overrides')) {
      context.handle(
        _cursorCycleOverridesMeta,
        cursorCycleOverrides.isAcceptableOrUnknown(
          data['cursor_cycle_overrides']!,
          _cursorCycleOverridesMeta,
        ),
      );
    }
    if (data.containsKey('cursor_care_notes')) {
      context.handle(
        _cursorCareNotesMeta,
        cursorCareNotes.isAcceptableOrUnknown(
          data['cursor_care_notes']!,
          _cursorCareNotesMeta,
        ),
      );
    }
    if (data.containsKey('cursor_visit_prep_items')) {
      context.handle(
        _cursorVisitPrepItemsMeta,
        cursorVisitPrepItems.isAcceptableOrUnknown(
          data['cursor_visit_prep_items']!,
          _cursorVisitPrepItemsMeta,
        ),
      );
    }
    if (data.containsKey('cursor_profile_guardians')) {
      context.handle(
        _cursorProfileGuardiansMeta,
        cursorProfileGuardians.isAcceptableOrUnknown(
          data['cursor_profile_guardians']!,
          _cursorProfileGuardiansMeta,
        ),
      );
    }
    if (data.containsKey('cursor_deleted_profiles')) {
      context.handle(
        _cursorDeletedProfilesMeta,
        cursorDeletedProfiles.isAcceptableOrUnknown(
          data['cursor_deleted_profiles']!,
          _cursorDeletedProfilesMeta,
        ),
      );
    }
    if (data.containsKey('cursor_day_entry_merge_events')) {
      context.handle(
        _cursorDayEntryMergeEventsMeta,
        cursorDayEntryMergeEvents.isAcceptableOrUnknown(
          data['cursor_day_entry_merge_events']!,
          _cursorDayEntryMergeEventsMeta,
        ),
      );
    }
    if (data.containsKey('cursor_profile_tag_registry')) {
      context.handle(
        _cursorProfileTagRegistryMeta,
        cursorProfileTagRegistry.isAcceptableOrUnknown(
          data['cursor_profile_tag_registry']!,
          _cursorProfileTagRegistryMeta,
        ),
      );
    }
    if (data.containsKey('cursor_day_entry_history')) {
      context.handle(
        _cursorDayEntryHistoryMeta,
        cursorDayEntryHistory.isAcceptableOrUnknown(
          data['cursor_day_entry_history']!,
          _cursorDayEntryHistoryMeta,
        ),
      );
    }
    if (data.containsKey('last_full_pull_at')) {
      context.handle(
        _lastFullPullAtMeta,
        lastFullPullAt.isAcceptableOrUnknown(
          data['last_full_pull_at']!,
          _lastFullPullAtMeta,
        ),
      );
    }
    if (data.containsKey('last_sync_at')) {
      context.handle(
        _lastSyncAtMeta,
        lastSyncAt.isAcceptableOrUnknown(
          data['last_sync_at']!,
          _lastSyncAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('server_clock_offset_ms')) {
      context.handle(
        _serverClockOffsetMsMeta,
        serverClockOffsetMs.isAcceptableOrUnknown(
          data['server_clock_offset_ms']!,
          _serverClockOffsetMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      boundUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bound_user_id'],
      ),
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      cursorProfiles: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cursor_profiles'],
      )!,
      cursorDayEntries: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cursor_day_entries'],
      )!,
      cursorObservations: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cursor_observations'],
      )!,
      cursorProfileModes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cursor_profile_modes'],
      )!,
      cursorCycleOverrides: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cursor_cycle_overrides'],
      )!,
      cursorCareNotes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cursor_care_notes'],
      )!,
      cursorVisitPrepItems: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cursor_visit_prep_items'],
      )!,
      cursorProfileGuardians: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cursor_profile_guardians'],
      )!,
      cursorDeletedProfiles: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cursor_deleted_profiles'],
      )!,
      cursorDayEntryMergeEvents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cursor_day_entry_merge_events'],
      )!,
      cursorProfileTagRegistry: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cursor_profile_tag_registry'],
      )!,
      cursorDayEntryHistory: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cursor_day_entry_history'],
      )!,
      lastFullPullAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_full_pull_at'],
      ),
      lastSyncAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_sync_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      serverClockOffsetMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_clock_offset_ms'],
      ),
    );
  }

  @override
  $SyncStateTable createAlias(String alias) {
    return $SyncStateTable(attachedDatabase, alias);
  }
}

class SyncStateRow extends DataClass implements Insertable<SyncStateRow> {
  final int id;

  /// The Supabase user this database is bound to; null while signed out
  /// or never bound.
  final String? boundUserId;

  /// Stable per-install identifier minted by the sync engine. Defaults to
  /// the empty string so the row can be created by a cursor write before
  /// the engine has bound the device.
  final String deviceId;

  /// Per-table pull cursors (`server_version` high-water marks, KTD2).
  final int cursorProfiles;
  final int cursorDayEntries;

  /// Issue #240: the `observations` pull cursor, same shape as
  /// [cursorDayEntries].
  final int cursorObservations;

  /// Issue #188: the `profile_modes` pull cursor, same shape as
  /// [cursorProfiles].
  final int cursorProfileModes;

  /// Issue #188: the `cycle_overrides` pull cursor, same shape as
  /// [cursorDayEntries].
  final int cursorCycleOverrides;

  /// Issue #128: the `care_notes` pull cursor, same shape as
  /// [cursorDayEntries].
  final int cursorCareNotes;

  /// Issue #128: the `visit_prep_items` pull cursor, same shape as
  /// [cursorDayEntries].
  final int cursorVisitPrepItems;

  /// Issue #525: the `profile_guardians` pull cursor, same shape as
  /// [cursorDayEntries]. Before this column existed, `profileGuardians`
  /// paged from version 0 every cycle (see the sync engine's
  /// `_startingCursor`, pre-#525) — every 15-minute tick forced a full
  /// sequential scan of the global `profile_guardians` table plus one
  /// `is_profile_guardian()` RLS check per scanned row.
  final int cursorProfileGuardians;

  /// Issue #597: the `deleted_profiles` pull cursor, same shape as
  /// [cursorProfileGuardians] — same fix, same table shape (pull-only, a
  /// server-owned `server_version` already exists and is already indexed
  /// server-side). Before this column existed, `deletedProfiles` paged
  /// from version 0 every cycle (see the sync engine's `_startingCursor`,
  /// pre-#597), same tradeoff #525 closed for `profileGuardians` — this
  /// table stayed small enough for a full scan to be cheap at the time,
  /// but the same per-cycle full-scan cost applies as it grows.
  final int cursorDeletedProfiles;

  /// Issue #130: the `day_entry_merge_events` pull cursor, same shape as
  /// [cursorDayEntries].
  final int cursorDayEntryMergeEvents;

  /// Issue #257: the `profile_tag_registry` pull cursor, same shape as
  /// [cursorDayEntries].
  final int cursorProfileTagRegistry;

  /// Issue #170: the `day_entry_history` pull cursor, same shape as
  /// [cursorDayEntries] (the table is pull-only, so this cursor plus the
  /// apply path are its entire sync surface).
  final int cursorDayEntryHistory;
  final DateTime? lastFullPullAt;
  final DateTime? lastSyncAt;

  /// Last sync failure, as a type name or short code — never health content.
  final String? lastError;

  /// `server_now - device_now` in milliseconds, learned from the push RPC;
  /// the storage clock adds it when stamping local writes.
  final int? serverClockOffsetMs;
  const SyncStateRow({
    required this.id,
    this.boundUserId,
    required this.deviceId,
    required this.cursorProfiles,
    required this.cursorDayEntries,
    required this.cursorObservations,
    required this.cursorProfileModes,
    required this.cursorCycleOverrides,
    required this.cursorCareNotes,
    required this.cursorVisitPrepItems,
    required this.cursorProfileGuardians,
    required this.cursorDeletedProfiles,
    required this.cursorDayEntryMergeEvents,
    required this.cursorProfileTagRegistry,
    required this.cursorDayEntryHistory,
    this.lastFullPullAt,
    this.lastSyncAt,
    this.lastError,
    this.serverClockOffsetMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || boundUserId != null) {
      map['bound_user_id'] = Variable<String>(boundUserId);
    }
    map['device_id'] = Variable<String>(deviceId);
    map['cursor_profiles'] = Variable<int>(cursorProfiles);
    map['cursor_day_entries'] = Variable<int>(cursorDayEntries);
    map['cursor_observations'] = Variable<int>(cursorObservations);
    map['cursor_profile_modes'] = Variable<int>(cursorProfileModes);
    map['cursor_cycle_overrides'] = Variable<int>(cursorCycleOverrides);
    map['cursor_care_notes'] = Variable<int>(cursorCareNotes);
    map['cursor_visit_prep_items'] = Variable<int>(cursorVisitPrepItems);
    map['cursor_profile_guardians'] = Variable<int>(cursorProfileGuardians);
    map['cursor_deleted_profiles'] = Variable<int>(cursorDeletedProfiles);
    map['cursor_day_entry_merge_events'] = Variable<int>(
      cursorDayEntryMergeEvents,
    );
    map['cursor_profile_tag_registry'] = Variable<int>(
      cursorProfileTagRegistry,
    );
    map['cursor_day_entry_history'] = Variable<int>(cursorDayEntryHistory);
    if (!nullToAbsent || lastFullPullAt != null) {
      map['last_full_pull_at'] = Variable<DateTime>(lastFullPullAt);
    }
    if (!nullToAbsent || lastSyncAt != null) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    if (!nullToAbsent || serverClockOffsetMs != null) {
      map['server_clock_offset_ms'] = Variable<int>(serverClockOffsetMs);
    }
    return map;
  }

  SyncStateCompanion toCompanion(bool nullToAbsent) {
    return SyncStateCompanion(
      id: Value(id),
      boundUserId: boundUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(boundUserId),
      deviceId: Value(deviceId),
      cursorProfiles: Value(cursorProfiles),
      cursorDayEntries: Value(cursorDayEntries),
      cursorObservations: Value(cursorObservations),
      cursorProfileModes: Value(cursorProfileModes),
      cursorCycleOverrides: Value(cursorCycleOverrides),
      cursorCareNotes: Value(cursorCareNotes),
      cursorVisitPrepItems: Value(cursorVisitPrepItems),
      cursorProfileGuardians: Value(cursorProfileGuardians),
      cursorDeletedProfiles: Value(cursorDeletedProfiles),
      cursorDayEntryMergeEvents: Value(cursorDayEntryMergeEvents),
      cursorProfileTagRegistry: Value(cursorProfileTagRegistry),
      cursorDayEntryHistory: Value(cursorDayEntryHistory),
      lastFullPullAt: lastFullPullAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastFullPullAt),
      lastSyncAt: lastSyncAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      serverClockOffsetMs: serverClockOffsetMs == null && nullToAbsent
          ? const Value.absent()
          : Value(serverClockOffsetMs),
    );
  }

  factory SyncStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateRow(
      id: serializer.fromJson<int>(json['id']),
      boundUserId: serializer.fromJson<String?>(json['boundUserId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      cursorProfiles: serializer.fromJson<int>(json['cursorProfiles']),
      cursorDayEntries: serializer.fromJson<int>(json['cursorDayEntries']),
      cursorObservations: serializer.fromJson<int>(json['cursorObservations']),
      cursorProfileModes: serializer.fromJson<int>(json['cursorProfileModes']),
      cursorCycleOverrides: serializer.fromJson<int>(
        json['cursorCycleOverrides'],
      ),
      cursorCareNotes: serializer.fromJson<int>(json['cursorCareNotes']),
      cursorVisitPrepItems: serializer.fromJson<int>(
        json['cursorVisitPrepItems'],
      ),
      cursorProfileGuardians: serializer.fromJson<int>(
        json['cursorProfileGuardians'],
      ),
      cursorDeletedProfiles: serializer.fromJson<int>(
        json['cursorDeletedProfiles'],
      ),
      cursorDayEntryMergeEvents: serializer.fromJson<int>(
        json['cursorDayEntryMergeEvents'],
      ),
      cursorProfileTagRegistry: serializer.fromJson<int>(
        json['cursorProfileTagRegistry'],
      ),
      cursorDayEntryHistory: serializer.fromJson<int>(
        json['cursorDayEntryHistory'],
      ),
      lastFullPullAt: serializer.fromJson<DateTime?>(json['lastFullPullAt']),
      lastSyncAt: serializer.fromJson<DateTime?>(json['lastSyncAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      serverClockOffsetMs: serializer.fromJson<int?>(
        json['serverClockOffsetMs'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'boundUserId': serializer.toJson<String?>(boundUserId),
      'deviceId': serializer.toJson<String>(deviceId),
      'cursorProfiles': serializer.toJson<int>(cursorProfiles),
      'cursorDayEntries': serializer.toJson<int>(cursorDayEntries),
      'cursorObservations': serializer.toJson<int>(cursorObservations),
      'cursorProfileModes': serializer.toJson<int>(cursorProfileModes),
      'cursorCycleOverrides': serializer.toJson<int>(cursorCycleOverrides),
      'cursorCareNotes': serializer.toJson<int>(cursorCareNotes),
      'cursorVisitPrepItems': serializer.toJson<int>(cursorVisitPrepItems),
      'cursorProfileGuardians': serializer.toJson<int>(cursorProfileGuardians),
      'cursorDeletedProfiles': serializer.toJson<int>(cursorDeletedProfiles),
      'cursorDayEntryMergeEvents': serializer.toJson<int>(
        cursorDayEntryMergeEvents,
      ),
      'cursorProfileTagRegistry': serializer.toJson<int>(
        cursorProfileTagRegistry,
      ),
      'cursorDayEntryHistory': serializer.toJson<int>(cursorDayEntryHistory),
      'lastFullPullAt': serializer.toJson<DateTime?>(lastFullPullAt),
      'lastSyncAt': serializer.toJson<DateTime?>(lastSyncAt),
      'lastError': serializer.toJson<String?>(lastError),
      'serverClockOffsetMs': serializer.toJson<int?>(serverClockOffsetMs),
    };
  }

  SyncStateRow copyWith({
    int? id,
    Value<String?> boundUserId = const Value.absent(),
    String? deviceId,
    int? cursorProfiles,
    int? cursorDayEntries,
    int? cursorObservations,
    int? cursorProfileModes,
    int? cursorCycleOverrides,
    int? cursorCareNotes,
    int? cursorVisitPrepItems,
    int? cursorProfileGuardians,
    int? cursorDeletedProfiles,
    int? cursorDayEntryMergeEvents,
    int? cursorProfileTagRegistry,
    int? cursorDayEntryHistory,
    Value<DateTime?> lastFullPullAt = const Value.absent(),
    Value<DateTime?> lastSyncAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    Value<int?> serverClockOffsetMs = const Value.absent(),
  }) => SyncStateRow(
    id: id ?? this.id,
    boundUserId: boundUserId.present ? boundUserId.value : this.boundUserId,
    deviceId: deviceId ?? this.deviceId,
    cursorProfiles: cursorProfiles ?? this.cursorProfiles,
    cursorDayEntries: cursorDayEntries ?? this.cursorDayEntries,
    cursorObservations: cursorObservations ?? this.cursorObservations,
    cursorProfileModes: cursorProfileModes ?? this.cursorProfileModes,
    cursorCycleOverrides: cursorCycleOverrides ?? this.cursorCycleOverrides,
    cursorCareNotes: cursorCareNotes ?? this.cursorCareNotes,
    cursorVisitPrepItems: cursorVisitPrepItems ?? this.cursorVisitPrepItems,
    cursorProfileGuardians:
        cursorProfileGuardians ?? this.cursorProfileGuardians,
    cursorDeletedProfiles: cursorDeletedProfiles ?? this.cursorDeletedProfiles,
    cursorDayEntryMergeEvents:
        cursorDayEntryMergeEvents ?? this.cursorDayEntryMergeEvents,
    cursorProfileTagRegistry:
        cursorProfileTagRegistry ?? this.cursorProfileTagRegistry,
    cursorDayEntryHistory: cursorDayEntryHistory ?? this.cursorDayEntryHistory,
    lastFullPullAt: lastFullPullAt.present
        ? lastFullPullAt.value
        : this.lastFullPullAt,
    lastSyncAt: lastSyncAt.present ? lastSyncAt.value : this.lastSyncAt,
    lastError: lastError.present ? lastError.value : this.lastError,
    serverClockOffsetMs: serverClockOffsetMs.present
        ? serverClockOffsetMs.value
        : this.serverClockOffsetMs,
  );
  SyncStateRow copyWithCompanion(SyncStateCompanion data) {
    return SyncStateRow(
      id: data.id.present ? data.id.value : this.id,
      boundUserId: data.boundUserId.present
          ? data.boundUserId.value
          : this.boundUserId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      cursorProfiles: data.cursorProfiles.present
          ? data.cursorProfiles.value
          : this.cursorProfiles,
      cursorDayEntries: data.cursorDayEntries.present
          ? data.cursorDayEntries.value
          : this.cursorDayEntries,
      cursorObservations: data.cursorObservations.present
          ? data.cursorObservations.value
          : this.cursorObservations,
      cursorProfileModes: data.cursorProfileModes.present
          ? data.cursorProfileModes.value
          : this.cursorProfileModes,
      cursorCycleOverrides: data.cursorCycleOverrides.present
          ? data.cursorCycleOverrides.value
          : this.cursorCycleOverrides,
      cursorCareNotes: data.cursorCareNotes.present
          ? data.cursorCareNotes.value
          : this.cursorCareNotes,
      cursorVisitPrepItems: data.cursorVisitPrepItems.present
          ? data.cursorVisitPrepItems.value
          : this.cursorVisitPrepItems,
      cursorProfileGuardians: data.cursorProfileGuardians.present
          ? data.cursorProfileGuardians.value
          : this.cursorProfileGuardians,
      cursorDeletedProfiles: data.cursorDeletedProfiles.present
          ? data.cursorDeletedProfiles.value
          : this.cursorDeletedProfiles,
      cursorDayEntryMergeEvents: data.cursorDayEntryMergeEvents.present
          ? data.cursorDayEntryMergeEvents.value
          : this.cursorDayEntryMergeEvents,
      cursorProfileTagRegistry: data.cursorProfileTagRegistry.present
          ? data.cursorProfileTagRegistry.value
          : this.cursorProfileTagRegistry,
      cursorDayEntryHistory: data.cursorDayEntryHistory.present
          ? data.cursorDayEntryHistory.value
          : this.cursorDayEntryHistory,
      lastFullPullAt: data.lastFullPullAt.present
          ? data.lastFullPullAt.value
          : this.lastFullPullAt,
      lastSyncAt: data.lastSyncAt.present
          ? data.lastSyncAt.value
          : this.lastSyncAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      serverClockOffsetMs: data.serverClockOffsetMs.present
          ? data.serverClockOffsetMs.value
          : this.serverClockOffsetMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateRow(')
          ..write('id: $id, ')
          ..write('boundUserId: $boundUserId, ')
          ..write('deviceId: $deviceId, ')
          ..write('cursorProfiles: $cursorProfiles, ')
          ..write('cursorDayEntries: $cursorDayEntries, ')
          ..write('cursorObservations: $cursorObservations, ')
          ..write('cursorProfileModes: $cursorProfileModes, ')
          ..write('cursorCycleOverrides: $cursorCycleOverrides, ')
          ..write('cursorCareNotes: $cursorCareNotes, ')
          ..write('cursorVisitPrepItems: $cursorVisitPrepItems, ')
          ..write('cursorProfileGuardians: $cursorProfileGuardians, ')
          ..write('cursorDeletedProfiles: $cursorDeletedProfiles, ')
          ..write('cursorDayEntryMergeEvents: $cursorDayEntryMergeEvents, ')
          ..write('cursorProfileTagRegistry: $cursorProfileTagRegistry, ')
          ..write('cursorDayEntryHistory: $cursorDayEntryHistory, ')
          ..write('lastFullPullAt: $lastFullPullAt, ')
          ..write('lastSyncAt: $lastSyncAt, ')
          ..write('lastError: $lastError, ')
          ..write('serverClockOffsetMs: $serverClockOffsetMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    boundUserId,
    deviceId,
    cursorProfiles,
    cursorDayEntries,
    cursorObservations,
    cursorProfileModes,
    cursorCycleOverrides,
    cursorCareNotes,
    cursorVisitPrepItems,
    cursorProfileGuardians,
    cursorDeletedProfiles,
    cursorDayEntryMergeEvents,
    cursorProfileTagRegistry,
    cursorDayEntryHistory,
    lastFullPullAt,
    lastSyncAt,
    lastError,
    serverClockOffsetMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateRow &&
          other.id == this.id &&
          other.boundUserId == this.boundUserId &&
          other.deviceId == this.deviceId &&
          other.cursorProfiles == this.cursorProfiles &&
          other.cursorDayEntries == this.cursorDayEntries &&
          other.cursorObservations == this.cursorObservations &&
          other.cursorProfileModes == this.cursorProfileModes &&
          other.cursorCycleOverrides == this.cursorCycleOverrides &&
          other.cursorCareNotes == this.cursorCareNotes &&
          other.cursorVisitPrepItems == this.cursorVisitPrepItems &&
          other.cursorProfileGuardians == this.cursorProfileGuardians &&
          other.cursorDeletedProfiles == this.cursorDeletedProfiles &&
          other.cursorDayEntryMergeEvents == this.cursorDayEntryMergeEvents &&
          other.cursorProfileTagRegistry == this.cursorProfileTagRegistry &&
          other.cursorDayEntryHistory == this.cursorDayEntryHistory &&
          other.lastFullPullAt == this.lastFullPullAt &&
          other.lastSyncAt == this.lastSyncAt &&
          other.lastError == this.lastError &&
          other.serverClockOffsetMs == this.serverClockOffsetMs);
}

class SyncStateCompanion extends UpdateCompanion<SyncStateRow> {
  final Value<int> id;
  final Value<String?> boundUserId;
  final Value<String> deviceId;
  final Value<int> cursorProfiles;
  final Value<int> cursorDayEntries;
  final Value<int> cursorObservations;
  final Value<int> cursorProfileModes;
  final Value<int> cursorCycleOverrides;
  final Value<int> cursorCareNotes;
  final Value<int> cursorVisitPrepItems;
  final Value<int> cursorProfileGuardians;
  final Value<int> cursorDeletedProfiles;
  final Value<int> cursorDayEntryMergeEvents;
  final Value<int> cursorProfileTagRegistry;
  final Value<int> cursorDayEntryHistory;
  final Value<DateTime?> lastFullPullAt;
  final Value<DateTime?> lastSyncAt;
  final Value<String?> lastError;
  final Value<int?> serverClockOffsetMs;
  const SyncStateCompanion({
    this.id = const Value.absent(),
    this.boundUserId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.cursorProfiles = const Value.absent(),
    this.cursorDayEntries = const Value.absent(),
    this.cursorObservations = const Value.absent(),
    this.cursorProfileModes = const Value.absent(),
    this.cursorCycleOverrides = const Value.absent(),
    this.cursorCareNotes = const Value.absent(),
    this.cursorVisitPrepItems = const Value.absent(),
    this.cursorProfileGuardians = const Value.absent(),
    this.cursorDeletedProfiles = const Value.absent(),
    this.cursorDayEntryMergeEvents = const Value.absent(),
    this.cursorProfileTagRegistry = const Value.absent(),
    this.cursorDayEntryHistory = const Value.absent(),
    this.lastFullPullAt = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.serverClockOffsetMs = const Value.absent(),
  });
  SyncStateCompanion.insert({
    this.id = const Value.absent(),
    this.boundUserId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.cursorProfiles = const Value.absent(),
    this.cursorDayEntries = const Value.absent(),
    this.cursorObservations = const Value.absent(),
    this.cursorProfileModes = const Value.absent(),
    this.cursorCycleOverrides = const Value.absent(),
    this.cursorCareNotes = const Value.absent(),
    this.cursorVisitPrepItems = const Value.absent(),
    this.cursorProfileGuardians = const Value.absent(),
    this.cursorDeletedProfiles = const Value.absent(),
    this.cursorDayEntryMergeEvents = const Value.absent(),
    this.cursorProfileTagRegistry = const Value.absent(),
    this.cursorDayEntryHistory = const Value.absent(),
    this.lastFullPullAt = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.serverClockOffsetMs = const Value.absent(),
  });
  static Insertable<SyncStateRow> custom({
    Expression<int>? id,
    Expression<String>? boundUserId,
    Expression<String>? deviceId,
    Expression<int>? cursorProfiles,
    Expression<int>? cursorDayEntries,
    Expression<int>? cursorObservations,
    Expression<int>? cursorProfileModes,
    Expression<int>? cursorCycleOverrides,
    Expression<int>? cursorCareNotes,
    Expression<int>? cursorVisitPrepItems,
    Expression<int>? cursorProfileGuardians,
    Expression<int>? cursorDeletedProfiles,
    Expression<int>? cursorDayEntryMergeEvents,
    Expression<int>? cursorProfileTagRegistry,
    Expression<int>? cursorDayEntryHistory,
    Expression<DateTime>? lastFullPullAt,
    Expression<DateTime>? lastSyncAt,
    Expression<String>? lastError,
    Expression<int>? serverClockOffsetMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (boundUserId != null) 'bound_user_id': boundUserId,
      if (deviceId != null) 'device_id': deviceId,
      if (cursorProfiles != null) 'cursor_profiles': cursorProfiles,
      if (cursorDayEntries != null) 'cursor_day_entries': cursorDayEntries,
      if (cursorObservations != null) 'cursor_observations': cursorObservations,
      if (cursorProfileModes != null)
        'cursor_profile_modes': cursorProfileModes,
      if (cursorCycleOverrides != null)
        'cursor_cycle_overrides': cursorCycleOverrides,
      if (cursorCareNotes != null) 'cursor_care_notes': cursorCareNotes,
      if (cursorVisitPrepItems != null)
        'cursor_visit_prep_items': cursorVisitPrepItems,
      if (cursorProfileGuardians != null)
        'cursor_profile_guardians': cursorProfileGuardians,
      if (cursorDeletedProfiles != null)
        'cursor_deleted_profiles': cursorDeletedProfiles,
      if (cursorDayEntryMergeEvents != null)
        'cursor_day_entry_merge_events': cursorDayEntryMergeEvents,
      if (cursorProfileTagRegistry != null)
        'cursor_profile_tag_registry': cursorProfileTagRegistry,
      if (cursorDayEntryHistory != null)
        'cursor_day_entry_history': cursorDayEntryHistory,
      if (lastFullPullAt != null) 'last_full_pull_at': lastFullPullAt,
      if (lastSyncAt != null) 'last_sync_at': lastSyncAt,
      if (lastError != null) 'last_error': lastError,
      if (serverClockOffsetMs != null)
        'server_clock_offset_ms': serverClockOffsetMs,
    });
  }

  SyncStateCompanion copyWith({
    Value<int>? id,
    Value<String?>? boundUserId,
    Value<String>? deviceId,
    Value<int>? cursorProfiles,
    Value<int>? cursorDayEntries,
    Value<int>? cursorObservations,
    Value<int>? cursorProfileModes,
    Value<int>? cursorCycleOverrides,
    Value<int>? cursorCareNotes,
    Value<int>? cursorVisitPrepItems,
    Value<int>? cursorProfileGuardians,
    Value<int>? cursorDeletedProfiles,
    Value<int>? cursorDayEntryMergeEvents,
    Value<int>? cursorProfileTagRegistry,
    Value<int>? cursorDayEntryHistory,
    Value<DateTime?>? lastFullPullAt,
    Value<DateTime?>? lastSyncAt,
    Value<String?>? lastError,
    Value<int?>? serverClockOffsetMs,
  }) {
    return SyncStateCompanion(
      id: id ?? this.id,
      boundUserId: boundUserId ?? this.boundUserId,
      deviceId: deviceId ?? this.deviceId,
      cursorProfiles: cursorProfiles ?? this.cursorProfiles,
      cursorDayEntries: cursorDayEntries ?? this.cursorDayEntries,
      cursorObservations: cursorObservations ?? this.cursorObservations,
      cursorProfileModes: cursorProfileModes ?? this.cursorProfileModes,
      cursorCycleOverrides: cursorCycleOverrides ?? this.cursorCycleOverrides,
      cursorCareNotes: cursorCareNotes ?? this.cursorCareNotes,
      cursorVisitPrepItems: cursorVisitPrepItems ?? this.cursorVisitPrepItems,
      cursorProfileGuardians:
          cursorProfileGuardians ?? this.cursorProfileGuardians,
      cursorDeletedProfiles:
          cursorDeletedProfiles ?? this.cursorDeletedProfiles,
      cursorDayEntryMergeEvents:
          cursorDayEntryMergeEvents ?? this.cursorDayEntryMergeEvents,
      cursorProfileTagRegistry:
          cursorProfileTagRegistry ?? this.cursorProfileTagRegistry,
      cursorDayEntryHistory:
          cursorDayEntryHistory ?? this.cursorDayEntryHistory,
      lastFullPullAt: lastFullPullAt ?? this.lastFullPullAt,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastError: lastError ?? this.lastError,
      serverClockOffsetMs: serverClockOffsetMs ?? this.serverClockOffsetMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (boundUserId.present) {
      map['bound_user_id'] = Variable<String>(boundUserId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (cursorProfiles.present) {
      map['cursor_profiles'] = Variable<int>(cursorProfiles.value);
    }
    if (cursorDayEntries.present) {
      map['cursor_day_entries'] = Variable<int>(cursorDayEntries.value);
    }
    if (cursorObservations.present) {
      map['cursor_observations'] = Variable<int>(cursorObservations.value);
    }
    if (cursorProfileModes.present) {
      map['cursor_profile_modes'] = Variable<int>(cursorProfileModes.value);
    }
    if (cursorCycleOverrides.present) {
      map['cursor_cycle_overrides'] = Variable<int>(cursorCycleOverrides.value);
    }
    if (cursorCareNotes.present) {
      map['cursor_care_notes'] = Variable<int>(cursorCareNotes.value);
    }
    if (cursorVisitPrepItems.present) {
      map['cursor_visit_prep_items'] = Variable<int>(
        cursorVisitPrepItems.value,
      );
    }
    if (cursorProfileGuardians.present) {
      map['cursor_profile_guardians'] = Variable<int>(
        cursorProfileGuardians.value,
      );
    }
    if (cursorDeletedProfiles.present) {
      map['cursor_deleted_profiles'] = Variable<int>(
        cursorDeletedProfiles.value,
      );
    }
    if (cursorDayEntryMergeEvents.present) {
      map['cursor_day_entry_merge_events'] = Variable<int>(
        cursorDayEntryMergeEvents.value,
      );
    }
    if (cursorProfileTagRegistry.present) {
      map['cursor_profile_tag_registry'] = Variable<int>(
        cursorProfileTagRegistry.value,
      );
    }
    if (cursorDayEntryHistory.present) {
      map['cursor_day_entry_history'] = Variable<int>(
        cursorDayEntryHistory.value,
      );
    }
    if (lastFullPullAt.present) {
      map['last_full_pull_at'] = Variable<DateTime>(lastFullPullAt.value);
    }
    if (lastSyncAt.present) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (serverClockOffsetMs.present) {
      map['server_clock_offset_ms'] = Variable<int>(serverClockOffsetMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateCompanion(')
          ..write('id: $id, ')
          ..write('boundUserId: $boundUserId, ')
          ..write('deviceId: $deviceId, ')
          ..write('cursorProfiles: $cursorProfiles, ')
          ..write('cursorDayEntries: $cursorDayEntries, ')
          ..write('cursorObservations: $cursorObservations, ')
          ..write('cursorProfileModes: $cursorProfileModes, ')
          ..write('cursorCycleOverrides: $cursorCycleOverrides, ')
          ..write('cursorCareNotes: $cursorCareNotes, ')
          ..write('cursorVisitPrepItems: $cursorVisitPrepItems, ')
          ..write('cursorProfileGuardians: $cursorProfileGuardians, ')
          ..write('cursorDeletedProfiles: $cursorDeletedProfiles, ')
          ..write('cursorDayEntryMergeEvents: $cursorDayEntryMergeEvents, ')
          ..write('cursorProfileTagRegistry: $cursorProfileTagRegistry, ')
          ..write('cursorDayEntryHistory: $cursorDayEntryHistory, ')
          ..write('lastFullPullAt: $lastFullPullAt, ')
          ..write('lastSyncAt: $lastSyncAt, ')
          ..write('lastError: $lastError, ')
          ..write('serverClockOffsetMs: $serverClockOffsetMs')
          ..write(')'))
        .toString();
  }
}

class $HealthSyncStateTable extends HealthSyncState
    with TableInfo<$HealthSyncStateTable, HealthSyncStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HealthSyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _platformMeta = const VerificationMeta(
    'platform',
  );
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _anchorMeta = const VerificationMeta('anchor');
  @override
  late final GeneratedColumn<String> anchor = GeneratedColumn<String>(
    'anchor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSyncedAtMeta = const VerificationMeta(
    'lastSyncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncedAt = GeneratedColumn<DateTime>(
    'last_synced_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [platform, anchor, lastSyncedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'health_sync_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<HealthSyncStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('platform')) {
      context.handle(
        _platformMeta,
        platform.isAcceptableOrUnknown(data['platform']!, _platformMeta),
      );
    } else if (isInserting) {
      context.missing(_platformMeta);
    }
    if (data.containsKey('anchor')) {
      context.handle(
        _anchorMeta,
        anchor.isAcceptableOrUnknown(data['anchor']!, _anchorMeta),
      );
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
        _lastSyncedAtMeta,
        lastSyncedAt.isAcceptableOrUnknown(
          data['last_synced_at']!,
          _lastSyncedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {platform};
  @override
  HealthSyncStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HealthSyncStateRow(
      platform: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}platform'],
      )!,
      anchor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}anchor'],
      ),
      lastSyncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_synced_at'],
      ),
    );
  }

  @override
  $HealthSyncStateTable createAlias(String alias) {
    return $HealthSyncStateTable(attachedDatabase, alias);
  }
}

class HealthSyncStateRow extends DataClass
    implements Insertable<HealthSyncStateRow> {
  /// The OS health platform this anchor belongs to: `healthkit` |
  /// `health_connect`.
  final String platform;

  /// The platform's opaque change anchor: Health Connect's
  /// `getChangesToken` token, or HealthKit's anchor UUID / last-read
  /// instant as a string. Null before the first successful read; clearing
  /// it signals "no anchor — do a full time-range read" (the
  /// `ChangesTokenExpiredException` fallback of issue #186).
  final String? anchor;

  /// The UTC instant this anchor was last persisted at.
  final DateTime? lastSyncedAt;
  const HealthSyncStateRow({
    required this.platform,
    this.anchor,
    this.lastSyncedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['platform'] = Variable<String>(platform);
    if (!nullToAbsent || anchor != null) {
      map['anchor'] = Variable<String>(anchor);
    }
    if (!nullToAbsent || lastSyncedAt != null) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt);
    }
    return map;
  }

  HealthSyncStateCompanion toCompanion(bool nullToAbsent) {
    return HealthSyncStateCompanion(
      platform: Value(platform),
      anchor: anchor == null && nullToAbsent
          ? const Value.absent()
          : Value(anchor),
      lastSyncedAt: lastSyncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncedAt),
    );
  }

  factory HealthSyncStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HealthSyncStateRow(
      platform: serializer.fromJson<String>(json['platform']),
      anchor: serializer.fromJson<String?>(json['anchor']),
      lastSyncedAt: serializer.fromJson<DateTime?>(json['lastSyncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'platform': serializer.toJson<String>(platform),
      'anchor': serializer.toJson<String?>(anchor),
      'lastSyncedAt': serializer.toJson<DateTime?>(lastSyncedAt),
    };
  }

  HealthSyncStateRow copyWith({
    String? platform,
    Value<String?> anchor = const Value.absent(),
    Value<DateTime?> lastSyncedAt = const Value.absent(),
  }) => HealthSyncStateRow(
    platform: platform ?? this.platform,
    anchor: anchor.present ? anchor.value : this.anchor,
    lastSyncedAt: lastSyncedAt.present ? lastSyncedAt.value : this.lastSyncedAt,
  );
  HealthSyncStateRow copyWithCompanion(HealthSyncStateCompanion data) {
    return HealthSyncStateRow(
      platform: data.platform.present ? data.platform.value : this.platform,
      anchor: data.anchor.present ? data.anchor.value : this.anchor,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HealthSyncStateRow(')
          ..write('platform: $platform, ')
          ..write('anchor: $anchor, ')
          ..write('lastSyncedAt: $lastSyncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(platform, anchor, lastSyncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HealthSyncStateRow &&
          other.platform == this.platform &&
          other.anchor == this.anchor &&
          other.lastSyncedAt == this.lastSyncedAt);
}

class HealthSyncStateCompanion extends UpdateCompanion<HealthSyncStateRow> {
  final Value<String> platform;
  final Value<String?> anchor;
  final Value<DateTime?> lastSyncedAt;
  final Value<int> rowid;
  const HealthSyncStateCompanion({
    this.platform = const Value.absent(),
    this.anchor = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HealthSyncStateCompanion.insert({
    required String platform,
    this.anchor = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : platform = Value(platform);
  static Insertable<HealthSyncStateRow> custom({
    Expression<String>? platform,
    Expression<String>? anchor,
    Expression<DateTime>? lastSyncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (platform != null) 'platform': platform,
      if (anchor != null) 'anchor': anchor,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HealthSyncStateCompanion copyWith({
    Value<String>? platform,
    Value<String?>? anchor,
    Value<DateTime?>? lastSyncedAt,
    Value<int>? rowid,
  }) {
    return HealthSyncStateCompanion(
      platform: platform ?? this.platform,
      anchor: anchor ?? this.anchor,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (platform.present) {
      map['platform'] = Variable<String>(platform.value);
    }
    if (anchor.present) {
      map['anchor'] = Variable<String>(anchor.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HealthSyncStateCompanion(')
          ..write('platform: $platform, ')
          ..write('anchor: $anchor, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LunarLogDatabase extends GeneratedDatabase {
  _$LunarLogDatabase(QueryExecutor e) : super(e);
  $LunarLogDatabaseManager get managers => $LunarLogDatabaseManager(this);
  late final $ProfilesTable profiles = $ProfilesTable(this);
  late final $DayEntriesTable dayEntries = $DayEntriesTable(this);
  late final $ProfileGuardiansTable profileGuardians = $ProfileGuardiansTable(
    this,
  );
  late final $ObservationsTable observations = $ObservationsTable(this);
  late final $ProfileModesTable profileModes = $ProfileModesTable(this);
  late final $CycleOverridesTable cycleOverrides = $CycleOverridesTable(this);
  late final $CareNotesTable careNotes = $CareNotesTable(this);
  late final $VisitPrepItemsTable visitPrepItems = $VisitPrepItemsTable(this);
  late final $DayEntryMergeEventsTable dayEntryMergeEvents =
      $DayEntryMergeEventsTable(this);
  late final $ProfileTagRegistryTable profileTagRegistry =
      $ProfileTagRegistryTable(this);
  late final $DayEntryHistoryTable dayEntryHistory = $DayEntryHistoryTable(
    this,
  );
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $SyncStateTable syncState = $SyncStateTable(this);
  late final $HealthSyncStateTable healthSyncState = $HealthSyncStateTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    profiles,
    dayEntries,
    profileGuardians,
    observations,
    profileModes,
    cycleOverrides,
    careNotes,
    visitPrepItems,
    dayEntryMergeEvents,
    profileTagRegistry,
    dayEntryHistory,
    appSettings,
    syncState,
    healthSyncState,
  ];
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$ProfilesTableCreateCompanionBuilder = ProfilesCompanion Function({
  required String id,
  required String displayName,
  required bool isMinor,
  Value<int> sortOrder,
  Value<DateTime?> archivedAt,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<DateTime?> deletedAt,
  Value<bool> dirty,
  Value<int> localRev,
  Value<int?> birthYear,
  Value<String?> relationship,
  Value<String> mode,
  Value<DateTime?> transferredAt,
  Value<String?> transferredToUserId,
  Value<String?> lastPeriodStart,
  Value<int?> typicalCycleLengthDays,
  Value<int?> typicalPeriodLengthDays,
  Value<String?> trackingPreferences,
  Value<String> bbtUnit,
  Value<String> weightUnit,
  Value<DateTime?> accessRevokedAt,
  Value<bool?> unitsUnconfirmed,
  Value<int> rowid,
});
typedef $$ProfilesTableUpdateCompanionBuilder = ProfilesCompanion Function({
  Value<String> id,
  Value<String> displayName,
  Value<bool> isMinor,
  Value<int> sortOrder,
  Value<DateTime?> archivedAt,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<bool> dirty,
  Value<int> localRev,
  Value<int?> birthYear,
  Value<String?> relationship,
  Value<String> mode,
  Value<DateTime?> transferredAt,
  Value<String?> transferredToUserId,
  Value<String?> lastPeriodStart,
  Value<int?> typicalCycleLengthDays,
  Value<int?> typicalPeriodLengthDays,
  Value<String?> trackingPreferences,
  Value<String> bbtUnit,
  Value<String> weightUnit,
  Value<DateTime?> accessRevokedAt,
  Value<bool?> unitsUnconfirmed,
  Value<int> rowid,
});

final class $$ProfilesTableReferences
    extends BaseReferences<_$LunarLogDatabase, $ProfilesTable, Profile> {
  $$ProfilesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$DayEntriesTable, List<DayEntry>>
  _dayEntriesRefsTable(_$LunarLogDatabase db) => MultiTypedResultKey.fromTable(
    db.dayEntries,
    aliasName: 'profiles__id__day_entries__profile_id',
  );

  $$DayEntriesTableProcessedTableManager get dayEntriesRefs {
    final manager = $$DayEntriesTableTableManager(
      $_db,
      $_db.dayEntries,
    ).filter((f) => f.profileId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_dayEntriesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ProfileGuardiansTable, List<ProfileGuardianData>>
  _profileGuardiansRefsTable(_$LunarLogDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.profileGuardians,
        aliasName: 'profiles__id__profile_guardians__profile_id',
      );

  $$ProfileGuardiansTableProcessedTableManager get profileGuardiansRefs {
    final manager = $$ProfileGuardiansTableTableManager(
      $_db,
      $_db.profileGuardians,
    ).filter((f) => f.profileId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _profileGuardiansRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ObservationsTable, List<Observation>>
  _observationsRefsTable(_$LunarLogDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.observations,
        aliasName: 'profiles__id__observations__profile_id',
      );

  $$ObservationsTableProcessedTableManager get observationsRefs {
    final manager = $$ObservationsTableTableManager(
      $_db,
      $_db.observations,
    ).filter((f) => f.profileId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_observationsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ProfileModesTable, List<ProfileModeData>>
  _profileModesRefsTable(_$LunarLogDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.profileModes,
        aliasName: 'profiles__id__profile_modes__profile_id',
      );

  $$ProfileModesTableProcessedTableManager get profileModesRefs {
    final manager = $$ProfileModesTableTableManager(
      $_db,
      $_db.profileModes,
    ).filter((f) => f.profileId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_profileModesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CycleOverridesTable, List<CycleOverrideData>>
  _cycleOverridesRefsTable(_$LunarLogDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.cycleOverrides,
        aliasName: 'profiles__id__cycle_overrides__profile_id',
      );

  $$CycleOverridesTableProcessedTableManager get cycleOverridesRefs {
    final manager = $$CycleOverridesTableTableManager(
      $_db,
      $_db.cycleOverrides,
    ).filter((f) => f.profileId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_cycleOverridesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CareNotesTable, List<CareNoteData>>
  _careNotesRefsTable(_$LunarLogDatabase db) => MultiTypedResultKey.fromTable(
    db.careNotes,
    aliasName: 'profiles__id__care_notes__profile_id',
  );

  $$CareNotesTableProcessedTableManager get careNotesRefs {
    final manager = $$CareNotesTableTableManager(
      $_db,
      $_db.careNotes,
    ).filter((f) => f.profileId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_careNotesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$VisitPrepItemsTable, List<VisitPrepItemData>>
  _visitPrepItemsRefsTable(_$LunarLogDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.visitPrepItems,
        aliasName: 'profiles__id__visit_prep_items__profile_id',
      );

  $$VisitPrepItemsTableProcessedTableManager get visitPrepItemsRefs {
    final manager = $$VisitPrepItemsTableTableManager(
      $_db,
      $_db.visitPrepItems,
    ).filter((f) => f.profileId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_visitPrepItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $DayEntryMergeEventsTable,
    List<DayEntryMergeEventData>
  >
  _dayEntryMergeEventsRefsTable(_$LunarLogDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.dayEntryMergeEvents,
        aliasName: 'profiles__id__day_entry_merge_events__profile_id',
      );

  $$DayEntryMergeEventsTableProcessedTableManager get dayEntryMergeEventsRefs {
    final manager = $$DayEntryMergeEventsTableTableManager(
      $_db,
      $_db.dayEntryMergeEvents,
    ).filter((f) => f.profileId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _dayEntryMergeEventsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $ProfileTagRegistryTable,
    List<ProfileTagRegistryEntry>
  >
  _profileTagRegistryRefsTable(_$LunarLogDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.profileTagRegistry,
        aliasName: 'profiles__id__profile_tag_registry__profile_id',
      );

  $$ProfileTagRegistryTableProcessedTableManager get profileTagRegistryRefs {
    final manager = $$ProfileTagRegistryTableTableManager(
      $_db,
      $_db.profileTagRegistry,
    ).filter((f) => f.profileId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _profileTagRegistryRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$DayEntryHistoryTable, List<DayEntryHistoryData>>
  _dayEntryHistoryRefsTable(_$LunarLogDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.dayEntryHistory,
        aliasName: 'profiles__id__day_entry_history__profile_id',
      );

  $$DayEntryHistoryTableProcessedTableManager get dayEntryHistoryRefs {
    final manager = $$DayEntryHistoryTableTableManager(
      $_db,
      $_db.dayEntryHistory,
    ).filter((f) => f.profileId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _dayEntryHistoryRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ProfilesTableFilterComposer
    extends Composer<_$LunarLogDatabase, $ProfilesTable> {
  $$ProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isMinor => $composableBuilder(
    column: $table.isMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localRev => $composableBuilder(
    column: $table.localRev,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get birthYear => $composableBuilder(
    column: $table.birthYear,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relationship => $composableBuilder(
    column: $table.relationship,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get transferredAt => $composableBuilder(
    column: $table.transferredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transferredToUserId => $composableBuilder(
    column: $table.transferredToUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastPeriodStart => $composableBuilder(
    column: $table.lastPeriodStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get typicalCycleLengthDays => $composableBuilder(
    column: $table.typicalCycleLengthDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get typicalPeriodLengthDays => $composableBuilder(
    column: $table.typicalPeriodLengthDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackingPreferences => $composableBuilder(
    column: $table.trackingPreferences,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bbtUnit => $composableBuilder(
    column: $table.bbtUnit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get weightUnit => $composableBuilder(
    column: $table.weightUnit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get accessRevokedAt => $composableBuilder(
    column: $table.accessRevokedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get unitsUnconfirmed => $composableBuilder(
    column: $table.unitsUnconfirmed,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> dayEntriesRefs(
    Expression<bool> Function($$DayEntriesTableFilterComposer f) f,
  ) {
    final $$DayEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.dayEntries,
      getReferencedColumn: (t) => t.profileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DayEntriesTableFilterComposer(
            $db: $db,
            $table: $db.dayEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> profileGuardiansRefs(
    Expression<bool> Function($$ProfileGuardiansTableFilterComposer f) f,
  ) {
    final $$ProfileGuardiansTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.profileGuardians,
      getReferencedColumn: (t) => t.profileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfileGuardiansTableFilterComposer(
            $db: $db,
            $table: $db.profileGuardians,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> observationsRefs(
    Expression<bool> Function($$ObservationsTableFilterComposer f) f,
  ) {
    final $$ObservationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.observations,
      getReferencedColumn: (t) => t.profileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObservationsTableFilterComposer(
            $db: $db,
            $table: $db.observations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> profileModesRefs(
    Expression<bool> Function($$ProfileModesTableFilterComposer f) f,
  ) {
    final $$ProfileModesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.profileModes,
      getReferencedColumn: (t) => t.profileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfileModesTableFilterComposer(
            $db: $db,
            $table: $db.profileModes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> cycleOverridesRefs(
    Expression<bool> Function($$CycleOverridesTableFilterComposer f) f,
  ) {
    final $$CycleOverridesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.cycleOverrides,
      getReferencedColumn: (t) => t.profileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CycleOverridesTableFilterComposer(
            $db: $db,
            $table: $db.cycleOverrides,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> careNotesRefs(
    Expression<bool> Function($$CareNotesTableFilterComposer f) f,
  ) {
    final $$CareNotesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.careNotes,
      getReferencedColumn: (t) => t.profileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CareNotesTableFilterComposer(
            $db: $db,
            $table: $db.careNotes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> visitPrepItemsRefs(
    Expression<bool> Function($$VisitPrepItemsTableFilterComposer f) f,
  ) {
    final $$VisitPrepItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.visitPrepItems,
      getReferencedColumn: (t) => t.profileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VisitPrepItemsTableFilterComposer(
            $db: $db,
            $table: $db.visitPrepItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> dayEntryMergeEventsRefs(
    Expression<bool> Function($$DayEntryMergeEventsTableFilterComposer f) f,
  ) {
    final $$DayEntryMergeEventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.dayEntryMergeEvents,
      getReferencedColumn: (t) => t.profileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DayEntryMergeEventsTableFilterComposer(
            $db: $db,
            $table: $db.dayEntryMergeEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> profileTagRegistryRefs(
    Expression<bool> Function($$ProfileTagRegistryTableFilterComposer f) f,
  ) {
    final $$ProfileTagRegistryTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.profileTagRegistry,
      getReferencedColumn: (t) => t.profileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfileTagRegistryTableFilterComposer(
            $db: $db,
            $table: $db.profileTagRegistry,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> dayEntryHistoryRefs(
    Expression<bool> Function($$DayEntryHistoryTableFilterComposer f) f,
  ) {
    final $$DayEntryHistoryTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.dayEntryHistory,
      getReferencedColumn: (t) => t.profileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DayEntryHistoryTableFilterComposer(
            $db: $db,
            $table: $db.dayEntryHistory,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProfilesTableOrderingComposer
    extends Composer<_$LunarLogDatabase, $ProfilesTable> {
  $$ProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isMinor => $composableBuilder(
    column: $table.isMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localRev => $composableBuilder(
    column: $table.localRev,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get birthYear => $composableBuilder(
    column: $table.birthYear,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relationship => $composableBuilder(
    column: $table.relationship,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get transferredAt => $composableBuilder(
    column: $table.transferredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transferredToUserId => $composableBuilder(
    column: $table.transferredToUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastPeriodStart => $composableBuilder(
    column: $table.lastPeriodStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get typicalCycleLengthDays => $composableBuilder(
    column: $table.typicalCycleLengthDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get typicalPeriodLengthDays => $composableBuilder(
    column: $table.typicalPeriodLengthDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackingPreferences => $composableBuilder(
    column: $table.trackingPreferences,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bbtUnit => $composableBuilder(
    column: $table.bbtUnit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get weightUnit => $composableBuilder(
    column: $table.weightUnit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get accessRevokedAt => $composableBuilder(
    column: $table.accessRevokedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get unitsUnconfirmed => $composableBuilder(
    column: $table.unitsUnconfirmed,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProfilesTableAnnotationComposer
    extends Composer<_$LunarLogDatabase, $ProfilesTable> {
  $$ProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isMinor =>
      $composableBuilder(column: $table.isMinor, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<int> get localRev =>
      $composableBuilder(column: $table.localRev, builder: (column) => column);

  GeneratedColumn<int> get birthYear =>
      $composableBuilder(column: $table.birthYear, builder: (column) => column);

  GeneratedColumn<String> get relationship => $composableBuilder(
    column: $table.relationship,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<DateTime> get transferredAt => $composableBuilder(
    column: $table.transferredAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get transferredToUserId => $composableBuilder(
    column: $table.transferredToUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastPeriodStart => $composableBuilder(
    column: $table.lastPeriodStart,
    builder: (column) => column,
  );

  GeneratedColumn<int> get typicalCycleLengthDays => $composableBuilder(
    column: $table.typicalCycleLengthDays,
    builder: (column) => column,
  );

  GeneratedColumn<int> get typicalPeriodLengthDays => $composableBuilder(
    column: $table.typicalPeriodLengthDays,
    builder: (column) => column,
  );

  GeneratedColumn<String> get trackingPreferences => $composableBuilder(
    column: $table.trackingPreferences,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bbtUnit =>
      $composableBuilder(column: $table.bbtUnit, builder: (column) => column);

  GeneratedColumn<String> get weightUnit => $composableBuilder(
    column: $table.weightUnit,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get accessRevokedAt => $composableBuilder(
    column: $table.accessRevokedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get unitsUnconfirmed => $composableBuilder(
    column: $table.unitsUnconfirmed,
    builder: (column) => column,
  );

  Expression<T> dayEntriesRefs<T extends Object>(
    Expression<T> Function($$DayEntriesTableAnnotationComposer a) f,
  ) {
    final $$DayEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.dayEntries,
      getReferencedColumn: (t) => t.profileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DayEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.dayEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> profileGuardiansRefs<T extends Object>(
    Expression<T> Function($$ProfileGuardiansTableAnnotationComposer a) f,
  ) {
    final $$ProfileGuardiansTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.profileGuardians,
      getReferencedColumn: (t) => t.profileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfileGuardiansTableAnnotationComposer(
            $db: $db,
            $table: $db.profileGuardians,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> observationsRefs<T extends Object>(
    Expression<T> Function($$ObservationsTableAnnotationComposer a) f,
  ) {
    final $$ObservationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.observations,
      getReferencedColumn: (t) => t.profileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObservationsTableAnnotationComposer(
            $db: $db,
            $table: $db.observations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> profileModesRefs<T extends Object>(
    Expression<T> Function($$ProfileModesTableAnnotationComposer a) f,
  ) {
    final $$ProfileModesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.profileModes,
      getReferencedColumn: (t) => t.profileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfileModesTableAnnotationComposer(
            $db: $db,
            $table: $db.profileModes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> cycleOverridesRefs<T extends Object>(
    Expression<T> Function($$CycleOverridesTableAnnotationComposer a) f,
  ) {
    final $$CycleOverridesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.cycleOverrides,
      getReferencedColumn: (t) => t.profileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CycleOverridesTableAnnotationComposer(
            $db: $db,
            $table: $db.cycleOverrides,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> careNotesRefs<T extends Object>(
    Expression<T> Function($$CareNotesTableAnnotationComposer a) f,
  ) {
    final $$CareNotesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.careNotes,
      getReferencedColumn: (t) => t.profileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CareNotesTableAnnotationComposer(
            $db: $db,
            $table: $db.careNotes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> visitPrepItemsRefs<T extends Object>(
    Expression<T> Function($$VisitPrepItemsTableAnnotationComposer a) f,
  ) {
    final $$VisitPrepItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.visitPrepItems,
      getReferencedColumn: (t) => t.profileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VisitPrepItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.visitPrepItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> dayEntryMergeEventsRefs<T extends Object>(
    Expression<T> Function($$DayEntryMergeEventsTableAnnotationComposer a) f,
  ) {
    final $$DayEntryMergeEventsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.dayEntryMergeEvents,
          getReferencedColumn: (t) => t.profileId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DayEntryMergeEventsTableAnnotationComposer(
                $db: $db,
                $table: $db.dayEntryMergeEvents,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> profileTagRegistryRefs<T extends Object>(
    Expression<T> Function($$ProfileTagRegistryTableAnnotationComposer a) f,
  ) {
    final $$ProfileTagRegistryTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.profileTagRegistry,
          getReferencedColumn: (t) => t.profileId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ProfileTagRegistryTableAnnotationComposer(
                $db: $db,
                $table: $db.profileTagRegistry,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> dayEntryHistoryRefs<T extends Object>(
    Expression<T> Function($$DayEntryHistoryTableAnnotationComposer a) f,
  ) {
    final $$DayEntryHistoryTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.dayEntryHistory,
      getReferencedColumn: (t) => t.profileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DayEntryHistoryTableAnnotationComposer(
            $db: $db,
            $table: $db.dayEntryHistory,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProfilesTableTableManager
    extends
        RootTableManager<
          _$LunarLogDatabase,
          $ProfilesTable,
          Profile,
          $$ProfilesTableFilterComposer,
          $$ProfilesTableOrderingComposer,
          $$ProfilesTableAnnotationComposer,
          $$ProfilesTableCreateCompanionBuilder,
          $$ProfilesTableUpdateCompanionBuilder,
          (Profile, $$ProfilesTableReferences),
          Profile,
          PrefetchHooks Function({
            bool dayEntriesRefs,
            bool profileGuardiansRefs,
            bool observationsRefs,
            bool profileModesRefs,
            bool cycleOverridesRefs,
            bool careNotesRefs,
            bool visitPrepItemsRefs,
            bool dayEntryMergeEventsRefs,
            bool profileTagRegistryRefs,
            bool dayEntryHistoryRefs,
          })
        > {
  $$ProfilesTableTableManager(_$LunarLogDatabase db, $ProfilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<bool> isMinor = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> localRev = const Value.absent(),
                Value<int?> birthYear = const Value.absent(),
                Value<String?> relationship = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<DateTime?> transferredAt = const Value.absent(),
                Value<String?> transferredToUserId = const Value.absent(),
                Value<String?> lastPeriodStart = const Value.absent(),
                Value<int?> typicalCycleLengthDays = const Value.absent(),
                Value<int?> typicalPeriodLengthDays = const Value.absent(),
                Value<String?> trackingPreferences = const Value.absent(),
                Value<String> bbtUnit = const Value.absent(),
                Value<String> weightUnit = const Value.absent(),
                Value<DateTime?> accessRevokedAt = const Value.absent(),
                Value<bool?> unitsUnconfirmed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProfilesCompanion(
                id: id,
                displayName: displayName,
                isMinor: isMinor,
                sortOrder: sortOrder,
                archivedAt: archivedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                dirty: dirty,
                localRev: localRev,
                birthYear: birthYear,
                relationship: relationship,
                mode: mode,
                transferredAt: transferredAt,
                transferredToUserId: transferredToUserId,
                lastPeriodStart: lastPeriodStart,
                typicalCycleLengthDays: typicalCycleLengthDays,
                typicalPeriodLengthDays: typicalPeriodLengthDays,
                trackingPreferences: trackingPreferences,
                bbtUnit: bbtUnit,
                weightUnit: weightUnit,
                accessRevokedAt: accessRevokedAt,
                unitsUnconfirmed: unitsUnconfirmed,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String displayName,
                required bool isMinor,
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> localRev = const Value.absent(),
                Value<int?> birthYear = const Value.absent(),
                Value<String?> relationship = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<DateTime?> transferredAt = const Value.absent(),
                Value<String?> transferredToUserId = const Value.absent(),
                Value<String?> lastPeriodStart = const Value.absent(),
                Value<int?> typicalCycleLengthDays = const Value.absent(),
                Value<int?> typicalPeriodLengthDays = const Value.absent(),
                Value<String?> trackingPreferences = const Value.absent(),
                Value<String> bbtUnit = const Value.absent(),
                Value<String> weightUnit = const Value.absent(),
                Value<DateTime?> accessRevokedAt = const Value.absent(),
                Value<bool?> unitsUnconfirmed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProfilesCompanion.insert(
                id: id,
                displayName: displayName,
                isMinor: isMinor,
                sortOrder: sortOrder,
                archivedAt: archivedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                dirty: dirty,
                localRev: localRev,
                birthYear: birthYear,
                relationship: relationship,
                mode: mode,
                transferredAt: transferredAt,
                transferredToUserId: transferredToUserId,
                lastPeriodStart: lastPeriodStart,
                typicalCycleLengthDays: typicalCycleLengthDays,
                typicalPeriodLengthDays: typicalPeriodLengthDays,
                trackingPreferences: trackingPreferences,
                bbtUnit: bbtUnit,
                weightUnit: weightUnit,
                accessRevokedAt: accessRevokedAt,
                unitsUnconfirmed: unitsUnconfirmed,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProfilesTable, Profile>(table),
                  $$ProfilesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                dayEntriesRefs = false,
                profileGuardiansRefs = false,
                observationsRefs = false,
                profileModesRefs = false,
                cycleOverridesRefs = false,
                careNotesRefs = false,
                visitPrepItemsRefs = false,
                dayEntryMergeEventsRefs = false,
                profileTagRegistryRefs = false,
                dayEntryHistoryRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (dayEntriesRefs) db.dayEntries,
                    if (profileGuardiansRefs) db.profileGuardians,
                    if (observationsRefs) db.observations,
                    if (profileModesRefs) db.profileModes,
                    if (cycleOverridesRefs) db.cycleOverrides,
                    if (careNotesRefs) db.careNotes,
                    if (visitPrepItemsRefs) db.visitPrepItems,
                    if (dayEntryMergeEventsRefs) db.dayEntryMergeEvents,
                    if (profileTagRegistryRefs) db.profileTagRegistry,
                    if (dayEntryHistoryRefs) db.dayEntryHistory,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (dayEntriesRefs)
                        await $_getPrefetchedData<
                          Profile,
                          $ProfilesTable,
                          DayEntry
                        >(
                          currentTable: table,
                          referencedTable: $$ProfilesTableReferences
                              ._dayEntriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProfilesTableReferences(
                                db,
                                table,
                                p0,
                              ).dayEntriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.profileId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (profileGuardiansRefs)
                        await $_getPrefetchedData<
                          Profile,
                          $ProfilesTable,
                          ProfileGuardianData
                        >(
                          currentTable: table,
                          referencedTable: $$ProfilesTableReferences
                              ._profileGuardiansRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProfilesTableReferences(
                                db,
                                table,
                                p0,
                              ).profileGuardiansRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.profileId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (observationsRefs)
                        await $_getPrefetchedData<
                          Profile,
                          $ProfilesTable,
                          Observation
                        >(
                          currentTable: table,
                          referencedTable: $$ProfilesTableReferences
                              ._observationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProfilesTableReferences(
                                db,
                                table,
                                p0,
                              ).observationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.profileId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (profileModesRefs)
                        await $_getPrefetchedData<
                          Profile,
                          $ProfilesTable,
                          ProfileModeData
                        >(
                          currentTable: table,
                          referencedTable: $$ProfilesTableReferences
                              ._profileModesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProfilesTableReferences(
                                db,
                                table,
                                p0,
                              ).profileModesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.profileId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (cycleOverridesRefs)
                        await $_getPrefetchedData<
                          Profile,
                          $ProfilesTable,
                          CycleOverrideData
                        >(
                          currentTable: table,
                          referencedTable: $$ProfilesTableReferences
                              ._cycleOverridesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProfilesTableReferences(
                                db,
                                table,
                                p0,
                              ).cycleOverridesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.profileId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (careNotesRefs)
                        await $_getPrefetchedData<
                          Profile,
                          $ProfilesTable,
                          CareNoteData
                        >(
                          currentTable: table,
                          referencedTable: $$ProfilesTableReferences
                              ._careNotesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProfilesTableReferences(
                                db,
                                table,
                                p0,
                              ).careNotesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.profileId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (visitPrepItemsRefs)
                        await $_getPrefetchedData<
                          Profile,
                          $ProfilesTable,
                          VisitPrepItemData
                        >(
                          currentTable: table,
                          referencedTable: $$ProfilesTableReferences
                              ._visitPrepItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProfilesTableReferences(
                                db,
                                table,
                                p0,
                              ).visitPrepItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.profileId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (dayEntryMergeEventsRefs)
                        await $_getPrefetchedData<
                          Profile,
                          $ProfilesTable,
                          DayEntryMergeEventData
                        >(
                          currentTable: table,
                          referencedTable: $$ProfilesTableReferences
                              ._dayEntryMergeEventsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProfilesTableReferences(
                                db,
                                table,
                                p0,
                              ).dayEntryMergeEventsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.profileId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (profileTagRegistryRefs)
                        await $_getPrefetchedData<
                          Profile,
                          $ProfilesTable,
                          ProfileTagRegistryEntry
                        >(
                          currentTable: table,
                          referencedTable: $$ProfilesTableReferences
                              ._profileTagRegistryRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProfilesTableReferences(
                                db,
                                table,
                                p0,
                              ).profileTagRegistryRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.profileId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (dayEntryHistoryRefs)
                        await $_getPrefetchedData<
                          Profile,
                          $ProfilesTable,
                          DayEntryHistoryData
                        >(
                          currentTable: table,
                          referencedTable: $$ProfilesTableReferences
                              ._dayEntryHistoryRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProfilesTableReferences(
                                db,
                                table,
                                p0,
                              ).dayEntryHistoryRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.profileId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$LunarLogDatabase,
      $ProfilesTable,
      Profile,
      $$ProfilesTableFilterComposer,
      $$ProfilesTableOrderingComposer,
      $$ProfilesTableAnnotationComposer,
      $$ProfilesTableCreateCompanionBuilder,
      $$ProfilesTableUpdateCompanionBuilder,
      (Profile, $$ProfilesTableReferences),
      Profile,
      PrefetchHooks Function({
        bool dayEntriesRefs,
        bool profileGuardiansRefs,
        bool observationsRefs,
        bool profileModesRefs,
        bool cycleOverridesRefs,
        bool careNotesRefs,
        bool visitPrepItemsRefs,
        bool dayEntryMergeEventsRefs,
        bool profileTagRegistryRefs,
        bool dayEntryHistoryRefs,
      })
    >;
typedef $$DayEntriesTableCreateCompanionBuilder = DayEntriesCompanion Function({
  required String id,
  required String profileId,
  required String localDate,
  required String tz,
  required FlowLevel flow,
  Value<List<String>> tags,
  Value<String?> note,
  Value<bool> pms,
  Value<bool?> pmsUnconfirmed,
  required DateTime updatedAt,
  Value<DateTime?> deletedAt,
  Value<bool> dirty,
  Value<int> localRev,
  Value<String?> loggedByUserId,
  Value<String?> lastModifiedByUserId,
  Value<String> source,
  Value<String?> sourceId,
  Value<String?> importId,
  Value<int> rowid,
});
typedef $$DayEntriesTableUpdateCompanionBuilder = DayEntriesCompanion Function({
  Value<String> id,
  Value<String> profileId,
  Value<String> localDate,
  Value<String> tz,
  Value<FlowLevel> flow,
  Value<List<String>> tags,
  Value<String?> note,
  Value<bool> pms,
  Value<bool?> pmsUnconfirmed,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<bool> dirty,
  Value<int> localRev,
  Value<String?> loggedByUserId,
  Value<String?> lastModifiedByUserId,
  Value<String> source,
  Value<String?> sourceId,
  Value<String?> importId,
  Value<int> rowid,
});

final class $$DayEntriesTableReferences
    extends BaseReferences<_$LunarLogDatabase, $DayEntriesTable, DayEntry> {
  $$DayEntriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ProfilesTable _profileIdTable(_$LunarLogDatabase db) =>
      db.profiles.createAlias('day_entries__profile_id__profiles__id');

  $$ProfilesTableProcessedTableManager get profileId {
    final $_column = $_itemColumn<String>('profile_id')!;

    final manager = $$ProfilesTableTableManager(
      $_db,
      $_db.profiles,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_profileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ObservationsTable, List<Observation>>
  _observationsRefsTable(_$LunarLogDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.observations,
        aliasName: 'day_entries__id__observations__day_entry_id',
      );

  $$ObservationsTableProcessedTableManager get observationsRefs {
    final manager = $$ObservationsTableTableManager(
      $_db,
      $_db.observations,
    ).filter((f) => f.dayEntryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_observationsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$DayEntriesTableFilterComposer
    extends Composer<_$LunarLogDatabase, $DayEntriesTable> {
  $$DayEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tz => $composableBuilder(
    column: $table.tz,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<FlowLevel, FlowLevel, String> get flow =>
      $composableBuilder(
        column: $table.flow,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String> get tags =>
      $composableBuilder(
        column: $table.tags,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pms => $composableBuilder(
    column: $table.pms,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pmsUnconfirmed => $composableBuilder(
    column: $table.pmsUnconfirmed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localRev => $composableBuilder(
    column: $table.localRev,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get loggedByUserId => $composableBuilder(
    column: $table.loggedByUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastModifiedByUserId => $composableBuilder(
    column: $table.lastModifiedByUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get importId => $composableBuilder(
    column: $table.importId,
    builder: (column) => ColumnFilters(column),
  );

  $$ProfilesTableFilterComposer get profileId {
    final $$ProfilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableFilterComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> observationsRefs(
    Expression<bool> Function($$ObservationsTableFilterComposer f) f,
  ) {
    final $$ObservationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.observations,
      getReferencedColumn: (t) => t.dayEntryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObservationsTableFilterComposer(
            $db: $db,
            $table: $db.observations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DayEntriesTableOrderingComposer
    extends Composer<_$LunarLogDatabase, $DayEntriesTable> {
  $$DayEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tz => $composableBuilder(
    column: $table.tz,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get flow => $composableBuilder(
    column: $table.flow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pms => $composableBuilder(
    column: $table.pms,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pmsUnconfirmed => $composableBuilder(
    column: $table.pmsUnconfirmed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localRev => $composableBuilder(
    column: $table.localRev,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get loggedByUserId => $composableBuilder(
    column: $table.loggedByUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastModifiedByUserId => $composableBuilder(
    column: $table.lastModifiedByUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get importId => $composableBuilder(
    column: $table.importId,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProfilesTableOrderingComposer get profileId {
    final $$ProfilesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableOrderingComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DayEntriesTableAnnotationComposer
    extends Composer<_$LunarLogDatabase, $DayEntriesTable> {
  $$DayEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get localDate =>
      $composableBuilder(column: $table.localDate, builder: (column) => column);

  GeneratedColumn<String> get tz =>
      $composableBuilder(column: $table.tz, builder: (column) => column);

  GeneratedColumnWithTypeConverter<FlowLevel, String> get flow =>
      $composableBuilder(column: $table.flow, builder: (column) => column);

  GeneratedColumnWithTypeConverter<List<String>, String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<bool> get pms =>
      $composableBuilder(column: $table.pms, builder: (column) => column);

  GeneratedColumn<bool> get pmsUnconfirmed => $composableBuilder(
    column: $table.pmsUnconfirmed,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<int> get localRev =>
      $composableBuilder(column: $table.localRev, builder: (column) => column);

  GeneratedColumn<String> get loggedByUserId => $composableBuilder(
    column: $table.loggedByUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastModifiedByUserId => $composableBuilder(
    column: $table.lastModifiedByUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get importId =>
      $composableBuilder(column: $table.importId, builder: (column) => column);

  $$ProfilesTableAnnotationComposer get profileId {
    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableAnnotationComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> observationsRefs<T extends Object>(
    Expression<T> Function($$ObservationsTableAnnotationComposer a) f,
  ) {
    final $$ObservationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.observations,
      getReferencedColumn: (t) => t.dayEntryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObservationsTableAnnotationComposer(
            $db: $db,
            $table: $db.observations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DayEntriesTableTableManager
    extends
        RootTableManager<
          _$LunarLogDatabase,
          $DayEntriesTable,
          DayEntry,
          $$DayEntriesTableFilterComposer,
          $$DayEntriesTableOrderingComposer,
          $$DayEntriesTableAnnotationComposer,
          $$DayEntriesTableCreateCompanionBuilder,
          $$DayEntriesTableUpdateCompanionBuilder,
          (DayEntry, $$DayEntriesTableReferences),
          DayEntry,
          PrefetchHooks Function({bool profileId, bool observationsRefs})
        > {
  $$DayEntriesTableTableManager(_$LunarLogDatabase db, $DayEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DayEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DayEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DayEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> profileId = const Value.absent(),
                Value<String> localDate = const Value.absent(),
                Value<String> tz = const Value.absent(),
                Value<FlowLevel> flow = const Value.absent(),
                Value<List<String>> tags = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<bool> pms = const Value.absent(),
                Value<bool?> pmsUnconfirmed = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> localRev = const Value.absent(),
                Value<String?> loggedByUserId = const Value.absent(),
                Value<String?> lastModifiedByUserId = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> sourceId = const Value.absent(),
                Value<String?> importId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DayEntriesCompanion(
                id: id,
                profileId: profileId,
                localDate: localDate,
                tz: tz,
                flow: flow,
                tags: tags,
                note: note,
                pms: pms,
                pmsUnconfirmed: pmsUnconfirmed,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                dirty: dirty,
                localRev: localRev,
                loggedByUserId: loggedByUserId,
                lastModifiedByUserId: lastModifiedByUserId,
                source: source,
                sourceId: sourceId,
                importId: importId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String profileId,
                required String localDate,
                required String tz,
                required FlowLevel flow,
                Value<List<String>> tags = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<bool> pms = const Value.absent(),
                Value<bool?> pmsUnconfirmed = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> localRev = const Value.absent(),
                Value<String?> loggedByUserId = const Value.absent(),
                Value<String?> lastModifiedByUserId = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> sourceId = const Value.absent(),
                Value<String?> importId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DayEntriesCompanion.insert(
                id: id,
                profileId: profileId,
                localDate: localDate,
                tz: tz,
                flow: flow,
                tags: tags,
                note: note,
                pms: pms,
                pmsUnconfirmed: pmsUnconfirmed,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                dirty: dirty,
                localRev: localRev,
                loggedByUserId: loggedByUserId,
                lastModifiedByUserId: lastModifiedByUserId,
                source: source,
                sourceId: sourceId,
                importId: importId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DayEntriesTable, DayEntry>(table),
                  $$DayEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({profileId = false, observationsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (observationsRefs) db.observations,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (profileId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.profileId,
                            referencedTable: $$DayEntriesTableReferences
                                ._profileIdTable(db),
                            referencedColumn: $$DayEntriesTableReferences
                                ._profileIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (observationsRefs)
                        await $_getPrefetchedData<
                          DayEntry,
                          $DayEntriesTable,
                          Observation
                        >(
                          currentTable: table,
                          referencedTable: $$DayEntriesTableReferences
                              ._observationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DayEntriesTableReferences(
                                db,
                                table,
                                p0,
                              ).observationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.dayEntryId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$DayEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$LunarLogDatabase,
      $DayEntriesTable,
      DayEntry,
      $$DayEntriesTableFilterComposer,
      $$DayEntriesTableOrderingComposer,
      $$DayEntriesTableAnnotationComposer,
      $$DayEntriesTableCreateCompanionBuilder,
      $$DayEntriesTableUpdateCompanionBuilder,
      (DayEntry, $$DayEntriesTableReferences),
      DayEntry,
      PrefetchHooks Function({bool profileId, bool observationsRefs})
    >;
typedef $$ProfileGuardiansTableCreateCompanionBuilder =
    ProfileGuardiansCompanion Function({
      required String id,
      required String profileId,
      required String userId,
      required String role,
      Value<String> status,
      Value<String?> displayName,
      Value<String?> invitedBy,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> serverVersion,
      Value<int> rowid,
    });
typedef $$ProfileGuardiansTableUpdateCompanionBuilder =
    ProfileGuardiansCompanion Function({
      Value<String> id,
      Value<String> profileId,
      Value<String> userId,
      Value<String> role,
      Value<String> status,
      Value<String?> displayName,
      Value<String?> invitedBy,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> serverVersion,
      Value<int> rowid,
    });

final class $$ProfileGuardiansTableReferences
    extends
        BaseReferences<
          _$LunarLogDatabase,
          $ProfileGuardiansTable,
          ProfileGuardianData
        > {
  $$ProfileGuardiansTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ProfilesTable _profileIdTable(_$LunarLogDatabase db) =>
      db.profiles.createAlias('profile_guardians__profile_id__profiles__id');

  $$ProfilesTableProcessedTableManager get profileId {
    final $_column = $_itemColumn<String>('profile_id')!;

    final manager = $$ProfilesTableTableManager(
      $_db,
      $_db.profiles,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_profileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ProfileGuardiansTableFilterComposer
    extends Composer<_$LunarLogDatabase, $ProfileGuardiansTable> {
  $$ProfileGuardiansTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get invitedBy => $composableBuilder(
    column: $table.invitedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnFilters(column),
  );

  $$ProfilesTableFilterComposer get profileId {
    final $$ProfilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableFilterComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProfileGuardiansTableOrderingComposer
    extends Composer<_$LunarLogDatabase, $ProfileGuardiansTable> {
  $$ProfileGuardiansTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get invitedBy => $composableBuilder(
    column: $table.invitedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProfilesTableOrderingComposer get profileId {
    final $$ProfilesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableOrderingComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProfileGuardiansTableAnnotationComposer
    extends Composer<_$LunarLogDatabase, $ProfileGuardiansTable> {
  $$ProfileGuardiansTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get invitedBy =>
      $composableBuilder(column: $table.invitedBy, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => column,
  );

  $$ProfilesTableAnnotationComposer get profileId {
    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableAnnotationComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProfileGuardiansTableTableManager
    extends
        RootTableManager<
          _$LunarLogDatabase,
          $ProfileGuardiansTable,
          ProfileGuardianData,
          $$ProfileGuardiansTableFilterComposer,
          $$ProfileGuardiansTableOrderingComposer,
          $$ProfileGuardiansTableAnnotationComposer,
          $$ProfileGuardiansTableCreateCompanionBuilder,
          $$ProfileGuardiansTableUpdateCompanionBuilder,
          (ProfileGuardianData, $$ProfileGuardiansTableReferences),
          ProfileGuardianData,
          PrefetchHooks Function({bool profileId})
        > {
  $$ProfileGuardiansTableTableManager(
    _$LunarLogDatabase db,
    $ProfileGuardiansTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfileGuardiansTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProfileGuardiansTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProfileGuardiansTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> profileId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
                Value<String?> invitedBy = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProfileGuardiansCompanion(
                id: id,
                profileId: profileId,
                userId: userId,
                role: role,
                status: status,
                displayName: displayName,
                invitedBy: invitedBy,
                createdAt: createdAt,
                updatedAt: updatedAt,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String profileId,
                required String userId,
                required String role,
                Value<String> status = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
                Value<String?> invitedBy = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProfileGuardiansCompanion.insert(
                id: id,
                profileId: profileId,
                userId: userId,
                role: role,
                status: status,
                displayName: displayName,
                invitedBy: invitedBy,
                createdAt: createdAt,
                updatedAt: updatedAt,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProfileGuardiansTable, ProfileGuardianData>(
                    table,
                  ),
                  $$ProfileGuardiansTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({profileId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (profileId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.profileId,
                        referencedTable: $$ProfileGuardiansTableReferences
                            ._profileIdTable(db),
                        referencedColumn: $$ProfileGuardiansTableReferences
                            ._profileIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ProfileGuardiansTableProcessedTableManager =
    ProcessedTableManager<
      _$LunarLogDatabase,
      $ProfileGuardiansTable,
      ProfileGuardianData,
      $$ProfileGuardiansTableFilterComposer,
      $$ProfileGuardiansTableOrderingComposer,
      $$ProfileGuardiansTableAnnotationComposer,
      $$ProfileGuardiansTableCreateCompanionBuilder,
      $$ProfileGuardiansTableUpdateCompanionBuilder,
      (ProfileGuardianData, $$ProfileGuardiansTableReferences),
      ProfileGuardianData,
      PrefetchHooks Function({bool profileId})
    >;
typedef $$ObservationsTableCreateCompanionBuilder =
    ObservationsCompanion Function({
      required String id,
      required String dayEntryId,
      required String profileId,
      required String localDate,
      Value<DateTime?> observedAt,
      required String tz,
      Value<String?> category,
      Value<String?> code,
      Value<double?> valueNum,
      Value<String?> valueText,
      Value<String?> unit,
      Value<int?> intensity,
      Value<bool> excluded,
      Value<String> source,
      Value<String?> sourceId,
      Value<String?> importId,
      Value<DateTime?> exportedToPlatformAt,
      Value<String?> raw,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<bool> dirty,
      Value<int> localRev,
      Value<String?> loggedByUserId,
      Value<String?> lastModifiedByUserId,
      Value<int> rowid,
    });
typedef $$ObservationsTableUpdateCompanionBuilder =
    ObservationsCompanion Function({
      Value<String> id,
      Value<String> dayEntryId,
      Value<String> profileId,
      Value<String> localDate,
      Value<DateTime?> observedAt,
      Value<String> tz,
      Value<String?> category,
      Value<String?> code,
      Value<double?> valueNum,
      Value<String?> valueText,
      Value<String?> unit,
      Value<int?> intensity,
      Value<bool> excluded,
      Value<String> source,
      Value<String?> sourceId,
      Value<String?> importId,
      Value<DateTime?> exportedToPlatformAt,
      Value<String?> raw,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<bool> dirty,
      Value<int> localRev,
      Value<String?> loggedByUserId,
      Value<String?> lastModifiedByUserId,
      Value<int> rowid,
    });

final class $$ObservationsTableReferences
    extends
        BaseReferences<_$LunarLogDatabase, $ObservationsTable, Observation> {
  $$ObservationsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $DayEntriesTable _dayEntryIdTable(_$LunarLogDatabase db) =>
      db.dayEntries.createAlias('observations__day_entry_id__day_entries__id');

  $$DayEntriesTableProcessedTableManager get dayEntryId {
    final $_column = $_itemColumn<String>('day_entry_id')!;

    final manager = $$DayEntriesTableTableManager(
      $_db,
      $_db.dayEntries,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_dayEntryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ProfilesTable _profileIdTable(_$LunarLogDatabase db) =>
      db.profiles.createAlias('observations__profile_id__profiles__id');

  $$ProfilesTableProcessedTableManager get profileId {
    final $_column = $_itemColumn<String>('profile_id')!;

    final manager = $$ProfilesTableTableManager(
      $_db,
      $_db.profiles,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_profileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ObservationsTableFilterComposer
    extends Composer<_$LunarLogDatabase, $ObservationsTable> {
  $$ObservationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tz => $composableBuilder(
    column: $table.tz,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get valueNum => $composableBuilder(
    column: $table.valueNum,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valueText => $composableBuilder(
    column: $table.valueText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get intensity => $composableBuilder(
    column: $table.intensity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get excluded => $composableBuilder(
    column: $table.excluded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get importId => $composableBuilder(
    column: $table.importId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get exportedToPlatformAt => $composableBuilder(
    column: $table.exportedToPlatformAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get raw => $composableBuilder(
    column: $table.raw,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localRev => $composableBuilder(
    column: $table.localRev,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get loggedByUserId => $composableBuilder(
    column: $table.loggedByUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastModifiedByUserId => $composableBuilder(
    column: $table.lastModifiedByUserId,
    builder: (column) => ColumnFilters(column),
  );

  $$DayEntriesTableFilterComposer get dayEntryId {
    final $$DayEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.dayEntryId,
      referencedTable: $db.dayEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DayEntriesTableFilterComposer(
            $db: $db,
            $table: $db.dayEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProfilesTableFilterComposer get profileId {
    final $$ProfilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableFilterComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ObservationsTableOrderingComposer
    extends Composer<_$LunarLogDatabase, $ObservationsTable> {
  $$ObservationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tz => $composableBuilder(
    column: $table.tz,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get valueNum => $composableBuilder(
    column: $table.valueNum,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valueText => $composableBuilder(
    column: $table.valueText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get intensity => $composableBuilder(
    column: $table.intensity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get excluded => $composableBuilder(
    column: $table.excluded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get importId => $composableBuilder(
    column: $table.importId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get exportedToPlatformAt => $composableBuilder(
    column: $table.exportedToPlatformAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get raw => $composableBuilder(
    column: $table.raw,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localRev => $composableBuilder(
    column: $table.localRev,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get loggedByUserId => $composableBuilder(
    column: $table.loggedByUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastModifiedByUserId => $composableBuilder(
    column: $table.lastModifiedByUserId,
    builder: (column) => ColumnOrderings(column),
  );

  $$DayEntriesTableOrderingComposer get dayEntryId {
    final $$DayEntriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.dayEntryId,
      referencedTable: $db.dayEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DayEntriesTableOrderingComposer(
            $db: $db,
            $table: $db.dayEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProfilesTableOrderingComposer get profileId {
    final $$ProfilesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableOrderingComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ObservationsTableAnnotationComposer
    extends Composer<_$LunarLogDatabase, $ObservationsTable> {
  $$ObservationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get localDate =>
      $composableBuilder(column: $table.localDate, builder: (column) => column);

  GeneratedColumn<DateTime> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tz =>
      $composableBuilder(column: $table.tz, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<double> get valueNum =>
      $composableBuilder(column: $table.valueNum, builder: (column) => column);

  GeneratedColumn<String> get valueText =>
      $composableBuilder(column: $table.valueText, builder: (column) => column);

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<int> get intensity =>
      $composableBuilder(column: $table.intensity, builder: (column) => column);

  GeneratedColumn<bool> get excluded =>
      $composableBuilder(column: $table.excluded, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get importId =>
      $composableBuilder(column: $table.importId, builder: (column) => column);

  GeneratedColumn<DateTime> get exportedToPlatformAt => $composableBuilder(
    column: $table.exportedToPlatformAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get raw =>
      $composableBuilder(column: $table.raw, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<int> get localRev =>
      $composableBuilder(column: $table.localRev, builder: (column) => column);

  GeneratedColumn<String> get loggedByUserId => $composableBuilder(
    column: $table.loggedByUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastModifiedByUserId => $composableBuilder(
    column: $table.lastModifiedByUserId,
    builder: (column) => column,
  );

  $$DayEntriesTableAnnotationComposer get dayEntryId {
    final $$DayEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.dayEntryId,
      referencedTable: $db.dayEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DayEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.dayEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProfilesTableAnnotationComposer get profileId {
    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableAnnotationComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ObservationsTableTableManager
    extends
        RootTableManager<
          _$LunarLogDatabase,
          $ObservationsTable,
          Observation,
          $$ObservationsTableFilterComposer,
          $$ObservationsTableOrderingComposer,
          $$ObservationsTableAnnotationComposer,
          $$ObservationsTableCreateCompanionBuilder,
          $$ObservationsTableUpdateCompanionBuilder,
          (Observation, $$ObservationsTableReferences),
          Observation,
          PrefetchHooks Function({bool dayEntryId, bool profileId})
        > {
  $$ObservationsTableTableManager(
    _$LunarLogDatabase db,
    $ObservationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ObservationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ObservationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ObservationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> dayEntryId = const Value.absent(),
                Value<String> profileId = const Value.absent(),
                Value<String> localDate = const Value.absent(),
                Value<DateTime?> observedAt = const Value.absent(),
                Value<String> tz = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<String?> code = const Value.absent(),
                Value<double?> valueNum = const Value.absent(),
                Value<String?> valueText = const Value.absent(),
                Value<String?> unit = const Value.absent(),
                Value<int?> intensity = const Value.absent(),
                Value<bool> excluded = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> sourceId = const Value.absent(),
                Value<String?> importId = const Value.absent(),
                Value<DateTime?> exportedToPlatformAt = const Value.absent(),
                Value<String?> raw = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> localRev = const Value.absent(),
                Value<String?> loggedByUserId = const Value.absent(),
                Value<String?> lastModifiedByUserId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ObservationsCompanion(
                id: id,
                dayEntryId: dayEntryId,
                profileId: profileId,
                localDate: localDate,
                observedAt: observedAt,
                tz: tz,
                category: category,
                code: code,
                valueNum: valueNum,
                valueText: valueText,
                unit: unit,
                intensity: intensity,
                excluded: excluded,
                source: source,
                sourceId: sourceId,
                importId: importId,
                exportedToPlatformAt: exportedToPlatformAt,
                raw: raw,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                dirty: dirty,
                localRev: localRev,
                loggedByUserId: loggedByUserId,
                lastModifiedByUserId: lastModifiedByUserId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String dayEntryId,
                required String profileId,
                required String localDate,
                Value<DateTime?> observedAt = const Value.absent(),
                required String tz,
                Value<String?> category = const Value.absent(),
                Value<String?> code = const Value.absent(),
                Value<double?> valueNum = const Value.absent(),
                Value<String?> valueText = const Value.absent(),
                Value<String?> unit = const Value.absent(),
                Value<int?> intensity = const Value.absent(),
                Value<bool> excluded = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> sourceId = const Value.absent(),
                Value<String?> importId = const Value.absent(),
                Value<DateTime?> exportedToPlatformAt = const Value.absent(),
                Value<String?> raw = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> localRev = const Value.absent(),
                Value<String?> loggedByUserId = const Value.absent(),
                Value<String?> lastModifiedByUserId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ObservationsCompanion.insert(
                id: id,
                dayEntryId: dayEntryId,
                profileId: profileId,
                localDate: localDate,
                observedAt: observedAt,
                tz: tz,
                category: category,
                code: code,
                valueNum: valueNum,
                valueText: valueText,
                unit: unit,
                intensity: intensity,
                excluded: excluded,
                source: source,
                sourceId: sourceId,
                importId: importId,
                exportedToPlatformAt: exportedToPlatformAt,
                raw: raw,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                dirty: dirty,
                localRev: localRev,
                loggedByUserId: loggedByUserId,
                lastModifiedByUserId: lastModifiedByUserId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ObservationsTable, Observation>(table),
                  $$ObservationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({dayEntryId = false, profileId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (dayEntryId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.dayEntryId,
                        referencedTable: $$ObservationsTableReferences
                            ._dayEntryIdTable(db),
                        referencedColumn: $$ObservationsTableReferences
                            ._dayEntryIdTable(db)
                            .id,
                      ) as T;
                    }
                    if (profileId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.profileId,
                        referencedTable: $$ObservationsTableReferences
                            ._profileIdTable(db),
                        referencedColumn: $$ObservationsTableReferences
                            ._profileIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ObservationsTableProcessedTableManager =
    ProcessedTableManager<
      _$LunarLogDatabase,
      $ObservationsTable,
      Observation,
      $$ObservationsTableFilterComposer,
      $$ObservationsTableOrderingComposer,
      $$ObservationsTableAnnotationComposer,
      $$ObservationsTableCreateCompanionBuilder,
      $$ObservationsTableUpdateCompanionBuilder,
      (Observation, $$ObservationsTableReferences),
      Observation,
      PrefetchHooks Function({bool dayEntryId, bool profileId})
    >;
typedef $$ProfileModesTableCreateCompanionBuilder =
    ProfileModesCompanion Function({
      required String profileId,
      Value<String> mode,
      Value<String?> modeStartedOn,
      Value<String?> estimatedDueDate,
      Value<String?> birthControlMethod,
      Value<String?> birthControlStartedOn,
      Value<String?> birthControlStoppedOn,
      Value<bool> healthSyncConsent,
      required DateTime updatedAt,
      Value<bool> dirty,
      Value<int> localRev,
      Value<int> rowid,
    });
typedef $$ProfileModesTableUpdateCompanionBuilder =
    ProfileModesCompanion Function({
      Value<String> profileId,
      Value<String> mode,
      Value<String?> modeStartedOn,
      Value<String?> estimatedDueDate,
      Value<String?> birthControlMethod,
      Value<String?> birthControlStartedOn,
      Value<String?> birthControlStoppedOn,
      Value<bool> healthSyncConsent,
      Value<DateTime> updatedAt,
      Value<bool> dirty,
      Value<int> localRev,
      Value<int> rowid,
    });

final class $$ProfileModesTableReferences
    extends
        BaseReferences<
          _$LunarLogDatabase,
          $ProfileModesTable,
          ProfileModeData
        > {
  $$ProfileModesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ProfilesTable _profileIdTable(_$LunarLogDatabase db) =>
      db.profiles.createAlias('profile_modes__profile_id__profiles__id');

  $$ProfilesTableProcessedTableManager get profileId {
    final $_column = $_itemColumn<String>('profile_id')!;

    final manager = $$ProfilesTableTableManager(
      $_db,
      $_db.profiles,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_profileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ProfileModesTableFilterComposer
    extends Composer<_$LunarLogDatabase, $ProfileModesTable> {
  $$ProfileModesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modeStartedOn => $composableBuilder(
    column: $table.modeStartedOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get estimatedDueDate => $composableBuilder(
    column: $table.estimatedDueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get birthControlMethod => $composableBuilder(
    column: $table.birthControlMethod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get birthControlStartedOn => $composableBuilder(
    column: $table.birthControlStartedOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get birthControlStoppedOn => $composableBuilder(
    column: $table.birthControlStoppedOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get healthSyncConsent => $composableBuilder(
    column: $table.healthSyncConsent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localRev => $composableBuilder(
    column: $table.localRev,
    builder: (column) => ColumnFilters(column),
  );

  $$ProfilesTableFilterComposer get profileId {
    final $$ProfilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableFilterComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProfileModesTableOrderingComposer
    extends Composer<_$LunarLogDatabase, $ProfileModesTable> {
  $$ProfileModesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modeStartedOn => $composableBuilder(
    column: $table.modeStartedOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get estimatedDueDate => $composableBuilder(
    column: $table.estimatedDueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get birthControlMethod => $composableBuilder(
    column: $table.birthControlMethod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get birthControlStartedOn => $composableBuilder(
    column: $table.birthControlStartedOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get birthControlStoppedOn => $composableBuilder(
    column: $table.birthControlStoppedOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get healthSyncConsent => $composableBuilder(
    column: $table.healthSyncConsent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localRev => $composableBuilder(
    column: $table.localRev,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProfilesTableOrderingComposer get profileId {
    final $$ProfilesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableOrderingComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProfileModesTableAnnotationComposer
    extends Composer<_$LunarLogDatabase, $ProfileModesTable> {
  $$ProfileModesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get modeStartedOn => $composableBuilder(
    column: $table.modeStartedOn,
    builder: (column) => column,
  );

  GeneratedColumn<String> get estimatedDueDate => $composableBuilder(
    column: $table.estimatedDueDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get birthControlMethod => $composableBuilder(
    column: $table.birthControlMethod,
    builder: (column) => column,
  );

  GeneratedColumn<String> get birthControlStartedOn => $composableBuilder(
    column: $table.birthControlStartedOn,
    builder: (column) => column,
  );

  GeneratedColumn<String> get birthControlStoppedOn => $composableBuilder(
    column: $table.birthControlStoppedOn,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get healthSyncConsent => $composableBuilder(
    column: $table.healthSyncConsent,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<int> get localRev =>
      $composableBuilder(column: $table.localRev, builder: (column) => column);

  $$ProfilesTableAnnotationComposer get profileId {
    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableAnnotationComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProfileModesTableTableManager
    extends
        RootTableManager<
          _$LunarLogDatabase,
          $ProfileModesTable,
          ProfileModeData,
          $$ProfileModesTableFilterComposer,
          $$ProfileModesTableOrderingComposer,
          $$ProfileModesTableAnnotationComposer,
          $$ProfileModesTableCreateCompanionBuilder,
          $$ProfileModesTableUpdateCompanionBuilder,
          (ProfileModeData, $$ProfileModesTableReferences),
          ProfileModeData,
          PrefetchHooks Function({bool profileId})
        > {
  $$ProfileModesTableTableManager(
    _$LunarLogDatabase db,
    $ProfileModesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfileModesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProfileModesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProfileModesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> profileId = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<String?> modeStartedOn = const Value.absent(),
                Value<String?> estimatedDueDate = const Value.absent(),
                Value<String?> birthControlMethod = const Value.absent(),
                Value<String?> birthControlStartedOn = const Value.absent(),
                Value<String?> birthControlStoppedOn = const Value.absent(),
                Value<bool> healthSyncConsent = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> localRev = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProfileModesCompanion(
                profileId: profileId,
                mode: mode,
                modeStartedOn: modeStartedOn,
                estimatedDueDate: estimatedDueDate,
                birthControlMethod: birthControlMethod,
                birthControlStartedOn: birthControlStartedOn,
                birthControlStoppedOn: birthControlStoppedOn,
                healthSyncConsent: healthSyncConsent,
                updatedAt: updatedAt,
                dirty: dirty,
                localRev: localRev,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String profileId,
                Value<String> mode = const Value.absent(),
                Value<String?> modeStartedOn = const Value.absent(),
                Value<String?> estimatedDueDate = const Value.absent(),
                Value<String?> birthControlMethod = const Value.absent(),
                Value<String?> birthControlStartedOn = const Value.absent(),
                Value<String?> birthControlStoppedOn = const Value.absent(),
                Value<bool> healthSyncConsent = const Value.absent(),
                required DateTime updatedAt,
                Value<bool> dirty = const Value.absent(),
                Value<int> localRev = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProfileModesCompanion.insert(
                profileId: profileId,
                mode: mode,
                modeStartedOn: modeStartedOn,
                estimatedDueDate: estimatedDueDate,
                birthControlMethod: birthControlMethod,
                birthControlStartedOn: birthControlStartedOn,
                birthControlStoppedOn: birthControlStoppedOn,
                healthSyncConsent: healthSyncConsent,
                updatedAt: updatedAt,
                dirty: dirty,
                localRev: localRev,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProfileModesTable, ProfileModeData>(table),
                  $$ProfileModesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({profileId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (profileId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.profileId,
                        referencedTable: $$ProfileModesTableReferences
                            ._profileIdTable(db),
                        referencedColumn: $$ProfileModesTableReferences
                            ._profileIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ProfileModesTableProcessedTableManager =
    ProcessedTableManager<
      _$LunarLogDatabase,
      $ProfileModesTable,
      ProfileModeData,
      $$ProfileModesTableFilterComposer,
      $$ProfileModesTableOrderingComposer,
      $$ProfileModesTableAnnotationComposer,
      $$ProfileModesTableCreateCompanionBuilder,
      $$ProfileModesTableUpdateCompanionBuilder,
      (ProfileModeData, $$ProfileModesTableReferences),
      ProfileModeData,
      PrefetchHooks Function({bool profileId})
    >;
typedef $$CycleOverridesTableCreateCompanionBuilder =
    CycleOverridesCompanion Function({
      required String id,
      required String profileId,
      required String cycleStartDate,
      Value<bool> excludedFromAverage,
      Value<bool> manualStart,
      Value<String?> noteId,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<bool> dirty,
      Value<int> localRev,
      Value<int> rowid,
    });
typedef $$CycleOverridesTableUpdateCompanionBuilder =
    CycleOverridesCompanion Function({
      Value<String> id,
      Value<String> profileId,
      Value<String> cycleStartDate,
      Value<bool> excludedFromAverage,
      Value<bool> manualStart,
      Value<String?> noteId,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<bool> dirty,
      Value<int> localRev,
      Value<int> rowid,
    });

final class $$CycleOverridesTableReferences
    extends
        BaseReferences<
          _$LunarLogDatabase,
          $CycleOverridesTable,
          CycleOverrideData
        > {
  $$CycleOverridesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ProfilesTable _profileIdTable(_$LunarLogDatabase db) =>
      db.profiles.createAlias('cycle_overrides__profile_id__profiles__id');

  $$ProfilesTableProcessedTableManager get profileId {
    final $_column = $_itemColumn<String>('profile_id')!;

    final manager = $$ProfilesTableTableManager(
      $_db,
      $_db.profiles,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_profileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CycleOverridesTableFilterComposer
    extends Composer<_$LunarLogDatabase, $CycleOverridesTable> {
  $$CycleOverridesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cycleStartDate => $composableBuilder(
    column: $table.cycleStartDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get excludedFromAverage => $composableBuilder(
    column: $table.excludedFromAverage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get manualStart => $composableBuilder(
    column: $table.manualStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localRev => $composableBuilder(
    column: $table.localRev,
    builder: (column) => ColumnFilters(column),
  );

  $$ProfilesTableFilterComposer get profileId {
    final $$ProfilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableFilterComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CycleOverridesTableOrderingComposer
    extends Composer<_$LunarLogDatabase, $CycleOverridesTable> {
  $$CycleOverridesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cycleStartDate => $composableBuilder(
    column: $table.cycleStartDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get excludedFromAverage => $composableBuilder(
    column: $table.excludedFromAverage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get manualStart => $composableBuilder(
    column: $table.manualStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localRev => $composableBuilder(
    column: $table.localRev,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProfilesTableOrderingComposer get profileId {
    final $$ProfilesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableOrderingComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CycleOverridesTableAnnotationComposer
    extends Composer<_$LunarLogDatabase, $CycleOverridesTable> {
  $$CycleOverridesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cycleStartDate => $composableBuilder(
    column: $table.cycleStartDate,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get excludedFromAverage => $composableBuilder(
    column: $table.excludedFromAverage,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get manualStart => $composableBuilder(
    column: $table.manualStart,
    builder: (column) => column,
  );

  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<int> get localRev =>
      $composableBuilder(column: $table.localRev, builder: (column) => column);

  $$ProfilesTableAnnotationComposer get profileId {
    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableAnnotationComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CycleOverridesTableTableManager
    extends
        RootTableManager<
          _$LunarLogDatabase,
          $CycleOverridesTable,
          CycleOverrideData,
          $$CycleOverridesTableFilterComposer,
          $$CycleOverridesTableOrderingComposer,
          $$CycleOverridesTableAnnotationComposer,
          $$CycleOverridesTableCreateCompanionBuilder,
          $$CycleOverridesTableUpdateCompanionBuilder,
          (CycleOverrideData, $$CycleOverridesTableReferences),
          CycleOverrideData,
          PrefetchHooks Function({bool profileId})
        > {
  $$CycleOverridesTableTableManager(
    _$LunarLogDatabase db,
    $CycleOverridesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CycleOverridesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CycleOverridesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CycleOverridesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> profileId = const Value.absent(),
                Value<String> cycleStartDate = const Value.absent(),
                Value<bool> excludedFromAverage = const Value.absent(),
                Value<bool> manualStart = const Value.absent(),
                Value<String?> noteId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> localRev = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CycleOverridesCompanion(
                id: id,
                profileId: profileId,
                cycleStartDate: cycleStartDate,
                excludedFromAverage: excludedFromAverage,
                manualStart: manualStart,
                noteId: noteId,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                dirty: dirty,
                localRev: localRev,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String profileId,
                required String cycleStartDate,
                Value<bool> excludedFromAverage = const Value.absent(),
                Value<bool> manualStart = const Value.absent(),
                Value<String?> noteId = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> localRev = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CycleOverridesCompanion.insert(
                id: id,
                profileId: profileId,
                cycleStartDate: cycleStartDate,
                excludedFromAverage: excludedFromAverage,
                manualStart: manualStart,
                noteId: noteId,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                dirty: dirty,
                localRev: localRev,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CycleOverridesTable, CycleOverrideData>(table),
                  $$CycleOverridesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({profileId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (profileId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.profileId,
                        referencedTable: $$CycleOverridesTableReferences
                            ._profileIdTable(db),
                        referencedColumn: $$CycleOverridesTableReferences
                            ._profileIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CycleOverridesTableProcessedTableManager =
    ProcessedTableManager<
      _$LunarLogDatabase,
      $CycleOverridesTable,
      CycleOverrideData,
      $$CycleOverridesTableFilterComposer,
      $$CycleOverridesTableOrderingComposer,
      $$CycleOverridesTableAnnotationComposer,
      $$CycleOverridesTableCreateCompanionBuilder,
      $$CycleOverridesTableUpdateCompanionBuilder,
      (CycleOverrideData, $$CycleOverridesTableReferences),
      CycleOverrideData,
      PrefetchHooks Function({bool profileId})
    >;
typedef $$CareNotesTableCreateCompanionBuilder = CareNotesCompanion Function({
  required String id,
  required String profileId,
  required String body,
  required DateTime updatedAt,
  Value<DateTime?> deletedAt,
  Value<bool> dirty,
  Value<int> localRev,
  Value<String?> loggedByUserId,
  Value<String?> lastModifiedByUserId,
  Value<int> rowid,
});
typedef $$CareNotesTableUpdateCompanionBuilder = CareNotesCompanion Function({
  Value<String> id,
  Value<String> profileId,
  Value<String> body,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<bool> dirty,
  Value<int> localRev,
  Value<String?> loggedByUserId,
  Value<String?> lastModifiedByUserId,
  Value<int> rowid,
});

final class $$CareNotesTableReferences
    extends BaseReferences<_$LunarLogDatabase, $CareNotesTable, CareNoteData> {
  $$CareNotesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ProfilesTable _profileIdTable(_$LunarLogDatabase db) =>
      db.profiles.createAlias('care_notes__profile_id__profiles__id');

  $$ProfilesTableProcessedTableManager get profileId {
    final $_column = $_itemColumn<String>('profile_id')!;

    final manager = $$ProfilesTableTableManager(
      $_db,
      $_db.profiles,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_profileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CareNotesTableFilterComposer
    extends Composer<_$LunarLogDatabase, $CareNotesTable> {
  $$CareNotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localRev => $composableBuilder(
    column: $table.localRev,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get loggedByUserId => $composableBuilder(
    column: $table.loggedByUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastModifiedByUserId => $composableBuilder(
    column: $table.lastModifiedByUserId,
    builder: (column) => ColumnFilters(column),
  );

  $$ProfilesTableFilterComposer get profileId {
    final $$ProfilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableFilterComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CareNotesTableOrderingComposer
    extends Composer<_$LunarLogDatabase, $CareNotesTable> {
  $$CareNotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localRev => $composableBuilder(
    column: $table.localRev,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get loggedByUserId => $composableBuilder(
    column: $table.loggedByUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastModifiedByUserId => $composableBuilder(
    column: $table.lastModifiedByUserId,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProfilesTableOrderingComposer get profileId {
    final $$ProfilesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableOrderingComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CareNotesTableAnnotationComposer
    extends Composer<_$LunarLogDatabase, $CareNotesTable> {
  $$CareNotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<int> get localRev =>
      $composableBuilder(column: $table.localRev, builder: (column) => column);

  GeneratedColumn<String> get loggedByUserId => $composableBuilder(
    column: $table.loggedByUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastModifiedByUserId => $composableBuilder(
    column: $table.lastModifiedByUserId,
    builder: (column) => column,
  );

  $$ProfilesTableAnnotationComposer get profileId {
    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableAnnotationComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CareNotesTableTableManager
    extends
        RootTableManager<
          _$LunarLogDatabase,
          $CareNotesTable,
          CareNoteData,
          $$CareNotesTableFilterComposer,
          $$CareNotesTableOrderingComposer,
          $$CareNotesTableAnnotationComposer,
          $$CareNotesTableCreateCompanionBuilder,
          $$CareNotesTableUpdateCompanionBuilder,
          (CareNoteData, $$CareNotesTableReferences),
          CareNoteData,
          PrefetchHooks Function({bool profileId})
        > {
  $$CareNotesTableTableManager(_$LunarLogDatabase db, $CareNotesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CareNotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CareNotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CareNotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> profileId = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> localRev = const Value.absent(),
                Value<String?> loggedByUserId = const Value.absent(),
                Value<String?> lastModifiedByUserId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CareNotesCompanion(
                id: id,
                profileId: profileId,
                body: body,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                dirty: dirty,
                localRev: localRev,
                loggedByUserId: loggedByUserId,
                lastModifiedByUserId: lastModifiedByUserId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String profileId,
                required String body,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> localRev = const Value.absent(),
                Value<String?> loggedByUserId = const Value.absent(),
                Value<String?> lastModifiedByUserId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CareNotesCompanion.insert(
                id: id,
                profileId: profileId,
                body: body,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                dirty: dirty,
                localRev: localRev,
                loggedByUserId: loggedByUserId,
                lastModifiedByUserId: lastModifiedByUserId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CareNotesTable, CareNoteData>(table),
                  $$CareNotesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({profileId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (profileId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.profileId,
                        referencedTable: $$CareNotesTableReferences
                            ._profileIdTable(db),
                        referencedColumn: $$CareNotesTableReferences
                            ._profileIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CareNotesTableProcessedTableManager =
    ProcessedTableManager<
      _$LunarLogDatabase,
      $CareNotesTable,
      CareNoteData,
      $$CareNotesTableFilterComposer,
      $$CareNotesTableOrderingComposer,
      $$CareNotesTableAnnotationComposer,
      $$CareNotesTableCreateCompanionBuilder,
      $$CareNotesTableUpdateCompanionBuilder,
      (CareNoteData, $$CareNotesTableReferences),
      CareNoteData,
      PrefetchHooks Function({bool profileId})
    >;
typedef $$VisitPrepItemsTableCreateCompanionBuilder =
    VisitPrepItemsCompanion Function({
      required String id,
      required String profileId,
      required String body,
      Value<bool> isChecked,
      Value<String?> checkedByUserId,
      Value<DateTime?> checkedAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<bool> dirty,
      Value<int> localRev,
      Value<String?> loggedByUserId,
      Value<String?> lastModifiedByUserId,
      Value<int> rowid,
    });
typedef $$VisitPrepItemsTableUpdateCompanionBuilder =
    VisitPrepItemsCompanion Function({
      Value<String> id,
      Value<String> profileId,
      Value<String> body,
      Value<bool> isChecked,
      Value<String?> checkedByUserId,
      Value<DateTime?> checkedAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<bool> dirty,
      Value<int> localRev,
      Value<String?> loggedByUserId,
      Value<String?> lastModifiedByUserId,
      Value<int> rowid,
    });

final class $$VisitPrepItemsTableReferences
    extends
        BaseReferences<
          _$LunarLogDatabase,
          $VisitPrepItemsTable,
          VisitPrepItemData
        > {
  $$VisitPrepItemsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ProfilesTable _profileIdTable(_$LunarLogDatabase db) =>
      db.profiles.createAlias('visit_prep_items__profile_id__profiles__id');

  $$ProfilesTableProcessedTableManager get profileId {
    final $_column = $_itemColumn<String>('profile_id')!;

    final manager = $$ProfilesTableTableManager(
      $_db,
      $_db.profiles,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_profileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$VisitPrepItemsTableFilterComposer
    extends Composer<_$LunarLogDatabase, $VisitPrepItemsTable> {
  $$VisitPrepItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isChecked => $composableBuilder(
    column: $table.isChecked,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get checkedByUserId => $composableBuilder(
    column: $table.checkedByUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get checkedAt => $composableBuilder(
    column: $table.checkedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localRev => $composableBuilder(
    column: $table.localRev,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get loggedByUserId => $composableBuilder(
    column: $table.loggedByUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastModifiedByUserId => $composableBuilder(
    column: $table.lastModifiedByUserId,
    builder: (column) => ColumnFilters(column),
  );

  $$ProfilesTableFilterComposer get profileId {
    final $$ProfilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableFilterComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$VisitPrepItemsTableOrderingComposer
    extends Composer<_$LunarLogDatabase, $VisitPrepItemsTable> {
  $$VisitPrepItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isChecked => $composableBuilder(
    column: $table.isChecked,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get checkedByUserId => $composableBuilder(
    column: $table.checkedByUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get checkedAt => $composableBuilder(
    column: $table.checkedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localRev => $composableBuilder(
    column: $table.localRev,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get loggedByUserId => $composableBuilder(
    column: $table.loggedByUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastModifiedByUserId => $composableBuilder(
    column: $table.lastModifiedByUserId,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProfilesTableOrderingComposer get profileId {
    final $$ProfilesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableOrderingComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$VisitPrepItemsTableAnnotationComposer
    extends Composer<_$LunarLogDatabase, $VisitPrepItemsTable> {
  $$VisitPrepItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<bool> get isChecked =>
      $composableBuilder(column: $table.isChecked, builder: (column) => column);

  GeneratedColumn<String> get checkedByUserId => $composableBuilder(
    column: $table.checkedByUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get checkedAt =>
      $composableBuilder(column: $table.checkedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<int> get localRev =>
      $composableBuilder(column: $table.localRev, builder: (column) => column);

  GeneratedColumn<String> get loggedByUserId => $composableBuilder(
    column: $table.loggedByUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastModifiedByUserId => $composableBuilder(
    column: $table.lastModifiedByUserId,
    builder: (column) => column,
  );

  $$ProfilesTableAnnotationComposer get profileId {
    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableAnnotationComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$VisitPrepItemsTableTableManager
    extends
        RootTableManager<
          _$LunarLogDatabase,
          $VisitPrepItemsTable,
          VisitPrepItemData,
          $$VisitPrepItemsTableFilterComposer,
          $$VisitPrepItemsTableOrderingComposer,
          $$VisitPrepItemsTableAnnotationComposer,
          $$VisitPrepItemsTableCreateCompanionBuilder,
          $$VisitPrepItemsTableUpdateCompanionBuilder,
          (VisitPrepItemData, $$VisitPrepItemsTableReferences),
          VisitPrepItemData,
          PrefetchHooks Function({bool profileId})
        > {
  $$VisitPrepItemsTableTableManager(
    _$LunarLogDatabase db,
    $VisitPrepItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VisitPrepItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VisitPrepItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VisitPrepItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> profileId = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<bool> isChecked = const Value.absent(),
                Value<String?> checkedByUserId = const Value.absent(),
                Value<DateTime?> checkedAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> localRev = const Value.absent(),
                Value<String?> loggedByUserId = const Value.absent(),
                Value<String?> lastModifiedByUserId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VisitPrepItemsCompanion(
                id: id,
                profileId: profileId,
                body: body,
                isChecked: isChecked,
                checkedByUserId: checkedByUserId,
                checkedAt: checkedAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                dirty: dirty,
                localRev: localRev,
                loggedByUserId: loggedByUserId,
                lastModifiedByUserId: lastModifiedByUserId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String profileId,
                required String body,
                Value<bool> isChecked = const Value.absent(),
                Value<String?> checkedByUserId = const Value.absent(),
                Value<DateTime?> checkedAt = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> localRev = const Value.absent(),
                Value<String?> loggedByUserId = const Value.absent(),
                Value<String?> lastModifiedByUserId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VisitPrepItemsCompanion.insert(
                id: id,
                profileId: profileId,
                body: body,
                isChecked: isChecked,
                checkedByUserId: checkedByUserId,
                checkedAt: checkedAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                dirty: dirty,
                localRev: localRev,
                loggedByUserId: loggedByUserId,
                lastModifiedByUserId: lastModifiedByUserId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$VisitPrepItemsTable, VisitPrepItemData>(table),
                  $$VisitPrepItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({profileId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (profileId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.profileId,
                        referencedTable: $$VisitPrepItemsTableReferences
                            ._profileIdTable(db),
                        referencedColumn: $$VisitPrepItemsTableReferences
                            ._profileIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$VisitPrepItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$LunarLogDatabase,
      $VisitPrepItemsTable,
      VisitPrepItemData,
      $$VisitPrepItemsTableFilterComposer,
      $$VisitPrepItemsTableOrderingComposer,
      $$VisitPrepItemsTableAnnotationComposer,
      $$VisitPrepItemsTableCreateCompanionBuilder,
      $$VisitPrepItemsTableUpdateCompanionBuilder,
      (VisitPrepItemData, $$VisitPrepItemsTableReferences),
      VisitPrepItemData,
      PrefetchHooks Function({bool profileId})
    >;
typedef $$DayEntryMergeEventsTableCreateCompanionBuilder =
    DayEntryMergeEventsCompanion Function({
      required String id,
      required String profileId,
      required String localDate,
      required String winningRowId,
      required String losingRowId,
      required String field,
      required String losingValueText,
      Value<String?> losingAuthorUserId,
      Value<String?> winningAuthorUserId,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<bool> dirty,
      Value<int> localRev,
      Value<int> rowid,
    });
typedef $$DayEntryMergeEventsTableUpdateCompanionBuilder =
    DayEntryMergeEventsCompanion Function({
      Value<String> id,
      Value<String> profileId,
      Value<String> localDate,
      Value<String> winningRowId,
      Value<String> losingRowId,
      Value<String> field,
      Value<String> losingValueText,
      Value<String?> losingAuthorUserId,
      Value<String?> winningAuthorUserId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> dirty,
      Value<int> localRev,
      Value<int> rowid,
    });

final class $$DayEntryMergeEventsTableReferences
    extends
        BaseReferences<
          _$LunarLogDatabase,
          $DayEntryMergeEventsTable,
          DayEntryMergeEventData
        > {
  $$DayEntryMergeEventsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ProfilesTable _profileIdTable(_$LunarLogDatabase db) => db.profiles
      .createAlias('day_entry_merge_events__profile_id__profiles__id');

  $$ProfilesTableProcessedTableManager get profileId {
    final $_column = $_itemColumn<String>('profile_id')!;

    final manager = $$ProfilesTableTableManager(
      $_db,
      $_db.profiles,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_profileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DayEntryMergeEventsTableFilterComposer
    extends Composer<_$LunarLogDatabase, $DayEntryMergeEventsTable> {
  $$DayEntryMergeEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get winningRowId => $composableBuilder(
    column: $table.winningRowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get losingRowId => $composableBuilder(
    column: $table.losingRowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get field => $composableBuilder(
    column: $table.field,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get losingValueText => $composableBuilder(
    column: $table.losingValueText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get losingAuthorUserId => $composableBuilder(
    column: $table.losingAuthorUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get winningAuthorUserId => $composableBuilder(
    column: $table.winningAuthorUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localRev => $composableBuilder(
    column: $table.localRev,
    builder: (column) => ColumnFilters(column),
  );

  $$ProfilesTableFilterComposer get profileId {
    final $$ProfilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableFilterComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DayEntryMergeEventsTableOrderingComposer
    extends Composer<_$LunarLogDatabase, $DayEntryMergeEventsTable> {
  $$DayEntryMergeEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get winningRowId => $composableBuilder(
    column: $table.winningRowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get losingRowId => $composableBuilder(
    column: $table.losingRowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get field => $composableBuilder(
    column: $table.field,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get losingValueText => $composableBuilder(
    column: $table.losingValueText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get losingAuthorUserId => $composableBuilder(
    column: $table.losingAuthorUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get winningAuthorUserId => $composableBuilder(
    column: $table.winningAuthorUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localRev => $composableBuilder(
    column: $table.localRev,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProfilesTableOrderingComposer get profileId {
    final $$ProfilesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableOrderingComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DayEntryMergeEventsTableAnnotationComposer
    extends Composer<_$LunarLogDatabase, $DayEntryMergeEventsTable> {
  $$DayEntryMergeEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get localDate =>
      $composableBuilder(column: $table.localDate, builder: (column) => column);

  GeneratedColumn<String> get winningRowId => $composableBuilder(
    column: $table.winningRowId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get losingRowId => $composableBuilder(
    column: $table.losingRowId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get field =>
      $composableBuilder(column: $table.field, builder: (column) => column);

  GeneratedColumn<String> get losingValueText => $composableBuilder(
    column: $table.losingValueText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get losingAuthorUserId => $composableBuilder(
    column: $table.losingAuthorUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get winningAuthorUserId => $composableBuilder(
    column: $table.winningAuthorUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<int> get localRev =>
      $composableBuilder(column: $table.localRev, builder: (column) => column);

  $$ProfilesTableAnnotationComposer get profileId {
    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableAnnotationComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DayEntryMergeEventsTableTableManager
    extends
        RootTableManager<
          _$LunarLogDatabase,
          $DayEntryMergeEventsTable,
          DayEntryMergeEventData,
          $$DayEntryMergeEventsTableFilterComposer,
          $$DayEntryMergeEventsTableOrderingComposer,
          $$DayEntryMergeEventsTableAnnotationComposer,
          $$DayEntryMergeEventsTableCreateCompanionBuilder,
          $$DayEntryMergeEventsTableUpdateCompanionBuilder,
          (DayEntryMergeEventData, $$DayEntryMergeEventsTableReferences),
          DayEntryMergeEventData,
          PrefetchHooks Function({bool profileId})
        > {
  $$DayEntryMergeEventsTableTableManager(
    _$LunarLogDatabase db,
    $DayEntryMergeEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DayEntryMergeEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DayEntryMergeEventsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DayEntryMergeEventsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> profileId = const Value.absent(),
                Value<String> localDate = const Value.absent(),
                Value<String> winningRowId = const Value.absent(),
                Value<String> losingRowId = const Value.absent(),
                Value<String> field = const Value.absent(),
                Value<String> losingValueText = const Value.absent(),
                Value<String?> losingAuthorUserId = const Value.absent(),
                Value<String?> winningAuthorUserId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> localRev = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DayEntryMergeEventsCompanion(
                id: id,
                profileId: profileId,
                localDate: localDate,
                winningRowId: winningRowId,
                losingRowId: losingRowId,
                field: field,
                losingValueText: losingValueText,
                losingAuthorUserId: losingAuthorUserId,
                winningAuthorUserId: winningAuthorUserId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                dirty: dirty,
                localRev: localRev,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String profileId,
                required String localDate,
                required String winningRowId,
                required String losingRowId,
                required String field,
                required String losingValueText,
                Value<String?> losingAuthorUserId = const Value.absent(),
                Value<String?> winningAuthorUserId = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<bool> dirty = const Value.absent(),
                Value<int> localRev = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DayEntryMergeEventsCompanion.insert(
                id: id,
                profileId: profileId,
                localDate: localDate,
                winningRowId: winningRowId,
                losingRowId: losingRowId,
                field: field,
                losingValueText: losingValueText,
                losingAuthorUserId: losingAuthorUserId,
                winningAuthorUserId: winningAuthorUserId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                dirty: dirty,
                localRev: localRev,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $DayEntryMergeEventsTable,
                    DayEntryMergeEventData
                  >(table),
                  $$DayEntryMergeEventsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({profileId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (profileId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.profileId,
                        referencedTable: $$DayEntryMergeEventsTableReferences
                            ._profileIdTable(db),
                        referencedColumn: $$DayEntryMergeEventsTableReferences
                            ._profileIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DayEntryMergeEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$LunarLogDatabase,
      $DayEntryMergeEventsTable,
      DayEntryMergeEventData,
      $$DayEntryMergeEventsTableFilterComposer,
      $$DayEntryMergeEventsTableOrderingComposer,
      $$DayEntryMergeEventsTableAnnotationComposer,
      $$DayEntryMergeEventsTableCreateCompanionBuilder,
      $$DayEntryMergeEventsTableUpdateCompanionBuilder,
      (DayEntryMergeEventData, $$DayEntryMergeEventsTableReferences),
      DayEntryMergeEventData,
      PrefetchHooks Function({bool profileId})
    >;
typedef $$ProfileTagRegistryTableCreateCompanionBuilder =
    ProfileTagRegistryCompanion Function({
      required String id,
      required String profileId,
      required String code,
      required String displayName,
      required String category,
      Value<bool> intensityEnabled,
      Value<DateTime?> hiddenAt,
      Value<int?> sortOrder,
      Value<String?> createdBy,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<bool> dirty,
      Value<int> localRev,
      Value<int> rowid,
    });
typedef $$ProfileTagRegistryTableUpdateCompanionBuilder =
    ProfileTagRegistryCompanion Function({
      Value<String> id,
      Value<String> profileId,
      Value<String> code,
      Value<String> displayName,
      Value<String> category,
      Value<bool> intensityEnabled,
      Value<DateTime?> hiddenAt,
      Value<int?> sortOrder,
      Value<String?> createdBy,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<bool> dirty,
      Value<int> localRev,
      Value<int> rowid,
    });

final class $$ProfileTagRegistryTableReferences
    extends
        BaseReferences<
          _$LunarLogDatabase,
          $ProfileTagRegistryTable,
          ProfileTagRegistryEntry
        > {
  $$ProfileTagRegistryTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ProfilesTable _profileIdTable(_$LunarLogDatabase db) =>
      db.profiles.createAlias('profile_tag_registry__profile_id__profiles__id');

  $$ProfilesTableProcessedTableManager get profileId {
    final $_column = $_itemColumn<String>('profile_id')!;

    final manager = $$ProfilesTableTableManager(
      $_db,
      $_db.profiles,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_profileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ProfileTagRegistryTableFilterComposer
    extends Composer<_$LunarLogDatabase, $ProfileTagRegistryTable> {
  $$ProfileTagRegistryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get intensityEnabled => $composableBuilder(
    column: $table.intensityEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get hiddenAt => $composableBuilder(
    column: $table.hiddenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localRev => $composableBuilder(
    column: $table.localRev,
    builder: (column) => ColumnFilters(column),
  );

  $$ProfilesTableFilterComposer get profileId {
    final $$ProfilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableFilterComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProfileTagRegistryTableOrderingComposer
    extends Composer<_$LunarLogDatabase, $ProfileTagRegistryTable> {
  $$ProfileTagRegistryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get intensityEnabled => $composableBuilder(
    column: $table.intensityEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get hiddenAt => $composableBuilder(
    column: $table.hiddenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localRev => $composableBuilder(
    column: $table.localRev,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProfilesTableOrderingComposer get profileId {
    final $$ProfilesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableOrderingComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProfileTagRegistryTableAnnotationComposer
    extends Composer<_$LunarLogDatabase, $ProfileTagRegistryTable> {
  $$ProfileTagRegistryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<bool> get intensityEnabled => $composableBuilder(
    column: $table.intensityEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get hiddenAt =>
      $composableBuilder(column: $table.hiddenAt, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<String> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<int> get localRev =>
      $composableBuilder(column: $table.localRev, builder: (column) => column);

  $$ProfilesTableAnnotationComposer get profileId {
    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableAnnotationComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProfileTagRegistryTableTableManager
    extends
        RootTableManager<
          _$LunarLogDatabase,
          $ProfileTagRegistryTable,
          ProfileTagRegistryEntry,
          $$ProfileTagRegistryTableFilterComposer,
          $$ProfileTagRegistryTableOrderingComposer,
          $$ProfileTagRegistryTableAnnotationComposer,
          $$ProfileTagRegistryTableCreateCompanionBuilder,
          $$ProfileTagRegistryTableUpdateCompanionBuilder,
          (ProfileTagRegistryEntry, $$ProfileTagRegistryTableReferences),
          ProfileTagRegistryEntry,
          PrefetchHooks Function({bool profileId})
        > {
  $$ProfileTagRegistryTableTableManager(
    _$LunarLogDatabase db,
    $ProfileTagRegistryTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfileTagRegistryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProfileTagRegistryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProfileTagRegistryTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> profileId = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<bool> intensityEnabled = const Value.absent(),
                Value<DateTime?> hiddenAt = const Value.absent(),
                Value<int?> sortOrder = const Value.absent(),
                Value<String?> createdBy = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> localRev = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProfileTagRegistryCompanion(
                id: id,
                profileId: profileId,
                code: code,
                displayName: displayName,
                category: category,
                intensityEnabled: intensityEnabled,
                hiddenAt: hiddenAt,
                sortOrder: sortOrder,
                createdBy: createdBy,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                dirty: dirty,
                localRev: localRev,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String profileId,
                required String code,
                required String displayName,
                required String category,
                Value<bool> intensityEnabled = const Value.absent(),
                Value<DateTime?> hiddenAt = const Value.absent(),
                Value<int?> sortOrder = const Value.absent(),
                Value<String?> createdBy = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> localRev = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProfileTagRegistryCompanion.insert(
                id: id,
                profileId: profileId,
                code: code,
                displayName: displayName,
                category: category,
                intensityEnabled: intensityEnabled,
                hiddenAt: hiddenAt,
                sortOrder: sortOrder,
                createdBy: createdBy,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                dirty: dirty,
                localRev: localRev,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $ProfileTagRegistryTable,
                    ProfileTagRegistryEntry
                  >(table),
                  $$ProfileTagRegistryTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({profileId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (profileId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.profileId,
                        referencedTable: $$ProfileTagRegistryTableReferences
                            ._profileIdTable(db),
                        referencedColumn: $$ProfileTagRegistryTableReferences
                            ._profileIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ProfileTagRegistryTableProcessedTableManager =
    ProcessedTableManager<
      _$LunarLogDatabase,
      $ProfileTagRegistryTable,
      ProfileTagRegistryEntry,
      $$ProfileTagRegistryTableFilterComposer,
      $$ProfileTagRegistryTableOrderingComposer,
      $$ProfileTagRegistryTableAnnotationComposer,
      $$ProfileTagRegistryTableCreateCompanionBuilder,
      $$ProfileTagRegistryTableUpdateCompanionBuilder,
      (ProfileTagRegistryEntry, $$ProfileTagRegistryTableReferences),
      ProfileTagRegistryEntry,
      PrefetchHooks Function({bool profileId})
    >;
typedef $$DayEntryHistoryTableCreateCompanionBuilder =
    DayEntryHistoryCompanion Function({
      required String id,
      required String entryId,
      required String profileId,
      required String changedByUserId,
      required DateTime changedAt,
      required String changeKind,
      required List<String> changedFields,
      Value<int> rowid,
    });
typedef $$DayEntryHistoryTableUpdateCompanionBuilder =
    DayEntryHistoryCompanion Function({
      Value<String> id,
      Value<String> entryId,
      Value<String> profileId,
      Value<String> changedByUserId,
      Value<DateTime> changedAt,
      Value<String> changeKind,
      Value<List<String>> changedFields,
      Value<int> rowid,
    });

final class $$DayEntryHistoryTableReferences
    extends
        BaseReferences<
          _$LunarLogDatabase,
          $DayEntryHistoryTable,
          DayEntryHistoryData
        > {
  $$DayEntryHistoryTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ProfilesTable _profileIdTable(_$LunarLogDatabase db) =>
      db.profiles.createAlias('day_entry_history__profile_id__profiles__id');

  $$ProfilesTableProcessedTableManager get profileId {
    final $_column = $_itemColumn<String>('profile_id')!;

    final manager = $$ProfilesTableTableManager(
      $_db,
      $_db.profiles,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_profileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DayEntryHistoryTableFilterComposer
    extends Composer<_$LunarLogDatabase, $DayEntryHistoryTable> {
  $$DayEntryHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get changedByUserId => $composableBuilder(
    column: $table.changedByUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get changedAt => $composableBuilder(
    column: $table.changedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get changeKind => $composableBuilder(
    column: $table.changeKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String>
  get changedFields => $composableBuilder(
    column: $table.changedFields,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  $$ProfilesTableFilterComposer get profileId {
    final $$ProfilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableFilterComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DayEntryHistoryTableOrderingComposer
    extends Composer<_$LunarLogDatabase, $DayEntryHistoryTable> {
  $$DayEntryHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get changedByUserId => $composableBuilder(
    column: $table.changedByUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get changedAt => $composableBuilder(
    column: $table.changedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get changeKind => $composableBuilder(
    column: $table.changeKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get changedFields => $composableBuilder(
    column: $table.changedFields,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProfilesTableOrderingComposer get profileId {
    final $$ProfilesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableOrderingComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DayEntryHistoryTableAnnotationComposer
    extends Composer<_$LunarLogDatabase, $DayEntryHistoryTable> {
  $$DayEntryHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entryId =>
      $composableBuilder(column: $table.entryId, builder: (column) => column);

  GeneratedColumn<String> get changedByUserId => $composableBuilder(
    column: $table.changedByUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get changedAt =>
      $composableBuilder(column: $table.changedAt, builder: (column) => column);

  GeneratedColumn<String> get changeKind => $composableBuilder(
    column: $table.changeKind,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<List<String>, String> get changedFields =>
      $composableBuilder(
        column: $table.changedFields,
        builder: (column) => column,
      );

  $$ProfilesTableAnnotationComposer get profileId {
    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.profileId,
      referencedTable: $db.profiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProfilesTableAnnotationComposer(
            $db: $db,
            $table: $db.profiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DayEntryHistoryTableTableManager
    extends
        RootTableManager<
          _$LunarLogDatabase,
          $DayEntryHistoryTable,
          DayEntryHistoryData,
          $$DayEntryHistoryTableFilterComposer,
          $$DayEntryHistoryTableOrderingComposer,
          $$DayEntryHistoryTableAnnotationComposer,
          $$DayEntryHistoryTableCreateCompanionBuilder,
          $$DayEntryHistoryTableUpdateCompanionBuilder,
          (DayEntryHistoryData, $$DayEntryHistoryTableReferences),
          DayEntryHistoryData,
          PrefetchHooks Function({bool profileId})
        > {
  $$DayEntryHistoryTableTableManager(
    _$LunarLogDatabase db,
    $DayEntryHistoryTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DayEntryHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DayEntryHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DayEntryHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> entryId = const Value.absent(),
                Value<String> profileId = const Value.absent(),
                Value<String> changedByUserId = const Value.absent(),
                Value<DateTime> changedAt = const Value.absent(),
                Value<String> changeKind = const Value.absent(),
                Value<List<String>> changedFields = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DayEntryHistoryCompanion(
                id: id,
                entryId: entryId,
                profileId: profileId,
                changedByUserId: changedByUserId,
                changedAt: changedAt,
                changeKind: changeKind,
                changedFields: changedFields,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String entryId,
                required String profileId,
                required String changedByUserId,
                required DateTime changedAt,
                required String changeKind,
                required List<String> changedFields,
                Value<int> rowid = const Value.absent(),
              }) => DayEntryHistoryCompanion.insert(
                id: id,
                entryId: entryId,
                profileId: profileId,
                changedByUserId: changedByUserId,
                changedAt: changedAt,
                changeKind: changeKind,
                changedFields: changedFields,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DayEntryHistoryTable, DayEntryHistoryData>(
                    table,
                  ),
                  $$DayEntryHistoryTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({profileId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (profileId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.profileId,
                        referencedTable: $$DayEntryHistoryTableReferences
                            ._profileIdTable(db),
                        referencedColumn: $$DayEntryHistoryTableReferences
                            ._profileIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DayEntryHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$LunarLogDatabase,
      $DayEntryHistoryTable,
      DayEntryHistoryData,
      $$DayEntryHistoryTableFilterComposer,
      $$DayEntryHistoryTableOrderingComposer,
      $$DayEntryHistoryTableAnnotationComposer,
      $$DayEntryHistoryTableCreateCompanionBuilder,
      $$DayEntryHistoryTableUpdateCompanionBuilder,
      (DayEntryHistoryData, $$DayEntryHistoryTableReferences),
      DayEntryHistoryData,
      PrefetchHooks Function({bool profileId})
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$LunarLogDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$LunarLogDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$LunarLogDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$LunarLogDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$LunarLogDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$LunarLogDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AppSettingsTable, AppSetting>(table),
                  BaseReferences<
                    _$LunarLogDatabase,
                    $AppSettingsTable,
                    AppSetting
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$LunarLogDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$LunarLogDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;
typedef $$SyncStateTableCreateCompanionBuilder = SyncStateCompanion Function({
  Value<int> id,
  Value<String?> boundUserId,
  Value<String> deviceId,
  Value<int> cursorProfiles,
  Value<int> cursorDayEntries,
  Value<int> cursorObservations,
  Value<int> cursorProfileModes,
  Value<int> cursorCycleOverrides,
  Value<int> cursorCareNotes,
  Value<int> cursorVisitPrepItems,
  Value<int> cursorProfileGuardians,
  Value<int> cursorDeletedProfiles,
  Value<int> cursorDayEntryMergeEvents,
  Value<int> cursorProfileTagRegistry,
  Value<int> cursorDayEntryHistory,
  Value<DateTime?> lastFullPullAt,
  Value<DateTime?> lastSyncAt,
  Value<String?> lastError,
  Value<int?> serverClockOffsetMs,
});
typedef $$SyncStateTableUpdateCompanionBuilder = SyncStateCompanion Function({
  Value<int> id,
  Value<String?> boundUserId,
  Value<String> deviceId,
  Value<int> cursorProfiles,
  Value<int> cursorDayEntries,
  Value<int> cursorObservations,
  Value<int> cursorProfileModes,
  Value<int> cursorCycleOverrides,
  Value<int> cursorCareNotes,
  Value<int> cursorVisitPrepItems,
  Value<int> cursorProfileGuardians,
  Value<int> cursorDeletedProfiles,
  Value<int> cursorDayEntryMergeEvents,
  Value<int> cursorProfileTagRegistry,
  Value<int> cursorDayEntryHistory,
  Value<DateTime?> lastFullPullAt,
  Value<DateTime?> lastSyncAt,
  Value<String?> lastError,
  Value<int?> serverClockOffsetMs,
});

class $$SyncStateTableFilterComposer
    extends Composer<_$LunarLogDatabase, $SyncStateTable> {
  $$SyncStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get boundUserId => $composableBuilder(
    column: $table.boundUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cursorProfiles => $composableBuilder(
    column: $table.cursorProfiles,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cursorDayEntries => $composableBuilder(
    column: $table.cursorDayEntries,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cursorObservations => $composableBuilder(
    column: $table.cursorObservations,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cursorProfileModes => $composableBuilder(
    column: $table.cursorProfileModes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cursorCycleOverrides => $composableBuilder(
    column: $table.cursorCycleOverrides,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cursorCareNotes => $composableBuilder(
    column: $table.cursorCareNotes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cursorVisitPrepItems => $composableBuilder(
    column: $table.cursorVisitPrepItems,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cursorProfileGuardians => $composableBuilder(
    column: $table.cursorProfileGuardians,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cursorDeletedProfiles => $composableBuilder(
    column: $table.cursorDeletedProfiles,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cursorDayEntryMergeEvents => $composableBuilder(
    column: $table.cursorDayEntryMergeEvents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cursorProfileTagRegistry => $composableBuilder(
    column: $table.cursorProfileTagRegistry,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cursorDayEntryHistory => $composableBuilder(
    column: $table.cursorDayEntryHistory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastFullPullAt => $composableBuilder(
    column: $table.lastFullPullAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverClockOffsetMs => $composableBuilder(
    column: $table.serverClockOffsetMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncStateTableOrderingComposer
    extends Composer<_$LunarLogDatabase, $SyncStateTable> {
  $$SyncStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get boundUserId => $composableBuilder(
    column: $table.boundUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cursorProfiles => $composableBuilder(
    column: $table.cursorProfiles,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cursorDayEntries => $composableBuilder(
    column: $table.cursorDayEntries,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cursorObservations => $composableBuilder(
    column: $table.cursorObservations,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cursorProfileModes => $composableBuilder(
    column: $table.cursorProfileModes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cursorCycleOverrides => $composableBuilder(
    column: $table.cursorCycleOverrides,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cursorCareNotes => $composableBuilder(
    column: $table.cursorCareNotes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cursorVisitPrepItems => $composableBuilder(
    column: $table.cursorVisitPrepItems,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cursorProfileGuardians => $composableBuilder(
    column: $table.cursorProfileGuardians,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cursorDeletedProfiles => $composableBuilder(
    column: $table.cursorDeletedProfiles,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cursorDayEntryMergeEvents => $composableBuilder(
    column: $table.cursorDayEntryMergeEvents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cursorProfileTagRegistry => $composableBuilder(
    column: $table.cursorProfileTagRegistry,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cursorDayEntryHistory => $composableBuilder(
    column: $table.cursorDayEntryHistory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastFullPullAt => $composableBuilder(
    column: $table.lastFullPullAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverClockOffsetMs => $composableBuilder(
    column: $table.serverClockOffsetMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncStateTableAnnotationComposer
    extends Composer<_$LunarLogDatabase, $SyncStateTable> {
  $$SyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get boundUserId => $composableBuilder(
    column: $table.boundUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get cursorProfiles => $composableBuilder(
    column: $table.cursorProfiles,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cursorDayEntries => $composableBuilder(
    column: $table.cursorDayEntries,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cursorObservations => $composableBuilder(
    column: $table.cursorObservations,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cursorProfileModes => $composableBuilder(
    column: $table.cursorProfileModes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cursorCycleOverrides => $composableBuilder(
    column: $table.cursorCycleOverrides,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cursorCareNotes => $composableBuilder(
    column: $table.cursorCareNotes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cursorVisitPrepItems => $composableBuilder(
    column: $table.cursorVisitPrepItems,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cursorProfileGuardians => $composableBuilder(
    column: $table.cursorProfileGuardians,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cursorDeletedProfiles => $composableBuilder(
    column: $table.cursorDeletedProfiles,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cursorDayEntryMergeEvents => $composableBuilder(
    column: $table.cursorDayEntryMergeEvents,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cursorProfileTagRegistry => $composableBuilder(
    column: $table.cursorProfileTagRegistry,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cursorDayEntryHistory => $composableBuilder(
    column: $table.cursorDayEntryHistory,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastFullPullAt => $composableBuilder(
    column: $table.lastFullPullAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<int> get serverClockOffsetMs => $composableBuilder(
    column: $table.serverClockOffsetMs,
    builder: (column) => column,
  );
}

class $$SyncStateTableTableManager
    extends
        RootTableManager<
          _$LunarLogDatabase,
          $SyncStateTable,
          SyncStateRow,
          $$SyncStateTableFilterComposer,
          $$SyncStateTableOrderingComposer,
          $$SyncStateTableAnnotationComposer,
          $$SyncStateTableCreateCompanionBuilder,
          $$SyncStateTableUpdateCompanionBuilder,
          (
            SyncStateRow,
            BaseReferences<_$LunarLogDatabase, $SyncStateTable, SyncStateRow>,
          ),
          SyncStateRow,
          PrefetchHooks Function()
        > {
  $$SyncStateTableTableManager(_$LunarLogDatabase db, $SyncStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> boundUserId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int> cursorProfiles = const Value.absent(),
                Value<int> cursorDayEntries = const Value.absent(),
                Value<int> cursorObservations = const Value.absent(),
                Value<int> cursorProfileModes = const Value.absent(),
                Value<int> cursorCycleOverrides = const Value.absent(),
                Value<int> cursorCareNotes = const Value.absent(),
                Value<int> cursorVisitPrepItems = const Value.absent(),
                Value<int> cursorProfileGuardians = const Value.absent(),
                Value<int> cursorDeletedProfiles = const Value.absent(),
                Value<int> cursorDayEntryMergeEvents = const Value.absent(),
                Value<int> cursorProfileTagRegistry = const Value.absent(),
                Value<int> cursorDayEntryHistory = const Value.absent(),
                Value<DateTime?> lastFullPullAt = const Value.absent(),
                Value<DateTime?> lastSyncAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int?> serverClockOffsetMs = const Value.absent(),
              }) => SyncStateCompanion(
                id: id,
                boundUserId: boundUserId,
                deviceId: deviceId,
                cursorProfiles: cursorProfiles,
                cursorDayEntries: cursorDayEntries,
                cursorObservations: cursorObservations,
                cursorProfileModes: cursorProfileModes,
                cursorCycleOverrides: cursorCycleOverrides,
                cursorCareNotes: cursorCareNotes,
                cursorVisitPrepItems: cursorVisitPrepItems,
                cursorProfileGuardians: cursorProfileGuardians,
                cursorDeletedProfiles: cursorDeletedProfiles,
                cursorDayEntryMergeEvents: cursorDayEntryMergeEvents,
                cursorProfileTagRegistry: cursorProfileTagRegistry,
                cursorDayEntryHistory: cursorDayEntryHistory,
                lastFullPullAt: lastFullPullAt,
                lastSyncAt: lastSyncAt,
                lastError: lastError,
                serverClockOffsetMs: serverClockOffsetMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> boundUserId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int> cursorProfiles = const Value.absent(),
                Value<int> cursorDayEntries = const Value.absent(),
                Value<int> cursorObservations = const Value.absent(),
                Value<int> cursorProfileModes = const Value.absent(),
                Value<int> cursorCycleOverrides = const Value.absent(),
                Value<int> cursorCareNotes = const Value.absent(),
                Value<int> cursorVisitPrepItems = const Value.absent(),
                Value<int> cursorProfileGuardians = const Value.absent(),
                Value<int> cursorDeletedProfiles = const Value.absent(),
                Value<int> cursorDayEntryMergeEvents = const Value.absent(),
                Value<int> cursorProfileTagRegistry = const Value.absent(),
                Value<int> cursorDayEntryHistory = const Value.absent(),
                Value<DateTime?> lastFullPullAt = const Value.absent(),
                Value<DateTime?> lastSyncAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int?> serverClockOffsetMs = const Value.absent(),
              }) => SyncStateCompanion.insert(
                id: id,
                boundUserId: boundUserId,
                deviceId: deviceId,
                cursorProfiles: cursorProfiles,
                cursorDayEntries: cursorDayEntries,
                cursorObservations: cursorObservations,
                cursorProfileModes: cursorProfileModes,
                cursorCycleOverrides: cursorCycleOverrides,
                cursorCareNotes: cursorCareNotes,
                cursorVisitPrepItems: cursorVisitPrepItems,
                cursorProfileGuardians: cursorProfileGuardians,
                cursorDeletedProfiles: cursorDeletedProfiles,
                cursorDayEntryMergeEvents: cursorDayEntryMergeEvents,
                cursorProfileTagRegistry: cursorProfileTagRegistry,
                cursorDayEntryHistory: cursorDayEntryHistory,
                lastFullPullAt: lastFullPullAt,
                lastSyncAt: lastSyncAt,
                lastError: lastError,
                serverClockOffsetMs: serverClockOffsetMs,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncStateTable, SyncStateRow>(table),
                  BaseReferences<
                    _$LunarLogDatabase,
                    $SyncStateTable,
                    SyncStateRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStateTableProcessedTableManager =
    ProcessedTableManager<
      _$LunarLogDatabase,
      $SyncStateTable,
      SyncStateRow,
      $$SyncStateTableFilterComposer,
      $$SyncStateTableOrderingComposer,
      $$SyncStateTableAnnotationComposer,
      $$SyncStateTableCreateCompanionBuilder,
      $$SyncStateTableUpdateCompanionBuilder,
      (
        SyncStateRow,
        BaseReferences<_$LunarLogDatabase, $SyncStateTable, SyncStateRow>,
      ),
      SyncStateRow,
      PrefetchHooks Function()
    >;
typedef $$HealthSyncStateTableCreateCompanionBuilder =
    HealthSyncStateCompanion Function({
      required String platform,
      Value<String?> anchor,
      Value<DateTime?> lastSyncedAt,
      Value<int> rowid,
    });
typedef $$HealthSyncStateTableUpdateCompanionBuilder =
    HealthSyncStateCompanion Function({
      Value<String> platform,
      Value<String?> anchor,
      Value<DateTime?> lastSyncedAt,
      Value<int> rowid,
    });

class $$HealthSyncStateTableFilterComposer
    extends Composer<_$LunarLogDatabase, $HealthSyncStateTable> {
  $$HealthSyncStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get anchor => $composableBuilder(
    column: $table.anchor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HealthSyncStateTableOrderingComposer
    extends Composer<_$LunarLogDatabase, $HealthSyncStateTable> {
  $$HealthSyncStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get anchor => $composableBuilder(
    column: $table.anchor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HealthSyncStateTableAnnotationComposer
    extends Composer<_$LunarLogDatabase, $HealthSyncStateTable> {
  $$HealthSyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get platform =>
      $composableBuilder(column: $table.platform, builder: (column) => column);

  GeneratedColumn<String> get anchor =>
      $composableBuilder(column: $table.anchor, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => column,
  );
}

class $$HealthSyncStateTableTableManager
    extends
        RootTableManager<
          _$LunarLogDatabase,
          $HealthSyncStateTable,
          HealthSyncStateRow,
          $$HealthSyncStateTableFilterComposer,
          $$HealthSyncStateTableOrderingComposer,
          $$HealthSyncStateTableAnnotationComposer,
          $$HealthSyncStateTableCreateCompanionBuilder,
          $$HealthSyncStateTableUpdateCompanionBuilder,
          (
            HealthSyncStateRow,
            BaseReferences<
              _$LunarLogDatabase,
              $HealthSyncStateTable,
              HealthSyncStateRow
            >,
          ),
          HealthSyncStateRow,
          PrefetchHooks Function()
        > {
  $$HealthSyncStateTableTableManager(
    _$LunarLogDatabase db,
    $HealthSyncStateTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HealthSyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HealthSyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HealthSyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> platform = const Value.absent(),
                Value<String?> anchor = const Value.absent(),
                Value<DateTime?> lastSyncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HealthSyncStateCompanion(
                platform: platform,
                anchor: anchor,
                lastSyncedAt: lastSyncedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String platform,
                Value<String?> anchor = const Value.absent(),
                Value<DateTime?> lastSyncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HealthSyncStateCompanion.insert(
                platform: platform,
                anchor: anchor,
                lastSyncedAt: lastSyncedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$HealthSyncStateTable, HealthSyncStateRow>(table),
                  BaseReferences<
                    _$LunarLogDatabase,
                    $HealthSyncStateTable,
                    HealthSyncStateRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HealthSyncStateTableProcessedTableManager =
    ProcessedTableManager<
      _$LunarLogDatabase,
      $HealthSyncStateTable,
      HealthSyncStateRow,
      $$HealthSyncStateTableFilterComposer,
      $$HealthSyncStateTableOrderingComposer,
      $$HealthSyncStateTableAnnotationComposer,
      $$HealthSyncStateTableCreateCompanionBuilder,
      $$HealthSyncStateTableUpdateCompanionBuilder,
      (
        HealthSyncStateRow,
        BaseReferences<
          _$LunarLogDatabase,
          $HealthSyncStateTable,
          HealthSyncStateRow
        >,
      ),
      HealthSyncStateRow,
      PrefetchHooks Function()
    >;

class $LunarLogDatabaseManager {
  final _$LunarLogDatabase _db;
  $LunarLogDatabaseManager(this._db);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db, _db.profiles);
  $$DayEntriesTableTableManager get dayEntries =>
      $$DayEntriesTableTableManager(_db, _db.dayEntries);
  $$ProfileGuardiansTableTableManager get profileGuardians =>
      $$ProfileGuardiansTableTableManager(_db, _db.profileGuardians);
  $$ObservationsTableTableManager get observations =>
      $$ObservationsTableTableManager(_db, _db.observations);
  $$ProfileModesTableTableManager get profileModes =>
      $$ProfileModesTableTableManager(_db, _db.profileModes);
  $$CycleOverridesTableTableManager get cycleOverrides =>
      $$CycleOverridesTableTableManager(_db, _db.cycleOverrides);
  $$CareNotesTableTableManager get careNotes =>
      $$CareNotesTableTableManager(_db, _db.careNotes);
  $$VisitPrepItemsTableTableManager get visitPrepItems =>
      $$VisitPrepItemsTableTableManager(_db, _db.visitPrepItems);
  $$DayEntryMergeEventsTableTableManager get dayEntryMergeEvents =>
      $$DayEntryMergeEventsTableTableManager(_db, _db.dayEntryMergeEvents);
  $$ProfileTagRegistryTableTableManager get profileTagRegistry =>
      $$ProfileTagRegistryTableTableManager(_db, _db.profileTagRegistry);
  $$DayEntryHistoryTableTableManager get dayEntryHistory =>
      $$DayEntryHistoryTableTableManager(_db, _db.dayEntryHistory);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db, _db.syncState);
  $$HealthSyncStateTableTableManager get healthSyncState =>
      $$HealthSyncStateTableTableManager(_db, _db.healthSyncState);
}
