// Issue #1526: the iPhone Health sync screen must name everything lunarlog
// writes to Apple Health.
//
// It did not. The screen never mentioned cervical mucus, ovulation tests or
// basal body temperature, and its symptoms sentence named four of the twelve
// symptom types as if they were the list. The Android screen had the full
// sentence all along.
//
// These tests tie the screen's wording to the lists the write path is built
// from, so a type or a tag cannot be added to what is written without the
// screen saying so:
//
//  * `kHealthKitWrittenTypeCaseNames` (lib/data/health/health_written_types
//    .dart), which `test/release/health_deletion_types_test.dart` holds
//    equal to the Swift lists the authorization sheet is built from;
//  * `kSymptomHealthKitTypeIdentifiers`, the tag-to-symptom table;
//  * the cervical mucus and ovulation test tables.
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_fertility_mapping.dart';
import 'package:lunarlog/data/health/health_symptom_mapping.dart';
import 'package:lunarlog/data/health/health_written_types.dart';
import 'package:lunarlog/domain/care_modes.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/tags.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';

void main() {
  final l10n = AppLocalizationsEn();

  /// Everything the iPhone screen says about what is written, as one text.
  final iphoneWriting = [
    l10n.healthSyncWrittenTypes,
    l10n.healthSyncFlowCollapseNote,
    l10n.healthSyncWriteSymptoms,
  ].join('\n');

  /// How the iPhone screen names each HealthKit type the app writes. A type
  /// with no entry here fails the first test below.
  const namedAs = <String, String>{
    'menstrualFlow': 'flow',
    'intermenstrualBleeding': 'spotting between periods',
    'cervicalMucusQuality': 'cervical mucus',
    'ovulationTestResult': 'ovulation test results',
    'basalBodyTemperature': 'basal body temperature',
    'abdominalCramps': 'Cramps',
    'headache': 'Headache',
    'lowerBackPain': 'Back pain',
    'breastPain': 'Breast tenderness',
    'bloating': 'Bloating',
    'acne': 'Acne',
    'nausea': 'Nausea',
    'fatigue': 'Fatigue',
    'dizziness': 'Dizziness',
    'moodChanges': "'Mood Changes'",
    'sleepChanges': 'Sleep trouble',
    'appetiteChanges': 'Other craving',
  };

  final tagByCode = {for (final tag in kTagTaxonomy) tag.code: tag};

  test('every HealthKit type the app writes is named on the iPhone screen',
      () {
    expect(
      namedAs.keys.toSet(),
      kHealthKitWrittenTypeCaseNames,
      reason: 'the set of HealthKit types the app writes changed: name the '
          'new type on the iPhone screen (healthSyncWrittenTypes or '
          'healthSyncWriteSymptoms in app_en.arb) and in this table',
    );
    for (final entry in namedAs.entries) {
      expect(iphoneWriting, contains(entry.value), reason: entry.key);
    }
  });

  test('every tag written as a symptom is named by the label the app shows '
      'for it', () {
    for (final entry in kSymptomHealthKitTypeIdentifiers.entries) {
      final tag = tagByCode[entry.key];
      expect(tag, isNotNull, reason: entry.key);
      if (entry.value == 'moodChanges') continue; // the Feelings sentence
      expect(
        l10n.healthSyncWriteSymptoms,
        contains(tag!.display),
        reason: '${entry.key} is written as ${entry.value}',
      );
    }
  });

  test('"every tag under Feelings is written as Mood Changes" is true, in '
      'both directions', () {
    final feelings = [
      for (final tag in kTagTaxonomy)
        if (tag.category == TagCategory.feelings) tag.code,
    ];
    expect(feelings, isNotEmpty);
    for (final code in feelings) {
      expect(kSymptomHealthKitTypeIdentifiers[code], 'moodChanges',
          reason: code);
    }
    // And nothing outside Feelings is written as a mood.
    for (final entry in kSymptomHealthKitTypeIdentifiers.entries) {
      if (entry.value != 'moodChanges') continue;
      expect(tagByCode[entry.key]!.category, TagCategory.feelings,
          reason: entry.key);
    }
    // The heading the sentence points at is the one the day sheet shows, in
    // every mode.
    for (final mode in ProfileMode.values) {
      expect(
        careModeCopyFor(mode, irregularFraming: false)
            .categoryLabel(TagCategory.feelings),
        'Feelings',
        reason: mode.name,
      );
    }
    expect(l10n.healthSyncWriteSymptoms, contains('under Feelings'));
  });

  test('the discharge tags the list names are exactly the ones written', () {
    expect(
      kCervicalMucusHealthKitValues.keys.toSet(),
      {'sticky', 'creamy', 'egg_white'},
    );
    for (final code in kCervicalMucusHealthKitValues.keys) {
      expect(
        l10n.healthSyncWrittenTypes,
        contains(tagByCode[code]!.display.toLowerCase()),
        reason: code,
      );
    }
    // Health Connect is written the same three, and its sentence says so.
    expect(
      kCervicalMucusHealthConnectAppearances.keys.toSet(),
      kCervicalMucusHealthKitValues.keys.toSet(),
    );
  });

  test('a peak ovulation test is written the same as a positive one, as the '
      'screen says', () {
    expect(
      kOvulationTestHealthKitResults['ovulation_peak'],
      kOvulationTestHealthKitResults['ovulation_positive'],
    );
    expect(
      kOvulationTestHealthKitResults['ovulation_negative'],
      isNot(kOvulationTestHealthKitResults['ovulation_positive']),
    );
    expect(
      l10n.healthSyncFlowCollapseNote,
      contains('A peak ovulation test is written the same as a positive one.'),
    );
  });

  test('the sentence claims no symptom the app does not write', () {
    // The tags named in the list, by the labels in the sentence.
    final sentence = l10n.healthSyncWriteSymptoms;
    final listed = sentence
        .substring(sentence.indexOf(': ') + 2, sentence.indexOf('. '))
        .replaceAll(' and ', ', ')
        .split(', ')
        .map((label) => label.trim())
        .toSet();
    final written = {
      for (final entry in kSymptomHealthKitTypeIdentifiers.entries)
        if (entry.value != 'moodChanges') tagByCode[entry.key]!.display,
    };
    expect(listed, written);
  });
}
