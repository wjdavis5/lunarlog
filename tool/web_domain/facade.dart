/// The web client's JSON-in/JSON-out facade over `lib/domain` (issue #1251,
/// epic #831 slice for the domain module).
///
/// `lib/domain` is pure Dart (161 files, no Flutter/`dart:io`/`dart:ui`/Drift
/// imports), so it compiles to JavaScript with `dart compile js` (dart2js —
/// plain script output, no `wasm-unsafe-eval`, so it loads under the #1249
/// CSP's `script-src 'self'`). This file is the single entry surface the
/// compiled module exposes; `main.dart` is the only line of `dart:js_interop`
/// glue, and everything here is plain Dart so `flutter test` can pin it.
///
/// **Every call is JSON-in/JSON-out** — `handleFacadeCall(method, requestJson)`
/// returns a response envelope:
///
/// ```
/// {"ok": true, "data": <method-specific JSON>}
/// {"ok": false, "error": "<human-readable message>"}
/// ```
///
/// The facade never throws across the boundary: a malformed request, an
/// unknown method, or an invalid input value (a bad date, an unknown IANA
/// zone) comes back as `{"ok": false, ...}` for the TypeScript wrapper to
/// surface. Domain logic itself stays untouched — this file only decodes
/// inputs, mirrors the resolution order `CyclePredictionService` applies on
/// device, runs the pure functions, and serializes their outputs.
///
/// **Input shape is the app's own export shape** (`account_export.dart`'s
/// per-row keys: `localDate`, `flow`, `tags`, `notePrivate`, `pms`, ...).
/// The web client maps its Supabase rows onto that shape once, and the same
/// codec then feeds prediction, history, insights, and the export builder.
/// Two documented extensions beyond the export row: `profileId` (the export
/// nests entries under a profile; a flat request needs the id supplied) and
/// `deletedAt` (the web client holds tombstones the device repositories
/// never return). `deletedAt` is accepted on input and then dropped: every
/// method here mirrors what its device counterpart reads from live-only
/// repositories (`ProfilesRepository.list`, `DayEntriesRepository.listForProfile`),
/// so a tombstoned profile or entry reaches no output — export included
/// (issue #1274: `buildAccountExport`'s contract is that its inputs are
/// already tombstone-free; feeding it one would put deleted data back into
/// the world as a live row).
///
/// **Timezone data is loaded explicitly** (`package:timezone`'s
/// `latest_10y` window — every zone *name* with ten years of transition
/// data; a cycle tracker computes on civil dates within that window, and
/// the full `latest_all` database would roughly quadruple the module's
/// size for no function it can reach). Date-math requests carry the
/// browser's IANA zone as `tz`; the facade resolves it against the
/// database (an unknown name is an error, never a silent UTC fallback) and
/// installs it as the process-local location. `today` is always passed in —
/// the facade never reads a clock, exactly like `DayEntryPolicy.validateDate`'s
/// own contract.
///
/// Resolution order for `predict` mirrors `CyclePredictionService`'s
/// (`prediction_service.dart`'s `_resolve`): predictions-disabled, then the
/// life-stage-mode suppression (issue #528), then the birth-control branch
/// (issue #233, via the `birthControlMethodInEffectOn` seam), then
/// `computePredictionFromEntries`, then the #218 provisional seeding from
/// onboarding facts as the only fallback.
library;

import 'dart:convert';

import 'package:lunarlog/domain/birth_control.dart';
import 'package:lunarlog/domain/content/cycle_literacy_library.dart';
import 'package:lunarlog/domain/export/account_export.dart';
import 'package:lunarlog/domain/insights/bbt_chart.dart';
import 'package:lunarlog/domain/insights/cramp_prediction.dart';
import 'package:lunarlog/domain/insights/cycle_insights_calculator.dart';
import 'package:lunarlog/domain/insights/cycle_recap.dart';
import 'package:lunarlog/domain/insights/symptom_trends.dart';
import 'package:lunarlog/domain/logging/custom_tag_registry.dart';
import 'package:lunarlog/domain/logging/day_entry_policy.dart';
import 'package:lunarlog/domain/logging/today_log.dart';
import 'package:lunarlog/domain/logging/tracking_preferences.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/measurement_unit.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/models/profile_relationship.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/cycle_subphase.dart';
import 'package:lunarlog/domain/prediction/forecast.dart';
import 'package:lunarlog/domain/prediction/pms.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/prediction/setup_period_mark.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart';
import 'package:lunarlog/domain/sharing/invite_links.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'iana_aliases.dart';

/// Facade surface version, reported by `main.dart` as `lunarlogDomain
/// .version`. Bump on a breaking request/response shape change so the
/// TypeScript wrapper can pin what it validates.
const String kWebDomainFacadeVersion = '1';

// ---------------------------------------------------------------------------
// Dispatch
// ---------------------------------------------------------------------------

/// Runs one facade call. [method] names one of the supported calls;
/// [requestJson] is its request object, JSON-encoded. Never throws: every
/// failure mode is an `{"ok": false, "error": ...}` envelope (see this
/// file's doc comment).
String handleFacadeCall(String method, String requestJson) {
  try {
    final Object? decoded = jsonDecode(requestJson);
    if (decoded is! Map<String, Object?>) {
      return _error('request must be a JSON object');
    }
    final Object? data = switch (method) {
      'predict' => predictFromJson(decoded),
      'cycleHistory' => cycleHistoryFromJson(decoded),
      'insights' => insightsFromJson(decoded),
      'bbtChart' => bbtChartFromJson(decoded),
      'cycleRecap' => cycleRecapFromJson(decoded),
      'phaseInsights' => phaseInsightsFromJson(decoded),
      'calendarForecast' => calendarForecastFromJson(decoded),
      'validateDayEntryDate' => validateDayEntryDateFromJson(decoded),
      'buildExport' => buildExportFromJson(decoded),
      'parseInviteLink' => parseInviteLinkFromJson(decoded),
      'todayLog' => todayLogFromJson(decoded),
      _ => throw ArgumentError.value(method, 'method', 'unknown facade method'),
    };
    return jsonEncode({'ok': true, 'data': data});
  } on FormatException catch (e) {
    return _error('request is not valid JSON: ${e.message}');
  } on ArgumentError catch (e) {
    return _error(e.message?.toString() ?? e.toString());
  }
}

String _error(String message) => jsonEncode({'ok': false, 'error': message});

// ---------------------------------------------------------------------------
// predict
// ---------------------------------------------------------------------------

/// The service-equivalent prediction resolution (see this file's doc
/// comment for the order), JSON-in/JSON-out.
///
/// Request keys: `today` (ISO date, required), `tz` (IANA name, required),
/// `entries` (export-row day entries, required), `profileId` (optional, the
/// entries' profile), `omittedCycleStarts` (optional ISO dates), `facts`
/// (optional onboarding facts), `birthControl` (optional raw state),
/// `lifecycleMode` (optional raw mode string; absent means `tracking`),
/// `predictionsEnabled` (optional, default true).
Map<String, Object?> predictFromJson(Map<String, Object?> request) {
  final today = _requireToday(request);
  _configureTimeZone(_requireTimeZone(request));
  final entries = _requireEntries(request);
  return predictionToJson(
    _resolvePrediction(
      entries: entries,
      today: today,
      omittedCycleStarts: _optionalDates(
        request['omittedCycleStarts'],
        'omittedCycleStarts',
      ),
      facts: _optionalFacts(request['facts']),
      birthControlState: _optionalBirthControl(request['birthControl']),
      lifecycleMode: LifecycleMode.fromDb(
        _optionalString(request['lifecycleMode']),
      ),
      predictionsEnabled: _optionalBool(
        request['predictionsEnabled'],
        defaultValue: true,
      ),
    ),
  );
}

