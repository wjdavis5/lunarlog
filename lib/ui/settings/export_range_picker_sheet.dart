/// Date-range picker for the clinical (FHIR) export flow (Issue #459) — a
/// modal sheet offering the presets [FhirExportRangePreset] enumerates,
/// plus a custom start/end step. Pops with the resolved [FhirExportRange],
/// or `null` if dismissed without choosing. All preset resolution lives in
/// `lib/domain/export/fhir_export_range.dart` (pure Dart, its own tests);
/// this file is presentation only.
library;

import 'package:flutter/material.dart';

import '../../domain/export/fhir_export_range.dart';
import '../../domain/models/day_entry.dart';
import '../../domain/models/local_date.dart';
import '../../observability/route_names.dart';

/// Human label for [preset], shared between the picker's own radio list and
/// any caller that wants matching copy (e.g. a post-export confirmation).
String fhirExportRangePresetLabel(FhirExportRangePreset preset) {
  switch (preset) {
    case FhirExportRangePreset.last3Cycles:
      return 'Last 3 cycles';
    case FhirExportRangePreset.last6Cycles:
      return 'Last 6 cycles';
    case FhirExportRangePreset.last12Cycles:
      return 'Last 12 cycles';
    case FhirExportRangePreset.last12Months:
      return 'Last 12 months';
    case FhirExportRangePreset.everything:
      return 'Everything';
    case FhirExportRangePreset.custom:
      return 'Custom range…';
  }
}

/// The presets offered, in display order — [FhirExportRangePreset.last6Cycles]
/// is both first selected here and the picker's opening default, matching
/// [defaultFhirExportRange].
const List<FhirExportRangePreset> kFhirExportRangePresetOrder = [
  FhirExportRangePreset.last3Cycles,
  FhirExportRangePreset.last6Cycles,
  FhirExportRangePreset.last12Cycles,
  FhirExportRangePreset.last12Months,
  FhirExportRangePreset.everything,
  FhirExportRangePreset.custom,
];

/// Opens the picker as a modal bottom sheet; resolves to the chosen
/// [FhirExportRange], or `null` if dismissed without choosing. [entries]
/// backs the cycle-count presets (via [fhirExportRangeForCycleCount]);
/// [today] is the civil date "now" resolves to for every relative preset
/// and bounds the custom date pickers.
Future<FhirExportRange?> showExportRangePickerSheet(
  BuildContext context, {
  required List<DayEntry> entries,
  required LocalDate today,
}) => showModalBottomSheet<FhirExportRange>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  routeSettings: const RouteSettings(name: kRouteExportRangePickerSheet),
  builder: (context) => ExportRangePickerSheet(entries: entries, today: today),
);

/// The sheet body. A [StatefulWidget] so the custom-range step can hold its
/// own in-progress start/end before the operator confirms — issue #642,
/// LLA-012: bounded via [Flexible]/[SingleChildScrollView] rather than a
/// fixed [Column], and the confirm/cancel row stays outside the scrolling
/// region so it is always reachable even with a keyboard inset or large
/// text scaling.
class ExportRangePickerSheet extends StatefulWidget {
  const ExportRangePickerSheet({
    super.key,
    required this.entries,
    required this.today,
  });

  final List<DayEntry> entries;
  final LocalDate today;

  @override
  State<ExportRangePickerSheet> createState() => _ExportRangePickerSheetState();
}

class _ExportRangePickerSheetState extends State<ExportRangePickerSheet> {
  FhirExportRangePreset _selected = FhirExportRangePreset.last6Cycles;
  LocalDate? _customStart;
  LocalDate? _customEnd;

  bool get _isCustomComplete =>
      _customStart != null &&
      _customEnd != null &&
      !_customStart!.isAfter(_customEnd!);

  bool get _canConfirm =>
      _selected != FhirExportRangePreset.custom || _isCustomComplete;

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                'Export range',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: RadioGroup<FhirExportRangePreset>(
                  groupValue: _selected,
                  onChanged: (value) =>
                      setState(() => _selected = value ?? _selected),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final preset in kFhirExportRangePresetOrder)
                        _presetTile(preset),
                      if (_selected == FhirExportRangePreset.custom)
                        _customRangeRow(context),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const ValueKey('export-range-cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('export-range-confirm'),
                    onPressed: _canConfirm ? _confirm : null,
                    child: const Text('Export'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// No `groupValue`/`onChanged` here (the pre-`RadioGroup` API, deprecated
  /// since Flutter 3.32) — this tile reads/writes through the ancestor
  /// [RadioGroup] wrapping the whole preset list above instead.
  Widget _presetTile(FhirExportRangePreset preset) =>
      RadioListTile<FhirExportRangePreset>(
        key: ValueKey('export-range-preset-${preset.name}'),
        title: Text(fhirExportRangePresetLabel(preset)),
        value: preset,
      );

  Widget _customRangeRow(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton(
            key: const ValueKey('export-range-custom-start'),
            onPressed: () => _pickCustomDate(context, isStart: true),
            child: Text(_customStart?.iso ?? 'Start date'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            key: const ValueKey('export-range-custom-end'),
            onPressed: () => _pickCustomDate(context, isStart: false),
            child: Text(_customEnd?.iso ?? 'End date'),
          ),
        ),
      ],
    ),
  );

  Future<void> _pickCustomDate(
    BuildContext context, {
    required bool isStart,
  }) async {
    final today = widget.today.toDateTime();
    final currentPick = isStart ? _customStart : _customEnd;
    final initial = currentPick?.toDateTime() ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    final date = LocalDate.fromDateTime(picked);
    setState(() {
      if (isStart) {
        _customStart = date;
      } else {
        _customEnd = date;
      }
    });
  }

  void _confirm() {
    final range = resolveFhirExportRangePreset(
      preset: _selected,
      entries: widget.entries,
      today: widget.today,
      customStart: _customStart,
      customEnd: _customEnd,
    );
    Navigator.of(context).pop(range);
  }
}
