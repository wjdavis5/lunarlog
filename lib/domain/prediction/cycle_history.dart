/// Cycle history (issue #132; roadmap U2, R4/R5/R6, KTD2): the pure
/// derivation behind the history list, its statistics, and the confidence
/// framing — plus the codecs for the device-local state the feature
/// persists (the per-profile omission list and the late-resolver snooze).
///
/// Nothing here is Flutter; nothing derived is ever persisted (pure
/// recompute per stream emission, matching `prediction.dart`). Only the
/// two small settings values below cross the store boundary, and both are
/// device-local by settled decision (issue #132 brief, KTD2) — an
/// omission made on one device does not sync, which the history UI states
/// in a caption rather than hiding.
///
/// Vocabulary is cycle-only (R13/PRIVACY.md): period/cycle days, no
/// fertility or ovulation wording anywhere in this file.
library;

import 'dart:convert';

import '../episodes/episodes.dart';
import '../models/day_entry.dart';
import '../models/local_date.dart';
import '../repositories/settings_store.dart';
import 'prediction.dart' show kMaxAveragedCycles, kMinCycleDays, kMaxCycleDays;

// ----------------------------------------------------------- persistence keys

/// Device-local omission list for [profileId] (KTD2): a JSON array of
/// cycle-start ISO dates excluded from the averages.
String omittedCyclesSettingKey(String profileId) => 'omittedCycles.$profileId';

/// Device-local late-resolver snooze for [profileId]: the ISO date until
/// which the "remind me in three days" choice keeps the late resolver
/// quiet (it reappears on that date).
String lateSnoozeSettingKey(String profileId) => 'lateSnooze.$profileId';

/// Days a "remind me in three days" choice quiets the late resolver (R6).
const int kLateSnoozeDays = 3;

/// Parses a stored omission list. Unset, empty, or malformed values
/// degrade to an empty set; a partially malformed list keeps what parses.
/// Never throws — a corrupt value must not take the prediction stream
/// down with it.
Set<LocalDate> parseOmittedCycles(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const {};
  }
  if (decoded is! List) return const {};
  final dates = <LocalDate>{};
  for (final item in decoded) {
    if (item is! String) continue;
    try {
      dates.add(LocalDate.fromIso(item));
    } on ArgumentError {
      // Skip a value that is not a real date; keep the rest.
    }
  }
  return dates;
}

/// Encodes an omission list canonically (sorted ISO dates) so equal sets
/// always produce equal strings.
String encodeOmittedCycles(Iterable<LocalDate> dates) =>
    jsonEncode([for (final date in (dates.toList()..sort())) date.iso]);

/// Parses a stored snooze date; unset/empty/malformed means "no snooze".
LocalDate? parseLateSnooze(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return LocalDate.fromIso(raw);
  } on ArgumentError {
    return null;
  }
}

String encodeLateSnooze(LocalDate date) => date.iso;

/// Whether the late resolver stays quiet on [today] (i.e. [snoozeUntil]
/// is still in the future). The resolver reappears on the snooze date
/// itself — "remind me in three days" means it asks again on day three.
bool isLateSnoozed({
  required LocalDate today,
  required LocalDate? snoozeUntil,
}) => snoozeUntil != null && today.isBefore(snoozeUntil);

// ------------------------------------------------------------- read/write seam

/// Read-modify-write access to one profile's device-local omission list.
/// Deliberately tiny: a read, a set-union/difference, a write — the drift
/// watch on the key drives every recomputation downstream.
class CycleExclusionList {
  CycleExclusionList(this._settings);

  final SettingsStore _settings;

  Future<Set<LocalDate>> load(String profileId) async => parseOmittedCycles(
    await _settings.get(omittedCyclesSettingKey(profileId)),
  );

  Stream<Set<LocalDate>> watch(String profileId) => _settings
      .watch(omittedCyclesSettingKey(profileId))
      .map(parseOmittedCycles);