/// Issue #528 + #233 + #218 + #225, in `CyclePredictionService._resolve`'s
/// exact order — the one piece of the *service* (not the engine) the web
/// client must reproduce, because the service's own class is welded to
/// repository streams.
CyclePrediction _resolvePrediction({
  required List<DayEntry> entries,
  required LocalDate today,
  required Set<LocalDate> omittedCycleStarts,
  required CycleFacts? facts,
  required BirthControlState? birthControlState,
  required LifecycleMode lifecycleMode,
  required bool predictionsEnabled,
}) {
  if (!predictionsEnabled) return const PredictionsDisabled();
  if (CyclePredictionService.suppressesPrediction(lifecycleMode)) {
    return PredictionsSuppressed(lifecycleMode: lifecycleMode);
  }
  final birthControl = _activeBirthControlFor(birthControlState, today);
  final computed = computePredictionFromEntries(
    entries: entries,
    today: today,
    omittedCycleStarts: omittedCycleStarts,
    birthControl: birthControl,
  );
  if (birthControl == null &&
      computed is NotEnoughHistory &&
      (facts?.canSeed ?? false)) {
    // Issue #1392: the same entries-aware seed the service uses, so a
    // period logged since onboarding re-anchors the web estimate too.
    // Issue #1412: and the same omission list, so a cycle skipped on a
    // phone advances the web's provisional estimate as well.
    return seedProvisionalPredictionFromEntries(
      facts: facts!,
      entries: entries,
      today: today,
      omittedCycleStarts: omittedCycleStarts,
    );
  }
  return computed;
}

/// `CyclePredictionService._activeBirthControlFor`, verbatim: resolve the
/// raw state through the `birthControlMethodInEffectOn` seam and carry the
/// (tolerantly parsed) regimen start as the pack anchor. Null when no
/// tracked method is in effect on [today].
ActiveBirthControl? _activeBirthControlFor(
  BirthControlState? state,
  LocalDate today,
) {
  if (state == null) return null;
  final method = birthControlMethodInEffectOn(
    storedMethod: state.method,
    startedOn: state.startedOn,
    stoppedOn: state.stoppedOn,
    date: today,
  );
  if (method == null) return null;
  return ActiveBirthControl(
    method: method,
    startedOn: _parseStartDate(state.startedOn),
  );
}

LocalDate? _parseStartDate(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  try {
    return LocalDate.fromIso(iso);
  } on ArgumentError {
    return null;
  }
}

// ---------------------------------------------------------------------------
// cycleHistory
// ---------------------------------------------------------------------------

/// The history list and its statistics (`deriveCycleHistoryFromEntries`).
///
/// Request keys: `today`, `tz`, `entries` (required), `profileId`
/// (optional), `omittedCycleStarts` (optional).
Map<String, Object?> cycleHistoryFromJson(Map<String, Object?> request) {
  final today = _requireToday(request);
  _configureTimeZone(_requireTimeZone(request));
  final entries = _requireEntries(request);
  // The per-cycle bleed-day counts the web cycle comparison renders
  // (issue #1253) come from the same episodes the view itself derives
  // from — computed here, beside the call, so lib/domain stays untouched
  // and the count is the engine's own episode length, never a
  // re-derivation.
  final bleedDaysByStart = <String, int>{
    for (final episode in deriveEpisodes(bleedDatesOf(entries)))
      episode.start.iso: episode.lengthDays,
  };
  return historyViewToJson(
    deriveCycleHistoryFromEntries(
      entries: entries,
      today: today,
      omittedCycleStarts: _optionalDates(
        request['omittedCycleStarts'],
        'omittedCycleStarts',
      ),
    ),
    bleedDaysByStart: bleedDaysByStart,
  );
}

/// Serializes [view] with the derived flags the UI branches on (`open`,
/// `outlier`, `countedInAverages`) alongside the stored ones, plus each
/// item's own bleed-day count (`bleedDaysByStart[start]`, null when the
/// episode list no longer carries that start — defensive, never expected).
Map<String, Object?> historyViewToJson(
  CycleHistoryView view, {
  Map<String, int> bleedDaysByStart = const {},
}) => {
  'items': [
    for (final item in view.items)
      {
        'start': item.start.iso,
        'lengthDays': item.lengthDays,
        'omitted': item.omitted,
        'open': item.isOpen,
        'outlier': item.outlier,
        'countedInAverages': item.countedInAverages,
        'bleedDays': bleedDaysByStart[item.start.iso],
      },
  ],
  'episodeCount': view.episodeCount,
  'completedCycleCount': view.completedCycleCount,
  'validCycleCount': view.validCycleCount,
  'averagedCycleCount': view.averagedCycleCount,
  'meanCycleLengthDays': view.meanCycleLengthDays,
  'meanPeriodLengthDays': view.meanPeriodLengthDays,
  'variationDays': view.variationDays,
  'confidence': view.confidence?.name,
};

// ---------------------------------------------------------------------------
// insights
// ---------------------------------------------------------------------------

/// The home screen's insight report (`CycleInsightsCalculator.compute`),
/// computed against the same service-equivalent prediction `predict`
/// resolves (the cramp predictor needs the active estimate's next-start
/// anchor; suppression, disabled, and thin-history pass a null
/// prediction through, exactly like the device UI does).
///
/// Request keys: the same set `predict` takes.
Map<String, Object?> insightsFromJson(Map<String, Object?> request) {
  final today = _requireToday(request);
  _configureTimeZone(_requireTimeZone(request));
  final entries = _requireEntries(request);
  final prediction = _resolvePrediction(
    entries: entries,
    today: today,
    omittedCycleStarts: _optionalDates(
      request['omittedCycleStarts'],
      'omittedCycleStarts',
    ),
    facts: _optionalFacts(request['facts']),
    birthControlState: _optionalBirthControl(request['birthControl']),
    lifecycleMode: LifecycleMode.fromDb(
      _optionalString(request['lifecycleMode']),
    ),
    predictionsEnabled: _optionalBool(
      request['predictionsEnabled'],
      defaultValue: true,
    ),
  );
  final report = CycleInsightsCalculator.compute(
    entries: entries,
    episodes: deriveEpisodes(bleedDatesOf(entries)),
    prediction: prediction is ActivePrediction ? prediction : null,
  );
  return insightsReportToJson(report);
}

/// Serializes a [CycleInsightsReport]. `frequencyByCycleDay` and
/// `flowByCycleDay` carry cycle-day numbers as keys; JSON object keys are
/// strings, so they are stringified here (the Zod side reads them back as
/// `record<string, number>`).
///
/// The display strings the phone computes above the payload
/// (`SymptomPattern.timingSummary`, `TrendDirection.displayName`,
/// `CrampPrediction.summaryText`) are carried here as well (issue #1796):
/// the web client renders them instead of re-deriving Dart string logic in
/// TypeScript, the same rule `todayLog` follows for its labels.
Map<String, Object?> insightsReportToJson(CycleInsightsReport report) => {
  'symptomPatterns': [
    for (final pattern in report.symptomPatterns)
      {
        'tag': pattern.tag,
        'totalOccurrences': pattern.totalOccurrences,
        'cycleCount': pattern.cycleCount,
        'frequencyByCycleDay': {
          for (final entry in pattern.frequencyByCycleDay.entries)
            '${entry.key}': entry.value,
        },
        'peakCycleDays': [...pattern.peakCycleDays],
        'trend': pattern.trend.name,
        'trendDisplayName': pattern.trend.displayName,
        'timingSummary': pattern.timingSummary,
        'meetsThreshold': pattern.meetsThreshold,
      },
  ],
  'flowPattern': _flowPatternToJson(report.flowPattern),
  'crampPrediction': _crampPredictionToJson(report.crampPrediction),
  'analyzedCycleCount': report.analyzedCycleCount,
  'hasEnoughData': report.hasEnoughData,
};

