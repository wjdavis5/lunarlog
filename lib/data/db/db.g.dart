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
    lastPeriodStart,
    typicalCycleLengthDays,
    typicalPeriodLengthDays,
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
    this.lastPeriodStart,
    this.typicalCycleLengthDays,
    this.typicalPeriodLengthDays,
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
      lastPeriodStart: lastPeriodStart == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPeriodStart),
      typicalCycleLengthDays: typicalCycleLengthDays == null && nullToAbsent
          ? const Value.absent()
          : Value(typicalCycleLengthDays),
      typicalPeriodLengthDays: typicalPeriodLengthDays == null && nullToAbsent
          ? const Value.absent()
          : Value(typicalPeriodLengthDays),
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
      lastPeriodStart: serializer.fromJson<String?>(json['lastPeriodStart']),
      typicalCycleLengthDays: serializer.fromJson<int?>(
        json['typicalCycleLengthDays'],
      ),
      typicalPeriodLengthDays: serializer.fromJson<int?>(
        json['typicalPeriodLengthDays'],
      ),
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
      'lastPeriodStart': serializer.toJson<String?>(lastPeriodStart),
      'typicalCycleLengthDays': serializer.toJson<int?>(typicalCycleLengthDays),
      'typicalPeriodLengthDays': serializer.toJson<int?>(
        typicalPeriodLengthDays,
      ),
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
    Value<String?> lastPeriodStart = const Value.absent(),
    Value<int?> typicalCycleLengthDays = const Value.absent(),
    Value<int?> typicalPeriodLengthDays = const Value.absent(),
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
    lastPeriodStart: lastPeriodStart.present
        ? lastPeriodStart.value
        : this.lastPeriodStart,
    typicalCycleLengthDays: typicalCycleLengthDays.present
        ? typicalCycleLengthDays.value
        : this.typicalCycleLengthDays,
    typicalPeriodLengthDays: typicalPeriodLengthDays.present
        ? typicalPeriodLengthDays.value
        : this.typicalPeriodLengthDays,
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
      lastPeriodStart: data.lastPeriodStart.present
          ? data.lastPeriodStart.value
          : this.lastPeriodStart,
      typicalCycleLengthDays: data.typicalCycleLengthDays.present
          ? data.typicalCycleLengthDays.value
          : this.typicalCycleLengthDays,
      typicalPeriodLengthDays: data.typicalPeriodLengthDays.present
          ? data.typicalPeriodLengthDays.value
          : this.typicalPeriodLengthDays,
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
          ..write('lastPeriodStart: $lastPeriodStart, ')
          ..write('typicalCycleLengthDays: $typicalCycleLengthDays, ')
          ..write('typicalPeriodLengthDays: $typicalPeriodLengthDays')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
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
    lastPeriodStart,
    typicalCycleLengthDays,
    typicalPeriodLengthDays,
  );
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
          other.lastPeriodStart == this.lastPeriodStart &&
          other.typicalCycleLengthDays == this.typicalCycleLengthDays &&
          other.typicalPeriodLengthDays == this.typicalPeriodLengthDays);
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
  final Value<String?> lastPeriodStart;
  final Value<int?> typicalCycleLengthDays;
  final Value<int?> typicalPeriodLengthDays;
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
    this.lastPeriodStart = const Value.absent(),
    this.typicalCycleLengthDays = const Value.absent(),
    this.typicalPeriodLengthDays = const Value.absent(),
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
    this.lastPeriodStart = const Value.absent(),
    this.typicalCycleLengthDays = const Value.absent(),
    this.typicalPeriodLengthDays = const Value.absent(),
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
    Expression<String>? lastPeriodStart,
    Expression<int>? typicalCycleLengthDays,
    Expression<int>? typicalPeriodLengthDays,
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
      if (lastPeriodStart != null) 'last_period_start': lastPeriodStart,
      if (typicalCycleLengthDays != null)
        'typical_cycle_length_days': typicalCycleLengthDays,
      if (typicalPeriodLengthDays != null)
        'typical_period_length_days': typicalPeriodLengthDays,
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
    Value<String?>? lastPeriodStart,
    Value<int?>? typicalCycleLengthDays,
    Value<int?>? typicalPeriodLengthDays,
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
      lastPeriodStart: lastPeriodStart ?? this.lastPeriodStart,
      typicalCycleLengthDays:
          typicalCycleLengthDays ?? this.typicalCycleLengthDays,
      typicalPeriodLengthDays:
          typicalPeriodLengthDays ?? this.typicalPeriodLengthDays,
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
          ..write('lastPeriodStart: $lastPeriodStart, ')
          ..write('typicalCycleLengthDays: $typicalCycleLengthDays, ')
          ..write('typicalPeriodLengthDays: $typicalPeriodLengthDays, ')
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
          ..write('updatedAt: $updatedAt')
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
          other.updatedAt == this.updatedAt);
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
          ..write('lastFullPullAt: $lastFullPullAt, ')
          ..write('lastSyncAt: $lastSyncAt, ')
          ..write('lastError: $lastError, ')
          ..write('serverClockOffsetMs: $serverClockOffsetMs')
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
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $SyncStateTable syncState = $SyncStateTable(this);
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
    appSettings,
    syncState,
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
  Value<String?> lastPeriodStart,
  Value<int?> typicalCycleLengthDays,
  Value<int?> typicalPeriodLengthDays,
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
  Value<String?> lastPeriodStart,
  Value<int?> typicalCycleLengthDays,
  Value<int?> typicalPeriodLengthDays,
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
                Value<String?> lastPeriodStart = const Value.absent(),
                Value<int?> typicalCycleLengthDays = const Value.absent(),
                Value<int?> typicalPeriodLengthDays = const Value.absent(),
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
                lastPeriodStart: lastPeriodStart,
                typicalCycleLengthDays: typicalCycleLengthDays,
                typicalPeriodLengthDays: typicalPeriodLengthDays,
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
                Value<String?> lastPeriodStart = const Value.absent(),
                Value<int?> typicalCycleLengthDays = const Value.absent(),
                Value<int?> typicalPeriodLengthDays = const Value.absent(),
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
                lastPeriodStart: lastPeriodStart,
                typicalCycleLengthDays: typicalCycleLengthDays,
                typicalPeriodLengthDays: typicalPeriodLengthDays,
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
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db, _db.syncState);
}
