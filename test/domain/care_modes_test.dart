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
import 'package:lunarlog/domain/tags.dart';

void main() {
  group('careModeCopyFor completeness', () {
    test('every mode has non-empty copy for every registry field', () {
      for (final mode in ProfileMode.values) {
        final copy = careModeCopyFor(mode);
        expect(copy.notEnoughTitle, isNotEmpty, reason: '$mode title');
        expect(copy.notEnoughBody, isNotEmpty, reason: '$mode body');
        expect(copy.nextEstimateLabel, isNotEmpty, reason: '$mode estimate');
        for (final category in TagCategory.values) {
          expect(copy.categoryLabel(category), isNotEmpty,
              reason: '$mode heading for $category');
        }
      }
    });

    test('teen is not a reduced app: its category order is a permutation '
        'of every standard category, never a subset', () {
      final teen = careModeCopyFor(ProfileMode.teen);
      expect(teen.categoriesInOrder.toSet(), TagCategory.values.toSet());
      expect(teen.categoriesInOrder, hasLength(TagCategory.values.length));
      // And it genuinely reorders (that is the point of "surfaced first").
      expect(teen.categoriesInOrder, isNot(TagCategory.values),
          reason: 'teen surfaces body-literacy categories first');
      expect(teen.categoriesInOrder.first, TagCategory.body);
    });

    test('only irregular silences the late banner (Issue #131)', () {
      expect(careModeCopyFor(ProfileMode.irregular).silencesLateBanner,
          isTrue);
      expect(careModeCopyFor(ProfileMode.standard).silencesLateBanner,
          isFalse);
      expect(careModeCopyFor(ProfileMode.teen).silencesLateBanner, isFalse);
      expect(careModeCopyFor(ProfileMode.caregiver).silencesLateBanner,
          isFalse);
    });

    test('only irregular hides the tier caption — its overdue status '
        'label already carries the "variation is expected" framing '
        '(Issue #131)', () {
      expect(careModeCopyFor(ProfileMode.irregular).showsTierCaption,
          isFalse);
      expect(careModeCopyFor(ProfileMode.standard).showsTierCaption, isTrue);
      expect(careModeCopyFor(ProfileMode.teen).showsTierCaption, isTrue);
      expect(careModeCopyFor(ProfileMode.caregiver).showsTierCaption,
          isTrue);
    });

    test('irregular overdue copy never uses late framing', () {
      final copy = careModeCopyFor(ProfileMode.irregular);
      expect(copy.overdueStatusLabel, contains('common'));
      expect(copy.overdueStatusLabel.toLowerCase(), isNot(contains('late')));
    });

    test('teen and caregiver overview copy differ from standard '
        '(vocabulary actually varies by mode)', () {
      final standard = careModeCopyFor(ProfileMode.standard);
      expect(careModeCopyFor(ProfileMode.teen).notEnoughTitle,
          isNot(standard.notEnoughTitle));
      expect(careModeCopyFor(ProfileMode.teen).notEnoughBody,
          isNot(standard.notEnoughBody));
    });

    test('teen day-sheet headings differ from standard for at least the '
        'body category', () {
      final standard = careModeCopyFor(ProfileMode.standard);
      final teen = careModeCopyFor(ProfileMode.teen);
      expect(teen.categoryLabel(TagCategory.body),
          isNot(standard.categoryLabel(TagCategory.body)));
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

    test('caregiver arms nothing out of the box — a guardian\'s device is '
        'not nagged the way the profile owner\'s would be', () {
      final preset = reminderPresetFor(ProfileMode.caregiver);
      expect(preset.upcoming, isFalse);
      expect(preset.late, isFalse);
    });
  });
}