Map<String, Object?>? _flowPatternToJson(FlowPattern? pattern) {
  if (pattern == null) return null;
  return {
    'flowByCycleDay': {
      for (final day in pattern.flowByCycleDay.entries)
        '${day.key}': {
          for (final flow in day.value.entries) flow.key.name: flow.value,
        },
    },
    'typicalPeakFlow': pattern.typicalPeakFlow.toDb(),
    'typicalPeakDay': pattern.typicalPeakDay,
  };
}

Map<String, Object?>? _crampPredictionToJson(CrampPrediction? prediction) {
  if (prediction == null) return null;
  return {
    'predictedCycleDays': [...prediction.predictedCycleDays],
    'predictedDates': [for (final date in prediction.predictedDates) date.iso],
    'observedCycleCount': prediction.observedCycleCount,
    'totalCyclesAnalyzed': prediction.totalCyclesAnalyzed,
    'summaryText': prediction.summaryText,
    'disclaimer': prediction.disclaimer,
  };
}

// ---------------------------------------------------------------------------
// bbtChart
// ---------------------------------------------------------------------------

/// `bbtChart` (issue #1796): the BBT chart's per-cycle series, the same
/// `BbtChartData` the Analysis tab's chart consumes (`deriveBbtChartData`),
/// so the web plots exactly what the phone plots.
///
/// Request keys: `entries` (required - the same set `predict` takes), and
/// `observations` (optional): the profile's measurement rows, each carrying
/// `dayEntryId` (the day it was logged on), `category`, `valueNum`, `unit`,
/// `source`, `excluded`, and `deletedAt`. A row naming no day among
/// `entries`, a deleted row, or a row without a category is skipped here;
/// everything else the chart itself skips (another category, an excluded
/// row, a missing value) is skipped by `deriveBbtChartData`.
///
/// Response `data`: `{"series": [{"cycleStart", "points": [{"cycleDay",
/// "celsius", "date"}]}], "maxCycleDay", "isEmpty"}`. Celsius is canonical;
/// the web converts to the profile's display unit at render time.
Map<String, Object?> bbtChartFromJson(Map<String, Object?> request) {
  final entries = _requireEntries(request);
  final chart = deriveBbtChartData(
    episodes: deriveEpisodes(bleedDatesOf(entries)),
    observations: _observationsAcrossEntries(request['observations'], entries),
  );
  return bbtChartDataToJson(chart);
}

/// The live rows among [raw]'s, each resolved onto its own day among
/// [entries] by `dayEntryId`. A row naming no day, or a day not present in
/// [entries], is skipped. The row's own update instant crosses the boundary
/// (issue #1821): one date can carry more than one live BBT row, and
/// `deriveBbtChartData` breaks that tie by `updatedAt`; a row that carries
/// none falls back to its day entry's.
List<Observation> _observationsAcrossEntries(
  Object? raw,
  List<DayEntry> entries,
) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw ArgumentError('observations must be a JSON array');
  }
  final byId = {for (final entry in entries) entry.id: entry};
  final observations = <Observation>[];
  for (var i = 0; i < raw.length; i++) {
    final json = raw[i];
    if (json is! Map<String, Object?>) {
      throw ArgumentError('observations[$i] must be a JSON object');
    }
    if (_optionalDateTime(json['deletedAt']) != null) continue;
    final entry = byId[_optionalString(json['dayEntryId'])];
    if (entry == null) continue;
    final category = _optionalString(json['category']);
    if (category == null) continue;
    observations.add(
      _observationFor(
        entry,
        category: ObservationCategory.fromCode(category),
        valueNum: _optionalNum(json['valueNum'], 'observations[$i].valueNum'),
        unit: _optionalString(json['unit']),
        source: ObservationSource.fromDb(_optionalString(json['source'])),
        excluded: _optionalBool(json['excluded'], defaultValue: false),
        updatedAt: _optionalDateTime(json['updatedAt']),
      ),
    );
  }
  return observations;
}

/// Serializes [BbtChartData] in the form the chart draws: the most recent
/// cycles carrying data (most recent last, capped the way the app's chart
/// caps the overlay), each point with its cycle day, Celsius value, civil
/// date, and the domain's own x/y fractions, each series with its overlay
/// opacity, plus the y-axis Celsius range for the caption. A painter -
/// Flutter's or the web's - only turns these fractions into pixels; nothing
/// about the geometry is recomputed outside `lib/domain/insights/
/// bbt_chart.dart`.
Map<String, Object?> bbtChartDataToJson(BbtChartData chart) {
  final recent = bbtChartRecentSeries(chart);
  final (minCelsius, maxCelsius) = bbtChartValueRange(chart.allCelsiusValues);
  return {
    'series': [
      for (var i = 0; i < recent.length; i++)
        {
          'cycleStart': recent[i].cycleStart.iso,
          'opacity': bbtChartCycleOpacity(recent.length - 1 - i, recent.length),
          'points': [
            for (final point in recent[i].points)
              {
                'cycleDay': point.cycleDay,
                'celsius': point.celsius,
                'date': point.date.iso,
                'xFraction': bbtChartXFraction(
                  point.cycleDay,
                  chart.maxCycleDay,
                ),
                'yFraction': bbtChartYFraction(
                  point.celsius,
                  minCelsius,
                  maxCelsius,
                ),
              },
          ],
        },
    ],
    'maxCycleDay': chart.maxCycleDay,
    'minCelsius': minCelsius,
    'maxCelsius': maxCelsius,
    'isEmpty': chart.isEmpty,
  };
}

// ---------------------------------------------------------------------------
// cycleRecap
// ---------------------------------------------------------------------------

/// `cycleRecap` (issue #1796): the cycle-end recap the app offers when a new
/// period start closes the previous cycle (`deriveCycleRecap`), in the form
/// the card reads. The device-local pieces stay on the device: the
/// previous-statistics snapshot is not accepted (the web keeps nothing, so
/// the change facts read as the model's no-snapshot case), and the returned
/// `CycleStatisticSnapshot` is not carried.
///
/// Request keys: the same set `insights` takes.
/// Response `data`: `{"recap": null}` when fewer than two episodes exist,
/// else the recap's facts - cycle number and starts, lengths and deltas,
/// the estimate's means, spread and confidence, the change flags, the
/// recurring symptoms with their cycle days, and the cramp cluster days.
Map<String, Object?> cycleRecapFromJson(Map<String, Object?> request) {
  final today = _requireToday(request);
  _configureTimeZone(_requireTimeZone(request));
  final entries = _requireEntries(request);
  final prediction = _resolvePrediction(
    entries: entries,
    today: today,
    omittedCycleStarts: _optionalDates(
      request['omittedCycleStarts'],
      'omittedCycleStarts',
    ),
    facts: _optionalFacts(request['facts']),
    birthControlState: _optionalBirthControl(request['birthControl']),
    lifecycleMode: LifecycleMode.fromDb(
      _optionalString(request['lifecycleMode']),
    ),
    predictionsEnabled: _optionalBool(
      request['predictionsEnabled'],
      defaultValue: true,
    ),
  );
  final report = CycleInsightsCalculator.compute(
    entries: entries,
    episodes: deriveEpisodes(bleedDatesOf(entries)),
    prediction: prediction is ActivePrediction ? prediction : null,
  );
  final recap = deriveCycleRecap(
    entries: entries,
    prediction: prediction,
    report: report,
    today: today,
  );
  return {'recap': recap == null ? null : cycleRecapToJson(recap)};
}