  /// Adds [cycleStart] (idempotent). Used by the history list's omit
  /// toggle and by "skip this cycle" in the late resolver, which pass the
  /// same cycle-start key.
  Future<void> omit(String profileId, LocalDate cycleStart) async {
    await _write(profileId, {...await load(profileId), cycleStart});
  }

  /// Removes [cycleStart] (idempotent) — the reversible half of R4.
  Future<void> include(String profileId, LocalDate cycleStart) async {
    final next = {...await load(profileId)}..remove(cycleStart);
    await _write(profileId, next);
  }

  Future<void> _write(String profileId, Set<LocalDate> dates) => _settings.set(
    omittedCyclesSettingKey(profileId),
    encodeOmittedCycles(dates),
  );
}

// ------------------------------------------------------------------- models

/// R5: the confidence framing, mapped from usable-cycle count and spread
/// by [deriveCycleHistory]. `learning` is also the honest label for thin
/// history where no estimate exists at all.
enum CycleConfidence {
  high,
  learning,
  irregular;

  String get label => switch (this) {
    high => 'High confidence',
    learning => 'Learning',
    irregular => 'Irregular',
  };

  /// Plain-language summary (R5); deliberately free of numbers so it can
  /// sit under thin-data states without leaking partial estimates.
  String get summary => switch (this) {
    high =>
      'Recent cycles are steady — estimates are at their most '
          'reliable.',
    learning =>
      'Still learning — estimates improve after a few more '
          'cycles.',
    irregular => 'Cycles vary a lot — treat estimates as rough guides.',
  };
}

/// One row of the history list (R4). A cycle is "episode start through
/// next start" (KTD2): [lengthDays] is the gap to the next episode start,
/// so the open cycle (the newest episode, no next start yet) carries a
/// null length and pins to the top of the list.
class CycleHistoryItem {
  const CycleHistoryItem({
    required this.start,
    required this.lengthDays,
    required this.omitted,
  });

  /// The episode start this cycle begins on; also the omission-list key.
  final LocalDate start;

  /// Days to the next episode start; null for the open cycle.
  final int? lengthDays;

  /// Whether [start] is in the device-local omission list (a manual omit,
  /// or a skip of the open cycle via the late resolver).
  final bool omitted;

  bool get isOpen => lengthDays == null;

  /// Outside the 15–60 validity window — automatically flagged and never
  /// averaged, regardless of omission (the auto-flag half of R4).
  bool get outlier =>
      lengthDays != null &&
      (lengthDays! < kMinCycleDays || lengthDays! > kMaxCycleDays);

  /// Whether this cycle's length feeds the averages.
  bool get countedInAverages => lengthDays != null && !outlier && !omitted;
}

/// The full history surface for one profile: list, statistics, counts,
/// and confidence (R4/R5). Everything is a pure function of the episodes
/// and the omission set.
class CycleHistoryView {
  const CycleHistoryView({
    required this.items,
    required this.episodeCount,
    required this.completedCycleCount,
    required this.validCycleCount,
    required this.averagedCycleCount,
    required this.meanCycleLengthDays,
    required this.meanPeriodLengthDays,
    required this.variationDays,
    required this.confidence,
  });

  /// Reverse-chronological; the open cycle (if any) pinned first (R4).
  final List<CycleHistoryItem> items;

  final int episodeCount;

  /// All completed cycles, valid and invalid alike.
  final int completedCycleCount;

  /// Completed cycles within the 15–60 window (ignoring omissions).
  final int validCycleCount;

  /// Valid and not omitted — the cycles the averages actually use.
  final int averagedCycleCount;

  /// Mean of the most recent [kMaxAveragedCycles] counted lengths — the
  /// same number that drives the estimate. Null when nothing is counted.
  final double? meanCycleLengthDays;

  /// Mean episode (bleed) length over episodes whose start is not
  /// omitted, the open episode included. Null when there are no episodes.
  final double? meanPeriodLengthDays;

  /// Max − min of the averaged cycle lengths (the spread half of R5);
  /// null when fewer than two lengths are averaged.
  final int? variationDays;

  /// Null only when there is no history at all.
  final CycleConfidence? confidence;
}

