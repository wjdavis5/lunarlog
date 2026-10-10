/// Generates the web-domain parity fixtures (issue #1251): one JSON file of
/// `{name, method, request, expected}` cases whose `expected` envelopes are
/// computed HERE by the Dart domain itself, committed, and then asserted
/// from both directions:
///
/// * `test/domain/web_domain_fixtures_test.dart` re-runs every case through
///   `handleFacadeCall` and fails when the Dart domain's output drifts from
///   the committed file — a domain change that moves an output must
///   consciously regenerate this file (`dart run
///   tool/web_domain/generate_fixtures.dart`).
/// * `webapp/test/domain/parity.test.ts` runs every case through the
///   **compiled dart2js module** and fails when the compiled module's
///   output drifts from the same file — so Dart and JavaScript are pinned
///   to each other through the committed middle.
///
/// The cases mirror the shapes the Dart domain tests exercise (regular and
/// irregular histories, pack-driven and suppressed predictions, the
/// omission list, provisional seeding, PMS intervals, the date-bounds
/// policy, the export builder, invite links, and what the Today log card
/// says about a day), plus one `seed18m` case
/// shaped like the #710 seeded account (18 months, cycles 26–32 days) —
/// the input the parity suite also times for the spike's per-prediction
/// number.
///
/// Everything here is deterministic: fixed xorshift seeds, no clocks (every
/// date is anchored on a literal `today`), so the committed file only ever
/// changes when the domain's own output changes.
///
/// Run from the repo root:
///
/// ```
/// dart run tool/web_domain/generate_fixtures.dart
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:lunarlog/domain/models/local_date.dart';

import 'facade.dart';

void main() {
  final cases = <Map<String, Object?>>[
    ..._predictCases(),
    ..._cycleHistoryCases(),
    ..._insightCases(),
    ..._bbtChartCases(),
    ..._cycleRecapCases(),
    ..._phaseInsightsCases(),
    ..._calendarForecastCases(),
    ..._validateDateCases(),
    ..._exportCases(),
    ..._inviteLinkCases(),
    ..._todayLogCases(),
  ];

  const path = 'webapp/test/domain/fixtures.json';
  final encoder = const JsonEncoder.withIndent('  ');
  File(path).writeAsStringSync('${encoder.convert(cases)}\n');
  stdout.writeln('wrote ${cases.length} cases to $path');
}

// ---------------------------------------------------------------------------
// Deterministic primitives
// ---------------------------------------------------------------------------

/// Deterministic pseudo-random generator (fixed seed) so the generated
/// entries — and so the committed expected outputs — never churn between
/// runs.
class Rng {
  Rng(this._state);

  int _state;

  int next() {
    var x = _state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    _state = x & 0x7fffffff;
    return _state;
  }

  int nextBetween(int min, int max) => min + next() % (max - min + 1);
}

String _addDays(String iso, int days) =>
    LocalDate.fromIso(iso).addDays(days).iso;

// ---------------------------------------------------------------------------
// Entry builders
// ---------------------------------------------------------------------------

/// One export-shaped day-entry row.
Map<String, Object?> _entry({
  required String id,
  required String localDate,
  required String updatedAt,
  String profileId = 'profile-1',
  String flow = 'medium',
  List<String> tags = const [],
  bool pms = false,
  String? note,
  bool notePrivate = false,
  String? deletedAt,
  String source = 'manual',
}) => {
  'id': id,
  'profileId': profileId,
  'localDate': localDate,
  'tz': 'UTC',
  'flow': flow,
  'tags': tags,
  'note': note,
  'notePrivate': notePrivate,
  'pms': pms,
  'source': source,
  'sourceId': null,
  'importId': null,
  'updatedAt': updatedAt,
  'deletedAt': ?deletedAt,
};

/// Builds export-shaped day entries for cycles that start every
/// [cycleLengths] day apart from [firstStart], each bleeding
/// [periodLength] consecutive days at [flow]. The last entry of
/// [cycleLengths] starts the still-open cycle. Optional hooks place
/// bleed-day tags, late-cycle PMS markers ([pmsCycleDayOffset] days after
/// each start, flow `none` — the way the app logs them), and a tombstone.
List<Map<String, Object?>> _cycleEntries({
  required List<int> cycleLengths,
  required String firstStart,
  int periodLength = 4,
  String profileId = 'profile-1',
  String flow = 'medium',
  List<String> Function(int cycleIndex, int cycleDay)? tagsForDay,
  int? pmsCycleDayOffset,
  String? tombstoneAt,
}) {
  final entries = <Map<String, Object?>>[];
  for (var cycleIndex = 0; cycleIndex < cycleLengths.length; cycleIndex++) {
    final start = cycleIndex == 0
        ? firstStart
        : _addDays(firstStart, cycleLengths.take(cycleIndex).sum);
    for (var day = 0; day < periodLength; day++) {
      final date = _addDays(start, day);
      entries.add(
        _entry(
          id: 'entry-$profileId-$cycleIndex-$day',
          profileId: profileId,
          localDate: date,
          flow: flow,
          tags: tagsForDay?.call(cycleIndex, day + 1) ?? const [],
          updatedAt: '${date}T12:00:00.000Z',
        ),
      );
    }
    if (pmsCycleDayOffset != null) {
      final date = _addDays(start, pmsCycleDayOffset);
      entries.add(
        _entry(
          id: 'entry-$profileId-$cycleIndex-pms',
          profileId: profileId,
          localDate: date,
          flow: 'none',
          pms: true,
          updatedAt: '${date}T20:00:00.000Z',
        ),
      );
    }
  }
  if (tombstoneAt != null) {
    entries.add(
      _entry(
        id: 'entry-$profileId-tombstone',
        profileId: profileId,
        localDate: tombstoneAt,
        flow: 'heavy',
        note: 'deleted row',
        deletedAt: '${tombstoneAt}T21:00:00.000Z',
        updatedAt: '${tombstoneAt}T21:00:00.000Z',
      ),
    );
  }
  return entries;
}