/// Serializes a [CycleRecap]. Every fact is the model's own field; the
/// device-local `currentSnapshot` is deliberately not carried, so the change
/// flags read as the no-snapshot case the model documents.
Map<String, Object?> cycleRecapToJson(CycleRecap recap) => {
  'cycleNumber': recap.cycleNumber,
  'cycleStart': recap.cycleStart.iso,
  'previousCycleStart': recap.previousCycleStart?.iso,
  'cycleLengthDays': recap.cycleLengthDays,
  'previousCycleLengthDays': recap.previousCycleLengthDays,
  'lengthChangeDays': recap.lengthChangeDays,
  'bleedDayCountDelta': recap.bleedDayCountDelta,
  'hasEstimate': recap.hasEstimate,
  'confidence': recap.confidence.name,
  'meanCycleLengthDays': recap.meanCycleLengthDays,
  'meanPeriodLengthDays': recap.meanPeriodLengthDays,
  'spreadDays': recap.spreadDays,
  'usableCycleCount': recap.usableCycleCount,
  'statisticChange': recap.statisticChange,
  'tierChanged': recap.tierChanged,
  'previousConfidence': recap.previousConfidence?.name,
  'meanCycleShiftDays': recap.meanCycleShiftDays,
  'meanPeriodShiftDays': recap.meanPeriodShiftDays,
  'recurringSymptoms': [
    for (final symptom in recap.recurringSymptoms)
      {'tag': symptom.tag, 'cycleDays': [...symptom.cycleDays]},
  ],
  'crampCycleDays': recap.crampCycleDays == null
      ? null
      : [...recap.crampCycleDays!],
};

// ---------------------------------------------------------------------------
// phaseInsights
// ---------------------------------------------------------------------------

/// `phaseInsights` (issue #1796): the open cycle's current hormonal subphase,
/// as the Analysis tab's phase card reads it (`deriveSubphase`). The card's
/// display strings - the subphase name, its hormonal summary, what to track,
/// the hedged notice, the explainer, the day-range text - are the domain's
/// own, carried here like the insights and recap payloads.
///
/// Request keys: the same set `predict` takes.
/// Response `data`: `{"phase": null, "basis": null}` when the prediction is
/// not active; `{"phase": null, "basis": <name>}` when it is active but
/// non-statistical (a pack-driven or hormonal prediction has no ovulatory
/// subphase - issue #1118 - and the web renders the basis's own copy); else
/// `{"phase": {...}, "basis": "statistical"}` with the subphase's facts and
/// display strings, the cycle day and range, the dates, the hedge, and the
/// source provenance.
Map<String, Object?> phaseInsightsFromJson(Map<String, Object?> request) {
  final today = _requireToday(request);
  _configureTimeZone(_requireTimeZone(request));
  final entries = _requireEntries(request);
  final prediction = _resolvePrediction(
    entries: entries,
    today: today,
    omittedCycleStarts: _optionalDates(
      request['omittedCycleStarts'],
      'omittedCycleStarts',
    ),
    facts: _optionalFacts(request['facts']),
    birthControlState: _optionalBirthControl(request['birthControl']),
    lifecycleMode: LifecycleMode.fromDb(
      _optionalString(request['lifecycleMode']),
    ),
    predictionsEnabled: _optionalBool(
      request['predictionsEnabled'],
      defaultValue: true,
    ),
  );
  if (prediction is! ActivePrediction) {
    return {'phase': null, 'basis': null};
  }
  final basis = prediction.basis.name;
  if (prediction.basis != PredictionBasis.statistical) {
    return {'phase': null, 'basis': basis};
  }
  return {
    'phase': phaseInfoToJson(
      deriveSubphase(prediction: prediction),
    ),
    'basis': basis,
  };
}

/// Serializes a [CycleSubphaseInfo]. Every field is the model's own; the
/// day-range text and the subphase's display strings are carried so the web
/// renders them rather than re-deriving Dart string logic, and the primary
/// article's title comes from the bundled library so the web can label its
/// link without carrying the library itself.
Map<String, Object?> phaseInfoToJson(CycleSubphaseInfo info) => {
  'subphase': info.subphase.id,
  'displayName': info.subphase.displayName,
  'hormonalSummary': info.subphase.hormonalSummary,
  'whatToTrack': info.subphase.whatToTrack,
  'primaryArticleId': info.subphase.primaryArticleId,
  'primaryArticleTitle':
      CycleLiteracyLibrary.getArticleById(info.subphase.primaryArticleId)?.title,
  'cycleDay': info.cycleDay,
  'startCycleDay': info.startCycleDay,
  'endCycleDay': info.endCycleDay,
  'cycleDayRangeText': info.cycleDayRangeText,
  'startDate': info.startDate.iso,
  'endDate': info.endDate.iso,
  'isHedged': info.isHedged,
  'hedgedNotice': info.hedgedNotice,
  'biologicalExplainer': info.biologicalExplainer,
  'source': info.source,
  'reviewDate': info.reviewDate,
};

// ---------------------------------------------------------------------------
// validateDayEntryDate
// ---------------------------------------------------------------------------

/// `DayEntryPolicy.validateDate`, JSON-in/JSON-out.
///
/// Request keys: `date` (the candidate ISO date, required), `today`
/// (required), `birthYear` (optional int). Response `data` is
/// `{"status": "valid" | "futureDate" | "beforeBirthYear"}`.
Map<String, Object?> validateDayEntryDateFromJson(
  Map<String, Object?> request,
) {
  final date = _requireLocalDate(request, 'date');
  final today = _requireToday(request);
  final validation = DayEntryPolicy.validateDate(
    date,
    today: today,
    birthYear: _optionalInt(request['birthYear'], 'birthYear'),
  );
  final violation = validation.violation;
  return {'status': violation == null ? 'valid' : violation.name};
}

// ---------------------------------------------------------------------------
// buildExport
// ---------------------------------------------------------------------------

