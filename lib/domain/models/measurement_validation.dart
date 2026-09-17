/// Domain model: sanity ranges for numeric measurement entry (Issue #457).
///
/// These bounds are a UX floor/ceiling only — they exist to catch the class
/// of unrecoverable-looking typo (an extra digit, a decimal point slipped a
/// place) before a value is written, never to assert what is medically
/// normal. There is no server-side CHECK constraint mirroring them (unlike
/// `lib/domain/limits.dart`'s length/range constants, which do mirror a
/// migration's CHECK): `observations.value_num` accepts any numeric value
/// server-side, by design, so an imported or wearable-sourced value outside
/// these bounds still round-trips untouched — only this app's own manual
/// entry form is gated by [isValidBbt]/[isValidWeight].
///
/// Bounds are defined in each measurement's storage-neutral canonical unit
/// (Celsius, kilograms) and validated against an entered value via
/// [convertTemperature]/[convertWeight] — the same conversion
/// `lib/domain/models/measurement_unit.dart` already uses for display, so a
/// value typed in Fahrenheit or pounds is validated exactly as strictly as
/// the same physical value typed in Celsius or kilograms.
///
/// Pure Dart with no drift/Flutter imports (R14/R16) —
/// `test/architecture/layering_test.dart` enforces that.
library;

import 'measurement_unit.dart';

/// Basal body temperature sanity floor/ceiling, in Celsius (34.0-42.0 °C /
/// 93.2-107.6 °F) — generous enough to admit any real human BBT reading
/// (including a feverish one) while still catching a typo like an extra
/// leading digit or a misplaced decimal point.
const double kMinBbtCelsius = 34.0;
const double kMaxBbtCelsius = 42.0;

/// Weight sanity floor/ceiling, in kilograms (10-300 kg / 22-661 lb) —
/// generous enough to admit a minor profile's weight at the low end and an
/// adult's at the high end, without asserting a "normal" weight anywhere in
/// between.
const double kMinWeightKg = 10.0;
const double kMaxWeightKg = 300.0;

/// Whether [value], denominated in [unit], falls within the BBT sanity
/// range. Converts to Celsius first so the same physical range is enforced
/// regardless of which unit the operator is currently entering in.
bool isValidBbt(double value, BbtUnit unit) {
  final celsius = convertTemperature(value, from: unit, to: BbtUnit.celsius);
  return celsius >= kMinBbtCelsius && celsius <= kMaxBbtCelsius;
}

/// Whether [value], denominated in [unit], falls within the weight sanity
/// range. Same contract as [isValidBbt].
bool isValidWeight(double value, WeightUnit unit) {
  final kg = convertWeight(value, from: unit, to: WeightUnit.kg);
  return kg >= kMinWeightKg && kg <= kMaxWeightKg;
}

/// [kMinBbtCelsius]/[kMaxBbtCelsius] converted into [unit], for rendering a
/// range error message in whatever unit the operator is currently typing
/// in rather than always naming the canonical Celsius bounds.
(double min, double max) bbtRangeIn(BbtUnit unit) => (
      convertTemperature(kMinBbtCelsius, from: BbtUnit.celsius, to: unit),
      convertTemperature(kMaxBbtCelsius, from: BbtUnit.celsius, to: unit),
    );

/// [kMinWeightKg]/[kMaxWeightKg] converted into [unit]; same contract as
/// [bbtRangeIn].
(double min, double max) weightRangeIn(WeightUnit unit) => (
      convertWeight(kMinWeightKg, from: WeightUnit.kg, to: unit),
      convertWeight(kMaxWeightKg, from: WeightUnit.kg, to: unit),
    );