// ---------------------------------------------------------------------------
// Case plumbing
// ---------------------------------------------------------------------------

/// Runs one case through the facade right here: the generator itself fails
/// loudly if a case's request does not produce a success envelope, and the
/// committed `expected` is that envelope verbatim.
Map<String, Object?> _case(
  String name,
  String method,
  Map<String, Object?> request,
) {
  final response = handleFacadeCall(method, jsonEncode(request));
  final decoded = jsonDecode(response) as Map<String, Object?>;
  if (decoded['ok'] != true) {
    throw StateError('fixture case "$name" failed to compute: $response');
  }
  return {
    'name': name,
    'method': method,
    'request': request,
    'expected': decoded,
  };
}

// ---------------------------------------------------------------------------
// predict
// ---------------------------------------------------------------------------

List<Map<String, Object?>> _predictCases() {
  const today = '2026-09-30';
  final cases = <Map<String, Object?>>[];

  // Seven episode starts (six completed 28-day cycles), the seventh open:
  // a steady history at the `high` tier with a horizon-sized forecast.
  final regular = _cycleEntries(
    cycleLengths: [28, 28, 28, 28, 28, 28, 28],
    firstStart: _addDays(today, -196),
  );
  cases.add(
    _case('predict.active-regular', 'predict', {
      'today': today,
      'tz': 'UTC',
      'entries': regular,
    }),
  );

  // One logged episode: honest NotEnoughHistory with its counts.
  final thin = _cycleEntries(
    cycleLengths: [0],
    firstStart: _addDays(today, -10),
  );
  cases.add(
    _case('predict.not-enough-history', 'predict', {
      'today': today,
      'tz': 'UTC',
      'entries': thin,
    }),
  );

  // Varying lengths with a population spread well past the irregular
  // threshold (22/45/29/18/31 between five episode starts), an open cycle
  // 35 days old, and a deleted row the codecs must carry.
  final irregular = _cycleEntries(
    cycleLengths: const [22, 45, 29, 18, 31],
    firstStart: _addDays(today, -149),
    tombstoneAt: _addDays(today, -100),
  );
  cases.add(
    _case('predict.irregular-tier', 'predict', {
      'today': today,
      'tz': 'UTC',
      'entries': irregular,
    }),
  );

  // Pack-driven (issue #233): a pill regimen started this cycle predicts
  // from the pack schedule anchored on the regimen start (regimenSchedule
  // basis, high tier, zero spread), not from the irregular history behind
  // it.
  final packUser = _cycleEntries(
    cycleLengths: const [28, 27, 29],
    firstStart: _addDays(today, -90),
  );
  cases.add(
    _case('predict.pack-driven', 'predict', {
      'today': today,
      'tz': 'UTC',
      'entries': packUser,
      'birthControl': {
        'method': 'pill',
        'startedOn': _addDays(today, -20),
        'stoppedOn': null,
      },
    }),
  );

  // Continuous method in effect: suppressed outright (issue #233).
  cases.add(
    _case('predict.suppressed-continuous-method', 'predict', {
      'today': today,
      'tz': 'UTC',
      'entries': packUser,
      'birthControl': {
        'method': 'hormonal_iud',
        'startedOn': _addDays(today, -60),
        'stoppedOn': null,
      },
    }),
  );

  // Pregnancy mode: suppressed by life-stage (issue #528), checked ahead
  // of the birth-control branch.
  cases.add(
    _case('predict.suppressed-lifecycle', 'predict', {
      'today': today,
      'tz': 'UTC',
      'entries': regular,
      'birthControl': {
        'method': 'pill',
        'startedOn': _addDays(today, -60),
        'stoppedOn': null,
      },
      'lifecycleMode': 'pregnancy',
    }),
  );

  // Predictions turned off for the profile (issue #225): before every
  // other branch.
  cases.add(
    _case('predict.disabled', 'predict', {
      'today': today,
      'tz': 'UTC',
      'entries': regular,
      'predictionsEnabled': false,
    }),
  );

  // Late with a skipped history cycle (issues #132, #221): six episode
  // starts (five completed cycles), one omitted, and an open cycle 35
  // days old — the estimate is days late and has rolled forward.
  final late = _cycleEntries(
    cycleLengths: const [28, 28, 28, 28, 28, 28],
    firstStart: _addDays(today, -175),
  );
  cases.add(
    _case('predict.omitted-and-late', 'predict', {
      'today': today,
      'tz': 'UTC',
      'entries': late,
      'omittedCycleStarts': [_addDays(today, -119)],
    }),
  );

  // Provisional seeding from onboarding facts (issue #218): no usable
  // history, but a last period and a typical length. The one logged
  // episode (today-10) post-dates the supplied start (today-12), so it is
  // where the current cycle begins (issue #1392): the supplied cycle
  // length is kept, the supplied start is not.
  cases.add(
    _case('predict.provisional-seed', 'predict', {
      'today': today,
      'tz': 'UTC',
      'entries': thin,
      'facts': {
        'lastPeriodStart': _addDays(today, -12),
        'typicalCycleLengthDays': 30,
        'typicalPeriodLengthDays': 5,
      },
    }),
  );

  // The other side of issue #1392: the supplied start (today-3) is later
  // than the one logged episode (today-10..today-7), which is therefore an
  // earlier period — the onboarding answer stays the anchor and the
  // estimate never moves backwards.
  cases.add(
    _case('predict.provisional-seed-after-logged-period', 'predict', {
      'today': today,
      'tz': 'UTC',
      'entries': thin,
      'facts': {
        'lastPeriodStart': _addDays(today, -3),
        'typicalCycleLengthDays': 30,
        'typicalPeriodLengthDays': 5,
      },
    }),
  );

  // A skipped provisional cycle (issue #1412): nothing is logged, the
  // supplied start (today-35) is the anchor, and its 28-day estimate is 7
  // days past. The omission list names that anchor, so the estimate
  // advances one supplied cycle (to today+21) and is no longer late — the
  // computed path's skip rule, with the supplied length standing in for
  // the mean. Without the facade forwarding `omittedCycleStarts` to the
  // seeded branch this case reads `daysLate: 7`.
  cases.add(
    _case('predict.provisional-seed-skipped', 'predict', {
      'today': today,
      'tz': 'UTC',
      'entries': const <Map<String, Object?>>[],
      'facts': {
        'lastPeriodStart': _addDays(today, -35),
        'typicalCycleLengthDays': 28,
        'typicalPeriodLengthDays': 5,
      },
      'omittedCycleStarts': [_addDays(today, -35)],
    }),
  );

  // PMS markers late in each cycle (issue #220): enough usable intervals
  // for a predicted band.
  final pmsUser = _cycleEntries(
    cycleLengths: const [28, 28, 28, 28, 28],
    firstStart: _addDays(today, -140),
    pmsCycleDayOffset: 26,
  );
  cases.add(
    _case('predict.with-pms-band', 'predict', {
      'today': today,
      'tz': 'UTC',
      'entries': pmsUser,
    }),
  );

  // The #710 seeded shape: 18 months of realistic cycles (26-32 days,
  // 5-day bleeds, cramps/headache tags, late-cycle PMS markers). The
  // parity suite times this input for the spike's per-prediction number.
  final rng = Rng(0x1251);
  final seed18mLengths = List<int>.generate(19, (_) => rng.nextBetween(26, 32));
  var firstSeedStart = today;
  for (final length in seed18mLengths) {
    firstSeedStart = _addDays(firstSeedStart, -length);
  }
  final seed18m = _cycleEntries(
    cycleLengths: seed18mLengths,
    firstStart: firstSeedStart,
    periodLength: 5,
    tagsForDay: (cycleIndex, cycleDay) => [
      if (cycleDay == 2) 'cramps',
      if (cycleIndex % 3 == 0 && cycleDay == 3) 'headache',
    ],
    pmsCycleDayOffset: 24,
  );
  cases.add(
    _case('seed18m.predict', 'predict', {
      'today': today,
      'tz': 'UTC',
      'entries': seed18m,
    }),
  );

  return cases;
}