/// Builds an export document from web-held data (`buildAccountExport`) so
/// a web export restores on a phone (issue #1251's acceptance for the
/// export builder).
///
/// Tombstoned rows never reach the document (issue #1274): a profile with
/// `deletedAt` set is skipped here — its nested entries go with it, the
/// way the export nests them — and entry tombstones are dropped by the
/// shared entry decoder (`_entriesFromJson`). `buildAccountExport`'s
/// contract (`account_export.dart`'s header) is that its inputs are
/// already tombstone-free, so the filter has to happen before it runs; the
/// phone's own repositories do exactly this exclusion for the device
/// export.
///
/// Request keys: `exportedAt` (ISO datetime, required — the caller stamps
/// the moment so the facade never reads a clock), `appVersion` (required —
/// the web app's own version string), `appName` (optional), `profiles`
/// (required) — each an export-shaped profile whose `dayEntries` are the
/// export-shaped rows. The other payload kinds the phone exports
/// (observations, care notes, visit prep, modes, overrides, merge events,
/// custom tags, guardian notes) stay defaulted-empty in this v1: the web
/// client cannot read them yet (they are #831 follow-up slices), and the
/// phone's importer treats their absence as "nothing to add", not as
/// corruption. Documented v1 limitation, revisited when the web client
/// grows those surfaces.
Map<String, Object?> buildExportFromJson(Map<String, Object?> request) {
  final exportedAtIso = _optionalString(request['exportedAt']);
  if (exportedAtIso == null || exportedAtIso.isEmpty) {
    throw ArgumentError('exportedAt is required');
  }
  final exportedAt = DateTime.tryParse(exportedAtIso);
  if (exportedAt == null) {
    throw ArgumentError.value(
      exportedAtIso,
      'exportedAt',
      'not an ISO-8601 datetime',
    );
  }
  final appVersion = _optionalString(request['appVersion']);
  if (appVersion == null || appVersion.isEmpty) {
    throw ArgumentError('appVersion is required');
  }
  final rawProfiles = request['profiles'];
  if (rawProfiles is! List || rawProfiles.isEmpty) {
    throw ArgumentError('profiles must be a non-empty JSON array');
  }
  final profiles = <Profile>[];
  final entriesByProfile = <String, List<DayEntry>>{};
  final profileModesByProfile = <String, ProfileLifecycleMode?>{};
  for (var i = 0; i < rawProfiles.length; i++) {
    final raw = rawProfiles[i];
    if (raw is! Map<String, Object?>) {
      throw ArgumentError.value(i, 'profiles[$i]', 'not a JSON object');
    }
    final profile = profileFromJson(raw, 'profiles[$i]');
    // Issue #1274: a tombstoned profile is excluded exactly like
    // ProfilesRepository.list excludes it for the phone's export — its
    // nested entries go with it, since the document nests them under it.
    if (profile.deletedAt != null) continue;
    profiles.add(profile);
    entriesByProfile[profile.id] = _entriesFromJson(
      raw['dayEntries'],
      profile.id,
      'profiles[$i].dayEntries',
    );
    profileModesByProfile[profile.id] = _optionalProfileMode(
      raw['profileMode'],
      'profiles[$i].profileMode',
    );
  }
  return buildAccountExport(
    profiles: profiles,
    entriesByProfile: entriesByProfile,
    profileModesByProfile: profileModesByProfile,
    exportedAt: exportedAt,
    appName: _optionalString(request['appName']) ?? kAccountExportAppName,
    appVersion: appVersion,
  );
}

// ---------------------------------------------------------------------------
// parseInviteLink
// ---------------------------------------------------------------------------

/// `parseInviteLink`, JSON-in/JSON-out.
///
/// Request keys: `url` (the candidate link, required), `linkDomain`
/// (optional configured domain). Response `data` is the parsed link or
/// `null` for anything that is not one (the domain function's own
/// contract).
Object? parseInviteLinkFromJson(Map<String, Object?> request) {
  final url = _optionalString(request['url']);
  if (url == null || url.isEmpty) return null;
  final Uri uri;
  try {
    uri = Uri.parse(url);
  } on FormatException {
    return null;
  }
  final link = parseInviteLink(
    uri,
    linkDomain: _optionalString(request['linkDomain']) ?? '',
  );
  if (link == null) return null;
  return {
    'code': link.code,
    'profileId': link.profileId,
    'kind': link.kind,
    'isClaim': link.isClaim,
    'isPrediction': link.isPrediction,
  };
}

// ---------------------------------------------------------------------------
// todayLog
// ---------------------------------------------------------------------------

/// What is logged for one day, as the Today log card says it (issue #1489
/// in the app; the browser version's card asks here so the two cannot say
/// different things). Every rule is `lib/domain/logging/today_log.dart`'s:
/// whether anything is logged ([TodayLog.hasContent]), which flow the day
/// reads as ([TodayLog.flowLine]), which tags are named, by what label, and
/// how many are only counted ([todayLogTagsOf]), and which reading the day
/// sheet would open on ([TodayLog.bbt], [TodayLog.weight]).
///
/// Request keys:
///
/// * `entry` — the day's entry as an export-shaped row, or null/absent when
///   the day has none. A tombstoned row is nothing logged.
/// * `observations` (optional) — the rows attached to that entry, each with
///   `dayEntryId`, `category`, `valueNum`, `unit`, `source`, and
///   `deletedAt`. A tombstoned row, and a row attached to another entry,
///   are dropped here, as the device's per-entry read drops them.
/// * `customTags` (optional) — the profile's own tag registry, each row
///   with `code`, `displayName`, and `deletedAt`. A tombstoned row no
///   longer names anything; a retired one still does.
/// * `bbtUnit` / `weightUnit` (optional) — the profile's display units; a
///   reading is answered in them, whatever unit it was stored in.
///
/// Response: `hasContent`; `flow`, the level to label (`light`, `medium`,
/// `heavy`, `super_heavy`, `spotting`, `not_bleeding`) with bleed already
/// winning over spotting, or null when the day records no flow;
/// `hasSpotting`; `pms`; `tags`, the labels to show, already limited and in
/// stored order; `moreTagCount`, the tags past the limit plus the ones that
/// are counted and never named; `bbt` and `weight`, each `{value, unit}` or
/// null; and `hasNote`.
///
/// **The note's text is never in the response**, only the fact that one
/// exists. Nor is any tag code: a label, or a count. A day with nothing
/// logged answers the same shape with every field empty, so a tombstone
/// says nothing about what it used to hold.
Map<String, Object?> todayLogFromJson(Map<String, Object?> request) {
  final log = _todayLogFromJson(request);
  final entry = log.entry;
  if (entry == null || !log.hasContent) return _emptyTodayLog;
  final tags = todayLogTagsOf(
    entry.tags,
    _customTagsFromJson(request['customTags'], entry),
  );
  final bbtUnit = BbtUnit.fromDb(_optionalString(request['bbtUnit']));
  final weightUnit = WeightUnit.fromDb(_optionalString(request['weightUnit']));
  final bbt = log.bbt;
  final weight = log.weight;
  return {
    'hasContent': true,
    'flow': switch (log.flowLine) {
      null => null,
      TodayLogFlow.bleed => entry.flow.toDb(),
      TodayLogFlow.spotting => 'spotting',
      TodayLogFlow.notBleeding => FlowLevel.notBleeding.toDb(),
    },
    'hasSpotting': log.hasSpotting,
    'pms': entry.pms,
    'tags': tags.shown,
    'moreTagCount': tags.moreCount,
    'bbt': bbt == null
        ? null
        : {
            'value': convertTemperature(
              bbt.valueNum!,
              from: BbtUnit.fromDb(bbt.unit),
              to: bbtUnit,
            ),
            'unit': bbtUnit.toDb(),
          },
    'weight': weight == null
        ? null
        : {
            'value': convertWeight(
              weight.valueNum!,
              from: WeightUnit.fromDb(weight.unit),
              to: weightUnit,
            ),
            'unit': weightUnit.toDb(),
          },
    'hasNote': log.hasNote,
  };
}

/// The answer for a day with nothing logged.
const Map<String, Object?> _emptyTodayLog = {
  'hasContent': false,
  'flow': null,
  'hasSpotting': false,
  'pms': false,
  'tags': <String>[],
  'moreTagCount': 0,
  'bbt': null,
  'weight': null,
  'hasNote': false,
};

/// Decodes the request's entry and the observations attached to it into
/// the [TodayLog] the device's own watch would build.
TodayLog _todayLogFromJson(Map<String, Object?> request) {
  final rawEntry = request['entry'];
  if (rawEntry == null) return const TodayLog();
  if (rawEntry is! Map<String, Object?>) {
    throw ArgumentError('entry must be a JSON object or null');
  }
  final entry = dayEntryFromJson(
    rawEntry,
    profileId: _optionalString(rawEntry['profileId']) ?? 'web',
    field: 'entry',
  );
  final observations = _observationsFromJson(request['observations'], entry);
  return TodayLog(
    entry: entry,
    observations: [
      ...observations,
      // A row stored before spotting became its own record (issue #247)
      // carries it as the flow level. The device's read gives such a row a
      // spotting record when it has none
      // (`listForDayEntryWithLegacyAlias`); so does this one.
      if (_isLegacySpottingRow(entry) &&
          !observations.any(
            (o) => o.category == ObservationCategory.spotting,
          ))
        _observationFor(entry, category: ObservationCategory.spotting),
    ],
  );
}

