/// Widget tests for the reusable graded-intensity control (Issue #234).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/limits.dart';
import 'package:lunarlog/ui/components/intensity_selector.dart';

Widget _harness({
  required int? value,
  required ValueChanged<int?> onChanged,
  bool enabled = true,
  String? itemLabel,
  String? keyPrefix,
}) {
  return MaterialApp(
    home: Scaffold(
      body: IntensitySelector(
        groupLabel: 'Intensity',
        itemLabel: itemLabel,
        value: value,
        enabled: enabled,
        keyPrefix: keyPrefix,
        onChanged: onChanged,
      ),
    ),
  );
}

void main() {
  testWidgets('renders kIntensitySelectorLevels chips plus one Clear chip',
      (tester) async {
    await tester.pumpWidget(_harness(value: null, onChanged: (_) {}));

    expect(find.byType(ChoiceChip), findsNWidgets(kIntensitySelectorLevels.length));
    expect(find.byType(FilterChip), findsOneWidget);
    for (final level in kIntensitySelectorLevels) {
      expect(find.text('$level'), findsOneWidget);
    }
    expect(find.text('Clear'), findsOneWidget);
  });

  test('kIntensitySelectorLevels matches the 1-5 observation range', () {
    expect(
      kIntensitySelectorLevels,
      [for (var i = kMinObservationIntensity; i <= kMaxObservationIntensity; i++) i],
    );
  });

  testWidgets('tapping a level fires onChanged with that level',
      (tester) async {
    int? changed;
    await tester.pumpWidget(
      _harness(value: null, onChanged: (v) => changed = v),
    );

    await tester.tap(find.text('3'));
    expect(changed, 3);
  });

  testWidgets('the currently-selected level renders selected', (tester) async {
    await tester.pumpWidget(_harness(value: 4, onChanged: (_) {}));
    final chip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('4'), matching: find.byType(ChoiceChip)),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets('tapping Clear fires onChanged(null)', (tester) async {
    int? sentinel = -1;
    await tester.pumpWidget(
      _harness(value: 2, onChanged: (v) => sentinel = v),
    );

    await tester.tap(find.text('Clear'));
    expect(sentinel, isNull);
  });

  testWidgets('disabled: no chip responds to taps', (tester) async {
    var called = false;
    await tester.pumpWidget(
      _harness(value: null, enabled: false, onChanged: (_) => called = true),
    );

    final chip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('1'), matching: find.byType(ChoiceChip)),
    );
    expect(chip.onSelected, isNull);
    final clearChip = tester.widget<FilterChip>(find.byType(FilterChip));
    expect(clearChip.onSelected, isNull);
    expect(called, isFalse);
  });

  testWidgets('keyPrefix produces the pain-intensity-style ValueKeys',
      (tester) async {
    await tester.pumpWidget(
      _harness(value: 3, onChanged: (_) {}, keyPrefix: 'pain-intensity-cramps'),
    );

    expect(find.byKey(const ValueKey('pain-intensity-cramps-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('pain-intensity-cramps-5')), findsOneWidget);
    expect(find.byKey(const ValueKey('pain-intensity-cramps-clear')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pain-intensity-cramps-5')));
    await tester.pump();
  });

  testWidgets('with no keyPrefix, chips carry no explicit key', (tester) async {
    await tester.pumpWidget(_harness(value: null, onChanged: (_) {}));
    expect(find.byKey(const ValueKey('pain-intensity-cramps-1')), findsNothing);
  });

  testWidgets('itemLabel prefixes the per-chip semantics label', (tester) async {
    await tester.pumpWidget(
      _harness(value: null, onChanged: (_) {}, itemLabel: 'Cramps'),
    );
    final semantics = tester.getSemantics(
      find.ancestor(of: find.text('3'), matching: find.bySemanticsLabel('Intensity, Cramps 3')),
    );
    expect(semantics.label, 'Intensity, Cramps 3');
  });
}