// ---------------------------------------------------------------------------
// cycleHistory
// ---------------------------------------------------------------------------

List<Map<String, Object?>> _cycleHistoryCases() {
  const today = '2026-09-30';
  final entries = _cycleEntries(
    cycleLengths: const [28, 12, 29, 30],
    firstStart: _addDays(today, -110),
  );
  return [
    _case('cycleHistory.open-outlier-omitted', 'cycleHistory', {
      'today': today,
      'tz': 'UTC',
      'entries': entries,
      'omittedCycleStarts': [_addDays(today, -82)],
    }),
    // The same view requested with a legacy link name browsers still
    // report (issue #1273): the facade's alias table must accept it before
    // any date math happens, so the compiled module is pinned on a
    // `Asia/Calcutta` request exactly as a real browser sends it.
    _case('cycleHistory.legacy-tz-calcutta', 'cycleHistory', {
      'today': today,
      'tz': 'Asia/Calcutta',
      'entries': entries,
    }),
  ];
}

// ---------------------------------------------------------------------------
// insights
// ---------------------------------------------------------------------------

List<Map<String, Object?>> _insightCases() {
  const today = '2026-09-30';
  final entries = _cycleEntries(
    cycleLengths: const [28, 28, 28, 28, 28],
    firstStart: _addDays(today, -140),
    tagsForDay: (cycleIndex, cycleDay) => [
      if (cycleDay == 2) 'cramps',
      if (cycleDay == 3 && cycleIndex.isEven) 'cramps',
      if (cycleDay == 1) 'backache',
    ],
  );
  // Exactly kMinObservationCycles (3) completed cycles: a tag logged in
  // all three meets the reporting threshold, but _calculateTrend needs 4+
  // cycles to split halves, so every reported pattern's trend is
  // `insufficientData` (issue #1272 — the web Zod schema rejected that
  // value before this case existed, failing `insights()` outright for
  // 3-cycle profiles).
  final threeCycles = _cycleEntries(
    cycleLengths: const [28, 28, 28, 28],
    firstStart: _addDays(today, -112),
    tagsForDay: (cycleIndex, cycleDay) => [
      if (cycleDay == 2) 'cramps',
    ],
  );
  return [
    _case('insights.patterns-and-cramps', 'insights', {
      'today': today,
      'tz': 'UTC',
      'entries': entries,
    }),
    _case('insights.three-cycles-insufficient-trend', 'insights', {
      'today': today,
      'tz': 'UTC',
      'entries': threeCycles,
    }),
  ];
}

