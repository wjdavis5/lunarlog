/// Issue #1489: [TodayLog], the value the Today screen's log card and the
/// floating button's label are both read from, and [TodayLog.hasContent],
/// the one rule for "is anything logged today" the two share.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/logging/custom_tag_registry.dart';
import 'package:lunarlog/domain/logging/today_log.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';
import 'package:lunarlog/domain/tags.dart' show TagCategory, kTagTaxonomy;

final LocalDate kDay = LocalDate(2026, 8, 30);
final DateTime kNow = DateTime.utc(2026, 8, 30, 12);

CustomTag customTag(String code, String displayName) => CustomTag(
      id: 'tag-$code',
      profileId: 'p1',
      code: code,
      displayName: displayName,
      category: kCustomTagCategory,
      createdAt: kNow,
      updatedAt: kNow,
    );

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

    test('a spotting record alone is logged: the health import stores a '
        'spotting-only day with no flow at all', () {
      final spotting = observation(ObservationCategory.spotting);
      expect(log(entry(), [spotting]).hasContent, isTrue);
      // Whoever wrote it: an imported spotting record is still spotting.
      expect(
        log(entry(), [
          observation(
            ObservationCategory.spotting,
            source: ObservationSource.healthConnect,
          ),
        ]).hasContent,
        isTrue,
      );
      // A tombstoned entry is still nothing logged.
      expect(log(entry(deletedAt: kNow), [spotting]).hasContent, isFalse);
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

  // The rules below moved here from the app's Today log card so that the
  // browser version's card reads them through the web domain facade
  // instead of writing its own. The card's tests
  // (test/ui/components/today_log_card_test.dart) still pin them in the
  // reader's words.
  group('TodayLog.flowLine', () {
    final spotting = observation(ObservationCategory.spotting);

    test('no entry, and an entry with no flow, have no flow line', () {
      expect(log(null).flowLine, isNull);
      expect(log(entry()).flowLine, isNull);
      expect(log(entry(tags: const ['cramps'])).flowLine, isNull);
    });

    test('every bleed level is a bleed', () {
      for (final level in [
        FlowLevel.light,
        FlowLevel.medium,
        FlowLevel.heavy,
        FlowLevel.superHeavy,
      ]) {
        expect(
          log(entry(flow: level)).flowLine,
          TodayLogFlow.bleed,
          reason: '${level.name} is a bleed level',
        );
      }
    });

    test('an explicit "not bleeding" reads as itself', () {
      expect(
        log(entry(flow: FlowLevel.notBleeding)).flowLine,
        TodayLogFlow.notBleeding,
      );
    });

    test('a spotting record reads as spotting, not the "not bleeding" the '
        'flow was raised to', () {
      expect(
        log(entry(flow: FlowLevel.notBleeding), [spotting]).flowLine,
        TodayLogFlow.spotting,
      );
    });

    test('a spotting record with no flow at all, as the health import '
        'stores it, reads as spotting', () {
      expect(log(entry(), [spotting]).flowLine, TodayLogFlow.spotting);
    });

    test('bleed wins over spotting, as on the calendar', () {
      expect(
        log(entry(flow: FlowLevel.heavy), [spotting]).flowLine,
        TodayLogFlow.bleed,
      );
    });

    test('the flow level a row stored before spotting was its own record '
        'still reads as spotting', () {
      expect(
        // ignore: deprecated_member_use_from_same_package
        log(entry(flow: FlowLevel.spotting)).flowLine,
        TodayLogFlow.spotting,
      );
    });
  });

  group('isUnnamedOnToday', () {
    test('an ordinary curated tag is named', () {
      expect(isUnnamedOnToday('cramps', const []), isFalse);
      expect(isUnnamedOnToday('sticky', const []), isFalse);
      expect(isUnnamedOnToday('bloating', const []), isFalse);
    });

    test('every sex-life and test-result tag is counted, never named', () {
      final unnamed = kTagTaxonomy.where(
        (tag) => kTodayLogUnnamedCategories.contains(tag.category),
      );
      // The two categories are not empty, or this proves nothing.
      expect(
        unnamed.map((tag) => tag.category).toSet(),
        {TagCategory.sexLife, TagCategory.tests},
      );
      for (final tag in unnamed) {
        expect(
          isUnnamedOnToday(tag.code, const []),
          isTrue,
          reason: '${tag.code} must not be named on Today',
        );
      }
    });

    test('every other curated tag is named', () {
      for (final tag in kTagTaxonomy) {
        if (kTodayLogUnnamedCategories.contains(tag.category)) continue;
        expect(
          isUnnamedOnToday(tag.code, const []),
          isFalse,
          reason: '${tag.code} is an ordinary tag',
        );
      }
    });

    test('the unnamed categories are sex life and test results, no more',
        () {
      expect(
        kTodayLogUnnamedCategories,
        {TagCategory.sexLife, TagCategory.tests},
      );
    });

    test('a code neither the taxonomy nor the registry knows is counted',
        () {
      expect(isUnnamedOnToday('some_new_code', const []), isTrue);
      expect(
        isUnnamedOnToday('some_new_code', [
          customTag('back_cracking', 'Back cracking'),
        ]),
        isTrue,
      );
    });

    test('a custom tag is named once its registry row is in hand, even one '
        'that shares a word with an unnamed category', () {
      final registry = [
        customTag('back_cracking', 'Back cracking'),
        customTag('sex_ed_class', 'Sex ed class'),
      ];
      expect(isUnnamedOnToday('back_cracking', registry), isFalse);
      expect(isUnnamedOnToday('sex_ed_class', registry), isFalse);
      // Until then it is a code like any other this build cannot name.
      expect(isUnnamedOnToday('back_cracking', const []), isTrue);
    });

    test('a registry row cannot make a curated sex-life tag nameable', () {
      expect(
        isUnnamedOnToday('unprotected_sex', [
          customTag('unprotected_sex', 'Movie night'),
        ]),
        isTrue,
      );
    });
  });

  group('todayTagLabel', () {
    test('a self-describing tag reads by its own word', () {
      expect(todayTagLabel('cramps', const []), 'Cramps');
      expect(todayTagLabel('headache', const []), 'Headache');
      expect(todayTagLabel('pain_free', const []), 'Pain free');
    });

    test('a tag whose word needs its heading carries it', () {
      expect(
        todayTagLabel('sticky', const []),
        'Vaginal discharge: Sticky',
      );
      expect(todayTagLabel('normal', const []), 'Stool: Normal');
      expect(todayTagLabel('sweet', const []), 'Craving: Sweet');
      expect(
        todayTagLabel('0_to_3_hours', const []),
        'Sleep duration: 0-3 hours',
      );
      expect(todayTagLabel('pain', const []), 'Took pain medication');
    });

    test('digestion keeps its own word, with no "Digestion:" in front', () {
      expect(todayTagLabel('bloating', const []), 'Bloating');
      expect(todayTagLabel('nausea', const []), 'Nausea');
      for (final tag in kTagTaxonomy) {
        if (tag.category != TagCategory.digestion) continue;
        expect(
          todayTagLabel(tag.code, const []),
          isNot(startsWith('Digestion:')),
          reason: '${tag.code} says what it is without its heading',
        );
      }
    });

    test('a true clash is still told apart', () {
      expect(
        todayTagLabel('great_digestion', const []),
        'Great (digestion)',
      );
    });

    test('a custom tag reads by the name its registry row gives it', () {
      expect(
        todayTagLabel('back_cracking', [
          customTag('back_cracking', 'Back cracking'),
        ]),
        'Back cracking',
      );
    });
  });

  group('todayLogTagsOf', () {
    test('no tags is nothing to show and nothing to count', () {
      final tags = todayLogTagsOf(const [], const []);
      expect(tags.named, isEmpty);
      expect(tags.unnamedCount, 0);
      expect(tags.shown, isEmpty);
      expect(tags.moreCount, 0);
    });

    test('named tags keep the order the entry stores them in', () {
      final tags = todayLogTagsOf(
        const ['headache', 'cramps', 'pain_free'],
        const [],
      );
      expect(tags.named, ['Headache', 'Cramps', 'Pain free']);
      expect(tags.shown, ['Headache', 'Cramps', 'Pain free']);
      expect(tags.unnamedCount, 0);
      expect(tags.moreCount, 0);
    });

    test('sex-life, test-result and unknown tags are counted together and '
        'none of them is named', () {
      final tags = todayLogTagsOf(
        const [
          'cramps',
          'unprotected_sex',
          'pregnancy_positive',
          'withdrawal',
          'some_new_code',
        ],
        const [],
      );
      expect(tags.named, ['Cramps']);
      expect(tags.unnamedCount, 4);
      expect(tags.shown, ['Cramps']);
      expect(tags.moreCount, 4);
    });

    test('a day whose only tags are unnamed still has one to count', () {
      final tags = todayLogTagsOf(const ['protected_sex'], const []);
      expect(tags.named, isEmpty);
      expect(tags.shown, isEmpty);
      expect(tags.unnamedCount, 1);
      expect(tags.moreCount, 1);
    });

    test('a custom tag is named among the curated ones', () {
      final tags = todayLogTagsOf(
        const ['back_cracking', 'cramps', 'some_new_code'],
        [customTag('back_cracking', 'Back cracking')],
      );
      expect(tags.named, ['Back cracking', 'Cramps']);
      expect(tags.unnamedCount, 1);
    });
  });

  group('TodayLogTags, the six-tag limit', () {
    const labels = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];

    test('the limit is six', () {
      expect(kTodayLogMaxTags, 6);
    });

    test('six named tags are all shown, with nothing more', () {
      final tags = TodayLogTags(named: labels.take(6).toList());
      expect(tags.shown, ['A', 'B', 'C', 'D', 'E', 'F']);
      expect(tags.moreCount, 0);
    });

    test('the seventh is counted, not shown', () {
      final tags = TodayLogTags(named: labels.take(7).toList());
      expect(tags.shown, ['A', 'B', 'C', 'D', 'E', 'F']);
      expect(tags.moreCount, 1);
    });

    test('tags past the limit and unnamed tags are counted together', () {
      const tags = TodayLogTags(named: labels, unnamedCount: 3);
      expect(tags.shown, ['A', 'B', 'C', 'D', 'E', 'F']);
      expect(tags.moreCount, 5);
    });

    test('fewer than six leaves only the unnamed ones to count', () {
      const tags = TodayLogTags(named: ['A', 'B'], unnamedCount: 2);
      expect(tags.shown, ['A', 'B']);
      expect(tags.moreCount, 2);
    });
  });
}
