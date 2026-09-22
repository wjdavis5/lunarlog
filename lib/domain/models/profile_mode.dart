/// Domain model: the closed-set care mode of a profile (Issue #131, R12).
///
/// Mode is *presentation, not permission* (the issue's design constraints):
/// it varies vocabulary, defaults, and reminder presets prospectively, and
/// never grants or restricts access — guardian roles remain the only
/// capability model. It is chosen, never computed: nothing derives a mode
/// from [Profile.birthYear] or `isMinor`, and neither of those fields gates
/// anything automatically.
///
/// Issue #853 demotes `irregular` from a rival mode to a composed flag: a
/// profile is no longer *in* "irregular mode" — it carries a life-stage
/// mode (`standard`/`teen`) plus the independent
/// `Profile.irregularFraming` flag, and the two compose (`careModeCopyFor`
/// in `lib/domain/care_modes.dart`). The enum member survives as a
/// **legacy wire value** only: the server CHECK (`profiles_mode_check`)
/// still accepts it and every read boundary maps it to
/// `standard` + `irregularFraming: true` (the server data migration in
/// `20260920110000_profile_irregular_framing.sql`, the read-time mapping
/// in `row_codec.dart`'s `decodeProfile`, and the local v28 Drift step),
/// so an old client's push can never wedge a new one. It is never offered
/// as a picker choice ([choosableModes]).
///
/// Issue #850 retires `caregiver` the same way: it is no longer a rival mode
/// but a **legacy wire value** the server CHECK (`profiles_mode_check`)
/// still accepts and every read boundary maps to `standard`. A profile's
/// per-viewer posture is now the guardian *lens*
/// (`lib/domain/sharing/guardian_lens.dart`), a membership-identity fact,
/// not a chosen mode; reminders move to that lens in a later unit. The enum
/// member survives so [toDb] can still round-trip an old row, but
/// [choosableModes] never offers it and no copy or preset treats it
/// specially. No Drift schema bump is needed — the read boundary's
/// `fromDb` → `toDb()` fold (the same #853 precedent) and the next push
/// converge the local wire string.
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
  /// (an old row predating the column) means the same thing. The legacy
  /// `caregiver` wire value folds into `standard` (Issue #850) ahead of the
  /// wildcard so a stored pre-#850 row reads as the neutral default.
  static ProfileMode fromDb(String? value) => switch (value) {
        'teen' => teen,
        'caregiver' => standard,
        'irregular' => irregular,
        _ => standard,
      };

  /// The modes a picker may offer (Issue #853, #850): everything except the
  /// two legacy wire values — `irregular`, expressed as
  /// `standard` + `Profile.irregularFraming = true`, and the retired
  /// `caregiver`, now the guardian lens
  /// (`lib/domain/sharing/guardian_lens.dart`) rather than a chosen mode.
  static const List<ProfileMode> choosableModes = [
    standard,
    teen,
  ];

  String get label => switch (this) {
        standard => 'Standard',
        teen => 'Teen',
        caregiver => 'Caregiver',
        irregular => 'Irregular cycles',
      };

  /// One-line picker hint naming who the mode is for — copy is part of the
  /// deliverable (Issue #131: "copy review is part of this work"). The
  /// `irregular` and `caregiver` hints survive only for the read-path
  /// mappings of legacy rows; the picker never renders either (Issue #853
  /// replaces the former with the `irregularFraming` toggle's hint, #850
  /// replaces the latter with the per-viewer lens).
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
