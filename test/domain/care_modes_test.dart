/// Care-mode copy registry and reminder presets (Issue #131, R12): the
/// vocabulary rules are the deliverable, so this suite pins the registry's
/// structural invariants — every mode has complete copy, teen's category
/// ordering is a permutation (never a subset: "teen is not a euphemism for
/// a reduced app"), only irregular silences the late banner, and the
/// presets match the issue's stated defaults per mode.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/care_modes.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/notifications/reminder_presets.dart';
import 'package:lunarlog/domain/prediction/prediction.dart'
    show CycleConfidence;
import 'package:lunarlog/domain/tags.dart';

void main() {
  group('careModeCopyFor completeness', () {
    test('every mode has non-empty copy for every registry field', () {
      for (final mode in ProfileMode.values) {
        final copy = careModeCopyFor(mode, irregularFraming: false);
        expect(copy.notEnoughTitle, isNotEmpty, reason: '$mode title');
        expect(copy.notEnoughBody(2, 3), isNotEmpty, reason: '$mode body');
        expect(copy.nextEstimateLabel, isNotEmpty, reason: '$mode estimate');
        for (final category in TagCategory.values) {
          expect(
            copy.categoryLabel(category),
            isNotEmpty,
            reason: '$mode heading for $category',
          );
        }
      }
    });

    test('teen is not a reduced app: its category order is a permutation '
        'of every standard category, never a subset', () {
      final teen = careModeCopyFor(ProfileMode.teen, irregularFraming: false);
      expect(teen.categoriesInOrder.toSet(), TagCategory.values.toSet());
      expect(teen.categoriesInOrder, hasLength(TagCategory.values.length));
      // And it genuinely reorders (that is the point of "surfaced first").
      expect(
        teen.categoriesInOrder,
        isNot(TagCategory.values),
        reason: 'teen surfaces body-literacy categories first',
      );
      expect(teen.categoriesInOrder.first, TagCategory.body);
    });

    test('irregular and teen silence the late banner (Issue #131, #998); '
        'standard and caregiver keep it', () {
      expect(careModeCopyFor(ProfileMode.irregular, irregularFraming: false).silencesLateBanner, isTrue);
      expect(careModeCopyFor(ProfileMode.standard, irregularFraming: false).silencesLateBanner, isFalse);
      expect(careModeCopyFor(ProfileMode.teen, irregularFraming: false).silencesLateBanner, isTrue);
      expect(
        careModeCopyFor(ProfileMode.caregiver, irregularFraming: false).silencesLateBanner,
        isFalse,
      );
    });

    test('only irregular hides the tier caption — its overdue status '
        'label already carries the "variation is expected" framing '
        '(Issue #131)', () {
      expect(careModeCopyFor(ProfileMode.irregular, irregularFraming: false).showsTierCaption, isFalse);
      expect(careModeCopyFor(ProfileMode.standard, irregularFraming: false).showsTierCaption, isTrue);
      expect(careModeCopyFor(ProfileMode.teen, irregularFraming: false).showsTierCaption, isTrue);
      expect(careModeCopyFor(ProfileMode.caregiver, irregularFraming: false).showsTierCaption, isTrue);
    });

    test('only irregular hides the fertile-window row; every mode carries '
        'a real (non-empty) fertileWindowLabel/fertileWindowLegend, '
        "including irregular — teen's is deliberately plainer than "
        'standard/caregiver\'s (issue #143 review)', () {
      expect(
        careModeCopyFor(ProfileMode.irregular, irregularFraming: false).showsFertileWindow,
        isFalse,
      );
      expect(careModeCopyFor(ProfileMode.standard, irregularFraming: false).showsFertileWindow, isTrue);
      expect(careModeCopyFor(ProfileMode.teen, irregularFraming: false).showsFertileWindow, isTrue);
      expect(careModeCopyFor(ProfileMode.caregiver, irregularFraming: false).showsFertileWindow, isTrue);

      for (final mode in ProfileMode.values) {
        final copy = careModeCopyFor(mode, irregularFraming: false);
        expect(copy.fertileWindowLabel, isNotEmpty, reason: '$mode label');
        expect(copy.fertileWindowLegend, isNotEmpty, reason: '$mode legend');
      }

      final standard = careModeCopyFor(ProfileMode.standard, irregularFraming: false);
      final teen = careModeCopyFor(ProfileMode.teen, irregularFraming: false);
      expect(
        teen.fertileWindowLabel,
        isNot(standard.fertileWindowLabel),
        reason: 'teen uses plainer, less clinical phrasing',
      );
      expect(teen.fertileWindowLegend, isNot(standard.fertileWindowLegend));
      expect(
        careModeCopyFor(ProfileMode.caregiver, irregularFraming: false).fertileWindowLabel,
        standard.fertileWindowLabel,
        reason: 'caregiver matches standard\'s clinical framing',
      );
    });

    test('irregular overdue copy never uses late framing', () {
      final copy = careModeCopyFor(ProfileMode.irregular, irregularFraming: false);
      expect(copy.overdueStatusLabel, contains('common'));
      expect(copy.overdueStatusLabel.toLowerCase(), isNot(contains('late')));
    });

    test('teen overview copy differs from standard '
        '(vocabulary actually varies by mode)', () {
      final standard = careModeCopyFor(ProfileMode.standard, irregularFraming: false);
      expect(
        careModeCopyFor(ProfileMode.teen, irregularFraming: false).notEnoughTitle,
        isNot(standard.notEnoughTitle),
      );
      expect(
        careModeCopyFor(ProfileMode.teen, irregularFraming: false).notEnoughBody(2, 3),
        isNot(standard.notEnoughBody(2, 3)),
      );
    });

    test('teen day-sheet headings differ from standard for at least the '
        'body category', () {
      final standard = careModeCopyFor(ProfileMode.standard, irregularFraming: false);
      final teen = careModeCopyFor(ProfileMode.teen, irregularFraming: false);
      expect(
        teen.categoryLabel(TagCategory.body),
        isNot(standard.categoryLabel(TagCategory.body)),
      );
    });

    test('issue #251: every mode surfaces all eight feelings/mind/lifestyle '
        'categories; teen keeps the feelings/mind cluster right after body '
        '(the old mood position)', () {
      const newCategories = [
        TagCategory.feelings,
        TagCategory.mind,
        TagCategory.motivation,
        TagCategory.socialLife,
        TagCategory.leisure,
        TagCategory.meditation,
        TagCategory.pms,
        TagCategory.partying,
      ];
      for (final mode in ProfileMode.values) {
        final copy = careModeCopyFor(mode, irregularFraming: false);
        for (final category in newCategories) {
          expect(
            copy.categoriesInOrder,
            contains(category),
            reason: '$mode must still surface $category (never a subset)',
          );
          expect(
            copy.categoryLabel(category),
            isNotEmpty,
            reason: '$mode heading for $category',
          );
        }
      }
      final teenOrder = careModeCopyFor(ProfileMode.teen, irregularFraming: false).categoriesInOrder;
      expect(teenOrder[0], TagCategory.body);
      expect(teenOrder[1], TagCategory.feelings);
      expect(teenOrder[2], TagCategory.mind);
      // And standard keeps the appended cluster after body, in enum order.
      final standardOrder = careModeCopyFor(ProfileMode.standard, irregularFraming: false)
          .categoriesInOrder;
      expect(
        standardOrder.indexOf(TagCategory.body) + 1,
        standardOrder.indexOf(TagCategory.feelings),
      );
    });

    test('issue #252: every mode surfaces all six events/care categories; '
        'they append after the lifestyle cluster in every order', () {
      const newCategories = [
        TagCategory.collectionMethod,
        TagCategory.exercise,
        TagCategory.appointments,
        TagCategory.medication,
        TagCategory.ailments,
        TagCategory.supplements,
      ];
      for (final mode in ProfileMode.values) {
        final copy = careModeCopyFor(mode, irregularFraming: false);
        for (final category in newCategories) {
          expect(
            copy.categoriesInOrder,
            contains(category),
            reason: '$mode must still surface $category (never a subset)',
          );
          expect(
            copy.categoryLabel(category),
            isNotEmpty,
            reason: '$mode heading for $category',
          );
        }
      }
      // Standard/caregiver/irregular surface every category in enum
      // order, so the six append after partying; teen appends them after
      // partying too, keeping its body-literacy reorder untouched.
      for (final mode in ProfileMode.values) {
        final order = careModeCopyFor(mode, irregularFraming: false).categoriesInOrder;
        expect(
          order.indexOf(TagCategory.partying) + 1,
          order.indexOf(TagCategory.collectionMethod),
          reason: '$mode appends the events/care cluster after partying',
        );
      }
    });

    test('issue #253: every mode surfaces all three sensitive/fertility '
        'categories (sex_life, discharge, tests); they append after the '
        'events/care cluster in every order', () {
      const newCategories = [
        TagCategory.sexLife,
        TagCategory.discharge,
        TagCategory.tests,
      ];
      for (final mode in ProfileMode.values) {
        final copy = careModeCopyFor(mode, irregularFraming: false);
        for (final category in newCategories) {
          expect(
            copy.categoriesInOrder,
            contains(category),
            reason: '$mode must still surface $category (never a subset)',
          );
          expect(
            copy.categoryLabel(category),
            isNotEmpty,
            reason: '$mode heading for $category',
          );
        }
        // Appended after supplements in every mode's order.
        final order = copy.categoriesInOrder;
        expect(
          order.indexOf(TagCategory.supplements) + 1,
          order.indexOf(TagCategory.sexLife),
          reason: '$mode appends the sensitive/fertility cluster after '
              'supplements',
        );
      }
    });
  });

  group('issue #816: not-enough-history progress copy', () {
    test('states the live tally in completed cycles and what happens next',
        () {
      final standard = careModeCopyFor(ProfileMode.standard, irregularFraming: false);
      expect(
        standard.notEnoughBody(2, 3),
        '2 of 3 completed cycles — estimates start after the next period.',
      );
      expect(
        standard.notEnoughBody(1, 3),
        '1 of 3 completed cycles — 2 more periods until estimates.',
      );
      expect(
        standard.notEnoughBody(0, 3),
        '0 of 3 completed cycles — estimates start once 3 '
        'completed cycles are recorded.',
      );
    });

    test('every mode speaks the same "completed cycles" unit and never the '
        'old vague "a few cycles"', () {
      for (final mode in ProfileMode.values) {
        final body = careModeCopyFor(mode, irregularFraming: false).notEnoughBody(2, 3);
        expect(body, contains('completed cycles'), reason: '$mode');
        expect(body, isNot(contains('a few cycles')), reason: '$mode');
      }
    });
  });

  group('reminderPresetFor (Issue #131)', () {
    test('standard keeps both reminder types on (pre-#131 behavior)', () {
      final preset = reminderPresetFor(ProfileMode.standard);
      expect(preset.upcoming, isTrue);
      expect(preset.late, isTrue);
    });

    test('teen and irregular keep upcoming but drop late reminders', () {
      expect(reminderPresetFor(ProfileMode.teen).upcoming, isTrue);
      expect(reminderPresetFor(ProfileMode.teen).late, isFalse);
      expect(reminderPresetFor(ProfileMode.irregular).upcoming, isTrue);
      expect(reminderPresetFor(ProfileMode.irregular).late, isFalse);
    });

    test('the retired caregiver wire value arms like standard (Issue #850) — '
        'guardian reminder suppression is a lens concern now, not a mode', () {
      final preset = reminderPresetFor(ProfileMode.caregiver);
      expect(preset.upcoming, isTrue);
      expect(preset.late, isTrue);
    });
  });

  group('issue #853: composed irregular framing', () {
    test('the flag silences the late banner in every mode it composes with',
        () {
      for (final mode in ProfileMode.choosableModes) {
        final copy = careModeCopyFor(mode, irregularFraming: true);
        expect(copy.silencesLateBanner, isTrue, reason: '$mode');
        expect(copy.overdueStatusLabel, isNotEmpty, reason: '$mode');
      }
    });

    test('the flag hides the tier caption and the fertile window, keeping '
        'the base mode\'s real (non-empty) fertile-window strings', () {
      for (final mode in ProfileMode.choosableModes) {
        final copy = careModeCopyFor(mode, irregularFraming: true);
        expect(copy.showsTierCaption, isFalse, reason: '$mode');
        expect(copy.showsFertileWindow, isFalse, reason: '$mode');
        expect(copy.fertileWindowLabel, isNotEmpty, reason: '$mode');
        expect(copy.fertileWindowLegend, isNotEmpty, reason: '$mode');
      }
    });

    test('composition keeps the base mode\'s voice: title, category order '
        'and headings are unchanged', () {
      for (final mode in ProfileMode.choosableModes) {
        final base = careModeCopyFor(mode, irregularFraming: false);
        final composed = careModeCopyFor(mode, irregularFraming: true);
        expect(composed.notEnoughTitle, base.notEnoughTitle, reason: '$mode');
        expect(composed.categoriesInOrder, base.categoriesInOrder,
            reason: '$mode');
        expect(composed.categoryLabels, base.categoryLabels,
            reason: '$mode');
      }
    });

    test('teen + irregular never says late, anywhere in its surfaced copy',
        () {
      final copy = careModeCopyFor(ProfileMode.teen, irregularFraming: true);
      final surfaced = [
        copy.notEnoughTitle,
        copy.notEnoughBody(2, 3),
        copy.nextEstimateLabel,
        copy.overdueStatusLabel,
        copy.overdueActionLabel,
      ].join(' ').toLowerCase();
      expect(surfaced, isNot(contains('late')));
      // Issue #998: the teen composition now shares the base teen's own
      // quiet line, which is late-free and tier-independent.
      expect(copy.overdueStatusLabel, contains('normal'));
    });

    test('teen + irregular offers exactly one action: "log it when it '
        'comes" — never skip this cycle', () {
      final teen = careModeCopyFor(ProfileMode.teen, irregularFraming: true);
      expect(teen.overdueActionLabel, 'Log it when it comes');
      for (final mode in [ProfileMode.standard, ProfileMode.caregiver]) {
        expect(careModeCopyFor(mode, irregularFraming: true).overdueActionLabel,
            isEmpty,
            reason: '$mode composition stays a text-only line');
      }
      expect(teen.overdueActionLabel.toLowerCase(), isNot(contains('skip')));
    });

    test('the estimate label goes range-style in the mode\'s own register',
        () {
      expect(
        careModeCopyFor(ProfileMode.teen, irregularFraming: true)
            .nextEstimateLabel,
        'Your next period may start around:',
      );
      expect(
        careModeCopyFor(ProfileMode.standard, irregularFraming: true)
            .nextEstimateLabel,
        'Next period may start around:',
      );
    });

    test('the legacy irregular wire value is its own full copy and composing '
        'on top of it is a no-op', () {
      final legacy = careModeCopyFor(ProfileMode.irregular,
          irregularFraming: false);
      final composed = careModeCopyFor(ProfileMode.irregular,
          irregularFraming: true);
      expect(composed.silencesLateBanner, legacy.silencesLateBanner);
      expect(composed.overdueStatusLabel, legacy.overdueStatusLabel);
      expect(composed.overdueActionLabel, isEmpty);
    });

    test('choosableModes never offers the legacy irregular or caregiver wire '
        'values', () {
      expect(ProfileMode.choosableModes,
          isNot(contains(ProfileMode.irregular)));
      expect(ProfileMode.choosableModes,
          isNot(contains(ProfileMode.caregiver)));
      expect(ProfileMode.choosableModes,
          containsAll([ProfileMode.standard, ProfileMode.teen]));
    });
  });

  group('issue #853: irregularFramingInEffect (engine-derived default)', () {
    test('an explicit stored value wins in both directions', () {
      expect(
        irregularFramingInEffect(
            mode: ProfileMode.teen, stored: false,
            tier: CycleConfidence.learning),
        isFalse,
      );
      expect(
        irregularFramingInEffect(
            mode: ProfileMode.standard, stored: true,
            tier: CycleConfidence.high),
        isTrue,
      );
    });

    test('an unset teen reads ON until the engine reaches high — including '
        'with no estimate at all', () {
      for (final tier in [
        null,
        CycleConfidence.provisional,
        CycleConfidence.learning,
        CycleConfidence.irregular,
      ]) {
        expect(
          irregularFramingInEffect(
              mode: ProfileMode.teen, stored: null, tier: tier),
          isTrue,
          reason: 'tier $tier keeps the variance-expecting framing',
        );
      }
      expect(
        irregularFramingInEffect(
            mode: ProfileMode.teen, stored: null, tier: CycleConfidence.high),
        isFalse,
        reason: 'steady cycles lift the framing on their own',
      );
    });

    test('an unset non-teen mode (and the legacy wire value) reads by its '
        'own axis', () {
      expect(
        irregularFramingInEffect(
            mode: ProfileMode.standard, stored: null, tier: null),
        isFalse,
      );
      expect(
        irregularFramingInEffect(
            mode: ProfileMode.caregiver, stored: null,
            tier: CycleConfidence.learning),
        isFalse,
      );
      expect(
        irregularFramingInEffect(
            mode: ProfileMode.irregular, stored: null, tier: null),
        isTrue,
        reason: 'the legacy wire value still frames as irregular',
      );
    });
  });

  group('issue #853: reminderPresetFor composes with the flag', () {
    test('the flag drops late reminders from any mode that had them', () {
      final standard = reminderPresetFor(ProfileMode.standard,
          irregularFraming: true);
      expect(standard.upcoming, isTrue);
      expect(standard.late, isFalse);
    });

    test('the flag never re-arms what a mode had off', () {
      // Issue #850: caregiver now plans like standard, so the flag drops
      // its late window; teen's own preset already had late off.
      final caregiver = reminderPresetFor(ProfileMode.caregiver,
          irregularFraming: true);
      expect(caregiver.upcoming, isTrue);
      expect(caregiver.late, isFalse);
      final teen = reminderPresetFor(ProfileMode.teen,
          irregularFraming: true);
      expect(teen.upcoming, isTrue);
      expect(teen.late, isFalse);
    });

    test('without the flag the pre-#853 defaults hold', () {
      expect(reminderPresetFor(ProfileMode.standard).late, isTrue);
      expect(reminderPresetFor(ProfileMode.teen).late, isFalse);
    }
    );
  });

  group('issue #998: teen mode avoids late framing at every tier', () {
    test('teen silences the late banner and carries its own quiet line '
        'whether or not the irregular framing is composed', () {
      const expected =
          'No new period logged yet — a few days either way is normal.';
      for (final framed in [false, true]) {
        final copy =
            careModeCopyFor(ProfileMode.teen, irregularFraming: framed);
        expect(copy.silencesLateBanner, isTrue, reason: 'framed=$framed');
        expect(copy.overdueStatusLabel, expected, reason: 'framed=$framed');
        expect(copy.overdueActionLabel, 'Log it when it comes',
            reason: 'framed=$framed');
      }
    });

    test('every surfaced teen tier string is free of "late" — the framing '
        'axis no longer decides the overdue wording', () {
      final surfaced = [
        careModeCopyFor(ProfileMode.teen, irregularFraming: false),
        careModeCopyFor(ProfileMode.teen, irregularFraming: true),
      ]
          .expand((copy) => [
                copy.notEnoughTitle,
                copy.notEnoughBody(2, 3),
                copy.nextEstimateLabel,
                copy.overdueStatusLabel,
                copy.overdueActionLabel,
              ])
          .join(' ')
          .toLowerCase();
      expect(surfaced, isNot(contains('late')));
      expect(surfaced, isNot(contains('skip')));
    });

    test('the separate axis still works: teen at high confidence lifts the '
        'range/tier/caption framing while keeping the quiet overdue line', () {
      expect(
        irregularFramingInEffect(
            mode: ProfileMode.teen,
            stored: null,
            tier: CycleConfidence.high),
        isFalse,
        reason: 'high confidence still lifts the irregular-cycles framing',
      );
      final highTierTeen =
          careModeCopyFor(ProfileMode.teen, irregularFraming: false);
      expect(highTierTeen.silencesLateBanner, isTrue);
      expect(highTierTeen.showsTierCaption, isTrue);
      expect(highTierTeen.showsFertileWindow, isTrue);
    });
  });
}
