/// Issue #1489: the Today screen's log card — the summary [todayLogSummaryOf]
/// builds from a day's log, the lines the card shows for it, and the card
/// itself: its empty state, its Edit action, its one-sentence screen-reader
/// label, and the rule that the note's text is never on it.
///
/// The card mounted in the panel, and its live updates, are covered by
/// `test/ui/overview/today_log_overview_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/logging/custom_tag_registry.dart';
import 'package:lunarlog/domain/logging/today_log.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/measurement_unit.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/today_log_card.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';

final AppLocalizations kL10n = lookupAppLocalizations(const Locale('en'));

final LocalDate kDay = LocalDate(2026, 8, 30);
final DateTime kNow = DateTime.utc(2026, 8, 30, 12);

/// A note's text in these tests, and the words in it that appear nowhere
/// else on the card. Nothing the card renders or announces may contain
/// them.
const String kNoteText = 'zebra crossing after the dentist';
const List<String> kNoteWords = ['zebra', 'crossing', 'dentist'];

const Key kCard = ValueKey('today-log-card');
const Key kEdit = ValueKey('today-log-edit');
const Key kEmpty = ValueKey('today-log-empty');

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
      updatedAt: kNow,
    );

CustomTag customTag(String code, String displayName) => CustomTag(
      id: 'tag-$code',
      profileId: 'p1',
      code: code,
      displayName: displayName,
      category: kCustomTagCategory,
      createdAt: kNow,
      updatedAt: kNow,
    );

/// The summary of one day's log, in English.
TodayLogSummary? summaryOf(
  DayEntry? entry, {
  List<Observation> observations = const [],
  List<CustomTag> customTags = const [],
  BbtUnit bbtUnit = BbtUnit.celsius,
  WeightUnit weightUnit = WeightUnit.kg,
}) =>
    todayLogSummaryOf(
      TodayLog(entry: entry, observations: observations),
      l10n: kL10n,
      customTags: customTags,
      bbtUnit: bbtUnit,
      weightUnit: weightUnit,
    );