// ---------------------------------------------------------------------------
// bbtChart
// ---------------------------------------------------------------------------

/// The BBT chart's series (issue #1796): three completed 28-day cycles with
/// readings on a few days (Celsius and one Fahrenheit row, converted by the
/// chart), plus the rows it must not plot - an excluded reading, a deleted
/// one, a day that is not among the entries, and another category - the
/// same-date tie case (issue #1821), and the empty case.
List<Map<String, Object?>> _bbtChartCases() {
  const today = '2026-09-30';
  final entries = _cycleEntries(
    cycleLengths: const [28, 28, 28, 28],
    firstStart: _addDays(today, -84),
  );
  final observations = <Map<String, Object?>>[
    _bbtRow('entry-profile-1-0-0', 36.4),
    _bbtRow('entry-profile-1-0-1', 36.5),
    _bbtRow('entry-profile-1-0-2', 36.7),
    _bbtRow('entry-profile-1-1-1', 98.6, unit: 'fahrenheit'),
    _bbtRow('entry-profile-1-1-2', 36.9, excluded: true),
    _bbtRow(
      'entry-profile-1-2-0',
      36.6,
      deletedAt: '2026-08-01T00:00:00.000Z',
    ),
    _bbtRow('entry-not-in-entries', 36.8),
    _bbtRow('entry-profile-1-2-1', 60.0, category: 'weight'),
  ];
  return [
    _case('bbtChart.points-by-cycle', 'bbtChart', {
      'entries': entries,
      'observations': observations,
    }),
    _case('bbtChart.same-date-rows', 'bbtChart', {
      'entries': entries,
      'observations': <Map<String, Object?>>[
        // One date, two live rows (a manual entry alongside an imported
        // one): the newer row wins by its own updatedAt, never by the
        // request's array order - the newer row is listed first on
        // purpose (issue #1821). The older row's instant precedes its day
        // entry's own (noon, the fallback), the newer one follows it.
        _bbtRow(
          'entry-profile-1-0-1',
          36.9,
          updatedAt: '2026-07-09T15:00:00.000Z',
        ),
        _bbtRow(
          'entry-profile-1-0-1',
          36.5,
          updatedAt: '2026-07-09T09:00:00.000Z',
        ),
      ],
    }),
    _case('bbtChart.empty', 'bbtChart', {
      'entries': entries,
      'observations': const <Map<String, Object?>>[],
    }),
  ];
}

Map<String, Object?> _bbtRow(
  String dayEntryId,
  double valueNum, {
  String unit = 'celsius',
  String category = 'bbt',
  bool excluded = false,
  String? deletedAt,
  String? updatedAt,
}) => {
  'dayEntryId': dayEntryId,
  'category': category,
  'valueNum': valueNum,
  'unit': unit,
  'source': 'manual',
  if (excluded) 'excluded': true,
  'deletedAt': ?deletedAt,
  'updatedAt': ?updatedAt,
};

// ---------------------------------------------------------------------------
// cycleRecap
// ---------------------------------------------------------------------------

