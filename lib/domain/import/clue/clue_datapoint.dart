/// Domain models for the Clue import parser (Issue #190).
///
/// Pure Dart, no drift/Flutter/`dart:io` imports (R14/R16) — see
/// `clue_export_parser.dart` for the byte-stream -> [ClueDatapoint] parser
/// this file only declares the shapes for.
library;

import '../../models/local_date.dart';

/// Clue's four bleed levels plus the explicit "not bleeding today"
/// assertion (`period/none` — a positive assertion, never an absence of
/// data; see `clue_option_map.dart`'s `kCluePeriodLevels`). Named to
/// mirror the `FlowLevel` shape Issue #247 will add to the app's own enum
/// (a `superHeavy` level, and a not-bleeding state distinct from
/// "unlogged") without depending on that unmerged issue's still-unstable
/// enum: this type is reconciled to whatever #247 ships when the
/// bulk-write step (#172) consumes this parser's output.
///
/// **This enum's ordinals do not line up with `FlowLevel`'s**
/// (`lib/domain/models/flow_level.dart`'s `none, spotting, light, medium,
/// heavy` — Clue spotting is its own observation category here, never a
/// flow level; see `clue_option_map.dart`) — never convert between the
/// two by `.index`.
///
/// **Interim collapse rules, until #247 merges** (both lossy — this is
/// exactly why **#172 (the bulk-write step) must not consume this
/// parser's output before #247 merges**, or these collapses become
/// permanent data loss rather than a temporary interim mapping):
/// - [superHeavy] has no `FlowLevel` counterpart yet and would collapse
///   to `FlowLevel.heavy`.
/// - [notBleeding] has no `FlowLevel` counterpart distinct from
///   "unlogged" yet and would collapse to `FlowLevel.none` —
///   re-conflating an explicit "not bleeding today" assertion with a day
///   nothing was logged for at all.
enum ClueFlowLevel { notBleeding, light, medium, heavy, superHeavy }

/// Whether a [ClueFlowLevel] records bleeding — mirrors
/// `lib/domain/models/flow_level.dart`'s top-level `isBleed(FlowLevel)`.
/// [ClueFlowLevel.notBleeding] is the only level this excludes; every
/// other level, [ClueFlowLevel.superHeavy] included, counts.
extension ClueFlowLevelBleed on ClueFlowLevel {
  bool get isBleed => this != ClueFlowLevel.notBleeding;
}

/// Why a datapoint escaped to [ClueUnknownDatapoint] instead of being
/// mapped (Issue #199's escape hatch — `observations.raw`).
enum ClueUnknownReason {
  /// The `type` string is not in `clue_option_map.dart`'s table at all
  /// (a brand-new Clue category, or one of the never-attested ones such
  /// as weight).
  unknownType,

  /// `type` is known, but `value`'s shape did not match what that type
  /// expects (e.g. `bbt` with none of its attested numeric keys, or an
  /// option-based type whose `value` is neither `{option}` nor a list of
  /// those).
  unknownValueShape,
}

/// One `{date, type, value}` datapoint from `measurements.json`, after
/// date parsing and category/option mapping. Every subtype carries [date]
/// (the day it applies to) and [clueType] (the original `type` string,
/// kept for diagnostics even once mapped).
abstract class ClueDatapoint {
  ClueDatapoint(this.date, this.clueType);

  final LocalDate date;
  final String clueType;
}

/// Clue's `period` category — feeds cycle/episode reconstruction
/// (`clue_cycle_reconstruction.dart`), never an `observations` row.
/// [level] is [ClueFlowLevel.notBleeding] for the `none` export value: a
/// positive assertion that must never be dropped or read as "no entry".
class CluePeriodDatapoint extends ClueDatapoint {
  CluePeriodDatapoint(LocalDate date, this.level) : super(date, 'period');

  final ClueFlowLevel level;
}

/// Every other option- or free-text-based category (`pain`, `feelings`,
/// `spotting`, `tags`, ...): one row per selected option — multi-select
/// types produce one [ClueObservationDatapoint] per list element.
///
/// [code] is the mapped or passed-through option string. `Observation.code`
/// is free text and never validated against a closed set (Issue #240's own
/// doc comment on that model), so an option `clue_option_map.dart` doesn't
/// recognise still round-trips verbatim here rather than escaping to
/// [ClueUnknownDatapoint] — that escape hatch is reserved for an
/// unrecognised `type` or `value` *shape*, not merely an unrecognised
/// option string within an otherwise-known type. [isNegativeAssertion]
/// marks the documented "nothing happened" states (`pain_free`,
/// `no_sex_today`, discharge's `none`) — distinct from [CluePeriodDatapoint]'s
/// own `period/none` handling.
class ClueObservationDatapoint extends ClueDatapoint {
  ClueObservationDatapoint(
    super.date,
    super.clueType, {
    required this.category,
    required this.code,
    this.isNegativeAssertion = false,
  });

  /// lunarlog `observations.category` (e.g. `pain`, `spotting`, `tags`).
  final String category;

  /// lunarlog `observations.code` — the selected/free-text option,
  /// verbatim unless `clue_option_map.dart` remaps it (e.g.
  /// `period_cramps` -> `cramps`). Never snake_cased or otherwise
  /// normalised — this applies uniformly, which is what makes `tags`'
  /// "never normalised" requirement automatic rather than a special case.
  final String code;

  /// True for `pain_free`, `no_sex_today`, discharge's `none` — an
  /// explicit "nothing happened" state, never a positive symptom.
  final bool isNegativeAssertion;
}

/// `bbt` (and its `temperature`-type alias — Issue #190's LOW-confidence
/// pinned item: some community parsers use `type: "temperature"` for the
/// same category others call `bbt`) — a numeric datapoint, not an option
/// datapoint. [unit] is the literal value-key name the export used
/// (`celsius`, `fahrenheit`, `temperature`, or `value`) — carried through
/// rather than converted, since which physical unit `temperature`/`value`
/// denote is unattested (see `docs/import/clue-mapping.md`).
class ClueNumericDatapoint extends ClueDatapoint {
  ClueNumericDatapoint(
    super.date,
    super.clueType, {
    required this.category,
    required this.valueNum,
    required this.unit,
    this.excluded = false,
  });

  final String category;
  final double? valueNum;
  final String? unit;

  /// BBT's per-point exclusion flag (`value.excluded`, A1-44).
  final bool excluded;
}

/// The escape hatch (Issue #199): an unrecognised `type` or `value` shape,
/// preserved verbatim as [raw] for `observations.raw jsonb` rather than
/// rejected. Never fatal to the rest of the import.
class ClueUnknownDatapoint extends ClueDatapoint {
  ClueUnknownDatapoint(
    super.date,
    super.clueType, {
    required this.reason,
    required this.raw,
  });

  final ClueUnknownReason reason;

  /// The entire original `{date, type, value}` datapoint, as decoded JSON.
  ///
  /// **Carries health content verbatim.** Never log this, put it in a
  /// Sentry breadcrumb, or otherwise interpolate it into a diagnostic
  /// message — it is exactly the kind of payload
  /// `lib/observability/scrub.dart`'s allowlist-shaped scrubber is built
  /// to keep off the wire, and nothing in `lib/domain/import/` is exempt
  /// from that floor.
  final Map<String, Object?> raw;
}
