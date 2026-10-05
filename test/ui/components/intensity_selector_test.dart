/// Widget tests for the reusable graded-intensity control (Issue #234).
library;

import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
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

  testWidgets('the chosen level is selected, not disabled; Clear is '
      'disabled only when there is nothing to clear', (tester) async {
    final handle = tester.ensureSemantics();
    SemanticsNode node(String label) =>
        tester.getSemantics(find.bySemanticsLabel(label));

    await tester.pumpWidget(_harness(value: 3, onChanged: (_) {}));
    final chosen = node('Intensity, 3');
    expect(chosen.flagsCollection.isSelected, Tristate.isTrue);
    expect(
      chosen.flagsCollection.isEnabled,
      Tristate.isTrue,
      reason: 'the grade a person picked was announced as "disabled"',
    );
    expect(chosen.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    final other = node('Intensity, 4');
    expect(other.flagsCollection.isEnabled, Tristate.isTrue);
    expect(other.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(node('Intensity, Clear').flagsCollection.isEnabled, Tristate.isTrue);

    // Nothing chosen: there is nothing to clear, so Clear really is disabled.
    await tester.pumpWidget(_harness(value: null, onChanged: (_) {}));
    expect(
      node('Intensity, Clear').flagsCollection.isEnabled,
      Tristate.isFalse,
    );

    // The whole control turned off: every chip is disabled, the chosen one
    // included.
    await tester.pumpWidget(
      _harness(value: 3, onChanged: (_) {}, enabled: false),
    );
    expect(node('Intensity, 3').flagsCollection.isEnabled, Tristate.isFalse);
    expect(node('Intensity, 4').flagsCollection.isEnabled, Tristate.isFalse);
    handle.dispose();
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
