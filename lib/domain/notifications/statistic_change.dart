/// Cycle-statistic change detection for the `cycleStatisticChange` reminder
/// kind (Issue #178, Clue catalogue item 5).
///
/// The reminder fires on the day the app's own *displayed* cycle statistics
/// shift meaningfully — the issue leaves the threshold to implementation,
/// with the instruction to reuse the prediction engine's own change signal
/// rather than polling averages on a timer. The signal here is exactly the
/// prediction stream: the reminder coordinator observes every
/// [ActivePrediction] emission (one per entry write / sync landing), snapshots
/// the displayed values, and compares against the stored baseline — no timer
/// anywhere.
///
/// **What counts as "displayed"**: the snapshot carries the *rounded* means
/// and the confidence tier — literally the numbers and label the overview
/// renders ([ActivePrediction.meanCycleLengthDays].round(),
/// [ActivePrediction.meanPeriodLengthDays].round(),
/// [ActivePrediction.tier]) — not the raw doubles behind them. A sub-day
/// drift in the raw mean that cannot change the displayed number is not a
/// statistic change a user could ever see, so it never fires.
///
/// **Thresholds (PROVISIONAL)**, named constants like #213's own, pending the
/// same never-performed calibration against real histories (Clue does not
/// publish its own):
///
/// * the displayed confidence tier changes (any [CycleConfidence] transition —
///   including #218's `provisional` displacement when real cycles land);
/// * the displayed mean cycle length moves by at least
///   [kStatisticChangeMinCycleLengthShiftDays];
/// * the displayed mean period length moves by at least
///   [kStatisticChangeMinPeriodLengthShiftDays].
///
/// Pure Dart (R14/R16) with the store codecs the device-local persistence
/// (same posture as the reminder configs — never synced) needs.
library;

import 'dart:convert';

import '../models/local_date.dart';
import '../prediction/prediction.dart'
    show ActivePrediction, CycleConfidence;

/// The minimum displayed-mean shift (in whole days) that counts as a
/// meaningful cycle-length change (PROVISIONAL — see the library doc).
const int kStatisticChangeMinCycleLengthShiftDays = 2;

/// The minimum displayed-mean shift (in whole days) that counts as a
/// meaningful period-length change (PROVISIONAL — see the library doc).
/// Period averages are small integers, so a single displayed day is already
/// visible.
const int kStatisticChangeMinPeriodLengthShiftDays = 1;

/// One observation of the app's displayed cycle statistics: the rounded
/// averages and the confidence tier, exactly as the overview renders them.
class CycleStatisticSnapshot {
  const CycleStatisticSnapshot({
    required this.meanCycleLengthDays,
    required this.meanPeriodLengthDays,
    required this.tier,
  });

  /// The displayed statistics of one live prediction.
  factory CycleStatisticSnapshot.fromPrediction(ActivePrediction prediction) =>
      CycleStatisticSnapshot(
        meanCycleLengthDays: prediction.meanCycleLengthDays.round(),
        meanPeriodLengthDays: prediction.meanPeriodLengthDays.round(),
        tier: prediction.tier,
      );

  final int meanCycleLengthDays;
  final int meanPeriodLengthDays;
  final CycleConfidence tier;

  Map<String, Object?> toJson() => {
        'cycleDays': meanCycleLengthDays,
        'periodDays': meanPeriodLengthDays,
        'tier': tier.name,
      };

