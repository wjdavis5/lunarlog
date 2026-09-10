/// Domain model: a tracked person (the operator or one of the minors).
///
/// Pure Dart with no drift/Flutter imports (R14/R16). Archiving is a soft
/// UI concern (profile stays in history); deleting is a tombstone.
library;

import 'local_date.dart';
import 'measurement_unit.dart';
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
    this.transferredToUserId,
    this.lastPeriodStart,
    this.typicalCycleLengthDays,
    this.typicalPeriodLengthDays,
    this.bbtUnit = BbtUnit.celsius,
    this.weightUnit = WeightUnit.kg,
  });

  /// Storage-assigned ULID (empty on unsaved, client-created models).
  final String id;

  final String displayName;
  final bool isMinor;
  final int sortOrder;

  /// Care mode (Issue #131, R12): drives vocabulary, logging defaults, and
  /// reminder presets *prospectively*. Presentation only — never permission
  /// (guardian roles stay the only capability model) and never derived from
  /// [birthYear] or `isMinor`; neither feeds any care-mode decision. (Both
  /// do feed the #153 health-sync minor gate — see [birthYear] and
  /// [transferredToUserId] — which is a permission, but one this field
  /// never consults.) Chosen at creation or later from profile settings.
  final ProfileMode mode;

  /// UTC instant when the profile was archived, or null when live.
  final DateTime? archivedAt;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Null for live profiles: repository reads filter tombstones.
  final DateTime? deletedAt;

  /// Optional birth year of the profile subject (Issue #4 R1). Still never
  /// gates, forces, or auto-schedules an ownership *transfer* (R2), but no
  /// longer display-only: since the #153 health-sync guard it also feeds
  /// the fail-closed minor determination in
  /// `lib/domain/health/health_sync_binding.dart` (`_isMinorNow`) — an
  /// under-18-by-coarse-year profile is denied health-store binding unless
  /// the transferred-to-own-account exception holds. That gate fails
  /// closed on a missing year; it never uses this field for anything else.
  final int? birthYear;

  /// Optional closed-set relationship of the subject to the profile creator
  /// (R3), or null when unset or when the stored value is not one this
  /// build recognises.
  final ProfileRelationship? relationship;

  /// Instant this profile's ownership last moved, or null if it never has
  /// (R5). Server-owned — never set by a local write.
  final DateTime? transferredAt;

  /// The account that accepted this profile's last ownership transfer, or
  /// null if it never has (Issue #296). Server-owned exactly like
  /// [transferredAt] — stamped only by the server's
  /// `accept_ownership_transfer`, pulled but never pushed — so the
  /// health-sync minor gate can require that the last transfer targeted
  /// the *signed-in account itself*, not merely that a transfer happened
  /// and the caller happens to be the resolved owner. Null fails closed.
  final String? transferredToUserId;

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

  /// Per-profile BBT display unit (Issue #255): how a stored basal body
  /// temperature renders, independent of the unit any individual
  /// `observations` value was entered or imported in (each row carries its
  /// own `unit`). Presentation only — nothing converts stored values when
  /// this changes.
  final BbtUnit bbtUnit;

  /// Per-profile weight display unit (Issue #255). Same contract as
  /// [bbtUnit], for weight rows.
  final WeightUnit weightUnit;

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
    Object? transferredToUserId = _unset,
    Object? lastPeriodStart = _unset,
    Object? typicalCycleLengthDays = _unset,
    Object? typicalPeriodLengthDays = _unset,
    BbtUnit? bbtUnit,
    WeightUnit? weightUnit,
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
        transferredToUserId:
            _resolveNullable(transferredToUserId, this.transferredToUserId),
        lastPeriodStart:
            _resolveNullable(lastPeriodStart, this.lastPeriodStart),
        typicalCycleLengthDays: _resolveNullable(
            typicalCycleLengthDays, this.typicalCycleLengthDays),
        typicalPeriodLengthDays: _resolveNullable(
            typicalPeriodLengthDays, this.typicalPeriodLengthDays),
        bbtUnit: bbtUnit ?? this.bbtUnit,
        weightUnit: weightUnit ?? this.weightUnit,
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
      _sameSubjectMetadata(other) &&
      other.lastPeriodStart == lastPeriodStart &&
      other.typicalCycleLengthDays == typicalCycleLengthDays &&
      other.typicalPeriodLengthDays == typicalPeriodLengthDays &&
      _sameMeasurementUnits(other);

  /// Split from [_sameProfileDetails] (the [Observation]
  /// `_sameValue`/`_sameProvenance` pattern) so neither method's
  /// cyclomatic complexity - and so its CRAP score - grows past the gate
  /// as optional fields are added.
  bool _sameSubjectMetadata(Profile other) =>
      other.birthYear == birthYear &&
      other.relationship == relationship &&
      other.transferredAt == transferredAt &&
      other.transferredToUserId == transferredToUserId;

  /// Issue #255's two display-unit preferences, split out for the same
  /// reason as [_sameSubjectMetadata].
  bool _sameMeasurementUnits(Profile other) =>
      other.bbtUnit == bbtUnit && other.weightUnit == weightUnit;

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
        transferredToUserId,
        lastPeriodStart,
        typicalCycleLengthDays,
        typicalPeriodLengthDays,
        bbtUnit,
        weightUnit,
      );

  @override
  String toString() =>
      'Profile($id $displayName${isMinor ? ' minor' : ''}'
      '${archivedAt == null ? '' : ' [archived]'}'
      '${deletedAt == null ? '' : ' [tombstoned]'})';
}