bool _isLegacySpottingRow(DayEntry entry) =>
    entry.deletedAt == null &&
    // ignore: deprecated_member_use_from_same_package
    entry.flow == FlowLevel.spotting;

/// The live observations attached to [entry] among [raw]'s rows.
List<Observation> _observationsFromJson(Object? raw, DayEntry entry) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw ArgumentError('observations must be a JSON array');
  }
  final observations = <Observation>[];
  for (var i = 0; i < raw.length; i++) {
    final json = raw[i];
    if (json is! Map<String, Object?>) {
      throw ArgumentError('observations[$i] must be a JSON object');
    }
    if (_optionalDateTime(json['deletedAt']) != null) continue;
    final dayEntryId = _optionalString(json['dayEntryId']);
    if (dayEntryId != null && dayEntryId != entry.id) continue;
    final category = _optionalString(json['category']);
    if (category == null) continue;
    observations.add(
      _observationFor(
        entry,
        category: ObservationCategory.fromCode(category),
        valueNum: _optionalNum(json['valueNum'], 'observations[$i].valueNum'),
        unit: _optionalString(json['unit']),
        source: ObservationSource.fromDb(_optionalString(json['source'])),
      ),
    );
  }
  return observations;
}

/// One observation of [entry]'s day. The log reads only its category,
/// value, unit and source; the rest is the entry's own, save `updatedAt`:
/// a caller carrying the row's own update instant (the BBT chart's rows do,
/// issue #1821) supplies it, and a row without one falls back to the
/// entry's. `excluded` (BBT's own per-point exclusion flag, A1-44) is read
/// by the BBT chart's rows.
Observation _observationFor(
  DayEntry entry, {
  required ObservationCategory category,
  double? valueNum,
  String? unit,
  ObservationSource source = ObservationSource.manual,
  bool excluded = false,
  DateTime? updatedAt,
}) => Observation(
  id: '',
  dayEntryId: entry.id,
  profileId: entry.profileId,
  localDate: entry.localDate,
  tz: entry.tz,
  category: category,
  valueNum: valueNum,
  unit: unit,
  excluded: excluded,
  source: source,
  updatedAt: updatedAt ?? entry.updatedAt,
);

/// The live rows of the profile's own tag registry among [raw]'s. The log
/// reads only a row's code and display name.
List<CustomTag> _customTagsFromJson(Object? raw, DayEntry entry) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw ArgumentError('customTags must be a JSON array');
  }
  final tags = <CustomTag>[];
  for (var i = 0; i < raw.length; i++) {
    final json = raw[i];
    if (json is! Map<String, Object?>) {
      throw ArgumentError('customTags[$i] must be a JSON object');
    }
    if (_optionalDateTime(json['deletedAt']) != null) continue;
    final code = _optionalString(json['code']);
    final displayName = _optionalString(json['displayName']);
    if (code == null || displayName == null) continue;
    tags.add(
      CustomTag(
        id: '',
        profileId: entry.profileId,
        code: code,
        displayName: displayName,
        category: kCustomTagCategory,
        createdAt: entry.updatedAt,
        updatedAt: entry.updatedAt,
      ),
    );
  }
  return tags;
}

// ---------------------------------------------------------------------------
// Timezone
// ---------------------------------------------------------------------------

bool _timeZonesInitialized = false;

// A browser's `Intl.DateTimeFormat().resolvedOptions().timeZone` can still
// report legacy link names — the bare `UTC`/`GMT`, and pre-rename ids like
// `Asia/Calcutta`, `Europe/Kiev`, `Asia/Saigon`, `Asia/Katmandu` (issue
// #1273). package:timezone's generated database (both the 10y window and
// `latest`) carries the canonical targets but drops these
// backward-compatibility links, so they are aliased rather than rejected —
// a UTC-offset or renamed-zone user is not an unknown-zone error. The table
// is derived from tzdata's `backward` file, not hand-listed — see
// `iana_aliases.dart` and its generator.

/// Initializes the tz database once (explicitly, per the issue — dart2js
/// tree-shakes nothing here that the domain itself imports) and installs
/// [name] as the process-local location. An unknown IANA name throws an
/// [ArgumentError] (the envelope turns it into an error) — never a silent
/// UTC fallback.
void _configureTimeZone(String name) {
  if (!_timeZonesInitialized) {
    tzdata.initializeTimeZones();
    _timeZonesInitialized = true;
  }
  final resolved = tz.timeZoneDatabase.locations.containsKey(name)
      ? name
      : kIanaLegacyAliases[name];
  if (resolved == null ||
      !tz.timeZoneDatabase.locations.containsKey(resolved)) {
    throw ArgumentError.value(name, 'tz', 'unknown IANA time zone');
  }
  tz.setLocalLocation(tz.getLocation(resolved));
}

// ---------------------------------------------------------------------------
// calendarForecast
// ---------------------------------------------------------------------------

/// The month calendar's per-date forecast lookup (`forecastDayCells`) — the
/// exact cell map the app's month grid paints, so the web calendar renders
/// the app's own forecast math rather than a TypeScript re-derivation
/// (issue #1253; the parity fixtures pin it like every other method).
///
/// Request keys: the same set `predict` takes. The prediction is resolved
/// through the service-equivalent order first; a non-active prediction or
/// a stale history (issue #982 — the app suppresses the whole forecast
/// there, so a stale estimate can never draw bands 31 cycles out) answers
/// an empty cell map under the resolved `kind`, and only a live, fresh
/// `ActivePrediction` produces cells.
///
/// Response: a `kind` (`active` / `notEnoughHistory` / `suppressed` /
/// `disabled`), a `staleHistory` flag, and `cells` — a map keyed
/// `yyyy-MM-dd` whose values carry `predictedBleed`, `cycleDayNumber`
/// (int or null), `pmsBadge`, `crampsBadge`, `fertileWindow`, `tier`,
/// `cycleIndex`, `fertileTier` (tier name or null), and
/// `fertileCycleIndex` (int or null). Only dates strictly after `today`
/// appear (KTD3 — the past stays factual), exactly like the app.
///
/// It also carries `setupPeriodMarkDate` (issue #1476): the `yyyy-MM-dd`
/// day to mark as "last period start from setup", or null. Unlike the
/// cells it is never after `today`.
Map<String, Object?> calendarForecastFromJson(Map<String, Object?> request) {
  final today = _requireToday(request);
  _configureTimeZone(_requireTimeZone(request));
  final entries = _requireEntries(request);
  final prediction = _resolvePrediction(
    entries: entries,
    today: today,
    omittedCycleStarts: _optionalDates(
      request['omittedCycleStarts'],
      'omittedCycleStarts',
    ),
    facts: _optionalFacts(request['facts']),
    birthControlState: _optionalBirthControl(request['birthControl']),
    lifecycleMode: LifecycleMode.fromDb(
      _optionalString(request['lifecycleMode']),
    ),
    predictionsEnabled: _optionalBool(
      request['predictionsEnabled'],
      defaultValue: true,
    ),
  );
  final staleHistory = prediction is ActivePrediction && prediction.staleHistory;
  final cells = <String, Object?>{};
  if (prediction is ActivePrediction && !staleHistory) {
    final cycles = deriveForecast(prediction: prediction, today: today);
    // Issue #220: the PMS badge only ever draws inside a non-null
    // estimate's band; the app passes the live estimate's own `pms` here
    // (the same gating `month_calendar.dart` applies).
    final dayCells = forecastDayCells(
      cycles: cycles,
      today: today,
      pms: prediction.pms,
    );
    for (final entry in dayCells.entries) {
      cells[entry.key] = _forecastDayCellToJson(entry.value);
    }
  }
  return {
    'kind': _predictionKindName(prediction),
    'staleHistory': staleHistory,
    'cells': cells,
    // Issue #1476: the day to mark as "last period start from setup", or
    // null. The app's month grid asks the same function, so the two
    // calendars cannot disagree about when the mark shows.
    'setupPeriodMarkDate': setupPeriodMarkDateFor(prediction, today)?.iso,
  };
}

