/// Domain tests for issue #132's cycle-history derivation (R4/R5): the
/// reverse-chronological list with the open cycle pinned, omit and outlier
/// flags, the statistics row's numbers, the confidence mapping, and the
/// device-local persistence codecs (omission list + late snooze).
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/prediction.dart'
    show ActivePrediction, computePrediction;
import 'package:lunarlog/domain/repositories/settings_store.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

/// Episodes from start dates, each bleeding [length] days (4 by default).
List<Episode> episodesFromStarts(List<LocalDate> starts, [int length = 4]) => [
  for (final start in starts) Episode(start, start.addDays(length - 1)),
];

/// 28-day cycles ending 2026-05-13: lengths 28, 28, 28 (three completed
/// cycles — fewer than kAverageWindowCycles, so confidence reads
/// `learning`, not `high`; see kHighConfidenceStarts below for a full
/// 6-cycle window).
final List<LocalDate> kSteadyStarts = [
  d(2026, 2, 18),
  d(2026, 3, 18),
  d(2026, 4, 15),
  d(2026, 5, 13),
];

/// 28-day cycles ending 2026-06-18: six completed cycles — a full
/// kAverageWindowCycles(6) window, the minimum for `high` confidence
/// (issue #213 item 5).
final List<LocalDate> kHighConfidenceStarts = [
  d(2026, 1, 1),
  d(2026, 1, 29),
  d(2026, 2, 26),
  d(2026, 3, 26),
  d(2026, 4, 23),
  d(2026, 5, 21),
  d(2026, 6, 18),
];

