/// Acceptance test for the rendered PDF clinician summary (Issue #154):
/// build a document for a fixture profile/cycle set and assert each required
/// section is present in the bytes.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/export/clinical_pdf.dart';
import 'package:lunarlog/domain/export/clinical_pdf_summary.dart';
import 'package:lunarlog/domain/export/fhir_export_range.dart';
import 'package:lunarlog/domain/logging/custom_tag_registry.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/ui/overview/estimate_copy.dart' show kEstimateDisclaimer;

Profile _profile() => Profile(
  id: 'p1',
  displayName: 'Riley',
  isMinor: false,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

List<LocalDate> _starts(int count) => [
  for (var i = 0; i < count; i++) LocalDate(2025, 1, 1).addDays(i * 28),
];

List<DayEntry> _entries(List<LocalDate> starts) => [
  for (var i = 0; i < starts.length; i++) ...[
    DayEntry(
      id: 'e$i-a',
      profileId: 'p1',
      localDate: starts[i],
      tz: 'UTC',
      flow: FlowLevel.medium,
      tags: const ['cramps'],
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
    DayEntry(
      id: 'e$i-b',
      profileId: 'p1',
      localDate: starts[i].addDays(1),
      tz: 'UTC',
      flow: FlowLevel.medium,
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
  ],
];

ClinicalPdfSummary _fixtureSummary() {
  final starts = _starts(8);
  return buildClinicalPdfSummary(
    profile: _profile(),
    dayEntries: _entries(starts),
    observations: [
      Observation(
        id: 'o1',
        dayEntryId: 'e1-a',
        profileId: 'p1',
        localDate: starts[1],
        tz: 'UTC',
        category: ObservationCategory.pain,
        code: 'migraine',
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    ],
    range: FhirExportRange(
      preset: FhirExportRangePreset.last6Cycles,
      start: starts[1],
    ),
    rangeLabel: 'Last 6 cycles',
    generatedAt: DateTime.utc(2026, 6, 1, 12),
    birthControlMethod: 'Combined pill',
    medications: const ['Ibuprofen'],
    conditions: const ['Migraine'],
    derivedValueDisclaimers: const [kEstimateDisclaimer],
  );
}

void main() {
  test('produces a structurally valid, uncompressed PDF', () {
    final bytes = buildClinicalPdfDocument(_fixtureSummary());
    final text = latin1.decode(bytes);
    expect(text.startsWith('%PDF-1.4'), isTrue);
    expect(text.endsWith('%%EOF\n'), isTrue);
    // Uncompressed: the content stream holds literal, searchable text.
    expect(text, contains('BT /F1'));
  });

  test('carries the profile display name and the selected range', () {
    final text = latin1.decode(buildClinicalPdfDocument(_fixtureSummary()));
    expect(text, contains('Riley'));
    expect(text, contains('Last 6 cycles'));
  });

  test('contains every required section', () {
    final text = latin1.decode(buildClinicalPdfDocument(_fixtureSummary()));
    expect(text, contains('Cycle statistics'));
    expect(text, contains('Completed cycles'));
    expect(text, contains('Symptom frequency by cycle day'));
    expect(text, contains('Medications and birth control'));
    expect(text, contains('Conditions'));
  });

  test('contains the not-a-diagnosis line and the injected estimate '
      'disclaimer', () {
    final text = latin1.decode(buildClinicalPdfDocument(_fixtureSummary()));
    expect(text, contains('This summary is not a diagnosis'));
    // The em dash is encoded as the WinAnsi byte, so assert both halves.
    expect(text, contains('Estimates only'));
    expect(text, contains('not medical advice'));
  });

  test('states the graded 1-5 intensity scale (issue #1114)', () {
    expect(
      kClinicalSummaryPainScaleNote,
      'Pain intensity is self-rated in lunarlog from 1 (least intense) to 5 '
      '(most intense); individual ratings are not shown in this summary.',
    );
    final text = latin1.decode(buildClinicalPdfDocument(_fixtureSummary()));
    // The method note wraps at the printable width, so assert a word that
    // cannot break across a line rather than the whole sentence.
    expect(text, contains('self-rated'));
  });

  test('lists the per-cycle dates and lengths with irregular and omitted columns', () {
    final starts = _starts(8);
    final text = latin1.decode(buildClinicalPdfDocument(_fixtureSummary()));
    expect(text, contains(starts[1].iso));
    expect(text, contains(starts[6].iso));
    expect(text, contains('28')); // cycle length
    expect(text, contains('period'));
    expect(text, contains('irregular'));
    expect(text, contains('omitted'));
  });

  test('flags irregular short cycle in rendered PDF cycle table and method note', () {
    final shortStarts = [
      LocalDate(2026, 6, 1),
      LocalDate(2026, 6, 8),  // 7-day cycle -> irregular
      LocalDate(2026, 7, 6),  // 28-day cycle
      LocalDate(2026, 8, 3),  // open cycle
    ];
    final summary = buildClinicalPdfSummary(
      profile: _profile(),
      dayEntries: _entries(shortStarts),
      range: FhirExportRange.everything,
      rangeLabel: 'Everything',
      generatedAt: DateTime.utc(2026, 8, 3),
    );
    final text = latin1.decode(buildClinicalPdfDocument(summary));
    expect(text, contains('Cycles shorter than 15 days are omitted'));
    expect(text, contains('irregular'));
    // The 7-day cycle row has 'yes' under irregular.
    expect(text, contains('yes'));
  });

  test('paginates when the symptom grid overflows a page', () {
    final starts = _starts(8);
    final observations = [
      for (var tag = 0; tag < 200; tag++)
        Observation(
          id: 'o$tag',
          dayEntryId: 'd',
          profileId: 'p1',
          localDate: starts[(tag % 6) + 1].addDays(tag % 28),
          tz: 'UTC',
          category: ObservationCategory.pain,
          code: 'symptom_$tag',
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
    ];
    final summary = buildClinicalPdfSummary(
      profile: _profile(),
      dayEntries: _entries(starts),
      observations: observations,
      range: FhirExportRange(
        preset: FhirExportRangePreset.last6Cycles,
        start: starts[1],
      ),
      rangeLabel: 'Last 6 cycles',
      generatedAt: DateTime.utc(2026, 6, 1),
    );
    final text = latin1.decode(buildClinicalPdfDocument(summary));
    expect(RegExp(r'/Type /Page ').allMatches(text).length, greaterThan(1));
  });

  test('renders an empty summary without throwing', () {
    final summary = buildClinicalPdfSummary(
      profile: _profile(),
      dayEntries: const [],
      range: FhirExportRange.everything,
      rangeLabel: 'Everything',
      generatedAt: DateTime.utc(2026, 6, 1),
    );
    final text = latin1.decode(buildClinicalPdfDocument(summary));
    expect(text, contains('No completed cycles in the selected range.'));
    expect(text, contains('No symptoms were logged in the cycles shown'));
  });

  test('renders custom tags and spotting in PDF bytes, wellness codes '
      'excluded (#834, #794, #1144)', () {
    final starts = _starts(8);
    final entries = [
      for (final start in starts)
        DayEntry(
          id: 'e-${start.iso}',
          profileId: 'p1',
          localDate: start,
          tz: 'UTC',
          flow: FlowLevel.medium,
          tags: start == starts[1]
              ? const ['great_digestion', 'great_stool', 'acupuncture']
              : const [],
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
    ];
    final observations = [
      Observation(
        id: 'o-spotting',
        dayEntryId: 'd-spotting',
        profileId: 'p1',
        localDate: starts[1],
        tz: 'UTC',
        category: ObservationCategory.spotting,
        code: 'light',
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    ];
    final customTags = [
      CustomTag(
        id: 'ct-1',
        profileId: 'p1',
        code: 'acupuncture',
        displayName: 'Acupuncture',
        category: 'custom',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    ];
    final summary = buildClinicalPdfSummary(
      profile: _profile(),
      dayEntries: entries,
      observations: observations,
      customTags: customTags,
      range: FhirExportRange(
        preset: FhirExportRangePreset.last6Cycles,
        start: starts[1],
      ),
      rangeLabel: 'Last 6 cycles',
      generatedAt: DateTime.utc(2026, 6, 1),
    );
    final text = latin1.decode(buildClinicalPdfDocument(summary));
    expect(text, contains('Acupuncture'));
    expect(text, contains('Spotting'));
    // Issue #1144: wellness codes are not symptoms — the former
    // "Great (digestion)"/"Great (stool)" grid rows are gone. The colliding
    // display disambiguation those rows exercised stays pinned in
    // test/domain/tags_test.dart (`flatDisplayForTag`).
    expect(text, isNot(contains('Great (')));
  });

  test('Issue #1144: the symptom grid holds only cramps for a day also '
      'logged with wellness, medication and home-test tags', () {
    final starts = _starts(8);
    final entries = [
      for (final start in starts)
        DayEntry(
          id: 'e-${start.iso}',
          profileId: 'p1',
          localDate: start,
          tz: 'UTC',
          flow: FlowLevel.medium,
          tags: start == starts[1]
              ? const [
                  'great_digestion',
                  'antibiotic',
                  'pregnancy_positive',
                  'cramps',
                ]
              : const [],
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
    ];
    final summary = buildClinicalPdfSummary(
      profile: _profile(),
      dayEntries: entries,
      range: FhirExportRange(
        preset: FhirExportRangePreset.last6Cycles,
        start: starts[1],
      ),
      rangeLabel: 'Last 6 cycles',
      generatedAt: DateTime.utc(2026, 6, 1),
    );
    expect(summary.symptomGrid.map((row) => row.label), ['Cramps']);
    final text = latin1.decode(buildClinicalPdfDocument(summary));
    expect(text, contains('Cramps'));
    expect(text, isNot(contains('Antibiotic')));
    expect(text, isNot(contains('Pregnancy')));
    expect(text, isNot(contains('Great (')));
  });

  test('Issue #1204: a 40-character custom tag is truncated in the grid '
      'with a marker and listed in full below it', () {
    const longLabel = 'Headache behind left eye during exercise';
    expect(longLabel.length, kMaxCustomTagLabelLength);
    final starts = _starts(8);
    final entries = [
      for (final start in starts)
        DayEntry(
          id: 'e-${start.iso}',
          profileId: 'p1',
          localDate: start,
          tz: 'UTC',
          flow: FlowLevel.medium,
          tags: start == starts[1] ? const ['long-headache'] : const [],
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
    ];
    final customTags = [
      CustomTag(
        id: 'ct-long-headache',
        profileId: 'p1',
        code: 'long-headache',
        displayName: longLabel,
        category: 'custom',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    ];
    final summary = buildClinicalPdfSummary(
      profile: _profile(),
      dayEntries: entries,
      customTags: customTags,
      range: FhirExportRange(
        preset: FhirExportRangePreset.last6Cycles,
        start: starts[1],
      ),
      rangeLabel: 'Last 6 cycles',
      generatedAt: DateTime.utc(2026, 6, 1),
    );
    final text = latin1.decode(buildClinicalPdfDocument(summary));
    // The full label survives the document, in the footer that maps every
    // shortened grid label back to its full text.
    expect(text, contains('Labels shortened in the grid:'));
    expect(text, contains('= $longLabel'));
    // The grid row itself is the first 21 characters plus the ellipsis, so
    // the cut is visible. U+2026 travels as the WinAnsi byte 0x85
    // (minimal_pdf.dart's _winAnsiPunctuation), which latin1 decoding
    // surfaces as U+0085.
    expect(text, contains('Headache behind left \u0085'));
  });

  test('Issue #1204: a label that fits the 22-character column prints '
      'without a shortened-labels footer', () {
    const fittingLabel = 'Lower back pain today!';
    expect(fittingLabel.length, 22);
    final starts = _starts(8);
    final entries = [
      for (final start in starts)
        DayEntry(
          id: 'e-${start.iso}',
          profileId: 'p1',
          localDate: start,
          tz: 'UTC',
          flow: FlowLevel.medium,
          tags: start == starts[1] ? const ['lower-back'] : const [],
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
    ];
    final customTags = [
      CustomTag(
        id: 'ct-lower-back',
        profileId: 'p1',
        code: 'lower-back',
        displayName: fittingLabel,
        category: 'custom',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    ];
    final summary = buildClinicalPdfSummary(
      profile: _profile(),
      dayEntries: entries,
      customTags: customTags,
      range: FhirExportRange(
        preset: FhirExportRangePreset.last6Cycles,
        start: starts[1],
      ),
      rangeLabel: 'Last 6 cycles',
      generatedAt: DateTime.utc(2026, 6, 1),
    );
    final text = latin1.decode(buildClinicalPdfDocument(summary));
    expect(text, contains(fittingLabel));
    expect(text, isNot(contains('Labels shortened in the grid')));
  });

  test('Issue #1204: two labels sharing their first 22 characters are both '
      'mapped to their full text under the grid', () {
    const eyeLabel = 'Pressure behind left eye';
    const earLabel = 'Pressure behind left ear';
    final starts = _starts(8);
    final entries = [
      for (final start in starts)
        DayEntry(
          id: 'e-${start.iso}',
          profileId: 'p1',
          localDate: start,
          tz: 'UTC',
          flow: FlowLevel.medium,
          tags:
              start == starts[1] ? const ['pressure-eye', 'pressure-ear'] : const [],
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
    ];
    CustomTag pressureTag(String id, String code, String displayName) =>
        CustomTag(
          id: id,
          profileId: 'p1',
          code: code,
          displayName: displayName,
          category: 'custom',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        );
    final summary = buildClinicalPdfSummary(
      profile: _profile(),
      dayEntries: entries,
      customTags: [
        pressureTag('ct-eye', 'pressure-eye', eyeLabel),
        pressureTag('ct-ear', 'pressure-ear', earLabel),
      ],
      range: FhirExportRange(
        preset: FhirExportRangePreset.last6Cycles,
        start: starts[1],
      ),
      rangeLabel: 'Last 6 cycles',
      generatedAt: DateTime.utc(2026, 6, 1),
    );
    expect(summary.symptomGrid.map((row) => row.label), [
      // Frequency ties break alphabetically.
      earLabel,
      eyeLabel,
    ]);
    final text = latin1.decode(buildClinicalPdfDocument(summary));
    // The grid rows look identical (both cut at the same 21 characters +
    // ellipsis); the footer is what keeps them distinguishable. Each full
    // label gets its own footer line, so it appears contiguously.
    expect(text, contains('= $earLabel'));
    expect(text, contains('= $eyeLabel'));
  });
}
