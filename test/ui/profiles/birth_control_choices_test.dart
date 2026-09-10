/// Direct unit tests for the birth-control selector helpers (Issue
/// #216, canonicalized by Issue #260): label uniqueness, round-tripping
/// through the stored canonical id, the pre-#260 legacy stored values
/// (localized labels) still loading, and the degrade-to-not-answered
/// reverse mapping for values this build never writes.
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
      final stored = birthControlStoredValue(choice);
      if (choice == BirthControlChoice.notAnswered) {
        expect(stored, isNull);
        expect(birthControlChoiceForStored(stored), choice);
      } else {
        expect(stored, isNotNull);
        expect(birthControlChoiceForStored(stored), choice,
            reason: 'a stored id resolves back to its choice');
      }
    }
  });

  test('stored values are the canonical Issue #260 ids, never localized '
      'labels', () {
    expect(birthControlStoredValue(BirthControlChoice.pill), 'pill');
    expect(birthControlStoredValue(BirthControlChoice.injection), 'shot',
        reason: 'the selector\'s Injection choice stores the issue\'s '
            'canonical shot id');
    expect(birthControlStoredValue(BirthControlChoice.hormonalIud),
        'hormonal_iud');
    expect(birthControlStoredValue(BirthControlChoice.copperIud),
        'copper_iud');
  });

  test('pre-#260 stored labels still load (legacy read-only mapping)', () {
    expect(birthControlChoiceForStored('Pill'), BirthControlChoice.pill);
    expect(birthControlChoiceForStored('Injection'),
        BirthControlChoice.injection);
    expect(birthControlChoiceForStored('Hormonal IUD'),
        BirthControlChoice.hormonalIud);
    expect(birthControlChoiceForStored('Copper IUD'),
        BirthControlChoice.copperIud);
    expect(birthControlChoiceForStored('Vaginal ring'),
        BirthControlChoice.ring);
    expect(birthControlChoiceForStored('None'), BirthControlChoice.none);
  });

  test('an unknown stored value degrades to notAnswered instead of '
      'throwing', () {
    expect(birthControlChoiceForStored('Diaphragm'),
        BirthControlChoice.notAnswered);
  });
}