void main() {
  group('history list (R4)', () {
    test('reverse-chronological with the open cycle pinned to the top', () {
      final view = deriveCycleHistory(
        episodes: episodesFromStarts(kSteadyStarts),
        today: d(2026, 5, 20),
      );
      expect(view.items, hasLength(4));
      expect(
        view.items.first.isOpen,
        isTrue,
        reason: 'the open cycle (last start) pins to the top',
      );
      expect(view.items.first.start, d(2026, 5, 13));
      expect(view.items[1].start, d(2026, 4, 15));
      expect(view.items[1].lengthDays, 28);
      expect(view.items.last.start, d(2026, 2, 18));
    });

    test('a length outside the 15-60 window is flagged as an outlier', () {
      // Lengths 28, 70, 28: the middle cycle (start Jan 29) is outside
      // the window.
      final view = deriveCycleHistory(
        episodes: episodesFromStarts([
          d(2026, 1, 1),
          d(2026, 1, 29),
          d(2026, 4, 9),
          d(2026, 5, 7),
        ]),
        today: d(2026, 5, 12),
      );
      final outlier = view.items[2];
      expect(outlier.start, d(2026, 1, 29));
      expect(outlier.lengthDays, 70);
      expect(outlier.outlier, isTrue);
      expect(outlier.countedInAverages, isFalse);
      expect(view.items[1].outlier, isFalse);
    });

    test('omitted cycles carry the flag but stay in the list', () {
      final view = deriveCycleHistory(
        episodes: episodesFromStarts(kSteadyStarts),
        today: d(2026, 5, 20),
        omittedCycleStarts: {d(2026, 4, 15)},
      );
      final omittedItem = view.items.singleWhere(
        (item) => item.start == d(2026, 4, 15),
      );
      expect(omittedItem.omitted, isTrue);
      expect(omittedItem.countedInAverages, isFalse);
      expect(view.items, hasLength(4), reason: 'still visible (R4)');
    });

    test('skipping the open cycle marks its item omitted', () {
      final view = deriveCycleHistory(
        episodes: episodesFromStarts(kSteadyStarts),
        today: d(2026, 5, 20),
        omittedCycleStarts: {d(2026, 5, 13)},
      );
      expect(view.items.first.omitted, isTrue);
      expect(view.items.first.isOpen, isTrue);
    });

    test('no episodes at all -> empty view with null confidence and stats', () {
      final view = deriveCycleHistory(episodes: const [], today: d(2026, 1, 1));
      expect(view.items, isEmpty);
      expect(view.confidence, isNull);
      expect(view.meanCycleLengthDays, isNull);
      expect(view.meanPeriodLengthDays, isNull);
      expect(view.variationDays, isNull);
    });

    test('input order is irrelevant', () {
      final forward = deriveCycleHistory(
        episodes: episodesFromStarts(kSteadyStarts),
        today: d(2026, 5, 20),
      );
      final reversed = deriveCycleHistory(
        episodes: episodesFromStarts(kSteadyStarts.reversed.toList()),
        today: d(2026, 5, 20),
      );
      expect(forward.items.toString(), reversed.items.toString());
    });
  });

  group('statistics (R5)', () {
    test('mean cycle length uses the issue #213 displayed-averages window '
        '(6 cycles, not the old 3) — all 4 counted lengths fit inside it',
        () {
      // Lengths 28, 28, 48, 28: all four fit inside kAverageWindowCycles
      // (6), so the mean uses all four. Before issue #213
      // (kMaxAveragedCycles=3) only the most recent three (28, 48, 28) fed
      // this number.
      final view = deriveCycleHistory(
        episodes: episodesFromStarts([
          d(2026, 1, 1),
          d(2026, 1, 29),
          d(2026, 2, 26),
          d(2026, 4, 15),
          d(2026, 5, 13),
        ]),
        today: d(2026, 5, 18),
      );
      expect(view.averagedCycleCount, 4);
      expect(view.meanCycleLengthDays, 33.0);
      expect(view.variationDays, 20);
    });

    test('the averaged-cycle window truncates to exactly '
        'kAverageWindowCycles once more are counted (pins the constant)',
        () {
      // 7 completed valid cycles, lengths 21..27 (chronological, oldest to
      // newest) plus an 8th open episode. `counted` is built newest-first,
      // so kAverageWindowCycles(6)'s own head-slice keeps the six NEWEST
      // (22..27) and drops the single oldest (21): mean 24.5. This fails
      // if kAverageWindowCycles moves at all: 5 would additionally drop 22
      // (mean 25.0 over 23..27); 7 would keep every length (mean 24.0).
      final starts = <LocalDate>[d(2026, 1, 1)];
      var start = starts.first;
      for (final length in [21, 22, 23, 24, 25, 26, 27]) {
        start = start.addDays(length);
        starts.add(start);
      }
      final view = deriveCycleHistory(
        episodes: episodesFromStarts(starts),
        today: start.addDays(2),
      );
      expect(view.averagedCycleCount, 7);
      expect(view.meanCycleLengthDays, 24.5);
    });

    test('confidence tier and history stats agree on the most-recent '
        'window even when the older cycles are wildly different '
        '(reviewer failure scenario)', () {
      // 12 valid cycles: oldest six alternate 20/45 (well outside a
      // consistent range), newest six are all steady 28s. The averages
      // (and the confidence tier, since #213 shares one derivation) must
      // read off the newest six only — chip and stats agreeing at
      // `high`/28/0 — never a "mixed" number pulled from the stale tail.
      final starts = <LocalDate>[d(2025, 1, 1)];
      var start = starts.first;
      for (final length in [20, 45, 20, 45, 20, 45, 28, 28, 28, 28, 28, 28]) {
        start = start.addDays(length);
        starts.add(start);
      }
      final view = deriveCycleHistory(
        episodes: episodesFromStarts(starts),
        today: start.addDays(2),
      );
      expect(view.confidence, CycleConfidence.high);
      expect(view.meanCycleLengthDays, 28.0);
      expect(view.variationDays, 0);
    });

    test('omitting a cycle changes the averaged window and the spread', () {
      final view = deriveCycleHistory(
        episodes: episodesFromStarts([
          d(2026, 1, 1),
          d(2026, 1, 29),
          d(2026, 2, 26),
          d(2026, 4, 15),
          d(2026, 5, 13),
        ]),
        today: d(2026, 5, 18),
        omittedCycleStarts: {d(2026, 2, 26)},
      );
      expect(view.meanCycleLengthDays, 28.0);
      expect(view.variationDays, 0);
    });

    test('mean period length averages bleed days, excluding omitted '
        'episodes but including the open one', () {
      final episodes = [
        Episode(d(2026, 2, 18), d(2026, 2, 19)), // 2 days
        Episode(d(2026, 3, 18), d(2026, 3, 22)), // 5 days
        Episode(d(2026, 4, 15), d(2026, 4, 19)), // 5 days
        Episode(d(2026, 5, 13), d(2026, 5, 17)), // 5 days, open
      ];
      expect(
        deriveCycleHistory(episodes: episodes, today: d(2026, 5, 20))
            .meanPeriodLengthDays,
        closeTo(17 / 4, 1e-9),
        reason: 'all four episodes average to 4.25 days',
      );
      expect(
        deriveCycleHistory(
          episodes: episodes,
          today: d(2026, 5, 20),
          omittedCycleStarts: {d(2026, 2, 18)},
        ).meanPeriodLengthDays,
        5.0,
        reason: 'the omitted 2-day episode drops out of the mean',
      );
    });

    test('variation is null below two averaged lengths; means are null with '
        'nothing counted', () {
      final view = deriveCycleHistory(
        episodes: episodesFromStarts([d(2026, 1, 1), d(2026, 1, 29)]),
        today: d(2026, 2, 3),
      );
      expect(view.variationDays, isNull);
      expect(
        view.meanCycleLengthDays,
        28.0,
        reason: 'one counted length still has a mean',
      );

      final allOmitted = deriveCycleHistory(
        episodes: episodesFromStarts([d(2026, 1, 1), d(2026, 1, 29)]),
        today: d(2026, 2, 3),
        omittedCycleStarts: {d(2026, 1, 1)},
      );
      expect(allOmitted.meanCycleLengthDays, isNull);
      expect(
        allOmitted.meanPeriodLengthDays,
        4.0,
        reason: 'bleed lengths are only excluded per-episode',
      );
    });
  });

  group('confidence (issue #213 item 1: one derivation, the engine\'s own '
      'tier)', () {
    test('below three averaged cycles reads learning', () {
      final view = deriveCycleHistory(
        episodes: episodesFromStarts([d(2026, 1, 1), d(2026, 1, 29)]),
        today: d(2026, 2, 3),
      );
      expect(view.confidence, CycleConfidence.learning);
      expect(view.confidence!.label, 'Learning');
      expect(view.confidence!.summary, contains('Still learning'));
    });

    test('three steady cycles read learning, not high — the '
        'kAverageWindowCycles window is not yet full (issue #213 item 5)',
        () {
      final view = deriveCycleHistory(
        episodes: episodesFromStarts(kSteadyStarts),
        today: d(2026, 5, 20),
      );
      expect(view.confidence, CycleConfidence.learning);
    });

    test('six steady cycles — a full kAverageWindowCycles window — read '
        'high', () {
      final view = deriveCycleHistory(
        episodes: episodesFromStarts(kHighConfidenceStarts),
        today: d(2026, 6, 23),
      );
      expect(view.confidence, CycleConfidence.high);
    });

    test('a spread over the engine\'s threshold reads irregular', () {
      // Lengths 15, 60, 15 (population std-dev ≈21.2, over the 7-day
      // threshold) — the same ActivePrediction.tier the overview caption
      // renders, computed over the same episodes/today.
      final starts = <LocalDate>[d(2026, 1, 1)];
      var start = starts.first;
      for (final length in [15, 60, 15]) {
        start = start.addDays(length);
        starts.add(start);
      }
      final view = deriveCycleHistory(
        episodes: episodesFromStarts(starts),
        today: start.addDays(5),
      );
      expect(view.confidence, CycleConfidence.irregular);
    });

    test('a low valid ratio reads irregular even with a steady recent '
        'three', () {
      // Four invalid cycles (90, 95, 100, 65) then three steady valid ones
      // (28, 28, 28): the ratio is recency-windowed over all 7 completed
      // cycles (3/7 ≈ 0.43, under the engine's 0.5 threshold) even though
      // the averaged three are perfectly steady (spread 0).
      final starts = <LocalDate>[d(2025, 1, 1)];
      var start = starts.first;
      for (final length in [90, 95, 100, 65, 28, 28, 28]) {
        start = start.addDays(length);
        starts.add(start);
      }
      final view = deriveCycleHistory(
        episodes: episodesFromStarts(starts),
        today: start.addDays(5),
      );
      expect(view.completedCycleCount, 7);
      expect(view.validCycleCount, 3);
      expect(view.confidence, CycleConfidence.irregular);
    });

    test('omissions reduce the usable count toward learning', () {
      // kSteadyStarts has three completed cycles; omitting one leaves two
      // usable, below computePrediction's three-cycle minimum ->
      // NotEnoughHistory -> learning.
      final view = deriveCycleHistory(
        episodes: episodesFromStarts(kSteadyStarts),
        today: d(2026, 5, 20),
        omittedCycleStarts: {d(2026, 4, 15)},
      );
      expect(view.averagedCycleCount, 2);
      expect(view.confidence, CycleConfidence.learning);
    });

    test('the badge and the overview caption cannot diverge for lengths '
        '[24, 26, 28, 30, 32, 34] — issue #213 item 1\'s own example', () {
      // Population std-dev (the engine's spread metric) is ≈3.42 here,
      // under the 7-day threshold, so the tier is `high`. Before this
      // issue, this file's own `_confidenceFor` used max−min (10 days)
      // against a *different* provisional threshold and would have read
      // `irregular` instead — the exact divergence a single derivation
      // removes: both the history badge and the overview caption now come
      // from the same ActivePrediction.tier.
      final starts = <LocalDate>[d(2026, 1, 1)];
      var start = starts.first;
      for (final length in [24, 26, 28, 30, 32, 34]) {
        start = start.addDays(length);
        starts.add(start);
      }
      final today = start.addDays(5);

      final prediction = computePrediction(
        episodes: episodesFromStarts(starts),
        today: today,
      );
      final view = deriveCycleHistory(
        episodes: episodesFromStarts(starts),
        today: today,
      );

      expect(prediction, isA<ActivePrediction>());
      expect(view.confidence, (prediction as ActivePrediction).tier);
      expect(view.confidence, CycleConfidence.high);
    });
  });

  group('omission-list codec (KTD2)', () {
    test('key is per-profile', () {
      expect(omittedCyclesSettingKey('p1'), 'omittedCycles.p1');
      expect(lateSnoozeSettingKey('p1'), 'lateSnooze.p1');
    });

    test('parse: null, empty, non-list, and non-string entries degrade '
        'gracefully', () {
      expect(parseOmittedCycles(null), isEmpty);
      expect(parseOmittedCycles(''), isEmpty);
      expect(parseOmittedCycles('not json'), isEmpty);
      expect(parseOmittedCycles('{"a":1}'), isEmpty);
      expect(parseOmittedCycles('[2026-01-01, 5]'), isEmpty);
    });

    test('parse keeps valid dates around malformed ones; encode is '
        'canonical and round-trips', () {
      final parsed = parseOmittedCycles(
        '["2026-04-15", "nope", "2026-02-26", "2026-13-99"]',
      );
      expect(parsed, {d(2026, 4, 15), d(2026, 2, 26)});

      final encoded = encodeOmittedCycles(parsed);
      expect(
        encoded,
        '["2026-02-26","2026-04-15"]',
        reason: 'sorted, no whitespace',
      );
      expect(parseOmittedCycles(encoded), parsed);
    });

    test('snooze codec round-trips; boundaries of isLateSnoozed', () {
      expect(parseLateSnooze(null), isNull);
      expect(parseLateSnooze(''), isNull);
      expect(parseLateSnooze('garbage'), isNull);
      final until = d(2026, 9, 3);
      expect(parseLateSnooze(encodeLateSnooze(until)), until);

      expect(isLateSnoozed(today: d(2026, 9, 2), snoozeUntil: until), isTrue);
      expect(
        isLateSnoozed(today: until, snoozeUntil: until),
        isFalse,
        reason: 'the resolver reappears on the snooze date itself',
      );
      expect(isLateSnoozed(today: until, snoozeUntil: null), isFalse);
    });
  });

  group('CycleExclusionList (device-local read-modify-write)', () {
    late FakeSettingsStore store;
    late CycleExclusionList exclusions;

    setUp(() {
      store = FakeSettingsStore();
      exclusions = CycleExclusionList(store);
    });

    test('omit is idempotent and include reverses it', () async {
      expect(await exclusions.load('p1'), isEmpty);

      await exclusions.omit('p1', d(2026, 4, 15));
      await exclusions.omit('p1', d(2026, 4, 15));
      await exclusions.omit('p1', d(2026, 2, 26));
      expect(await exclusions.load('p1'), {d(2026, 4, 15), d(2026, 2, 26)});
      expect(store.values['omittedCycles.p1'], '["2026-02-26","2026-04-15"]');

      await exclusions.include('p1', d(2026, 4, 15));
      await exclusions.include('p1', d(2026, 4, 15));
      expect(await exclusions.load('p1'), {d(2026, 2, 26)});
    });

    test('lists are per-profile', () async {
      await exclusions.omit('p1', d(2026, 4, 15));
      expect(await exclusions.load('p2'), isEmpty);
    });

    test('watch emits the current set and again on every change', () async {
      final seen = <Set<LocalDate>>[];
      final sub = exclusions.watch('p1').listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      await exclusions.omit('p1', d(2026, 4, 15));
      await pumpEventQueue();
      expect(seen, [
        isEmpty,
        {d(2026, 4, 15)},
      ]);
    });
  });
}

/// Minimal in-memory [SettingsStore] with a replaying watch, mirroring
/// the drift store's watchSingleOrNull contract (current value first,
/// then every change).
class FakeSettingsStore implements SettingsStore {
  final values = <String, String>{};
  final _controllers = <String, StreamController<String?>>{};

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async {
    values[key] = value;
    _controllers[key]?.add(value);
  }

  @override
  Stream<String?> watch(String key) async* {
    yield values[key];
    yield* _controllerFor(key).stream;
  }

  StreamController<String?> _controllerFor(String key) => _controllers
      .putIfAbsent(key, () => StreamController<String?>.broadcast());
}
