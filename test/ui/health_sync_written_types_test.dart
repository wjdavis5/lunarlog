// Issue #1526: the iPhone Health sync screen must name everything lunarlog
// writes to Apple Health.
//
// It did not. The screen never mentioned cervical mucus, ovulation tests or
// basal body temperature, and its symptoms sentence named four of the twelve
// symptom types as if they were the list. The Android screen had the full
// sentence all along.
//
// These tests tie the screen's wording to the lists and functions the write
// path is built from, so a type, a tag or a condition cannot change in what
// is written without the screen having to change with it:
//
//  * `kHealthKitWrittenTypeCaseNames` (lib/data/health/health_written_types
//    .dart), which `test/release/health_deletion_types_test.dart` holds
//    equal to the Swift lists the authorization sheet is built from;
//  * `kSymptomHealthKitTypeIdentifiers` and `severityForPainIntensity`, the
//    tag-to-symptom table and the intensity it carries;
//  * the cervical mucus, ovulation test and temperature mappings.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_fertility_mapping.dart';
import 'package:lunarlog/data/health/health_symptom_mapping.dart';
import 'package:lunarlog/data/health/health_written_types.dart';
import 'package:lunarlog/domain/care_modes.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/tags.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';

/// "A, B, C or D".
String _orList(List<String> items) =>
    '${items.sublist(0, items.length - 1).join(', ')} or ${items.last}';

Observation _temperature({bool excluded = false}) => Observation(
      id: 'obs-1',
      dayEntryId: 'entry-1',
      profileId: 'p1',
      localDate: LocalDate(2026, 6, 2),
      tz: 'America/New_York',
      category: ObservationCategory.bbt,
      valueNum: 36.6,
      unit: 'celsius',
      excluded: excluded,
      source: ObservationSource.manual,
      updatedAt: DateTime.utc(2026, 6, 2),
    );

