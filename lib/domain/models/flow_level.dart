/// Domain flow-level value type (R14/R16: this is the copy the UI sees;
/// the drift enum in `lib/data/db/tables.dart` is mapped at the repository
/// boundary and never leaves `lib/data/`).
///
/// Issue #247 (epic: tracking-model) reshaped this from a flat 5-value
/// `none, spotting, light, medium, heavy` enum that conflated Clue's
/// Period and Spotting categories into one field:
///
/// * [superHeavy] is a new, fourth bleed level (Clue's `very_heavy`).
/// * [notBleeding] is a new, explicit "not bleeding today" assertion --
///   distinct from [none] ("nothing logged for this day at all"). A Clue
///   `period/none` import datapoint round-trips as [notBleeding], never
///   silently collapsed into "no entry".
/// * [spotting] is kept only as a **deprecated alias** for already-stored
///   data (global assumption #7: existing codes/values are never renamed,
///   only extended). Spotting is modelled going forward as its own
///   `observations` category row (`category: 'spotting', code:
///   'spotting'`), never a flow level -- lunarlog adopts Clue's own
///   definition of spotting: bleeding that is never counted toward period
///   length or cycle-start computation (never part of a period). On READ,
///   `lib/data/repositories/mappers.dart`'s `dayEntryToDomain` exposes a
///   stored `flow = 'spotting'` row as [notBleeding] (never [spotting]
///   itself) -- [spotting] only exists so `fromDb`/`FlowLevelConverter`
///   never throw on an old row or an old peer's sync payload.
///
/// [toDb]/[fromDb] are the server wire strings -- mirrors
/// `lib/domain/models/day_entry.dart`'s `DayEntrySource.toDb`/`fromDb`
/// pattern. Issue #303 collapsed the SQL-side allow-list (this enum's own
/// server mirror) into a single `public.flow_level` domain, backed by
/// `public.is_valid_flow_level()`, that `day_entries.flow`'s column type,
/// `sync_push`, and `bulk_import_entries` all now validate against --
/// see `supabase/migrations/20260915130000_data_consistency_bundle.sql`.
/// This enum stays the client mirror, kept in step by a guard test
/// ([FlowLevel]'s own `test/domain/models/flow_level_test.dart`) pinned
/// against the identical literal list `supabase/tests/
/// flow_level_domain_test.sql` pins on the SQL side, so the two can drift
/// apart only by breaking one suite or the other, never silently.
library;

enum FlowLevel {
  none,

  /// Deprecated alias for already-stored data (Issue #247) -- never
  /// written going forward. See this enum's own doc comment.
  @Deprecated('Spotting is its own observations category (Issue #247); '
      'stored only for backward compatibility with pre-#247 rows.')
  spotting,

  /// An explicit "not bleeding today" assertion (Issue #247) -- a
  /// positive fact, distinct from [none] ("nothing logged"). Never
  /// treated as a bleed day.
  notBleeding,
  light,
  medium,
  heavy,

  /// Issue #247 (Clue's `very_heavy`). The heaviest bleed level.
  superHeavy;

  /// The raw string stored on the row and sent over the wire -- matches
  /// the `public.flow_level` domain's allow-list (Issue #303,
  /// `supabase/migrations/20260915130000_data_consistency_bundle.sql`),
  /// which `day_entries.flow`'s column type, `sync_push`, and
  /// `bulk_import_entries` all now share.
  String toDb() => switch (this) {
        FlowLevel.none => 'none',
        // ignore: deprecated_member_use_from_same_package
        FlowLevel.spotting => 'spotting',
        FlowLevel.notBleeding => 'not_bleeding',
        FlowLevel.light => 'light',
        FlowLevel.medium => 'medium',
        FlowLevel.heavy => 'heavy',
        FlowLevel.superHeavy => 'super_heavy',
      };

  /// Normalises a raw `flow` string against the closed set: an
  /// unrecognised value degrades to [none] rather than throwing.
  static FlowLevel fromDb(String? raw) => switch (raw) {
        // ignore: deprecated_member_use_from_same_package
        'spotting' => FlowLevel.spotting,
        'not_bleeding' => FlowLevel.notBleeding,
        'light' => FlowLevel.light,
        'medium' => FlowLevel.medium,
        'heavy' => FlowLevel.heavy,
        'super_heavy' => FlowLevel.superHeavy,
        _ => FlowLevel.none,
      };
}

/// Whether [flow] records bleeding. [FlowLevel.none] (unlogged) and
/// [FlowLevel.notBleeding] (explicitly not bleeding) are both excluded;
/// so is the deprecated [FlowLevel.spotting] alias (Clue's own rule:
/// spotting is never part of a period -- see this file's library doc
/// comment). [FlowLevel.superHeavy] counts, same as every other real
/// bleed level.
bool isBleed(FlowLevel flow) => switch (flow) {
      FlowLevel.light ||
      FlowLevel.medium ||
      FlowLevel.heavy ||
      FlowLevel.superHeavy =>
        true,
      // ignore: deprecated_member_use_from_same_package
      FlowLevel.none || FlowLevel.notBleeding || FlowLevel.spotting => false,
    };

/// The human-readable label for [flow] (the `en` fallback; the day sheet
/// reads localized variants through `localizedFlowLabel`). Lives here since
/// #157 so pure-Dart consumers (e.g. the FHIR export) share the UI wording.
String flowLabel(FlowLevel flow) => switch (flow) {
      FlowLevel.none => 'None',
      // ignore: deprecated_member_use_from_same_package
      FlowLevel.spotting => 'Spotting',
      FlowLevel.notBleeding => 'Not bleeding',
      FlowLevel.light => 'Light',
      FlowLevel.medium => 'Medium',
      FlowLevel.heavy => 'Heavy',
      FlowLevel.superHeavy => 'Super heavy',
    };
