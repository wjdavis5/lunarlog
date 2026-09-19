/// The closed set of `observations.category` values lunarlog itself
/// branches on (Issue #847): `spotting`, `pain`, `bbt`, `weight`, and the
/// six per-day birth-control intake categories.
///
/// `observations.category` stays free text on the wire and in the database
/// (issue #240's D-10 decision — a ~200-code vocabulary stored, never
/// rejected, so a newer client's or an importer's category always
/// round-trips). This type is the *typed* projection the domain and UI
/// branch on: a row codec/Drift-mapper boundary converts once via
/// [ObservationCategory.fromCode], and everything downstream compares
/// against the named members instead of scattered string literals.
///
/// Unknown codes round-trip losslessly: [fromCode] returns a
/// [UnknownObservationCategory] carrying the raw string verbatim, whose
/// [ObservationCategory.wireCode] is byte-identical to what arrived. No
/// path ever silently maps an unrecognised category onto a known member.
///
/// The hierarchy is sealed so a category-driven `switch` is exhaustive —
/// the compiler flags every branch when a new member is added rather than
/// letting it fall through an `== 'literal'` no-op the way the pre-#847
/// string comparisons did.
library;

/// One stored `observations.category` value.
///
/// Equality and hashing are keyed on [wireCode] (rather than the concrete
/// subclass), so the named members compare equal to any other instance
/// carrying the same code and a value can never equal itself by accident.
sealed class ObservationCategory {
  const ObservationCategory(this.wireCode);

  /// The raw string stored on the row and sent over the wire.
  final String wireCode;

  /// An unrecognised code retained verbatim (a future category, a row from
  /// a newer client, an importer's own vocabulary) — never normalised onto
  /// a known member, so read → store → export → sync is byte-identical.
  const factory ObservationCategory.custom(String code) =
      UnknownObservationCategory;

  static const ObservationCategory spotting = SpottingCategory();
  static const ObservationCategory pain = PainCategory();
  static const ObservationCategory bbt = BbtCategory();
  static const ObservationCategory weight = WeightCategory();

  static const ObservationCategory birthControlPill =
      BirthControlCategory('birth_control_pill');
  static const ObservationCategory birthControlShot =
      BirthControlCategory('birth_control_shot');
  static const ObservationCategory birthControlImplant =
      BirthControlCategory('birth_control_implant');
  static const ObservationCategory birthControlPatch =
      BirthControlCategory('birth_control_patch');
  static const ObservationCategory birthControlRing =
      BirthControlCategory('birth_control_ring');
  static const ObservationCategory birthControlIud =
      BirthControlCategory('birth_control_iud');

  /// Every category this build knows by name — [fromCode]'s lookup table
  /// and the set a totality test can assert over. [UnknownObservationCategory]
  /// is deliberately absent: it is the fallback, not a member.
  static const List<ObservationCategory> known = [
    spotting,
    pain,
    bbt,
    weight,
    birthControlPill,
    birthControlShot,
    birthControlImplant,
    birthControlPatch,
    birthControlRing,
    birthControlIud,
  ];

  /// Total read of a stored or wire `category`: a known code parses to its
  /// member, anything else to an [UnknownObservationCategory] keeping the
  /// raw string. Never throws and never degrades an unknown code to a
  /// known member.
  static ObservationCategory fromCode(String code) {
    for (final category in known) {
      if (category.wireCode == code) return category;
    }
    return ObservationCategory.custom(code);
  }

  /// Whether this is one of the six per-day birth-control intake
  /// categories (`birth_control_*`). Modelled as one member of the family
  /// rather than six unrelated labels, mirroring
  /// `lib/domain/birth_control.dart`'s family-level treatment.
  bool get isBirthControl => this is BirthControlCategory;

  /// Whether this category holds a logged measurement (`bbt`/`weight`)
  /// rather than a symptom. Exhaustive over the hierarchy so a new member
  /// cannot silently be classified as a symptom by omission.
  bool get isMeasurement => switch (this) {
        BbtCategory() || WeightCategory() => true,
        SpottingCategory() ||
        PainCategory() ||
        BirthControlCategory() ||
        UnknownObservationCategory() =>
          false,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ObservationCategory && other.wireCode == wireCode;

  @override
  int get hashCode => wireCode.hashCode;

  @override
  String toString() => wireCode;
}

/// The `spotting` category (Issue #247's standalone spotting observation).
final class SpottingCategory extends ObservationCategory {
  const SpottingCategory() : super('spotting');
}

/// The `pain` category (Clue's symptom category; #256 grades it by code).
final class PainCategory extends ObservationCategory {
  const PainCategory() : super('pain');
}

/// The `bbt` category (basal body temperature; a numeric measurement).
final class BbtCategory extends ObservationCategory {
  const BbtCategory() : super('bbt');
}

/// The `weight` category (a numeric measurement).
final class WeightCategory extends ObservationCategory {
  const WeightCategory() : super('weight');
}

/// One of the six per-day birth-control intake categories (issue #260):
/// `birth_control_pill` / `_shot` / `_implant` / `_patch` / `_ring` /
/// `_iud`. Carries its own wire code so the family shares one type while
/// the method is still recoverable from [wireCode].
final class BirthControlCategory extends ObservationCategory {
  const BirthControlCategory(super.wireCode);
}

/// A category this build does not recognise, retained verbatim so it
/// survives every read/write path unchanged.
final class UnknownObservationCategory extends ObservationCategory {
  const UnknownObservationCategory(super.wireCode);
}
