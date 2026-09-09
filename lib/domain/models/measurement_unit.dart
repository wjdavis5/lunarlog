/// Domain model: display units for numeric measurements (Issue #255).
///
/// A per-profile *display* preference, independent of the unit any
/// individual value was entered or imported in: `observations.value_num`
/// always stores the number together with the unit it is actually in
/// (`observations.unit`, `celsius`/`fahrenheit`/`kg`/`lb`), and the
/// preference only decides how that stored value *renders*. It is never
/// a storage unit — nothing converts stored values when the preference
/// changes, the same way a currency app never rewrites amounts when the
/// locale changes.
///
/// Pure Dart with no drift/Flutter imports (R14/R16) — `test/architecture/`
/// `layering_test.dart` enforces that.
library;

/// BBT display unit, matching the database CHECK constraint
/// (`profiles_bbt_unit_check`): `celsius` or `fahrenheit`. The default is
/// Celsius — Clue's own default and the unit basal thermometers sold
/// outside the US report in.
enum BbtUnit {
  celsius,
  fahrenheit;

  /// The raw string stored on the row and sent over the wire; also the
  /// string an `observations.unit` value uses for a temperature row.
  String toDb() => switch (this) {
        celsius => 'celsius',
        fahrenheit => 'fahrenheit',
      };

  /// An unrecognised [value] degrades rather than throws: the preference
  /// is presentation-only, and a value this build doesn't recognise (a
  /// future addition, a row from a newer client) must fall back to the
  /// default instead of crashing a pull.
  static BbtUnit fromDb(String? value) => switch (value) {
        'fahrenheit' => fahrenheit,
        _ => celsius,
      };
}

/// Weight display unit, matching the database CHECK constraint
/// (`profiles_weight_unit_check`): `kg` or `lb`. The default is kilograms
/// — the same metric default the BBT preference's Celsius default follows.
enum WeightUnit {
  kg,
  lb;

  /// The raw string stored on the row and sent over the wire; also the
  /// string an `observations.unit` value uses for a weight row.
  String toDb() => switch (this) {
        kg => 'kg',
        lb => 'lb',
      };

  /// An unrecognised [value] degrades rather than throws — same rationale
  /// as [BbtUnit.fromDb].
  static WeightUnit fromDb(String? value) => switch (value) {
        'lb' => lb,
        _ => kg,
      };
}

/// Converts a temperature between the two [BbtUnit]s: [from] describes
/// what [value] is denominated in, [to] what it should be displayed as.
/// Identical units return the value unchanged, so a stored Celsius value
/// on a Celsius-displaying profile never drifts through a round trip.
double convertTemperature(
  double value, {
  required BbtUnit from,
  required BbtUnit to,
}) {
  if (from == to) return value;
  return switch ((from, to)) {
    (BbtUnit.celsius, BbtUnit.fahrenheit) => value * 9 / 5 + 32,
    (BbtUnit.fahrenheit, BbtUnit.celsius) => (value - 32) * 5 / 9,
    _ => value,
  };
}

/// Converts a weight between the two [WeightUnit]s. Identical units return
/// the value unchanged, mirroring [convertTemperature].
double convertWeight(
  double value, {
  required WeightUnit from,
  required WeightUnit to,
}) {
  if (from == to) return value;
  return switch ((from, to)) {
    // 1 lb = 0.45359237 kg exactly (the 1959 international yard and
    // pound agreement), so the conversion is lossless in both directions
    // relative to what any scale or export actually reports.
    (WeightUnit.kg, WeightUnit.lb) => value / 0.45359237,
    (WeightUnit.lb, WeightUnit.kg) => value * 0.45359237,
    _ => value,
  };
}