  /// Tolerant decode: any malformed field makes the whole snapshot null —
  /// a corrupt baseline reads as "never observed" (the next observation
  /// re-baselines silently) rather than as a fabricated change.
  static CycleStatisticSnapshot? fromJson(Map<String, Object?> json) {
    final cycleDays = json['cycleDays'];
    final periodDays = json['periodDays'];
    final tierName = json['tier'];
    if (cycleDays is! int || periodDays is! int || tierName is! String) {
      return null;
    }
    for (final tier in CycleConfidence.values) {
      if (tier.name == tierName) {
        return CycleStatisticSnapshot(
          meanCycleLengthDays: cycleDays,
          meanPeriodLengthDays: periodDays,
          tier: tier,
        );
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is CycleStatisticSnapshot &&
      other.meanCycleLengthDays == meanCycleLengthDays &&
      other.meanPeriodLengthDays == meanPeriodLengthDays &&
      other.tier == tier;

  @override
  int get hashCode =>
      Object.hash(meanCycleLengthDays, meanPeriodLengthDays, tier);

  @override
  String toString() => 'CycleStatisticSnapshot(cycle: $meanCycleLengthDays, '
      'period: $meanPeriodLengthDays, tier: ${tier.name})';
}

/// Whether the move from [previous] to [current] is a meaningful displayed
/// statistic change (the documented thresholds above). Two identical
/// snapshots never are.
bool isMeaningfulStatisticChange(
  CycleStatisticSnapshot previous,
  CycleStatisticSnapshot current,
) {
  if (previous == current) return false;
  if (previous.tier != current.tier) return true;
  final cycleShift =
      (current.meanCycleLengthDays - previous.meanCycleLengthDays).abs();
  if (cycleShift >= kStatisticChangeMinCycleLengthShiftDays) return true;
  final periodShift =
      (current.meanPeriodLengthDays - previous.meanPeriodLengthDays).abs();
  return periodShift >= kStatisticChangeMinPeriodLengthShiftDays;
}

/// Encodes the per-profile baseline map (`profileId -> last-observed
/// snapshot`) as the JSON string the settings store keeps — the same document
/// shape [decodeStatisticBaselines] parses.
String encodeStatisticBaselines(
        Map<String, CycleStatisticSnapshot> baselines) =>
    jsonEncode({
      'v': 1,
      'baselines': {
        for (final entry in baselines.entries) entry.key: entry.value.toJson(),
      },
    });

/// Decodes a stored `reminder_statistic_baselines` value. Anything malformed
/// — not a map, an unparseable string, a profile section that fails its own
/// decode — is dropped: a bad store value degrades to "no baseline yet"
/// (silently re-baselining on the next observation) rather than throwing.
Map<String, CycleStatisticSnapshot> decodeStatisticBaselines(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const {};
  }
  if (decoded is! Map<String, Object?>) return const {};
  final baselines = decoded['baselines'];
  if (baselines is! Map<String, Object?>) return const {};
  final parsed = <String, CycleStatisticSnapshot>{};
  for (final entry in baselines.entries) {
    if (entry.value is! Map<String, Object?>) continue;
    final snapshot =
        CycleStatisticSnapshot.fromJson(entry.value as Map<String, Object?>);
    if (snapshot != null) parsed[entry.key] = snapshot;
  }
  return parsed;
}

/// Encodes the per-profile statistic-change signal map (`profileId -> the
/// date a meaningful change was observed`) as the JSON string the settings
/// store keeps.
String encodeStatisticChangeSignals(Map<String, LocalDate> signals) =>
    jsonEncode({
      'v': 1,
      'signals': {
        for (final entry in signals.entries) entry.key: entry.value.iso,
      },
    });

/// Decodes a stored statistic-change-signal value; malformed dates and
/// malformed payloads degrade to "no signal" (empty map).
Map<String, LocalDate> decodeStatisticChangeSignals(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const {};
  }
  if (decoded is! Map<String, Object?>) return const {};
  final signals = decoded['signals'];
  if (signals is! Map<String, Object?>) return const {};
  final parsed = <String, LocalDate>{};
  for (final entry in signals.entries) {
    final value = entry.value;
    if (value is String && _isIsoDate(value)) {
      parsed[entry.key] = LocalDate.fromIso(value);
    }
  }
  return parsed;
}

bool _isIsoDate(String value) {
  if (value.length != 10) return false;
  return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);
}
