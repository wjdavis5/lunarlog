/// Pins the phrase `groupedChipSemantics` announces (issue #1426), for both
/// copies of the wrapper: the shared one the pickers use
/// (`lib/ui/components/chip_semantics.dart`) and the day sheet's own
/// (`lib/ui/logging/day_sheet.dart`). They are kept as two copies on
/// purpose, so nothing but a test holds them to the same phrase.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/ui/components/chip_semantics.dart' as components;
import 'package:lunarlog/ui/logging/day_sheet.dart' as day_sheet;

typedef _Wrapper = Widget Function({
  required String group,
  required String label,
  required bool selected,
  required Widget child,
  VoidCallback? onTap,
  bool? enabled,
});

void main() {
  const wrappers = <String, _Wrapper>{
    'components': components.groupedChipSemantics,
    'day sheet': day_sheet.groupedChipSemantics,
  };

  String labelOf(_Wrapper wrap, {required String group, required String label}) {
    final widget = wrap(
      group: group,
      label: label,
      selected: false,
      child: const SizedBox.shrink(),
    );
    return (widget as Semantics).properties.label!;
  }

  for (final MapEntry(key: name, value: wrap) in wrappers.entries) {
    group('groupedChipSemantics ($name copy)', () {
      test('joins a group and a label that differ', () {
        expect(labelOf(wrap, group: 'Flow', label: 'Medium'), 'Flow, Medium');
        expect(labelOf(wrap, group: 'Pain', label: 'Cramps'), 'Pain, Cramps');
      });

      test('says a word shared by the group and its only chip once', () {
        expect(
          labelOf(wrap, group: 'PMS', label: 'PMS'),
          'PMS',
          reason: 'the PMS toggle used to be announced as "PMS, PMS"',
        );
      });

      SemanticsProperties propertiesOf({
        required bool selected,
        VoidCallback? onTap,
        bool? enabled,
      }) =>
          (wrap(
            group: 'Flow',
            label: 'Medium',
            selected: selected,
            onTap: onTap,
            enabled: enabled,
            child: const SizedBox.shrink(),
          ) as Semantics)
              .properties;

      test('a chip with an action is a usable button', () {
        final properties = propertiesOf(selected: false, onTap: () {});
        expect(properties.enabled, isTrue);
        expect(properties.button, isTrue);
        expect(properties.onTap, isNotNull);
      });

      test('a chip with no action, and nothing said otherwise, is disabled',
          () {
        final properties = propertiesOf(selected: false);
        expect(properties.enabled, isFalse);
        expect(properties.button, isFalse);
        expect(properties.onTap, isNull);
      });

      test('the chosen chip of a single-choice row has no action and is not '
          'disabled', () {
        // A screen reader announced the value the person had picked as
        // "disabled" (TalkBack) or "dimmed" (VoiceOver), because choosing
        // it again does nothing and "no action" was read as "disabled".
        final properties = propertiesOf(selected: true, enabled: true);
        expect(properties.selected, isTrue);
        expect(properties.enabled, isTrue);
        expect(properties.button, isTrue);
        expect(properties.onTap, isNull);
      });

      test('a caller can still say a chip is disabled', () {
        final properties = propertiesOf(selected: true, enabled: false);
        expect(properties.enabled, isFalse);
        expect(properties.button, isFalse);
      });
    });
  }
}
