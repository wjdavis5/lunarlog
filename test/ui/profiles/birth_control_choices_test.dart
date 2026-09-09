/// Direct unit tests for the birth-control selector helpers (Issue
/// #216): label round-tripping through the stored free-text value, and
/// the degrade-to-not-answered reverse mapping for values this build
/// never writes (#260 will own the real vocabulary).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';
import 'package:lunarlog/ui/profiles/birth_control_choices.dart';

void main() {
  final l10n = AppLocalizationsEn();

  test('every choice has a distinct non-empty label', () {
    final labels = birthControlChoiceLabels(l10n);
    expect(labels.keys, containsAll(BirthControlChoice.values));
    final values = labels.values.toSet();
    expect(values.length, BirthControlChoice.values.length,
        reason: 'no two options may share a label');
    for (final label in values) {
      expect(label, isNotEmpty);
    }
  });

  test('stored value round-trips every answered choice; notAnswered '
      'stores null', () {
    for (final choice in BirthControlChoice.values) {
      final stored = birthControlStoredValue(choice, l10n);
      if (choice == BirthControlChoice.notAnswered) {
        expect(stored, isNull);
        expect(birthControlChoiceForStored(stored, l10n), choice);
      } else {
        expect(stored, isNotNull);
        expect(birthControlChoiceForStored(stored, l10n), choice,
            reason: 'a stored label resolves back to its choice');
      }
    }
  });

  test('an unknown stored value (a future #260 vocabulary) degrades to '
      'notAnswered instead of throwing', () {
    expect(birthControlChoiceForStored('Diaphragm', l10n),
        BirthControlChoice.notAnswered);
  });
}
