/// Domain model: a tracked person (the operator or one of the minors).
///
/// Pure Dart with no drift/Flutter imports (R14/R16). Archiving is a soft
/// UI concern (profile stays in history); deleting is a tombstone.
library;

import 'local_date.dart';
import 'profile_mode.dart';
import 'profile_relationship.dart';

class Profile {
  Profile({
    required this.id,
    required this.displayName,
    required this.isMinor,
    this.mode = ProfileMode.standard,
    this.sortOrder = 0,
    this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.birthYear,
    this.relationship,
    this.transferredAt,
    this.lastPeriodStart,
    this.typicalCycleLengthDays,
    this.typicalPeriodLengthDays,
  });

  /// Storage-assigned ULID (empty on unsaved, client-created models).
  final String id;

  final String displayName;
  final bool isMinor;
  final int sortOrder;

  /// Care mode (Issue #131, R12): drives vocabulary, logging defaults, and
  /// reminder presets *prospectively*. Presentation only — never permission
  /// (guardian roles stay the only capability model) and never derived from
  /// [birthYear] or `isMinor`; both of those stay inert display/context
  /// metadata. Chosen at creation or later from profile settings.
  final ProfileMode mode;

  /// UTC instant when the profile was archived, or null when live.
  final DateTime? archivedAt;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Null for live profiles: repository reads filter tombstones.
  final DateTime? deletedAt;

  /// Optional birth year of the profile subject (Issue #4 R1). Display and
  /// context only — never gates, forces, or auto-schedules an ownership
  /// transfer (R2).
  final int? birthYear;

  /// Optional closed-set relationship of the subject to the profile creator
  /// (R3), or null when unset or when the stored value is not one this
  /// build recognises.
  final ProfileRelationship? relationship;

  /// Instant this profile's ownership last moved, or null if it never has
  /// (R5). Server-owned — never set by a local write.
  final DateTime? transferredAt;

  /// Onboarding-collected cycle facts (Issue #218): the start date of the
  /// most recent period as supplied at first run (or edited later from
  /// profile settings). Optional and editable like every other fact
  /// below; feeds the provisional prediction seed — never a logged
  /// `day_entries` row (a supplied answer is not an observation).
  final LocalDate? lastPeriodStart;

  /// Onboarding-collected "typical cycle length" answer in days
  /// (Issue #218). Stored and synced as supplied; the seeding gate (see
  /// `CycleFacts.canSeed`) is what bounds which values can feed an
  /// estimate.
  final int? typicalCycleLengthDays;

  /// Onboarding-collected "typical period length" answer in days
  /// (Issue #218). Same treatment as [typicalCycleLengthDays].
  final int? typicalPeriodLengthDays;

  static const Object _unset = Object();

  /// Resolves a `copyWith` sentinel-typed parameter: an unpassed argument
  /// (still `_unset`) keeps [fallback]; anything else (including an explicit
  /// `null`) overrides it. Pulling this out of `copyWith` keeps each
  /// nullable field a single expression there instead of a ternary, which
  /// is what keeps that method's cyclomatic complexity (and so its CRAP
  /// score) low as more optional fields are added.
  static T? _resolveNullable<T>(Object? value, T? fallback) =>
      identical(value, _unset) ? fallback : value as T?;

  Profile copyWith({
    String? id,
    String? displayName,
    bool? isMinor,
    ProfileMode? mode,
    int? sortOrder,
    Object? archivedAt = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? deletedAt = _unset,
    Object? birthYear = _unset,
    Object? relationship = _unset,
    Object? transferredAt = _unset,
    Object? lastPeriodStart = _unset,
    Object? typicalCycleLengthDays = _unset,
    Object? typicalPeriodLengthDays = _unset,
  }) =>
      Profile(
        id: id ?? this.id,
        displayName: displayName ?? this.displayName,
        isMinor: isMinor ?? this.isMinor,
        mode: mode ?? this.mode,
        sortOrder: sortOrder ?? this.sortOrder,
        archivedAt: _resolveNullable(archivedAt, this.archivedAt),
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: _resolveNullable(deletedAt, this.deletedAt),
        birthYear: _resolveNullable(birthYear, this.birthYear),
        relationship: _resolveNullable(relationship, this.relationship),
        transferredAt: _resolveNullable(transferredAt, this.transferredAt),
        lastPeriodStart:
            _resolveNullable(lastPeriodStart, this.lastPeriodStart),
        typicalCycleLengthDays: _resolveNullable(
            typicalCycleLengthDays, this.typicalCycleLengthDays),
        typicalPeriodLengthDays: _resolveNullable(
            typicalPeriodLengthDays, this.typicalPeriodLengthDays),
      );

  /// Identity-ish fields: what a row's primary key and headline attributes
  /// are. Split from [_sameProfileDetails] purely to keep [operator ==]'s
  /// own cyclomatic complexity (and so its CRAP score) low as fields grow -
  /// mirrors the identity/details split already used by [ProfileGuardian].
  bool _sameProfileIdentity(Profile other) =>
      other.id == id &&
      other.displayName == displayName &&
      other.isMinor == isMinor &&
      other.mode == mode &&
      other.sortOrder == sortOrder &&
      other.createdAt == createdAt;

  bool _sameProfileDetails(Profile other) =>
      other.updatedAt == updatedAt &&
      other.archivedAt == archivedAt &&
      other.deletedAt == deletedAt &&
      other.birthYear == birthYear &&
      other.relationship == relationship &&
      other.transferredAt == transferredAt &&
      other.lastPeriodStart == lastPeriodStart &&
      other.typicalCycleLengthDays == typicalCycleLengthDays &&
      other.typicalPeriodLengthDays == typicalPeriodLengthDays;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Profile &&
          _sameProfileIdentity(other) &&
          _sameProfileDetails(other);

  @override
  int get hashCode => Object.hash(
        id,
        displayName,
        isMinor,
        mode,
        sortOrder,
        archivedAt,
        createdAt,
        updatedAt,
        deletedAt,
        birthYear,
        relationship,
        transferredAt,
        lastPeriodStart,
        typicalCycleLengthDays,
        typicalPeriodLengthDays,
      );

  @override
  String toString() =>
      'Profile($id $displayName${isMinor ? ' minor' : ''}'
      '${archivedAt == null ? '' : ' [archived]'}'
      '${deletedAt == null ? '' : ' [tombstoned]'})';
}
