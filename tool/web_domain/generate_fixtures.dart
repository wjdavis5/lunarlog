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
/// policy, the export builder, and invite links), plus one `seed18m` case
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
    ..._validateDateCases(),
    ..._exportCases(),
    ..._inviteLinkCases(),
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
  // history, but a last period and a typical length.
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
  return [
    _case('insights.patterns-and-cramps', 'insights', {
      'today': today,
      'tz': 'UTC',
      'entries': entries,
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

extension _Sum on Iterable<int> {
  int get sum {
    var total = 0;
    for (final value in this) {
      total += value;
    }
    return total;
  }
}