void main() {
  final l10n = AppLocalizationsEn();

  /// The list of what is written (first paragraph under "Writing").
  final list = l10n.healthSyncWrittenTypes;

  /// The symptoms paragraph, which the list points at.
  final symptoms = l10n.healthSyncWriteSymptoms;

  /// The value mappings.
  final mappings = l10n.healthSyncFlowCollapseNote;

  /// The item of the list that names each HealthKit type written, for the
  /// types that are not symptoms. Kept in the order the sentence gives them.
  const listed = <String, String>{
    'menstrualFlow': 'flow, with the first day of each period marked',
    'intermenstrualBleeding': 'spotting between periods',
    'cervicalMucusQuality':
        'discharge you tag as sticky, creamy or egg white (cervical mucus)',
    'ovulationTestResult': 'ovulation test results',
    'basalBodyTemperature':
        'basal body temperature, unless you exclude the reading from charts',
  };

  /// The last item of the list: the symptom types are named one paragraph
  /// down, by tag.
  const pointer = 'and the symptoms and moods listed below';

  final tagByCode = {for (final tag in kTagTaxonomy) tag.code: tag};
  final symptomTypes = kSymptomHealthKitTypeIdentifiers.values.toSet();

  /// The tags the symptoms paragraph lists, by label.
  Set<String> tagsListed() => symptoms
      .substring(symptoms.indexOf(': ') + 2, symptoms.indexOf('. '))
      .replaceAll(' and ', ', ')
      .split(', ')
      .map((label) => label.trim())
      .toSet();

  test('the list names every type written that is not a symptom, item for '
      'item, and nothing else', () {
    expect(
      listed.keys.toSet(),
      kHealthKitWrittenTypeCaseNames.difference(symptomTypes),
      reason: 'the HealthKit types the app writes changed: change the list '
          'on the iPhone screen (healthSyncWrittenTypes in app_en.arb) and '
          'this table together',
    );
    const opening = 'What lunarlog writes to the Health app: ';
    expect(list, startsWith(opening));
    expect(list, endsWith('.'));
    expect(
      list.substring(opening.length, list.length - 1).split('; '),
      [...listed.values, pointer],
    );
  });

  test('every symptom type written is reached through a tag the paragraph '
      'names, and the paragraph names no tag that is not written', () {
    final written = <String>{};
    for (final entry in kSymptomHealthKitTypeIdentifiers.entries) {
      final tag = tagByCode[entry.key];
      expect(tag, isNotNull, reason: entry.key);
      if (entry.value != 'moodChanges') written.add(tag!.display);
    }
    expect(tagsListed(), written);
    // The symptom types are exactly the ones the table can produce, so
    // naming every tag names every type.
    expect(
      symptomTypes,
      kHealthKitWrittenTypeCaseNames.difference(listed.keys.toSet()),
    );
    expect(symptoms, contains("'Mood Changes'"));
    expect(symptoms, endsWith('No other tag is written as a symptom.'));
  });

  test('"every tag under Feelings is written as Mood Changes" is true, in '
      'both directions, and the mood itself is not sent', () {
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
    // "Without saying which mood": any number of moods is one entry of the
    // one type, with no grade.
    final resolved = resolveHealthKitSymptoms(
      tags: feelings,
      gradedPainIntensities: const {},
    );
    expect(resolved, hasLength(1));
    expect(resolved.single.typeIdentifier, 'moodChanges');
    expect(resolved.single.severity, HealthSymptomSeverity.unspecified);
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
    expect(
      symptoms,
      contains("Every tag under Feelings is written as 'Mood Changes' "
          'without saying which mood.'),
    );
  });

  test('an intensity is written with the pain tags the paragraph names, as '
      'mild, moderate or severe', () {
    // Only pain tags carry an intensity; these are the written ones.
    final graded = [
      for (final code in kSymptomHealthKitTypeIdentifiers.keys)
        if (tagByCode[code]!.category == TagCategory.pain)
          tagByCode[code]!.display,
    ];
    expect(graded, isNotEmpty);
    expect(
      symptoms,
      contains('An intensity you give ${_orList(graded)} is written with it, '
          'as mild, moderate or severe.'),
    );
    expect(severityForPainIntensity(1), HealthSymptomSeverity.mild);
    expect(severityForPainIntensity(2), HealthSymptomSeverity.moderate);
    expect(severityForPainIntensity(3), HealthSymptomSeverity.moderate);
    expect(severityForPainIntensity(4), HealthSymptomSeverity.severe);
    expect(severityForPainIntensity(5), HealthSymptomSeverity.severe);
    expect(severityForPainIntensity(null), HealthSymptomSeverity.unspecified);
    // And it does travel with the tag.
    final resolved = resolveHealthKitSymptoms(
      tags: const ['cramps'],
      gradedPainIntensities: const {'cramps': 5},
    );
    expect(resolved.single.severity, HealthSymptomSeverity.severe);
  });

  test('the discharge tags the list names are exactly the ones written', () {
    expect(
      kCervicalMucusHealthKitValues.keys.toSet(),
      {'sticky', 'creamy', 'egg_white'},
    );
    final labels = [
      for (final code in kCervicalMucusHealthKitValues.keys)
        tagByCode[code]!.display.toLowerCase(),
    ];
    expect(
      listed['cervicalMucusQuality'],
      'discharge you tag as ${_orList(labels)} (cervical mucus)',
    );
  });

  test('negative, positive and peak ovulation tests are written, and peak '
      'the same as positive, as the screen says', () {
    final negative = kOvulationTestHealthKitResults['ovulation_negative'];
    final positive = kOvulationTestHealthKitResults['ovulation_positive'];
    final peak = kOvulationTestHealthKitResults['ovulation_peak'];
    expect(negative, isNotNull);
    expect(positive, isNotNull);
    expect(peak, isNotNull);
    expect(peak, positive);
    expect(negative, isNot(positive));
    expect(
      mappings,
      endsWith('A peak ovulation test is written the same as a positive one.'),
    );
  });

  test('a temperature reading excluded from charts is not written, as the '
      'list says, and one that is not excluded is', () {
    expect(resolveBasalBodyTemperature(_temperature()), isNotNull);
    expect(resolveBasalBodyTemperature(_temperature(excluded: true)), isNull);
    // The words are the toggle's own label.
    expect(l10n.daySheetMeasurementExcludeLabel, 'Exclude from charts');
  });

  test('a flow sample carries the first-day-of-period mark the list '
      'mentions', () {
    final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(swift, contains('HKMetadataKeyMenstrualCycleStart: '));
  });
}
