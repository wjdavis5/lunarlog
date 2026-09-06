/// Domain model: the closed-set relationship of a profile's subject to the
/// profile creator (Issue #4, KTD8).
///
/// Pure Dart with no drift/Flutter imports (R14/R16) — `test/architecture/`
/// `layering_test.dart` enforces that.
library;

/// Relationship of the profile subject to the profile creator, matching the
/// database check constraint (`profiles_relationship_check`).
enum ProfileRelationship {
  self,
  daughter,
  son,
  child,
  partner,
  other;

  String toDb() => switch (this) {
        self => 'self',
        daughter => 'daughter',
        son => 'son',
        child => 'child',
        partner => 'partner',
        other => 'other',
      };

  /// Unlike `GuardianRole.fromDb`, an unrecognised [value] returns null
  /// rather than throwing: relationship is optional, display-only metadata
  /// (R2), so a value this build doesn't recognise (a future addition, a
  /// row from a newer client) should degrade to "unset" rather than crash a
  /// pull.
  static ProfileRelationship? fromDb(String value) => switch (value) {
        'self' => self,
        'daughter' => daughter,
        'son' => son,
        'child' => child,
        'partner' => partner,
        'other' => other,
        _ => null,
      };

  String get label => switch (this) {
        self => 'Self',
        daughter => 'Daughter',
        son => 'Son',
        child => 'Child',
        partner => 'Partner',
        other => 'Other',
      };
}
