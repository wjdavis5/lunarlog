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
    transferredAt,
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
    if (data.containsKey('transferred_at')) {
      context.handle(
        _transferredAtMeta,
        transferredAt.isAcceptableOrUnknown(
          data['transferred_at']!,
          _transferredAtMeta,
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
      transferredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}transferred_at'],
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

  /// Instant this profile's ownership last moved via
  /// `accept_ownership_transfer`, or null if it never has (R5). Never
  /// client-writable — server-owned, pulled but never pushed (see
  /// `encodeProfile` in `row_codec.dart`).
  final DateTime? transferredAt;
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
    this.transferredAt,
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
    if (!nullToAbsent || transferredAt != null) {
      map['transferred_at'] = Variable<DateTime>(transferredAt);
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
      transferredAt: transferredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(transferredAt),
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
      transferredAt: serializer.fromJson<DateTime?>(json['transferredAt']),
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
      'transferredAt': serializer.toJson<DateTime?>(transferredAt),
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
    Value<DateTime?> transferredAt = const Value.absent(),
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
    transferredAt: transferredAt.present
        ? transferredAt.value
        : this.transferredAt,
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
      transferredAt: data.transferredAt.present
          ? data.transferredAt.value
          : this.transferredAt,
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
          ..write('transferredAt: $transferredAt')
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
    transferredAt,
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
          other.transferredAt == this.transferredAt);
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
  final Value<DateTime?> transferredAt;
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
    this.transferredAt = const Value.absent(),
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
    this.transferredAt = const Value.absent(),
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
    Expression<DateTime>? transferredAt,
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
      if (transferredAt != null) 'transferred_at': transferredAt,
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
    Value<DateTime?>? transferredAt,
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
      transferredAt: transferredAt ?? this.transferredAt,
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
    if (transferredAt.present) {
      map['transferred_at'] = Variable<DateTime>(transferredAt.value);
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
          ..write('transferredAt: $transferredAt, ')
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
    localDate,
    tz,
    flow,
    tags,
    note,
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
  const DayEntry({
    required this.id,
    required this.profileId,
    required this.localDate,
    required this.tz,
    required this.flow,
    required this.tags,
    this.note,
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

  DayEntriesCompanion toCompanion(bool nullToAbsent) {
    return DayEntriesCompanion(
      id: Value(id),
      profileId: Value(profileId),
      localDate: Value(localDate),
      tz: Value(tz),
      flow: Value(flow),
      tags: Value(tags),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
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
      'localDate': serializer.toJson<String>(localDate),
      'tz': serializer.toJson<String>(tz),
      'flow': serializer.toJson<FlowLevel>(flow),
      'tags': serializer.toJson<List<String>>(tags),
      'note': serializer.toJson<String?>(note),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'localRev': serializer.toJson<int>(localRev),
      'loggedByUserId': serializer.toJson<String?>(loggedByUserId),
      'lastModifiedByUserId': serializer.toJson<String?>(lastModifiedByUserId),
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
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    bool? dirty,
    int? localRev,
    Value<String?> loggedByUserId = const Value.absent(),
    Value<String?> lastModifiedByUserId = const Value.absent(),
  }) => DayEntry(
    id: id ?? this.id,
    profileId: profileId ?? this.profileId,
    localDate: localDate ?? this.localDate,
    tz: tz ?? this.tz,
    flow: flow ?? this.flow,
    tags: tags ?? this.tags,
    note: note.present ? note.value : this.note,
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
  DayEntry copyWithCompanion(DayEntriesCompanion data) {
    return DayEntry(
      id: data.id.present ? data.id.value : this.id,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      localDate: data.localDate.present ? data.localDate.value : this.localDate,
      tz: data.tz.present ? data.tz.value : this.tz,
      flow: data.flow.present ? data.flow.value : this.flow,
      tags: data.tags.present ? data.tags.value : this.tags,
      note: data.note.present ? data.note.value : this.note,
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
    return (StringBuffer('DayEntry(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('localDate: $localDate, ')
          ..write('tz: $tz, ')
          ..write('flow: $flow, ')
          ..write('tags: $tags, ')
          ..write('note: $note, ')
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
    localDate,
    tz,
    flow,
    tags,
    note,
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
      (other is DayEntry &&
          other.id == this.id &&
          other.profileId == this.profileId &&
          other.localDate == this.localDate &&
          other.tz == this.tz &&
          other.flow == this.flow &&
          other.tags == this.tags &&
          other.note == this.note &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.dirty == this.dirty &&
          other.localRev == this.localRev &&
          other.loggedByUserId == this.loggedByUserId &&
          other.lastModifiedByUserId == this.lastModifiedByUserId);
}

class DayEntriesCompanion extends UpdateCompanion<DayEntry> {
  final Value<String> id;
  final Value<String> profileId;
  final Value<String> localDate;
  final Value<String> tz;
  final Value<FlowLevel> flow;
  final Value<List<String>> tags;
  final Value<String?> note;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<bool> dirty;
  final Value<int> localRev;
  final Value<String?> loggedByUserId;
  final Value<String?> lastModifiedByUserId;
  final Value<int> rowid;
  const DayEntriesCompanion({
    this.id = const Value.absent(),
    this.profileId = const Value.absent(),
    this.localDate = const Value.absent(),
    this.tz = const Value.absent(),
    this.flow = const Value.absent(),
    this.tags = const Value.absent(),
    this.note = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.localRev = const Value.absent(),
    this.loggedByUserId = const Value.absent(),
    this.lastModifiedByUserId = const Value.absent(),
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
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.localRev = const Value.absent(),
    this.loggedByUserId = const Value.absent(),
    this.lastModifiedByUserId = const Value.absent(),
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
      if (localDate != null) 'local_date': localDate,
      if (tz != null) 'tz': tz,
      if (flow != null) 'flow': flow,
      if (tags != null) 'tags': tags,
      if (note != null) 'note': note,
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

  DayEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? profileId,
    Value<String>? localDate,
    Value<String>? tz,
    Value<FlowLevel>? flow,
    Value<List<String>>? tags,
    Value<String?>? note,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<bool>? dirty,
    Value<int>? localRev,
    Value<String?>? loggedByUserId,
    Value<String?>? lastModifiedByUserId,
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
    return (StringBuffer('DayEntriesCompanion(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('localDate: $localDate, ')
          ..write('tz: $tz, ')
          ..write('flow: $flow, ')
          ..write('tags: $tags, ')
          ..write('note: $note, ')
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
  Value<DateTime?> transferredAt,
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
  Value<DateTime?> transferredAt,
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

  ColumnFilters<DateTime> get transferredAt => $composableBuilder(
    column: $table.transferredAt,
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

  ColumnOrderings<DateTime> get transferredAt => $composableBuilder(
    column: $table.transferredAt,
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

  GeneratedColumn<DateTime> get transferredAt => $composableBuilder(
    column: $table.transferredAt,
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
                Value<DateTime?> transferredAt = const Value.absent(),
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
                transferredAt: transferredAt,
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
                Value<DateTime?> transferredAt = const Value.absent(),
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
                transferredAt: transferredAt,
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
              ({dayEntriesRefs = false, profileGuardiansRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (dayEntriesRefs) db.dayEntries,
                    if (profileGuardiansRefs) db.profileGuardians,
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
      PrefetchHooks Function({bool dayEntriesRefs, bool profileGuardiansRefs})
    >;
typedef $$DayEntriesTableCreateCompanionBuilder = DayEntriesCompanion Function({
  required String id,
  required String profileId,
  required String localDate,
  required String tz,
  required FlowLevel flow,
  Value<List<String>> tags,
  Value<String?> note,
  required DateTime updatedAt,
  Value<DateTime?> deletedAt,
  Value<bool> dirty,
  Value<int> localRev,
  Value<String?> loggedByUserId,
  Value<String?> lastModifiedByUserId,
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
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<bool> dirty,
  Value<int> localRev,
  Value<String?> loggedByUserId,
  Value<String?> lastModifiedByUserId,
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
          PrefetchHooks Function({bool profileId})
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
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> localRev = const Value.absent(),
                Value<String?> loggedByUserId = const Value.absent(),
                Value<String?> lastModifiedByUserId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DayEntriesCompanion(
                id: id,
                profileId: profileId,
                localDate: localDate,
                tz: tz,
                flow: flow,
                tags: tags,
                note: note,
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
                required String localDate,
                required String tz,
                required FlowLevel flow,
                Value<List<String>> tags = const Value.absent(),
                Value<String?> note = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> localRev = const Value.absent(),
                Value<String?> loggedByUserId = const Value.absent(),
                Value<String?> lastModifiedByUserId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DayEntriesCompanion.insert(
                id: id,
                profileId: profileId,
                localDate: localDate,
                tz: tz,
                flow: flow,
                tags: tags,
                note: note,
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
                  e.readTable<$DayEntriesTable, DayEntry>(table),
                  $$DayEntriesTableReferences(db, table, e),
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
                return [];
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
      PrefetchHooks Function({bool profileId})
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
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db, _db.syncState);
}
