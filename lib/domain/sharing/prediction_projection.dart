/// The derived-phase snapshot a prediction-only connection shares
/// (issue #151): period days, fertile days, ovulation days, and the PMS
/// window — civil dates only, never a note, tag, or flow value.
///
/// This is the exact payload shape the server allowlists:
/// `supabase/migrations/20260909200000_prediction_connections.sql`'
/// `prediction_projections_payload_keys_check` and its BEFORE trigger
/// reject any other key or non-date value, so [toJson] can never smuggle
/// raw entry content across the projection boundary — the recipient's
/// client receives only what this model holds, by construction on both
/// ends.
///
/// Issue #529 adds [confidenceTier] — the sharer's own [CycleConfidence]
/// tier, carried so the recipient's calendar can show it alongside the
/// disclaimers rather than presenting an undated estimate with no
/// reliability framing. It is nullable end to end (an absent key
/// deserializes to `null`, never a default tier) for backwards
/// compatibility with a payload published before this field existed.
/// Issue #593 widened `prediction_projections_payload_keys_check` and
/// `enforce_prediction_projection_payload()`
/// (`supabase/migrations/20260915140000_prediction_projection_confidence_
/// tier.sql`) to allowlist [confidenceTierKey] as an optional,
/// nullable, enum-checked key alongside the original five, so
/// [confidenceTier] now round-trips all the way to a recipient's device —
/// `lib/data/sharing/supabase_prediction_connection_service.dart`'s
/// `publishProjection` ships this model's full [toJson] unmodified.
///
/// The builder reads the sharer's own [ActivePrediction] (issue #213's
/// engine — the only implementation of the algorithm) and derives:
///   * period days — the current open episode's days so far
///     (`lastEpisodeStart`..`today` while `duringEpisode`) plus every
///     forecast cycle's predicted bleed band, strictly after today
///     (matching `forecast.dart`'s forward-only rendering rule);
///   * fertile days / ovulation days — `fertile_window.dart`'s
///     calendar-method back-calculation applied to every forecast cycle,
///     exactly as the sharer's own forward calendar renders them;
///   * PMS days — the engine's own data-driven PMS band
///     (`ActivePrediction.pms`'s `predictedStart`..`predictedEnd`, issue
///     #220), the same span the sharer's calendar renders; empty when the
///     engine has no PMS estimate (fewer usable intervals than the
///     prediction gate requires), so nothing derived is shared. (This
///     replaced the pre-#220 fixed lead window, exactly as this doc
///     always anticipated; the projection shape did not change.)
///
/// Pure Dart: no Flutter and no Supabase types cross this boundary.
library;

import '../models/local_date.dart';
import '../prediction/fertile_window.dart';
import '../prediction/pms.dart';
import '../prediction/prediction.dart';

/// Server-side bound, mirrored in the migration's payload trigger: each
/// date array holds at most 100 entries (a 12-cycle forecast of the
/// longest valid cycles stays well under it; the cap is defence in depth
/// against a future horizon change silently breaking publishes).
const int kProjectionMaxDatesPerField = 100;

/// One derived-phase snapshot: the complete content of a prediction-only
/// share. Nothing else exists server-side to show the recipient.
class PredictionProjection {
  const PredictionProjection({
    required this.generatedAt,
    required this.periodDays,
    required this.fertileDays,
    required this.ovulationDays,
    required this.pmsDays,
    this.confidenceTier,
  });

  /// The civil date the snapshot was computed as-of.
  final LocalDate generatedAt;

  /// Predicted (and current-episode) bleed days, sorted, deduplicated.
  final List<LocalDate> periodDays;

  /// Estimated fertile-window days, sorted, deduplicated.
  final List<LocalDate> fertileDays;

  /// Estimated ovulation days, sorted, deduplicated.
  final List<LocalDate> ovulationDays;

  /// PMS-window days, sorted, deduplicated.
  final List<LocalDate> pmsDays;

  /// The sharer's own confidence tier at publish time (issue #529),
  /// reusing [CycleConfidence] rather than inventing a second vocabulary.
  /// `null` when the field is absent from the payload (an older snapshot,
  /// or one published before this field existed) — never a guessed
  /// default. See the library doc comment for why this currently never
  /// crosses the wire in production.
  final CycleConfidence? confidenceTier;

