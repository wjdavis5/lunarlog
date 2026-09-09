/// Table-driven category/option mapping spec for the Clue importer (Issue
/// #190). Every map here is data, not control flow — `clue_export_parser.dart`
/// looks entries up rather than branching per `type`/option, which is what
/// keeps that file's own per-method complexity low under the CRAP gate.
///
/// See `docs/import/clue-mapping.md` for the full spec table with
/// confidence levels and citations; this file is that table encoded.
library;

import 'clue_datapoint.dart';

/// One option within a known Clue `type`: [code] remaps the raw export
/// string (e.g. `period_cramps` -> `cramps`); [negative] marks the
/// documented negative assertions (`pain_free`, `no_sex_today`,
/// discharge's `none`). `period`'s own `none` is handled separately by
/// [kCluePeriodLevels], not this table, since it maps to [ClueFlowLevel]
/// rather than an observation code.
class ClueOptionSpec {
  const ClueOptionSpec({this.code, this.negative = false});

  /// Null means "pass the raw option string through unchanged" — most
  /// options are not renamed; `Observation.code` is free text (Issue
  /// #240) and never validated against a closed set, so an option absent
  /// from this spec still round-trips correctly with no entry at all.
  final String? code;

  final bool negative;
}

/// One Clue export `type` (excluding `period` and `bbt`/`temperature`,
/// which have their own dedicated parsing — see `kCluePeriodLevels` and
/// `kClueNumericTypes`): [category] is the lunarlog `observations.category`
/// it lands on; [options] holds only the options that need renaming or a
/// negative-assertion flag. Everything else in a known type passes its
/// raw option string straight through as `code`.
class ClueTypeSpec {
  const ClueTypeSpec(this.category, {this.options = const {}});

  final String category;
  final Map<String, ClueOptionSpec> options;
}

/// `period`'s enum (HIGH confidence — Clue Help Center + real export
/// data): `none` is a positive "not bleeding today" assertion, not an
/// absence of data — see [ClueFlowLevel.notBleeding]'s own doc comment.
/// `very_heavy` is Clue's "Super heavy" level (Issue #247's `superHeavy`).
const Map<String, ClueFlowLevel> kCluePeriodLevels = {
  'none': ClueFlowLevel.notBleeding,
  'light': ClueFlowLevel.light,
  'medium': ClueFlowLevel.medium,
  'heavy': ClueFlowLevel.heavy,
  'very_heavy': ClueFlowLevel.superHeavy,
};

/// `bbt`'s own `type` plus its LOW-confidence `type`-level alias
/// (`temperature` — see `ClueNumericDatapoint`'s doc comment). A `type` in
/// this set is parsed numerically (`clue_export_parser.dart`'s
/// `_mapNumeric`), never looked up in [kClueTypeMap].
const Set<String> kClueNumericTypes = {'bbt', 'temperature'};

/// Value-key variants tried in this order for a numeric datapoint's value
/// map — first present, parseable key wins. `celsius` is HIGH confidence
/// (real export data); the rest are LOW-confidence, conflicting-source
/// variants kept for tolerance per Issue #190's pre-ship pin list.
const List<String> kClueBbtValueKeys = [
  'celsius',
  'fahrenheit',
  'temperature',
  'value',
];

/// Every other attested/medium-confidence Clue `type`, keyed by the
/// export's own `type` string (Issue #190's mapping table). A `type`
/// string not present here (and not in [kClueNumericTypes], and not
/// `period`) escapes to `ClueUnknownDatapoint(reason: unknownType)` per
/// Issue #199 — new/unattested categories (e.g. weight) are handled by
/// simply being absent, no special-casing required.
final Map<String, ClueTypeSpec> kClueTypeMap = {
  // Spotting: own category per #247, single-select, option set
  // undocumented — options pass straight through.
  'spotting': const ClueTypeSpec('spotting'),

  'pain': const ClueTypeSpec(
    'pain',
    options: {
      'period_cramps': ClueOptionSpec(code: 'cramps'),
      'lower_back': ClueOptionSpec(code: 'back_pain'),
      'pain_free': ClueOptionSpec(negative: true),
    },
  ),

  'feelings': const ClueTypeSpec('feelings'),

  'sex_life': const ClueTypeSpec(
    'sex_life',
    options: {
      'no_sex_today': ClueOptionSpec(negative: true),
    },
  ),

  'energy': const ClueTypeSpec('energy'),
  'pms': const ClueTypeSpec('pms'),

  'digestion': const ClueTypeSpec(
    'digestion',
    options: {
      'bloated': ClueOptionSpec(code: 'bloating'),
      'nauseous': ClueOptionSpec(code: 'nausea'),
      'nauseated': ClueOptionSpec(code: 'nausea'),
    },
  ),

  'discharge': const ClueTypeSpec(
    'discharge',
    options: {
      'none': ClueOptionSpec(negative: true),
    },
  ),

  'collection_method': const ClueTypeSpec('collection_method'),
  'social_life': const ClueTypeSpec('social_life'),
  'craving': const ClueTypeSpec('craving'),
  'mind': const ClueTypeSpec('mind'),
  // MEDIUM confidence, historic exports only (A1-8) — likely folded into
  // Mind in the current app; kept so an older export still round-trips.
  'motivation': const ClueTypeSpec('motivation'),
  // MEDIUM confidence, single-parser (A1-10).
  'sleep': const ClueTypeSpec('sleep'),
  'exercise': const ClueTypeSpec('exercise'),
  'stool': const ClueTypeSpec('stool'),
  // Option set not publicly documented (A1-22) — unknown option strings
  // pass through verbatim per #199's escape hatch for options.
  'leisure': const ClueTypeSpec('leisure'),
  'hair': const ClueTypeSpec('hair'),
  // MEDIUM confidence, single-parser (A1-14).
  'skin': const ClueTypeSpec('skin'),
  'medication': const ClueTypeSpec('medication'),
  'appointments': const ClueTypeSpec('appointments'),
  'ailments': const ClueTypeSpec('ailments'),
  // Free text (`[{"option": "<raw user free text>"}]`) — never
  // snake_cased or normalized; this table applies no transform to any
  // type's option strings unless explicitly listed above, so `tags`
  // needs no special case to satisfy that requirement.
  'tags': const ClueTypeSpec('tags'),
  // MEDIUM confidence, option strings unattested (A1-29) — six Clue
  // categories flattened (pill/shot/implant/patch/ring/IUD).
  'birth_control': const ClueTypeSpec('birth_control'),
  // Not in Clue's Help Center category list or the attested `type` list;
  // included defensively (cervical mucus overlaps conceptually with
  // Discharge) as its own category rather than guessed onto `discharge`,
  // since no source documents the two as the same export `type`.
  'mucus': const ClueTypeSpec('mucus'),
  // MEDIUM confidence (A1-24) — option strings unattested.
  'tests': const ClueTypeSpec('tests'),
};
