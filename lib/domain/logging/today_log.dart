/// What is logged for one civil day, as the Today screen reads it (issue
/// #1489).
///
/// Today used to show the estimate and nothing about the day's own log, so
/// a day with cramps logged looked the same as a day with nothing logged.
/// [TodayLog] is the value the Today log card and the floating button's
/// label are both derived from, and [TodayLog.hasContent] is the one rule
/// for "is anything logged today" that the two share.
///
/// Pure Dart with no drift/Flutter imports (R14/R16).
library;

import '../models/day_entry.dart';
import '../models/flow_level.dart';
import '../models/observation.dart';
import '../models/observation_category.dart';
import 'day_sheet_reconciliation.dart' show manualMeasurementIn;

/// One day's live entry and the observations attached to it.
class TodayLog {
  const TodayLog({this.entry, this.observations = const []});

  /// The day's live entry, or null when the day has none.
  final DayEntry? entry;

  /// The live observations attached to [entry]: spotting, and the BBT and
  /// weight readings the day sheet stores outside the entry row. Empty when
  /// there is no entry, or no observations seam to read them from.
  final List<Observation> observations;

  /// Whether the day has a note. Only the fact: nothing that reads a
  /// [TodayLog] for the Today screen is given the note's text.
  bool get hasNote => entry?.note?.trim().isNotEmpty ?? false;

  /// Whether the day carries a spotting record. Spotting is stored as its
  /// own observation, never as a flow level (issue #247), so the entry's
  /// flow alone reads "not bleeding" on a spotting day.
  bool get hasSpotting => observations.any(
        (observation) => observation.category == ObservationCategory.spotting,
      );

  /// The basal body temperature the day sheet shows for this day, if any.
  Observation? get bbt =>
      manualMeasurementIn(observations, ObservationCategory.bbt);

  /// The weight the day sheet shows for this day, if any.
  Observation? get weight =>
      manualMeasurementIn(observations, ObservationCategory.weight);

  /// Whether anything is logged for the day.
  ///
  /// No entry, a tombstoned entry, and an entry left with nothing on it all
  /// count as nothing logged — the day sheet autosaves, so opening it,
  /// picking a tag and taking it off again leaves a live row with no flow,
  /// no tags and no note. The PMS marker and a temperature or weight
  /// reading count as logged: each is something the person entered, and a
  /// day holding only one of them is not an empty day.
  bool get hasContent {
    final entry = this.entry;
    if (entry == null || entry.deletedAt != null) return false;
    return _entryHasContent(entry) || bbt != null || weight != null;
  }

  bool _entryHasContent(DayEntry entry) =>
      entry.flow != FlowLevel.none ||
      entry.tags.isNotEmpty ||
      entry.pms ||
      hasNote;
}