  /// The server's derived-phase key allowlist, in wire order.
  /// [confidenceTierKey] is allowlisted too (Issue #593) but held
  /// separately below since it is optional/nullable rather than one of
  /// these five always-present derived-phase arrays.
  static const List<String> allowedKeys = [
    'generated_at',
    'period_days',
    'fertile_days',
    'ovulation_days',
    'pms_days',
  ];

  /// The wire key for [confidenceTier] when present (Issue #593: an
  /// allowlisted, optional, nullable, enum-checked key alongside
  /// [allowedKeys] — see `enforce_prediction_projection_payload()` in
  /// `supabase/migrations/20260915140000_prediction_projection_confidence_
  /// tier.sql`).
  static const String confidenceTierKey = 'confidence_tier';

  /// This model's own wire form, and the full contract
  /// `upsert_prediction_projection` accepts (Issue #593): the five
  /// allowlisted keys plus [confidenceTierKey] when [confidenceTier] is
  /// non-null (omitted, not null, when absent — the same "absent means
  /// unknown" convention the rest of this payload already uses). Dates
  /// are `yyyy-MM-dd`.
  Map<String, Object?> toJson() => {
        'generated_at': generatedAt.iso,
        'period_days': [for (final d in periodDays) d.iso],
        'fertile_days': [for (final d in fertileDays) d.iso],
        'ovulation_days': [for (final d in ovulationDays) d.iso],
        'pms_days': [for (final d in pmsDays) d.iso],
        if (confidenceTier != null) confidenceTierKey: confidenceTier!.name,
      };

  /// Parses the server's payload. Unknown keys are ignored (a newer
  /// client's extra derived fields must not crash an older reader);
  /// malformed dates are skipped rather than thrown, so one bad value
  /// never blanks a whole calendar. [confidenceTierKey] is optional: an
  /// absent key, or a value that is not one of [CycleConfidence]'s names,
  /// deserializes to `null` rather than throwing or guessing a tier
  /// (issue #529's backwards-compatibility requirement).
  static PredictionProjection fromJson(Map<String, dynamic> json) {
    LocalDate? parseDate(Object? value) {
      if (value is! String) return null;
      try {
        return LocalDate.fromIso(value);
      } on ArgumentError {
        return null;
      }
    }

    List<LocalDate> parseDates(Object? value) {
      if (value is! List) return const [];
      final dates = <LocalDate>[
        for (final item in value) ?parseDate(item),
      ]..sort();
      return dates;
    }

    CycleConfidence? parseTier(Object? value) {
      if (value is! String) return null;
      for (final tier in CycleConfidence.values) {
        if (tier.name == value) return tier;
      }
      return null;
    }

    final generatedAt = parseDate(json['generated_at']);
    return PredictionProjection(
      generatedAt: generatedAt ?? LocalDate.today(),
      periodDays: parseDates(json['period_days']),
      fertileDays: parseDates(json['fertile_days']),
      ovulationDays: parseDates(json['ovulation_days']),
      pmsDays: parseDates(json['pms_days']),
      confidenceTier: parseTier(json[confidenceTierKey]),
    );
  }

