/// Domain model: the closed-set care mode of a profile (Issue #131, R12).
///
/// Mode is *presentation, not permission* (the issue's design constraints):
/// it varies vocabulary, defaults, and reminder presets prospectively, and
/// never grants or restricts access — guardian roles remain the only
/// capability model. It is chosen, never computed: nothing derives a mode
/// from [Profile.birthYear] or `isMinor`, and neither of those fields gates
/// anything automatically.
///
/// Pure Dart with no drift/Flutter imports (R14/R16) — `test/architecture/`
/// `layering_test.dart` enforces that.
library;

/// Care mode of a profile, matching the database CHECK constraint
/// (`profiles_mode_check`): `standard`, `teen`, `caregiver`, `irregular`.
enum ProfileMode {
  standard,
  teen,
  caregiver,
  irregular;

  String toDb() => switch (this) {
        standard => 'standard',
        teen => 'teen',
        caregiver => 'caregiver',
        irregular => 'irregular',
      };

  /// Like [ProfileRelationship.fromDb] an unrecognised [value] degrades
  /// rather than throws: mode is presentation-only, and a value this build
  /// doesn't recognise (a future addition, a row from a newer client) must
  /// fall back to the neutral default instead of crashing a pull. `null`
  /// (an old row predating the column) means the same thing.
  static ProfileMode fromDb(String? value) => switch (value) {
        'teen' => teen,
        'caregiver' => caregiver,
        'irregular' => irregular,
        _ => standard,
      };

  String get label => switch (this) {
        standard => 'Standard',
        teen => 'Teen',
        caregiver => 'Caregiver',
        irregular => 'Irregular cycles',
      };

  /// One-line picker hint naming who the mode is for — copy is part of the
  /// deliverable (Issue #131: "copy review is part of this work").
  String get hint => switch (this) {
        standard => 'Adult tracking with the default vocabulary.',
        teen => 'Framing for someone building body literacy for the first '
            'time. Same data, same honesty.',
        caregiver => 'For someone mainly logging on another person\'s '
            'profile. Fewer reminders by default.',
        irregular => 'Reframes overdue estimates — variation is treated as '
            'expected, not late.',
      };
}
