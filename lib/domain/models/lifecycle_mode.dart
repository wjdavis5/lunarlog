/// Domain model: the closed-set life-stage mode of a profile (Issue #188).
///
/// ORTHOGONAL to [ProfileMode] (Issue #131's care modes:
/// `standard`/`teen`/`caregiver`/`irregular`) and the two enums are never
/// merged. This axis varies *what the app computes and tracks by life
/// stage* (Clue's Period Tracking / Conceive / Pregnancy / Perimenopause /
/// Postpartum); #131's axis varies *vocabulary and framing by who is
/// reading* a profile. Both are per-profile, both sync, and they compose --
/// e.g. a teen profile in Period Tracking mode, or an adult profile in
/// Perimenopause mode with `caregiver` framing for the person helping her.
/// See issue #188's context ("This axis is orthogonal to #131... Do not
/// collapse them into one enum") and
/// `supabase/migrations/20260909000000_profile_modes_and_cycle_overrides.sql`'s
/// header, which states the same at the schema level for
/// `profile_modes.mode` vs `profiles.mode`.
///
/// Pure Dart with no drift/Flutter imports (R14/R16) — `test/architecture/`
/// `layering_test.dart` enforces that.
library;

/// Life-stage mode of a profile, matching the server's
/// `profile_modes_mode_check` CHECK constraint: `tracking` (Period
/// Tracking), `conceive`, `pregnancy`, `perimenopause`, `postpartum`.
///
/// Switching is free and reversible: tracked data is kept, only what is
/// computed and displayed changes (A2-32) — a switch never deletes or
/// rewrites `day_entries`/`observations`, and every switch triggers a full
/// prediction recompute on the client (the predictor already re-derives
/// from history; there is no persisted prediction state to invalidate).
enum LifecycleMode {
  tracking,
  conceive,
  pregnancy,
  perimenopause,
  postpartum;

  String toDb() => switch (this) {
        tracking => 'tracking',
        conceive => 'conceive',
        pregnancy => 'pregnancy',
        perimenopause => 'perimenopause',
        postpartum => 'postpartum',
      };

  /// Like [ProfileMode.fromDb], an unrecognised [value] degrades rather
  /// than throws: a value this build doesn't recognise (a future addition,
  /// a row from a newer client) falls back to the neutral default
  /// (`tracking`) instead of crashing a pull. `null` (no profile_modes row
  /// yet — rows are created lazily on first write) means the same thing.
  static LifecycleMode fromDb(String? value) => switch (value) {
        'conceive' => conceive,
        'pregnancy' => pregnancy,
        'perimenopause' => perimenopause,
        'postpartum' => postpartum,
        _ => tracking,
      };

  String get label => switch (this) {
        tracking => 'Period Tracking',
        conceive => 'Conceive',
        pregnancy => 'Pregnancy',
        perimenopause => 'Perimenopause',
        postpartum => 'Postpartum',
      };
}