  /// Every marked date, for calendar lookups. Phase precedence on overlap
  /// (period over fertile over PMS) is the caller's choice; this map is
  /// purely a lookup.
  Map<LocalDate, Set<PredictionPhase>> phasesByDate() {
    final map = <LocalDate, Set<PredictionPhase>>{};
    void add(List<LocalDate> days, PredictionPhase phase) {
      for (final d in days) {
        map.putIfAbsent(d, () => {}).add(phase);
      }
    }

    add(periodDays, PredictionPhase.period);
    add(fertileDays, PredictionPhase.fertile);
    add(ovulationDays, PredictionPhase.ovulation);
    add(pmsDays, PredictionPhase.pms);
    return map;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PredictionProjection &&
          other.generatedAt == generatedAt &&
          _sameDays(other.periodDays, periodDays) &&
          _sameDays(other.fertileDays, fertileDays) &&
          _sameDays(other.ovulationDays, ovulationDays) &&
          _sameDays(other.pmsDays, pmsDays) &&
          other.confidenceTier == confidenceTier;

  @override
  int get hashCode => Object.hash(
        generatedAt,
        Object.hashAll(periodDays),
        Object.hashAll(fertileDays),
        Object.hashAll(ovulationDays),
        Object.hashAll(pmsDays),
        confidenceTier,
      );

  @override
  String toString() => 'PredictionProjection(asOf: ${generatedAt.iso}, '
      'period: ${periodDays.length}d, fertile: ${fertileDays.length}d, '
      'ovulation: ${ovulationDays.length}d, pms: ${pmsDays.length}d, '
      'confidenceTier: ${confidenceTier?.name})';
}

/// The phases a prediction-only connection shares (issue #151: period,
/// fertile, ovulation, PMS — nothing else).
enum PredictionPhase { period, fertile, ovulation, pms }

bool _sameDays(List<LocalDate> a, List<LocalDate> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Builds the projection the sharer's device publishes, from the same
/// [ActivePrediction] the sharer's own calendar renders (see the library
/// doc for the per-field derivation). Decomposed into one private helper
/// per phase so each stays under the quality gate's CRAP ceiling.
///
/// [ActivePrediction.tier] is always populated on this type (it is a
/// required, non-nullable field there), so [confidenceTier] is always set
/// here — the only caller of this function ([LocalPredictionProjectionPublisher])
/// already skips publishing entirely when the current prediction is not
/// an [ActivePrediction] (`NotEnoughHistory`, no tier to share).
PredictionProjection buildPredictionProjection(ActivePrediction prediction) {
  // Issue LLA-064: a regimen-schedule (pack-driven withdrawal-bleed)
  // prediction carries no ovulatory signal — see [PredictionBasis]'s own
  // doc comment — so a share never derives fertile/ovulation days from
  // one, matching the sharer's own calendar (`forecast.dart`).
  final fertile = prediction.basis == PredictionBasis.regimenSchedule
      ? (fertile: <LocalDate>{}, ovulation: <LocalDate>{})
      : _fertileAndOvulationDays(prediction.forecast);
  return PredictionProjection(
    generatedAt: prediction.today,
    periodDays: _cappedSorted(_periodDays(prediction)),
    fertileDays: _cappedSorted(fertile.fertile),
    ovulationDays: _cappedSorted(fertile.ovulation),
    confidenceTier: prediction.tier,
    pmsDays: _cappedSorted(_pmsBand(prediction.pms)),
  );
}

/// The current open episode's days so far plus every forecast cycle's
/// predicted bleed band (strictly after today — KTD3's forward-only rule,
/// matching forecast.dart's own rendering).
Set<LocalDate> _periodDays(ActivePrediction prediction) {
  final today = prediction.today;
  final days = <LocalDate>{};
  if (prediction.duringEpisode) {
    var d = prediction.lastEpisodeStart;
    while (d.difference(today) <= 0 && days.length < kProjectionMaxDatesPerField) {
      days.add(d);
      d = d.addDays(1);
    }
  }
  for (final cycle in prediction.forecast) {
    for (var i = 0; i < cycle.estimatedPeriodLengthDays; i++) {
      final date = cycle.start.addDays(i);
      if (!date.isAfter(today)) continue;
      if (days.length >= kProjectionMaxDatesPerField) break;
      days.add(date);
    }
  }
  return days;
}

/// The fertile-window back-calculation of every forecast cycle
/// (`fertile_window.dart`, exactly as the sharer's own forward calendar
/// renders them).
({Set<LocalDate> fertile, Set<LocalDate> ovulation}) _fertileAndOvulationDays(
    List<PredictedCycle> forecast) {
  final fertileDays = <LocalDate>{};
  final ovulationDays = <LocalDate>{};
  for (final cycle in forecast) {
    final window = fertileWindowFor(start: cycle.start, tier: cycle.tier);
    ovulationDays.add(window.estimatedOvulation);
    var d = window.windowStart;
    while (d.difference(window.windowEnd) <= 0) {
      fertileDays.add(d);
      d = d.addDays(1);
    }
  }
  return (fertile: fertileDays, ovulation: ovulationDays);
}

/// The engine's own data-driven band (issue #220) — the same span the
/// sharer's calendar renders, and empty when the engine has no PMS
/// estimate at all, so a projection never invents a window the engine
/// does not stand behind.
Set<LocalDate> _pmsBand(PmsEstimate? pms) {
  final days = <LocalDate>{};
  if (pms == null) return days;
  var d = pms.predictedStart;
  while (d.difference(pms.predictedEnd) <= 0 &&
      days.length < kProjectionMaxDatesPerField) {
    days.add(d);
    d = d.addDays(1);
  }
  return days;
}

List<LocalDate> _cappedSorted(Set<LocalDate> days) {
  final sorted = days.toList()..sort();
  return sorted.length <= kProjectionMaxDatesPerField
      ? sorted
      : sorted.sublist(0, kProjectionMaxDatesPerField);
}