/// PROVISIONAL (issue #132): the confidence thresholds below are named
/// constants pending measurement against real histories (roadmap
/// assumption); they are expected to move once aggregate data exists.
const int kConfidenceMinAveragedCycles = 3;
const int kProvisionalIrregularSpreadDays = 7;
const double kProvisionalIrregularValidRatio = 0.6;

/// PROVISIONAL (see above): fewer averaged cycles than this reads as
/// `learning`; a raw valid-ratio or spread beyond these reads as
/// `irregular`.
CycleConfidence _confidenceFor({
  required int averagedCount,
  required int validCount,
  required int completedCount,
  required int variationDays,
}) {
  if (averagedCount < kConfidenceMinAveragedCycles) {
    return CycleConfidence.learning;
  }
  final ratio = completedCount == 0 ? 1.0 : validCount / completedCount;
  if (ratio < kProvisionalIrregularValidRatio) {
    return CycleConfidence.irregular;
  }
  if (variationDays > kProvisionalIrregularSpreadDays) {
    return CycleConfidence.irregular;
  }
  return CycleConfidence.high;
}

/// Derives the history view. Pure; the order of [episodes] is irrelevant.
CycleHistoryView deriveCycleHistory({
  required List<Episode> episodes,
  Set<LocalDate> omittedCycleStarts = const {},
}) {
  final sorted = [...episodes]..sort();
  if (sorted.isEmpty) {
    return const CycleHistoryView(
      items: [],
      episodeCount: 0,
      completedCycleCount: 0,
      validCycleCount: 0,
      averagedCycleCount: 0,
      meanCycleLengthDays: null,
      meanPeriodLengthDays: null,
      variationDays: null,
      confidence: null,
    );
  }

  final starts = [for (final episode in sorted) episode.start];
  // Open cycle pinned first (R4); completed cycles after it, newest first.
  final items = <CycleHistoryItem>[
    CycleHistoryItem(
      start: starts.last,
      lengthDays: null,
      omitted: omittedCycleStarts.contains(starts.last),
    ),
    for (var i = starts.length - 2; i >= 0; i--)
      CycleHistoryItem(
        start: starts[i],
        lengthDays: starts[i + 1].difference(starts[i]),
        omitted: omittedCycleStarts.contains(starts[i]),
      ),
  ];

  final counted = <int>[
    for (final item in items)
      if (item.countedInAverages) item.lengthDays!,
  ];
  final averaged = counted.length <= kMaxAveragedCycles
      ? counted
      : counted.sublist(counted.length - kMaxAveragedCycles);
  final bleedLengths = <int>[
    for (final episode in sorted)
      if (!omittedCycleStarts.contains(episode.start)) episode.lengthDays,
  ];
  final validCount = items
      .where((item) => !item.isOpen && !item.outlier)
      .length;
  final variation = averaged.length < 2 ? null : _spreadOf(averaged);

  return CycleHistoryView(
    items: List.unmodifiable(items),
    episodeCount: sorted.length,
    completedCycleCount: items.length - 1,
    validCycleCount: validCount,
    averagedCycleCount: counted.length,
    meanCycleLengthDays: _meanOf(averaged),
    meanPeriodLengthDays: _meanOf(bleedLengths),
    variationDays: variation,
    confidence: _confidenceFor(
      averagedCount: counted.length,
      validCount: validCount,
      completedCount: items.length - 1,
      variationDays: variation ?? 0,
    ),
  );
}

double? _meanOf(List<int> values) =>
    values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;

int _spreadOf(List<int> values) =>
    values.reduce((a, b) => a > b ? a : b) -
    values.reduce((a, b) => a < b ? a : b);

/// Convenience: derives episodes from raw entries first (mirrors
/// [computePredictionFromEntries]).
CycleHistoryView deriveCycleHistoryFromEntries({
  required Iterable<DayEntry> entries,
  Set<LocalDate> omittedCycleStarts = const {},
}) => deriveCycleHistory(
  episodes: deriveEpisodes(bleedDatesOf(entries)),
  omittedCycleStarts: omittedCycleStarts,
);