/// The discriminator name `predictionToJson` uses for each kind, so the
/// calendar response's `kind` matches the `predict` response's.
String _predictionKindName(CyclePrediction prediction) => switch (prediction) {
  ActivePrediction() => 'active',
  NotEnoughHistory() => 'notEnoughHistory',
  PredictionsSuppressed() => 'suppressed',
  PredictionsDisabled() => 'disabled',
};

Map<String, Object?> _forecastDayCellToJson(ForecastDayCell cell) => {
  'predictedBleed': cell.predictedBleed,
  'cycleDayNumber': cell.cycleDayNumber,
  'pmsBadge': cell.pmsBadge,
  'crampsBadge': cell.crampsBadge,
  'fertileWindow': cell.fertileWindow,
  'tier': cell.tier.name,
  'cycleIndex': cell.cycleIndex,
  'fertileTier': cell.fertileTier?.name,
  'fertileCycleIndex': cell.fertileCycleIndex,
};

// ---------------------------------------------------------------------------
// Input codecs
// ---------------------------------------------------------------------------

LocalDate _requireToday(Map<String, Object?> request) =>
    _requireLocalDate(request, 'today');

String _requireTimeZone(Map<String, Object?> request) {
  final tz = _optionalString(request['tz']);
  if (tz == null || tz.isEmpty) {
    throw ArgumentError('tz is required (the browser\'s IANA zone)');
  }
  return tz;
}

List<DayEntry> _requireEntries(Map<String, Object?> request) =>
    _entriesFromJson(request['entries'], 'web', 'entries');

List<DayEntry> _entriesFromJson(
  Object? raw,
  String defaultProfileId,
  String field,
) {
  if (raw == null) {
    throw ArgumentError('$field is required');
  }
  if (raw is! List) {
    throw ArgumentError.value(field, field, 'not a JSON array');
  }
  final entries = <DayEntry>[];
  for (var i = 0; i < raw.length; i++) {
    final json = raw[i];
    if (json is! Map<String, Object?>) {
      throw ArgumentError.value(
        '$field[$i]',
        '$field[$i]',
        'not a JSON object',
      );
    }
    final entry = dayEntryFromJson(
      json,
      profileId: _optionalString(json['profileId']) ?? defaultProfileId,
      field: '$field[$i]',
    );
    // Issue #1274: the facade is the web client's stand-in for the device's
    // live-only repositories, so a decoded tombstone is dropped at this
    // boundary instead of flowing into prediction, history, insights, or
    // the export document. (The prediction/history/insights engines filter
    // `deletedAt` defensively too; the export builder deliberately does
    // not — `buildAccountExport`'s contract is tombstone-free inputs.)
    if (entry.deletedAt != null) continue;
    entries.add(entry);
  }
  return entries;
}

/// Decodes one export-shaped day-entry row (`_exportDayEntry`'s keys), plus
/// the two facade extensions documented in this file's header (`profileId`
/// is injected by the caller; `deletedAt` is accepted because the web
/// client holds tombstones the device repositories never return — the
/// caller (`_entriesFromJson`) drops a decoded tombstone instead of using
/// it, so acceptance is transport tolerance, never a live row; issue
/// #1274).
DayEntry dayEntryFromJson(
  Map<String, Object?> json, {
  required String profileId,
  required String field,
}) {
  final id = _optionalString(json['id']);
  if (id == null || id.isEmpty) {
    throw ArgumentError('$field.id is required');
  }
  return DayEntry(
    id: id,
    profileId: profileId,
    localDate: _localDate(json['localDate'], '$field.localDate'),
    tz: _optionalString(json['tz']) ?? 'UTC',
    flow: FlowLevel.fromDb(_optionalString(json['flow'])),
    tags: _stringList(json['tags'], '$field.tags'),
    note: _optionalString(json['note']),
    notePrivate: _optionalBool(json['notePrivate'], defaultValue: false),
    pms: _optionalBool(json['pms'], defaultValue: false),
    updatedAt: _dateTime(json['updatedAt'], '$field.updatedAt'),
    deletedAt: _optionalDateTime(json['deletedAt']),
    source: DayEntrySource.fromDb(_optionalString(json['source'])),
    sourceId: _optionalString(json['sourceId']),
    importId: _optionalString(json['importId']),
  );
}

/// Decodes one export-shaped profile (`_exportProfile`'s keys, minus the
/// payload kinds web v1 does not hold — see [buildExportFromJson]'s doc
/// comment). [field] names the request path for error messages.
Profile profileFromJson(Map<String, Object?> json, String field) {
  final id = _optionalString(json['id']);
  if (id == null || id.isEmpty) {
    throw ArgumentError('$field.id is required');
  }
  final displayName = _optionalString(json['displayName']);
  if (displayName == null || displayName.isEmpty) {
    throw ArgumentError('$field.displayName is required');
  }
  return Profile(
    id: id,
    displayName: displayName,
    isMinor: _optionalBool(json['isMinor'], defaultValue: false),
    mode: ProfileMode.fromDb(_optionalString(json['mode'])),
    irregularFraming: _optionalBoolOrNull(json['irregularFraming']),
    sortOrder: _optionalInt(json['sortOrder'], '$field.sortOrder') ?? 0,
    archivedAt: _optionalDateTime(json['archivedAt']),
    createdAt: _dateTime(json['createdAt'], '$field.createdAt'),
    updatedAt: _dateTime(json['updatedAt'], '$field.updatedAt'),
    deletedAt: _optionalDateTime(json['deletedAt']),
    birthYear: _optionalInt(json['birthYear'], '$field.birthYear'),
    relationship: _optionalRelationship(json['relationship']),
    lastPeriodStart: _optionalLocalDate(json['lastPeriodStart']),
    typicalCycleLengthDays: _optionalInt(
      json['typicalCycleLengthDays'],
      '$field.typicalCycleLengthDays',
    ),
    typicalPeriodLengthDays: _optionalInt(
      json['typicalPeriodLengthDays'],
      '$field.typicalPeriodLengthDays',
    ),
    trackingPreferences: _optionalTrackingPreferences(
      json['trackingPreferences'],
      '$field.trackingPreferences',
    ),
    bbtUnit: BbtUnit.fromDb(_optionalString(json['bbtUnit'])),
    weightUnit: WeightUnit.fromDb(_optionalString(json['weightUnit'])),
  );
}

CycleFacts? _optionalFacts(Object? raw) {
  if (raw == null) return null;
  if (raw is! Map<String, Object?>) {
    throw ArgumentError.value('facts', 'facts', 'not a JSON object');
  }
  return CycleFacts(
    lastPeriodStart: _optionalLocalDate(raw['lastPeriodStart']),
    typicalCycleLengthDays: _optionalInt(
      raw['typicalCycleLengthDays'],
      'facts.typicalCycleLengthDays',
    ),
    typicalPeriodLengthDays: _optionalInt(
      raw['typicalPeriodLengthDays'],
      'facts.typicalPeriodLengthDays',
    ),
  );
}