/// The cycle-end recap (issue #1796): a five-cycle history where the cycle
/// that just closed carries every fact (lengths, deltas, the estimate's
/// means and confidence, the recurring symptoms, the cramp cluster), and the
/// one-cycle record where no cycle has completed and the response is the
/// null recap.
List<Map<String, Object?>> _cycleRecapCases() {
  const today = '2026-09-30';
  final entries = _cycleEntries(
    cycleLengths: const [28, 28, 28, 28, 28],
    firstStart: _addDays(today, -140),
    tagsForDay: (cycleIndex, cycleDay) => [
      if (cycleDay == 2) 'cramps',
      if (cycleDay == 3 && cycleIndex.isEven) 'cramps',
    ],
  );
  final thin = _cycleEntries(
    cycleLengths: const [28],
    firstStart: _addDays(today, -10),
  );
  return [
    _case('cycleRecap.completed-cycle', 'cycleRecap', {
      'today': today,
      'tz': 'UTC',
      'entries': entries,
    }),
    _case('cycleRecap.thin-record', 'cycleRecap', {
      'today': today,
      'tz': 'UTC',
      'entries': thin,
    }),
  ];
}

// ---------------------------------------------------------------------------
// phaseInsights
// ---------------------------------------------------------------------------

/// The phase card's payload (issue #1796): an active statistical cycle (a
/// subphase with its display strings), a pack-driven prediction (no
/// ovulatory subphase - issue #1118 - so `phase` is null and `basis` names
/// the reason), and a one-cycle record where no prediction is active yet.
List<Map<String, Object?>> _phaseInsightsCases() {
  const today = '2026-09-30';
  final regular = _cycleEntries(
    cycleLengths: const [28, 28, 28, 28, 28, 28, 28],
    firstStart: _addDays(today, -196),
  );
  final packUser = _cycleEntries(
    cycleLengths: const [28, 28, 28],
    firstStart: _addDays(today, -90),
  );
  final thin = _cycleEntries(
    cycleLengths: const [28],
    firstStart: _addDays(today, -10),
  );
  return [
    _case('phaseInsights.statistical-cycle', 'phaseInsights', {
      'today': today,
      'tz': 'UTC',
      'entries': regular,
    }),
    _case('phaseInsights.pack-driven', 'phaseInsights', {
      'today': today,
      'tz': 'UTC',
      'entries': packUser,
      'birthControl': {
        'method': 'pill',
        'startedOn': _addDays(today, -20),
        'stoppedOn': null,
      },
    }),
    _case('phaseInsights.thin-record', 'phaseInsights', {
      'today': today,
      'tz': 'UTC',
      'entries': thin,
    }),
  ];
}

// ---------------------------------------------------------------------------
// calendarForecast
// ---------------------------------------------------------------------------

/// The calendar's per-date forecast cells (issue #1253): an active fresh
/// history (bands, numerals, fertile windows, the PMS band), and the two
/// empty-map kinds the web calendar must not draw anything for — a
/// life-stage-suppressed prediction and a stale history.
List<Map<String, Object?>> _calendarForecastCases() {
  const today = '2026-09-30';
  final regular = _cycleEntries(
    cycleLengths: [28, 28, 28, 28, 28, 28, 28],
    firstStart: _addDays(today, -196),
    pmsCycleDayOffset: 26,
  );
  return [
    _case('calendarForecast.active-regular', 'calendarForecast', {
      'today': today,
      'tz': 'UTC',
      'entries': regular,
    }),
    // A life-stage suppression answers no cells, kind `suppressed` — the
    // web calendar shows logged days only, exactly like the app's.
    _case('calendarForecast.suppressed-lifecycle', 'calendarForecast', {
      'today': today,
      'tz': 'UTC',
      'entries': regular,
      'lifecycleMode': 'pregnancy',
    }),
    // Issue #1476: a profile with nothing logged, whose estimate is seeded
    // from the setup answers. The response names the supplied date as
    // `setupPeriodMarkDate`, the day both calendars mark as "last period
    // start from setup".
    _case('calendarForecast.setup-answer-seeds-the-estimate', 'calendarForecast', {
      'today': today,
      'tz': 'UTC',
      'entries': const <Object?>[],
      'facts': {
        'lastPeriodStart': _addDays(today, -12),
        'typicalCycleLengthDays': 30,
        'typicalPeriodLengthDays': 5,
      },
    }),
    // The same answers once a period logged after the supplied date has
    // taken over as the cycle's start: the estimate is still provisional,
    // and there is no mark (`setupPeriodMarkDate` is null).
    _case('calendarForecast.logged-period-takes-over-from-setup', 'calendarForecast', {
      'today': today,
      'tz': 'UTC',
      'entries': _cycleEntries(
        cycleLengths: const [28],
        firstStart: _addDays(today, -4),
      ),
      'facts': {
        'lastPeriodStart': _addDays(today, -32),
        'typicalCycleLengthDays': 30,
        'typicalPeriodLengthDays': 5,
      },
    }),
    // A stale history (issue #982) suppresses the whole forecast off the
    // same flag the app's calendar reads: five completed 28-day cycles,
    // then an open cycle 141 days old — well past the 4×mean stale
    // threshold, so the estimate is active but stale.
    _case('calendarForecast.stale-history', 'calendarForecast', {
      'today': today,
      'tz': 'UTC',
      'entries': _cycleEntries(
        cycleLengths: const [28, 28, 28, 28, 28],
        firstStart: _addDays(today, -253),
      ),
    }),
  ];
}