Future<void> pumpCard(
  WidgetTester tester, {
  required TodayLogSummary? summary,
  bool canEdit = true,
  VoidCallback? onEdit,
  double textScale = 1.0,
  Size physicalSize = const Size(390, 844),
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        // The panel's own shape: a padded ListView, so the card is as wide
        // as it is on the Today screen.
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TodayLogCard(
              summary: summary,
              canEdit: canEdit,
              onEdit: onEdit ?? () {},
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Every node of the real semantics tree, the one a screen reader reads.
List<SemanticsNode> semanticsNodes(WidgetTester tester) {
  final owner = tester.binding.renderViews.single.owner!.semanticsOwner!;
  final nodes = <SemanticsNode>[];
  void walk(SemanticsNode node) {
    nodes.add(node);
    for (final child in node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      walk(child);
    }
  }

  walk(owner.rootSemanticsNode!);
  return nodes;
}

/// Everything the card's own text widgets show.
List<String> cardTexts(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(of: find.byKey(kCard), matching: find.byType(Text)),
    )
    .map((text) => text.data ?? '')
    .toList();

void main() {
  group('todayLogSummaryOf', () {
    test('null when the day has no entry, an empty one, or a tombstone', () {
      expect(summaryOf(null), isNull);
      expect(summaryOf(entry()), isNull);
      expect(
        summaryOf(entry(flow: FlowLevel.medium, deletedAt: kNow)),
        isNull,
      );
    });

    test('a bleed level reads "{level} flow", in the calendar\'s words', () {
      expect(summaryOf(entry(flow: FlowLevel.light))!.flow, 'Light flow');
      expect(summaryOf(entry(flow: FlowLevel.medium))!.flow, 'Medium flow');
      expect(summaryOf(entry(flow: FlowLevel.heavy))!.flow, 'Heavy flow');
      expect(
        summaryOf(entry(flow: FlowLevel.superHeavy))!.flow,
        'Super heavy flow',
      );
    });

    test('an explicit "not bleeding" reads as itself', () {
      expect(
        summaryOf(entry(flow: FlowLevel.notBleeding))!.flow,
        'Not bleeding',
      );
    });

    test('no flow is left out', () {
      expect(summaryOf(entry(tags: const ['cramps']))!.flow, isNull);
    });

    test('a spotting day reads "Spotting", not the "not bleeding" its flow '
        'was raised to', () {
      expect(
        summaryOf(
          entry(flow: FlowLevel.notBleeding),
          observations: [observation(ObservationCategory.spotting)],
        )!.flow,
        'Spotting',
      );
    });

    test('a spotting-only day with no flow at all, as the health import '
        'stores it, is a logged day that reads "Spotting"', () {
      final summary = summaryOf(
        entry(),
        observations: [observation(ObservationCategory.spotting)],
      );
      expect(summary, isNotNull);
      expect(todayLogLines(summary!, kL10n), ['Spotting']);
    });

    test('bleed wins over spotting, as on the calendar', () {
      expect(
        summaryOf(
          entry(flow: FlowLevel.heavy),
          observations: [observation(ObservationCategory.spotting)],
        )!.flow,
        'Heavy flow',
      );
    });

    test('tags read by the day sheet\'s labels, in stored order', () {
      expect(
        summaryOf(entry(tags: const ['headache', 'cramps', 'pain_free']))!
            .tags,
        ['Headache', 'Cramps', 'Pain free'],
      );
    });

    test('a tag whose word needs its heading carries it, as in the '
        'export; a self-describing one does not', () {
      expect(
        summaryOf(
          entry(
            tags: const [
              'sticky',
              'normal',
              'sweet',
              '0_to_3_hours',
              'pain',
              'bloating',
              'great_digestion',
            ],
          ),
        )!
            .tags,
        [
          'Vaginal discharge: Sticky',
          'Stool: Normal',
          'Craving: Sweet',
          'Sleep duration: 0-3 hours',
          'Took pain medication',
          'Bloating',
          'Great (digestion)',
        ],
      );
    });

    test('sex-life and test-result tags are counted and never named', () {
      final summary = summaryOf(
        entry(
          tags: const [
            'cramps',
            'unprotected_sex',
            'pregnancy_positive',
            'withdrawal',
          ],
        ),
      )!;
      expect(summary.tags, ['Cramps']);
      expect(summary.unnamedTagCount, 3);
      final lines = todayLogLines(summary, kL10n);
      expect(lines, ['Cramps and 3 more']);
      for (final word in ['sex', 'Sex', 'Pregnancy', 'pregnancy', 'ithdrawal']) {
        expect(lines.join(' '), isNot(contains(word)));
      }
    });

    test('a day whose only tags are unnamed still counts as logged, and '
        'says how many', () {
      final one = summaryOf(entry(tags: const ['protected_sex']))!;
      expect(todayLogLines(one, kL10n), ['1 other entry']);
      final two = summaryOf(
        entry(tags: const ['protected_sex', 'ovulation_positive']),
      )!;
      expect(todayLogLines(two, kL10n), ['2 other entries']);
    });

    test('a custom tag is named even when it shares a word with an unnamed '
        'category', () {
      expect(
        summaryOf(
          entry(tags: const ['sex_ed_class']),
          customTags: [customTag('sex_ed_class', 'Sex ed class')],
        )!
            .tags,
        ['Sex ed class'],
      );
    });

    test('a custom tag in the profile\'s registry reads by the name it was '
        'given', () {
      final summary = summaryOf(
        entry(tags: const ['back_cracking', 'cramps']),
        customTags: [customTag('back_cracking', 'Back cracking')],
      )!;
      expect(summary.tags, ['Back cracking', 'Cramps']);
      expect(summary.unnamedTagCount, 0);
    });

    // A code this build does not know could be anything, a later version's
    // sex-life or test tag included, so Today never prints it. (The day
    // sheet still shows it: its own rule is that an unknown code is never
    // dropped.)
    test('a code neither the taxonomy nor the registry knows is counted, '
        'never printed', () {
      final summary = summaryOf(
        entry(tags: const ['back_cracking', 'cramps', 'some_new_code']),
        customTags: [customTag('back_cracking', 'Back cracking')],
      )!;
      expect(summary.tags, ['Back cracking', 'Cramps']);
      expect(summary.unnamedTagCount, 1);
      final lines = todayLogLines(summary, kL10n);
      expect(lines, ['Back cracking, Cramps and 1 more']);
      expect(lines.join(' '), isNot(contains('some_new_code')));
    });

    test('a day whose only tag is an unknown code is still a logged day, '
        'and says only how many', () {
      final summary = summaryOf(entry(tags: const ['some_new_code']))!;
      expect(summary.tags, isEmpty);
      expect(todayLogLines(summary, kL10n), ['1 other entry']);
    });

    test('unknown codes and the unnamed categories are counted together',
        () {
      final summary = summaryOf(
        entry(tags: const ['some_new_code', 'protected_sex', 'cramps']),
      )!;
      expect(summary.tags, ['Cramps']);
      expect(summary.unnamedTagCount, 2);
      expect(todayLogLines(summary, kL10n), ['Cramps and 2 more']);
    });

    test('with no registry in hand a custom tag is counted until its name '
        'is known', () {
      final summary = summaryOf(entry(tags: const ['back_cracking']))!;
      expect(summary.tags, isEmpty);
      expect(summary.unnamedTagCount, 1);
    });

    test('the PMS marker is named by the day sheet\'s own word', () {
      expect(summaryOf(entry(pms: true))!.details, ['PMS']);
    });

    test('a temperature and a weight read under the day sheet\'s field '
        'labels', () {
      final summary = summaryOf(
        entry(),
        observations: [
          observation(ObservationCategory.bbt,
              valueNum: 36.7, unit: 'celsius'),
          observation(ObservationCategory.weight, valueNum: 61, unit: 'kg'),
        ],
      )!;
      expect(summary.details, ['BBT (°C): 36.7', 'Weight (kg): 61']);
      expect(summary.flow, isNull);
      expect(summary.tags, isEmpty);
    });

    test('a reading is shown in the profile\'s unit, whatever it was '
        'stored in', () {
      final summary = summaryOf(
        entry(),
        observations: [
          observation(ObservationCategory.bbt, valueNum: 37, unit: 'celsius'),
          observation(ObservationCategory.weight, valueNum: 50, unit: 'kg'),
        ],
        bbtUnit: BbtUnit.fahrenheit,
        weightUnit: WeightUnit.lb,
      )!;
      expect(summary.details, ['BBT (°F): 98.6', 'Weight (lb): 110.23']);
    });

    test('hasNote says a note exists and nothing else about it', () {
      expect(summaryOf(entry(note: kNoteText))!.hasNote, isTrue);
      expect(summaryOf(entry(tags: const ['cramps']))!.hasNote, isFalse);
    });
  });

  group('todayLogLines', () {
    test('flow, then tags, then the rest, then the note', () {
      expect(
        todayLogLines(
          const TodayLogSummary(
            flow: 'Medium flow',
            tags: ['Cramps', 'Headache'],
            details: ['PMS', 'BBT (°C): 36.7'],
            hasNote: true,
          ),
          kL10n,
        ),
        [
          'Medium flow',
          'Cramps, Headache',
          'PMS',
          'BBT (°C): 36.7',
          'Note added',
        ],
      );
    });

    test('exactly six tags are all named', () {
      expect(
        todayLogLines(
          const TodayLogSummary(tags: ['A', 'B', 'C', 'D', 'E', 'F']),
          kL10n,
        ),
        ['A, B, C, D, E, F'],
      );
    });

    test('a seventh tag is counted, not named', () {
      expect(
        todayLogLines(
          const TodayLogSummary(tags: ['A', 'B', 'C', 'D', 'E', 'F', 'G']),
          kL10n,
        ),
        ['A, B, C, D, E, F and 1 more'],
      );
    });

    test('more than that are counted together', () {
      expect(
        todayLogLines(
          const TodayLogSummary(
            tags: ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I'],
          ),
          kL10n,
        ),
        ['A, B, C, D, E, F and 3 more'],
      );
    });

    test('nothing but a note is one line', () {
      expect(
        todayLogLines(const TodayLogSummary(hasNote: true), kL10n),
        ['Note added'],
      );
    });
  });

  group('TodayLogCard', () {
    testWidgets('nothing logged: one quiet line and no button, even for '
        'someone who may log', (tester) async {
      await pumpCard(tester, summary: null);

      expect(find.byKey(kCard), findsOneWidget);
      expect(find.byKey(kEmpty), findsOneWidget);
      expect(cardTexts(tester), ['Nothing logged today yet']);
      expect(find.byKey(kEdit), findsNothing,
          reason: 'the floating Log today button is the action');
      expect(
        find.descendant(
          of: find.byKey(kCard),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
        findsNothing,
      );
    });

    testWidgets('flow only', (tester) async {
      await pumpCard(
        tester,
        summary: summaryOf(entry(flow: FlowLevel.medium)),
      );

      expect(cardTexts(tester), ['Logged today', 'Edit', 'Medium flow']);
      expect(find.byKey(kEmpty), findsNothing);
    });

    testWidgets('tags only', (tester) async {
      await pumpCard(
        tester,
        summary: summaryOf(entry(tags: const ['cramps', 'headache'])),
      );

      expect(cardTexts(tester), ['Logged today', 'Edit', 'Cramps, Headache']);
    });

    testWidgets('flow, tags and a note, in that order', (tester) async {
      await pumpCard(
        tester,
        summary: summaryOf(
          entry(
            flow: FlowLevel.medium,
            tags: const ['cramps', 'headache'],
            note: kNoteText,
          ),
        ),
      );

      expect(cardTexts(tester), [
        'Logged today',
        'Edit',
        'Medium flow',
        'Cramps, Headache',
        'Note added',
      ]);
      final flow = tester.getTopLeft(find.text('Medium flow')).dy;
      final tags = tester.getTopLeft(find.text('Cramps, Headache')).dy;
      final note = tester.getTopLeft(find.text('Note added')).dy;
      expect(tester.getTopLeft(find.text('Logged today')).dy, lessThan(flow));
      expect(flow, lessThan(tags));
      expect(tags, lessThan(note));
    });

    testWidgets('more than six tags: six are named and the rest counted',
        (tester) async {
      await pumpCard(
        tester,
        summary: summaryOf(
          entry(
            tags: const [
              'cramps',
              'headache',
              'back_pain',
              'bloating',
              'nausea',
              'acne',
              'fatigue',
              'irritable',
            ],
          ),
        ),
      );

      expect(
        find.text(
          'Cramps, Headache, Back pain, Bloating, Nausea, Acne and 2 more',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Fatigue'), findsNothing);
      expect(find.textContaining('Irritable'), findsNothing);
    });

    testWidgets('a tag code this build does not know is nowhere in the tree '
        'or the semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCard(
        tester,
        summary: summaryOf(entry(tags: const ['cramps', 'some_new_code'])),
      );

      expect(find.text('Cramps and 1 more'), findsOneWidget);
      expect(
        find.textContaining('some_new_code', findRichText: true),
        findsNothing,
      );
      final spoken = semanticsNodes(tester)
          .map((node) => node.getSemanticsData())
          .map((data) => [data.label, data.value, data.hint, data.tooltip])
          .expand((fields) => fields)
          .join(' | ');
      expect(spoken, contains('Logged today: Cramps and 1 more.'));
      expect(spoken, isNot(contains('some_new_code')));
      handle.dispose();
    });

    testWidgets('the note\'s text is nowhere in the tree or the semantics',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCard(
        tester,
        summary: summaryOf(
          entry(tags: const ['cramps'], note: kNoteText),
        ),
      );

      expect(find.text('Note added'), findsOneWidget);
      for (final word in kNoteWords) {
        expect(
          find.textContaining(word, findRichText: true),
          findsNothing,
          reason: '"$word" is from the note',
        );
      }
      final spoken = semanticsNodes(tester)
          .map((node) => node.getSemanticsData())
          .map((data) => [data.label, data.value, data.hint, data.tooltip])
          .expand((fields) => fields)
          .join(' | ');
      expect(spoken, contains('Note added'));
      for (final word in kNoteWords) {
        expect(spoken, isNot(contains(word)), reason: '"$word" is from the note');
      }
      handle.dispose();
    });

    testWidgets('the summary reads as one sentence on one node, and Edit is '
        'a button of its own', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCard(
        tester,
        summary: summaryOf(
          entry(
            flow: FlowLevel.medium,
            tags: const ['cramps', 'headache'],
            note: kNoteText,
          ),
        ),
      );

      const sentence =
          'Logged today: Medium flow. Cramps, Headache. Note added.';
      final nodes = semanticsNodes(tester);
      expect(
        nodes.where((node) => node.getSemanticsData().label == sentence),
        hasLength(1),
      );
      // The lines the sentence is made of are not read a second time.
      for (final line in ['Logged today', 'Medium flow', 'Note added']) {
        expect(
          nodes.where((node) => node.getSemanticsData().label == line),
          isEmpty,
          reason: '"$line" must only be heard inside the sentence',
        );
      }
      final edit = nodes
          .where((node) => node.getSemanticsData().label == 'Edit')
          .toList();
      expect(edit, hasLength(1));
      final editData = edit.single.getSemanticsData();
      expect(editData.flagsCollection.isButton, isTrue);
      expect(editData.hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('tapping Edit calls back once', (tester) async {
      var edits = 0;
      await pumpCard(
        tester,
        summary: summaryOf(entry(flow: FlowLevel.light)),
        onEdit: () => edits++,
      );

      await tester.tap(find.byKey(kEdit));
      await tester.pump();
      expect(edits, 1);
    });

    testWidgets('read-only: the same summary, and no Edit', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCard(
        tester,
        summary: summaryOf(
          entry(flow: FlowLevel.medium, tags: const ['cramps']),
        ),
        canEdit: false,
      );

      expect(cardTexts(tester), ['Logged today', 'Medium flow', 'Cramps']);
      expect(find.byKey(kEdit), findsNothing);
      expect(
        semanticsNodes(tester).where(
          (node) =>
              node.getSemanticsData().label ==
              'Logged today: Medium flow. Cramps.',
        ),
        hasLength(1),
      );
      handle.dispose();
    });

    testWidgets('the Edit button keeps a 48dp tap target', (tester) async {
      await pumpCard(
        tester,
        summary: summaryOf(entry(flow: FlowLevel.light)),
      );

      final size = tester.getSize(find.byKey(kEdit));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    });

    // The fullest card the day sheet can produce: every line, the longest
    // labels, and more tags than fit.
    final fullest = summaryOf(
      entry(
        flow: FlowLevel.superHeavy,
        tags: const [
          'breast_tenderness',
          'migraine_with_aura',
          'back_pain',
          'bloating',
          'nausea',
          'acne',
          'fatigue',
        ],
        note: kNoteText,
        pms: true,
      ),
      observations: [
        observation(ObservationCategory.bbt, valueNum: 36.75, unit: 'celsius'),
        observation(ObservationCategory.weight, valueNum: 61.5, unit: 'kg'),
      ],
    );

    for (final scale in [1.0, 1.5, 2.0, 3.1]) {
      for (final canEdit in [true, false]) {
        testWidgets('no overflow at ${scale}x text scale on a phone-class '
            'viewport (${canEdit ? "with" : "without"} Edit)', (tester) async {
          await pumpCard(
            tester,
            summary: fullest,
            canEdit: canEdit,
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
          expect(find.text('Logged today'), findsOneWidget);
        });
      }

      testWidgets('the empty card does not overflow at ${scale}x text scale',
          (tester) async {
        await pumpCard(tester, summary: null, textScale: scale);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('no overflow at 3.1x text scale on the narrowest phone',
        (tester) async {
      await pumpCard(
        tester,
        summary: fullest,
        textScale: 3.1,
        physicalSize: const Size(320, 568),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