/// The raw `profile_modes` birth-control columns — the exact
/// [BirthControlState] shape the service's provider hands over.
BirthControlState? _optionalBirthControl(Object? raw) {
  if (raw == null) return null;
  if (raw is! Map<String, Object?>) {
    throw ArgumentError.value(
      'birthControl',
      'birthControl',
      'not a JSON object',
    );
  }
  return (
    method: _optionalString(raw['method']),
    startedOn: _optionalString(raw['startedOn']),
    stoppedOn: _optionalString(raw['stoppedOn']),
  );
}

ProfileRelationship? _optionalRelationship(Object? raw) {
  final value = _optionalString(raw);
  if (value == null || value.isEmpty) return null;
  return ProfileRelationship.fromDb(value);
}

TrackingPreferences? _optionalTrackingPreferences(Object? raw, String field) {
  if (raw == null) return null;
  if (raw is! Map<String, Object?>) {
    throw ArgumentError.value(field, field, 'not a JSON object');
  }
  // The export writes the decoded object; the domain's own codec parses
  // the serialized text form. Re-encode and hand it to the same tolerant
  // parser the sync engine uses — no second decode vocabulary here.
  return TrackingPreferences.fromJsonText(jsonEncode(raw));
}

ProfileLifecycleMode? _optionalProfileMode(Object? raw, String field) {
  if (raw == null) return null;
  if (raw is! Map<String, Object?>) {
    throw ArgumentError.value(field, field, 'not a JSON object');
  }
  return (
    mode: LifecycleMode.fromDb(_optionalString(raw['mode'])),
    modeStartedOn: _optionalString(raw['modeStartedOn']),
    estimatedDueDate: _optionalString(raw['estimatedDueDate']),
    postpartumBirthDate: _optionalString(raw['postpartumBirthDate']),
    birthControlMethod: _optionalString(raw['birthControlMethod']),
    birthControlStartedOn: _optionalString(raw['birthControlStartedOn']),
    birthControlStoppedOn: _optionalString(raw['birthControlStoppedOn']),
  );
}

// ---------------------------------------------------------------------------
// Output codecs
// ---------------------------------------------------------------------------

/// Serializes the sealed [CyclePrediction] union into the discriminated
/// shape the TypeScript side narrows on (`kind`).
Map<String, Object?> predictionToJson(CyclePrediction prediction) =>
    switch (prediction) {
      NotEnoughHistory() => {
        'kind': 'notEnoughHistory',
        'episodeCount': prediction.episodeCount,
        'completedCycleCount': prediction.completedCycleCount,
        'validCycleCount': prediction.validCycleCount,
        'usableCycleCount': prediction.usableCycleCount,
      },
      PredictionsSuppressed() => {
        'kind': 'suppressed',
        'method': prediction.method?.name,
        'lifecycleMode': prediction.lifecycleMode?.name,
      },
      PredictionsDisabled() => const {'kind': 'disabled'},
      ActivePrediction() => _activePredictionToJson(prediction),
    };

Map<String, Object?> _activePredictionToJson(ActivePrediction p) => {
  'kind': 'active',
  'today': p.today.iso,
  'lastEpisodeStart': p.lastEpisodeStart.iso,
  'estimatedNextStart': p.estimatedNextStart.iso,
  'originalEstimatedNextStart': p.originalEstimatedNextStart.iso,
  'averagedCycleLengths': [...p.averagedCycleLengths],
  'meanCycleLengthDays': p.meanCycleLengthDays,
  'cycleDay': p.cycleDay,
  'duringEpisode': p.duringEpisode,
  'completedCycleCount': p.completedCycleCount,
  'validCycleCount': p.validCycleCount,
  'meanPeriodLengthDays': p.meanPeriodLengthDays,
  'spreadDays': p.spreadDays,
  'validRatio': p.validRatio,
  'tier': p.tier.name,
  'basis': p.basis.name,
  'unusuallyLongCycle': p.unusuallyLongCycle,
  'staleHistory': p.staleHistory,
  'daysLate': p.daysLate,
  'daysUntilNextPeriod': p.daysUntilNextPeriod,
  'forecast': [
    for (final cycle in p.forecast)
      {
        'cycleIndex': cycle.cycleIndex,
        'start': cycle.start.iso,
        'estimatedPeriodLengthDays': cycle.estimatedPeriodLengthDays,
        'tier': cycle.tier.name,
        'spreadDays': cycle.spreadDays,
      },
  ],
  'pms': _pmsToJson(p.pms),
};

Map<String, Object?>? _pmsToJson(PmsEstimate? pms) {
  if (pms == null) return null;
  return {
    'meanOnsetDaysBeforeNextPeriod': pms.meanOnsetDaysBeforeNextPeriod,
    'meanLengthDays': pms.meanLengthDays,
    'usableIntervalCount': pms.usableIntervalCount,
    'tier': pms.tier.name,
    'predictedStart': pms.predictedStart.iso,
    'predictedEnd': pms.predictedEnd.iso,
  };
}

// ---------------------------------------------------------------------------
// Small typed readers (shared error wording)
// ---------------------------------------------------------------------------

LocalDate _requireLocalDate(Map<String, Object?> request, String field) {
  final value = request[field];
  if (value == null) {
    throw ArgumentError('$field is required');
  }
  return _localDate(value, field);
}

LocalDate? _optionalLocalDate(Object? raw) {
  final value = _optionalString(raw);
  if (value == null || value.isEmpty) return null;
  return LocalDate.fromIso(value);
}

LocalDate _localDate(Object? raw, String field) {
  final value = _optionalString(raw);
  if (value == null || value.isEmpty) {
    throw ArgumentError('$field is required (yyyy-MM-dd)');
  }
  try {
    return LocalDate.fromIso(value);
  } on ArgumentError {
    throw ArgumentError.value(value, field, 'not an ISO date (yyyy-MM-dd)');
  }
}

DateTime _dateTime(Object? raw, String field) {
  final value = _optionalString(raw);
  if (value == null || value.isEmpty) {
    throw ArgumentError('$field is required (ISO-8601 datetime)');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw ArgumentError.value(value, field, 'not an ISO-8601 datetime');
  }
  return parsed;
}

DateTime? _optionalDateTime(Object? raw) {
  final value = _optionalString(raw);
  if (value == null || value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw ArgumentError.value(value, 'datetime', 'not an ISO-8601 datetime');
  }
  return parsed;
}

String? _optionalString(Object? raw) => raw is String ? raw : null;

int? _optionalInt(Object? raw, String field) {
  if (raw == null) return null;
  if (raw is int) return raw;
  throw ArgumentError.value(raw, field, 'not an integer');
}

double? _optionalNum(Object? raw, String field) {
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();
  throw ArgumentError('$field must be a number');
}

bool _optionalBool(Object? raw, {required bool defaultValue}) {
  if (raw == null) return defaultValue;
  if (raw is bool) return raw;
  throw ArgumentError.value(raw, 'boolean', 'not a boolean');
}

bool? _optionalBoolOrNull(Object? raw) {
  if (raw == null) return null;
  if (raw is bool) return raw;
  throw ArgumentError.value(raw, 'boolean', 'not a boolean');
}

List<String> _stringList(Object? raw, String field) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw ArgumentError.value(field, field, 'not a JSON array');
  }
  return [
    for (var i = 0; i < raw.length; i++)
      if (raw[i] is String) raw[i] as String,
  ];
}

Set<LocalDate> _optionalDates(Object? raw, String field) {
  if (raw == null) return const {};
  if (raw is! List) {
    throw ArgumentError.value(field, field, 'not a JSON array');
  }
  final dates = <LocalDate>{};
  for (var i = 0; i < raw.length; i++) {
    dates.add(_localDate(raw[i], '$field[$i]'));
  }
  return dates;
}
