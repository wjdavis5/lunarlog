/// Issue #1489: [TodayLog], the value the Today screen's log card and the
/// floating button's label are both read from, and [TodayLog.hasContent],
/// the one rule for "is anything logged today" the two share.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/logging/today_log.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';

final LocalDate kDay = LocalDate(2026, 8, 30);
final DateTime kNow = DateTime.utc(2026, 8, 30, 12);

DayEntry entry({
  FlowLevel flow = FlowLevel.none,
  List<String> tags = const [],
  String? note,
  bool pms = false,
  DateTime? deletedAt,
}) =>
    DayEntry(
      id: 'e1',
      profileId: 'p1',
      localDate: kDay,
      tz: 'UTC',
      flow: flow,
      tags: tags,
      note: note,
      pms: pms,
      updatedAt: kNow,
      deletedAt: deletedAt,
    );

Observation observation(
  ObservationCategory category, {
  double? valueNum,
  String? unit,
  ObservationSource source = ObservationSource.manual,
}) =>
    Observation(
      id: 'o-${category.wireCode}',
      dayEntryId: 'e1',
      profileId: 'p1',
      localDate: kDay,
      tz: 'UTC',
      category: category,
      valueNum: valueNum,
      unit: unit,
      source: source,
      updatedAt: kNow,
    );

TodayLog log(DayEntry? entry, [List<Observation> observations = const []]) =>
    TodayLog(entry: entry, observations: observations);

void main() {
  group('TodayLog.hasContent', () {
    test('no entry is nothing logged', () {
      expect(log(null).hasContent, isFalse);
    });

    test('an entry with no flow, no tags and no note is nothing logged', () {
      expect(log(entry()).hasContent, isFalse);
    });

    test('a note of only spaces is not a note', () {
      expect(log(entry(note: '   ')).hasContent, isFalse);
      expect(log(entry(note: '   ')).hasNote, isFalse);
    });

    test('a tombstoned entry is nothing logged, whatever it still carries',
        () {
      final tombstone = entry(
        flow: FlowLevel.medium,
        tags: const ['cramps'],
        note: 'kept on the row',
        deletedAt: kNow,
      );
      expect(log(tombstone).hasContent, isFalse);
      expect(
        log(tombstone, [
          observation(ObservationCategory.bbt, valueNum: 36.7),
        ]).hasContent,
        isFalse,
      );
    });

    test('a flow level is logged, an explicit "not bleeding" included', () {
      expect(log(entry(flow: FlowLevel.light)).hasContent, isTrue);
      expect(log(entry(flow: FlowLevel.superHeavy)).hasContent, isTrue);
      expect(log(entry(flow: FlowLevel.notBleeding)).hasContent, isTrue);
    });

    test('tags alone are logged', () {
      expect(log(entry(tags: const ['cramps'])).hasContent, isTrue);
    });

    test('a note alone is logged', () {
      final withNote = log(entry(note: 'slept badly'));
      expect(withNote.hasContent, isTrue);
      expect(withNote.hasNote, isTrue);
    });

    test('the PMS marker alone is logged', () {
      expect(log(entry(pms: true)).hasContent, isTrue);
    });

    test('a hand-entered temperature or weight alone is logged', () {
      expect(
        log(entry(), [observation(ObservationCategory.bbt, valueNum: 36.7)])
            .hasContent,
        isTrue,
      );
      expect(
        log(entry(), [observation(ObservationCategory.weight, valueNum: 61)])
            .hasContent,
        isTrue,
      );
    });

    test('a reading another source wrote does not make the day logged', () {
      final wearable = observation(
        ObservationCategory.bbt,
        valueNum: 36.9,
        source: ObservationSource.wearable,
      );
      expect(log(entry(), [wearable]).hasContent, isFalse);
      expect(log(entry(), [wearable]).bbt, isNull);
    });
  });

  group('TodayLog readings', () {
    test('hasSpotting follows the spotting observation, not the flow', () {
      expect(log(entry(flow: FlowLevel.notBleeding)).hasSpotting, isFalse);
      expect(
        log(
          entry(flow: FlowLevel.notBleeding),
          [observation(ObservationCategory.spotting)],
        ).hasSpotting,
        isTrue,
      );
    });

    test('bbt and weight are the day\'s hand-entered readings', () {
      final bbt = observation(ObservationCategory.bbt, valueNum: 36.7);
      final weight = observation(ObservationCategory.weight, valueNum: 61);
      final withBoth = log(entry(), [bbt, weight]);
      expect(withBoth.bbt, same(bbt));
      expect(withBoth.weight, same(weight));
      expect(log(entry()).bbt, isNull);
      expect(log(entry()).weight, isNull);
    });
  });
}
