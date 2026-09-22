/// Widget tests for the clinical-export date-range picker (Issue #459).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/export/fhir_export_range.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';
import 'package:lunarlog/ui/settings/export_range_picker_sheet.dart';

Finder key(String value) => find.byKey(ValueKey(value));

DayEntry _entry(String id, LocalDate date) => DayEntry(
  id: id,
  profileId: 'p1',
  localDate: date,
  tz: 'UTC',
  flow: FlowLevel.medium,
  updatedAt: DateTime.utc(2026, 1, 1),
);

/// Opens the picker inside a minimal `MaterialApp`/`Scaffold` and leaves it
/// open — for tests that only inspect the sheet's own contents, never
/// confirm or cancel it (those build their own tree so they can capture
/// the resolved [FhirExportRange]).
Future<void> _open(
  WidgetTester tester, {
  List<DayEntry> entries = const [],
  LocalDate? today,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            key: const ValueKey('open'),
            onPressed: () => showExportRangePickerSheet(
              context,
              entries: entries,
              today: today ?? LocalDate(2026, 6, 1),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(key('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('opening state', () {
    testWidgets('every preset is listed, "last 6 cycles" pre-selected', (
      tester,
    ) async {
      await _open(tester);

      for (final preset in kFhirExportRangePresetOrder) {
        expect(key('export-range-preset-${preset.name}'), findsOneWidget);
        expect(find.text(fhirExportRangePresetLabel(AppLocalizationsEn(), preset)),
              findsOneWidget);
      }
      // The presets read/write through the ancestor `RadioGroup`, not their
      // own `groupValue` (removed with the pre-3.32 `RadioListTile` API).
      final group = tester.widget<RadioGroup<FhirExportRangePreset>>(
        find.byType(RadioGroup<FhirExportRangePreset>),
      );
      expect(group.groupValue, FhirExportRangePreset.last6Cycles);
    });

    testWidgets('the custom date fields are hidden until "Custom range" is '
        'chosen', (tester) async {
      await _open(tester);
      expect(key('export-range-custom-start'), findsNothing);
      expect(key('export-range-custom-end'), findsNothing);

      await tester.tap(key('export-range-preset-custom'));
      await tester.pumpAndSettle();

      expect(key('export-range-custom-start'), findsOneWidget);
      expect(key('export-range-custom-end'), findsOneWidget);
    });
  });

  group('confirm / cancel', () {
    testWidgets('cancel pops with null', (tester) async {
      FhirExportRange? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                key: const ValueKey('open'),
                onPressed: () async {
                  result = await showExportRangePickerSheet(
                    context,
                    entries: const [],
                    today: LocalDate(2026, 6, 1),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(key('open'));
      await tester.pumpAndSettle();

      await tester.tap(key('export-range-cancel'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('confirm with the default preset resolves the last-6-cycles '
        'range', (tester) async {
      FhirExportRange? result;
      final starts = [
        for (var i = 0; i < 5; i++) LocalDate(2025, 1, 1).addDays(i * 40),
      ];
      final entries = [for (final s in starts) _entry('e-${s.iso}', s)];

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                key: const ValueKey('open'),
                onPressed: () async {
                  result = await showExportRangePickerSheet(
                    context,
                    entries: entries,
                    today: LocalDate(2026, 6, 1),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(key('open'));
      await tester.pumpAndSettle();

      await tester.tap(key('export-range-confirm'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.preset, FhirExportRangePreset.last6Cycles);
    });

    testWidgets('confirm is disabled for "Custom range" until both dates '
        'are chosen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                key: const ValueKey('open'),
                onPressed: () => showExportRangePickerSheet(
                  context,
                  entries: const [],
                  today: LocalDate(2026, 6, 1),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(key('open'));
      await tester.pumpAndSettle();

      await tester.tap(key('export-range-preset-custom'));
      await tester.pumpAndSettle();

      final confirmDisabled = tester.widget<FilledButton>(
        key('export-range-confirm'),
      );
      expect(confirmDisabled.onPressed, isNull);
    });

    testWidgets('choosing a start and end date via the date pickers enables '
        'confirm and resolves a custom range', (tester) async {
      FhirExportRange? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                key: const ValueKey('open'),
                onPressed: () async {
                  result = await showExportRangePickerSheet(
                    context,
                    entries: const [],
                    today: LocalDate(2026, 6, 1),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(key('open'));
      await tester.pumpAndSettle();
      await tester.tap(key('export-range-preset-custom'));
      await tester.pumpAndSettle();

      await tester.tap(key('export-range-custom-start'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(key('export-range-custom-end'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final confirmEnabled = tester.widget<FilledButton>(
        key('export-range-confirm'),
      );
      expect(confirmEnabled.onPressed, isNotNull);

      await tester.tap(key('export-range-confirm'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.preset, FhirExportRangePreset.custom);
      expect(result!.start, isNotNull);
      expect(result!.end, isNotNull);
    });
  });
}