// ---------------------------------------------------------------------------
// validateDayEntryDate
// ---------------------------------------------------------------------------

List<Map<String, Object?>> _validateDateCases() {
  return [
    _case('validateDayEntryDate.valid', 'validateDayEntryDate', {
      'date': '2026-09-30',
      'today': '2026-09-30',
    }),
    _case('validateDayEntryDate.future', 'validateDayEntryDate', {
      'date': '2026-10-03',
      'today': '2026-09-30',
    }),
    _case('validateDayEntryDate.before-birth-year', 'validateDayEntryDate', {
      'date': '2010-05-01',
      'today': '2026-09-30',
      'birthYear': 2012,
    }),
  ];
}

// ---------------------------------------------------------------------------
// buildExport
// ---------------------------------------------------------------------------

List<Map<String, Object?>> _exportCases() {
  final adultEntries = _cycleEntries(
    cycleLengths: const [28, 28, 28],
    firstStart: '2026-06-01',
  );
  final teenEntries = _cycleEntries(
    cycleLengths: const [30, 31],
    firstStart: '2026-07-15',
    profileId: 'profile-2',
    flow: 'light',
  );
  // Issue #1274: the web client's rows carry tombstones, but the export
  // document is the app's own tombstone-free shape — a deleted profile is
  // gone with its nested entries, a deleted entry is gone from its live
  // profile. The compiled module is pinned to the same exclusion through
  // the Vitest parity suite.
  final tombstoneTargetEntries = _cycleEntries(
    cycleLengths: const [28, 28],
    firstStart: '2026-08-01',
    tombstoneAt: '2026-08-29',
  );
  Map<String, Object?> exportProfile(
    String id,
    String displayName,
    List<Map<String, Object?>> dayEntries, {
    String? deletedAt,
  }) => {
    'id': id,
    'displayName': displayName,
    'isMinor': false,
    'mode': 'standard',
    'irregularFraming': null,
    'bbtUnit': 'celsius',
    'weightUnit': 'kg',
    'sortOrder': 0,
    'archivedAt': null,
    'createdAt': '2026-01-01T00:00:00.000Z',
    'updatedAt': '2026-09-01T00:00:00.000Z',
    'birthYear': 1990,
    'relationship': null,
    'lastPeriodStart': null,
    'typicalCycleLengthDays': null,
    'typicalPeriodLengthDays': null,
    'trackingPreferences': null,
    'deletedAt': ?deletedAt,
    'dayEntries': dayEntries,
    'profileMode': null,
  };
  return [
    _case('buildExport.two-profiles', 'buildExport', {
      'exportedAt': '2026-09-30T10:00:00.000Z',
      'appVersion': '1.2.3',
      'profiles': [
        {
          'id': 'profile-1',
          'displayName': 'Ada',
          'isMinor': false,
          'mode': 'standard',
          'irregularFraming': null,
          'bbtUnit': 'celsius',
          'weightUnit': 'kg',
          'sortOrder': 0,
          'archivedAt': null,
          'createdAt': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-09-01T00:00:00.000Z',
          'birthYear': 1990,
          'relationship': null,
          'lastPeriodStart': '2026-09-01',
          'typicalCycleLengthDays': 28,
          'typicalPeriodLengthDays': 4,
          'trackingPreferences': null,
          'dayEntries': adultEntries,
          'profileMode': null,
        },
        {
          'id': 'profile-2',
          'displayName': 'Bea',
          'isMinor': true,
          'mode': 'teen',
          'irregularFraming': true,
          'bbtUnit': 'fahrenheit',
          'weightUnit': 'lbs',
          'sortOrder': 1,
          'archivedAt': null,
          'createdAt': '2026-02-01T00:00:00.000Z',
          'updatedAt': '2026-09-02T00:00:00.000Z',
          'birthYear': 2012,
          'relationship': 'daughter',
          'lastPeriodStart': null,
          'typicalCycleLengthDays': null,
          'typicalPeriodLengthDays': null,
          'trackingPreferences': {
            'reminderEnabled': true,
            'reminderHour': 9,
            'reminderMinute': 0,
          },
          'dayEntries': teenEntries,
          'profileMode': {
            'mode': 'tracking',
            'modeStartedOn': '2026-07-15',
            'estimatedDueDate': null,
            'postpartumBirthDate': null,
            'birthControlMethod': null,
            'birthControlStartedOn': null,
            'birthControlStoppedOn': null,
          },
        },
      ],
    }),
    _case('buildExport.tombstones-excluded', 'buildExport', {
      'exportedAt': '2026-09-30T10:00:00.000Z',
      'appVersion': '1.2.3',
      'profiles': [
        exportProfile('profile-1', 'Ada', tombstoneTargetEntries),
        exportProfile(
          'profile-dead',
          'Deleted profile',
          _cycleEntries(
            cycleLengths: const [28],
            firstStart: '2026-08-01',
            profileId: 'profile-dead',
          ),
          deletedAt: '2026-09-10T00:00:00.000Z',
        ),
      ],
    }),
  ];
}

