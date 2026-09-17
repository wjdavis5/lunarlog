/// Issue #257: the per-profile custom-tag registry's domain model and
/// pure helpers.
///
/// A [CustomTag] is one user-defined vocabulary entry: a stable
/// snake_case [code] (the same shape as a `kTagTaxonomy` code, stored on
/// `day_entries.tags`/`observations.code` exactly like a curated code) plus
/// the user's own [displayName]. The registry is **display vocabulary,
/// never an allowlist**: a stored code absent from the registry (never
/// created, retired, deleted, or simply not yet synced to this device)
/// still round-trips through every write path and renders as raw text
/// (#237 (TM-1)'s unknown-never-drop rule).
///
/// Retirement ([hiddenAt]) removes a code from the day-sheet picker while
/// stored rows referencing it keep rendering -- Clue's
/// delete-destroys-history failure mode is structurally impossible here:
/// nothing in this model, the storage layer, or the server can remove a
/// stored reference's ability to render.
library;

import '../limits.dart';
import '../tags.dart';

/// The display-label bound, mirroring the server's
/// `profile_tag_registry_display_name_length_check` (the issue's own
/// 40-character CHECK).
const int kMaxCustomTagLabelLength = 40;

/// The per-profile live-row ceiling, mirroring the server's
/// `c_max_tags_per_profile` (enforced there in `sync_push` -- a CHECK
/// cannot count siblings). Enforced client-side on create so a user hits
/// the wall with a friendly message instead of a rejected sync row.
const int kMaxCustomTagsPerProfile = 100;

/// The category every in-app custom-tag creation files under today. Free
/// text on the wire (a future Clue importer may file mapped tags under
/// their Clue category); this is the one value this build writes.
const String kCustomTagCategory = 'custom';

/// One row of the per-profile custom-tag registry.
class CustomTag {
  const CustomTag({
    required this.id,
    required this.profileId,
    required this.code,
    required this.displayName,
    required this.category,
    this.intensityEnabled = false,
    this.hiddenAt,
    this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  /// Client-generated ULID (stable across devices/sync).
  final String id;
  final String profileId;

  /// The stable snake_case identifier persisted on day entries, derived
  /// from the label at creation ([customTagCodeFromLabel]) and never
  /// changed after -- a rename rewrites [displayName] only, so historical
  /// rows keep resolving.
  final String code;

  /// The user's own label for the tag (bounded to
  /// [kMaxCustomTagLabelLength]).
  final String displayName;

  /// Free text, client-owned; [kCustomTagCategory] for in-app creations.
  final String category;

  /// Reserved for #259-style per-tag intensity affordances; false today
  /// (the day sheet's graded pain-intensity rows are taxonomy-driven).
  final bool intensityEnabled;

  /// RETIREMENT, not deletion: non-null removes the code from the
  /// day-sheet picker while stored rows referencing it keep rendering.
  final DateTime? hiddenAt;

  final int? sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// Whether this entry is offered by the day-sheet picker: live (not
  /// tombstoned) and not retired.
  bool get offered => deletedAt == null && hiddenAt == null;

  /// Whether this entry can still resolve a stored code to a display
  /// name: live, retired or not (a retired tag's rows keep rendering).
  bool get renders => deletedAt == null;

  // No ==/hashCode override: identity equality is what every consumer
  // wants (the picker keys chips by code, the manager lists rows by id),
  // and an eleven-field value equality sits past the quality gate's CRAP
  // ceiling with no coverage headroom (complexity 12 — 12 × (1 − cov)³ +
  // 12 ≥ 12 > 10 even fully covered).

  @override
  String toString() => 'CustomTag($code, $displayName)';
}

/// Derives a registry code from a user-typed label: lowercase, every
/// non-alphanumeric run collapsed to one underscore, underscores trimmed,
/// clamped to `kMaxTagLength` (64 -- the server's per-element bound).
///
/// Returns null when nothing alphanumeric survives ("!!" or "---"), which
/// [validateCustomTagLabel] reports to the UI as an invalid label before
/// this is ever reached.
String? customTagCodeFromLabel(String label) {
  final code = label
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (code.isEmpty) return null;
  return code.length > kMaxTagLength ? code.substring(0, kMaxTagLength) : code;
}

/// What is wrong with a would-be custom-tag label, if anything.
enum CustomTagLabelError {
  /// Empty or whitespace-only.
  empty,

  /// Longer than [kMaxCustomTagLabelLength] characters.
  tooLong,

  /// Contains no alphanumeric characters, so no code could be derived.
  noLettersOrDigits,

  /// Derives a code already used by another LIVE registry entry for this
  /// profile (case-insensitively -- the server dedupes on lower(code)).
  duplicateCode,

  /// Derives a code the static taxonomy already owns; the curated code
  /// renders already, and shadowing it would make one chip mean two
  /// different things.
  collidesWithTaxonomy,
}

/// Validates [label] against [registry] (the profile's LIVE entries --
/// tombstoned rows free their codes) and the static taxonomy. Pure: the
/// create flow calls this before any storage write, exactly the way
/// `validateTagCodes` gates a taxonomy pick.
CustomTagLabelError? validateCustomTagLabel(
  String label,
  Iterable<CustomTag> registry,
) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) return CustomTagLabelError.empty;
  if (trimmed.length > kMaxCustomTagLabelLength) {
    return CustomTagLabelError.tooLong;
  }
  final code = customTagCodeFromLabel(trimmed);
  if (code == null) return CustomTagLabelError.noLettersOrDigits;
  if (isValidTagCode(code)) return CustomTagLabelError.collidesWithTaxonomy;
  final lower = code.toLowerCase();
  for (final tag in registry) {
    if (tag.deletedAt == null && tag.code.toLowerCase() == lower) {
      return CustomTagLabelError.duplicateCode;
    }
  }
  return null;
}