// ---------------------------------------------------------------------------
// parseInviteLink
// ---------------------------------------------------------------------------

List<Map<String, Object?>> _inviteLinkCases() {
  return [
    _case('parseInviteLink.custom-scheme', 'parseInviteLink', {
      'url': 'lunarlog://invite?code=abc123&profile=p1',
      'linkDomain': '',
    }),
    _case('parseInviteLink.claim-kind', 'parseInviteLink', {
      'url': 'lunarlog://invite?code=abc123&profile=p1&kind=claim',
      'linkDomain': '',
    }),
    _case('parseInviteLink.universal', 'parseInviteLink', {
      'url': 'https://links.lunarlog.app/invite?code=xyz789',
      'linkDomain': 'https://links.lunarlog.app',
    }),
    _case('parseInviteLink.wrong-domain', 'parseInviteLink', {
      'url': 'https://evil.example/invite?code=xyz789',
      'linkDomain': 'links.lunarlog.app',
    }),
    _case('parseInviteLink.missing-code', 'parseInviteLink', {
      'url': 'lunarlog://invite?profile=p1',
      'linkDomain': '',
    }),
  ];
}

// ---------------------------------------------------------------------------
// todayLog
// ---------------------------------------------------------------------------

/// What the Today log card says about one day (issue #1489 in the app; the
/// browser version's card asks the same code). One case per thing the card
/// can say, and per thing it must not: the flow line and its precedence,
/// the tag labels and the two kinds of tag that are only counted, the
/// six-tag limit, readings in the profile's units, and a note reduced to
/// the fact that it exists.
List<Map<String, Object?>> _todayLogCases() {
  const today = '2026-09-30';
  const entryId = 'entry-today';

  Map<String, Object?> entry({
    String flow = 'none',
    List<String> tags = const [],
    bool pms = false,
    String? note,
    String? deletedAt,
  }) => _entry(
    id: entryId,
    localDate: today,
    updatedAt: '${today}T08:00:00.000Z',
    flow: flow,
    tags: tags,
    pms: pms,
    note: note,
    deletedAt: deletedAt,
  );

  Map<String, Object?> observation(
    String category, {
    num? valueNum,
    String? unit,
    String source = 'manual',
    String dayEntryId = entryId,
    String? deletedAt,
  }) => {
    'dayEntryId': dayEntryId,
    'category': category,
    'valueNum': valueNum,
    'unit': unit,
    'source': source,
    'deletedAt': deletedAt,
  };

  Map<String, Object?> customTag(
    String code,
    String displayName, {
    String? deletedAt,
  }) => {'code': code, 'displayName': displayName, 'deletedAt': deletedAt};

  return [
    // Nothing logged, three ways: no entry at all, an entry left with
    // nothing on it (the day editor saves a row even when everything was
    // taken off again), and a tombstone that still carries what it held.
    _case('todayLog.no-entry', 'todayLog', {'entry': null}),
    _case('todayLog.empty-entry', 'todayLog', {'entry': entry()}),
    _case('todayLog.tombstone-says-nothing', 'todayLog', {
      'entry': entry(
        flow: 'heavy',
        tags: const ['cramps'],
        pms: true,
        note: 'kept on the deleted row',
        deletedAt: '${today}T09:00:00.000Z',
      ),
      'observations': [observation('bbt', valueNum: 36.7, unit: 'celsius')],
    }),

    // The flow line. A bleed level is answered as the level; "not
    // bleeding" as itself; no flow as null.
    _case('todayLog.flow-medium', 'todayLog', {'entry': entry(flow: 'medium')}),
    _case('todayLog.flow-super-heavy', 'todayLog', {
      'entry': entry(flow: 'super_heavy'),
    }),
    _case('todayLog.flow-not-bleeding', 'todayLog', {
      'entry': entry(flow: 'not_bleeding'),
    }),
    // Spotting is its own record: the day editor raises the flow to "not
    // bleeding" when it stores one, and the card says "Spotting".
    _case('todayLog.spotting-over-not-bleeding', 'todayLog', {
      'entry': entry(flow: 'not_bleeding'),
      'observations': [observation('spotting')],
    }),
    // Bleed wins over spotting, as on the calendar.
    _case('todayLog.bleed-wins-over-spotting', 'todayLog', {
      'entry': entry(flow: 'heavy'),
      'observations': [observation('spotting')],
    }),
    // A spotting-only day as a health import stores it: no flow at all.
    // It is a logged day.
    _case('todayLog.spotting-only-from-import', 'todayLog', {
      'entry': entry(),
      'observations': [observation('spotting', source: 'apple_health')],
    }),
    // A row stored before spotting became its own record carries it as
    // the flow level, with no spotting record beside it.
    _case('todayLog.legacy-spotting-flow', 'todayLog', {
      'entry': entry(flow: 'spotting'),
    }),

    // Tags. Stored order; a tag whose word needs its heading carries it,
    // and digestion keeps its own word.
    _case('todayLog.tags-in-stored-order', 'todayLog', {
      'entry': entry(tags: const ['headache', 'cramps', 'pain_free']),
    }),
    _case('todayLog.tags-contextual-labels', 'todayLog', {
      'entry': entry(
        tags: const [
          'sticky',
          'normal',
          'sweet',
          '0_to_3_hours',
          'pain',
          'bloating',
        ],
      ),
    }),
    _case('todayLog.tags-digestion-clash', 'todayLog', {
      'entry': entry(tags: const ['great_digestion', 'nausea']),
    }),
    // Sex-life and test-result tags, and a code this build does not know,
    // are counted and never named.
    _case('todayLog.tags-unnamed-are-counted', 'todayLog', {
      'entry': entry(
        tags: const [
          'cramps',
          'unprotected_sex',
          'pregnancy_positive',
          'some_new_code',
        ],
      ),
    }),
    _case('todayLog.tags-only-unnamed', 'todayLog', {
      'entry': entry(tags: const ['protected_sex', 'ovulation_positive']),
    }),
    // Six are named; the two past the limit are counted, with the unnamed
    // one.
    _case('todayLog.tags-more-than-fit', 'todayLog', {
      'entry': entry(
        tags: const [
          'cramps',
          'headache',
          'back_pain',
          'fatigue',
          'acne',
          'migraine',
          'protected_sex',
          'anxious',
          'bloating',
        ],
      ),
    }),
    _case('todayLog.tags-exactly-six', 'todayLog', {
      'entry': entry(
        tags: const [
          'cramps',
          'headache',
          'back_pain',
          'fatigue',
          'acne',
          'migraine',
        ],
      ),
    }),
    // A profile's own tag reads by its registry name, even one that shares
    // a word with a category that is never named. A deleted registry row
    // names nothing, so its code is counted like any other this build
    // cannot name; so is a custom code with no row at all.
    _case('todayLog.custom-tags', 'todayLog', {
      'entry': entry(
        tags: const [
          'back_cracking',
          'cramps',
          'sex_ed_class',
          'gone_tag',
          'never_synced',
        ],
      ),
      'customTags': [
        customTag('back_cracking', 'Back cracking'),
        customTag('sex_ed_class', 'Sex ed class'),
        customTag('gone_tag', 'Gone', deletedAt: '2026-09-01T00:00:00.000Z'),
      ],
    }),

    // The PMS marker, and a note reduced to the fact that it exists.
    _case('todayLog.pms-and-note', 'todayLog', {
      'entry': entry(pms: true, note: 'zebra crossing after the dentist'),
    }),
    _case('todayLog.blank-note-is-no-note', 'todayLog', {
      'entry': entry(note: '   '),
    }),

    // Readings: the one the day editor would open on (entered by hand,
    // with a number), in the profile's units whatever it was stored in.
    _case('todayLog.readings-as-stored', 'todayLog', {
      'entry': entry(),
      'observations': [
        observation('bbt', valueNum: 36.7, unit: 'celsius'),
        observation('weight', valueNum: 61, unit: 'kg'),
      ],
    }),
    _case('todayLog.readings-in-profile-units', 'todayLog', {
      'entry': entry(),
      'observations': [
        observation('bbt', valueNum: 37, unit: 'celsius'),
        observation('weight', valueNum: 50, unit: 'kg'),
      ],
      'bbtUnit': 'fahrenheit',
      'weightUnit': 'lb',
    }),
    // What is not this day's reading: one a wearable wrote, a deleted
    // one, and one attached to another day's entry. With nothing else on
    // the entry, nothing is logged.
    _case('todayLog.readings-not-this-days', 'todayLog', {
      'entry': entry(),
      'observations': [
        observation('bbt', valueNum: 36.5, unit: 'celsius', source: 'wearable'),
        observation(
          'weight',
          valueNum: 60,
          unit: 'kg',
          deletedAt: '${today}T09:00:00.000Z',
        ),
        observation(
          'bbt',
          valueNum: 36.9,
          unit: 'celsius',
          dayEntryId: 'entry-yesterday',
        ),
        observation('spotting', dayEntryId: 'entry-yesterday'),
      ],
    }),

    // Everything at once.
    _case('todayLog.everything', 'todayLog', {
      'entry': entry(
        flow: 'light',
        tags: const ['cramps', 'withdrawal', 'sticky'],
        pms: true,
        note: 'zebra crossing after the dentist',
      ),
      'observations': [
        observation('spotting'),
        observation('bbt', valueNum: 97.9, unit: 'fahrenheit'),
        observation('weight', valueNum: 134.5, unit: 'lb'),
      ],
      'bbtUnit': 'fahrenheit',
      'weightUnit': 'lb',
    }),
  ];
}

extension _Sum on Iterable<int> {
  int get sum {
    var total = 0;
    for (final value in this) {
      total += value;
    }
    return total;
  }
}
