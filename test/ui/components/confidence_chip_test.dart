/// The confidence-tier chip's words have to be readable.
///
/// The chip used to draw its label in the tier colour on a tint of the same
/// colour. The tier colours are badge tones, held to 3:1 against the
/// surface (the minimum for a graphic), and on the tint the label came to
/// about 2.5:1 in both themes: measured on a rendered Today card. Small
/// text needs 4.5:1. These tests hold the label to that on every surface
/// the chip can sit on, for every tier, in both themes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/prediction/prediction.dart'
    show CycleConfidence;
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/confidence_chip.dart';
import 'package:lunarlog/ui/l10n/tiers.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';

import '../../support/wcag_contrast.dart';

final Map<String, ThemeData> _themes = {
  'light': AppTheme.lightTheme,
  'dark': AppTheme.darkTheme,
};

/// Every surface role a card or a page can paint behind the chip.
List<Color> _surfacesOf(ThemeData theme) {
  final scheme = theme.colorScheme;
  return [
    scheme.surface,
    scheme.surfaceContainerLowest,
    scheme.surfaceContainerLow,
    scheme.surfaceContainer,
    scheme.surfaceContainerHigh,
    scheme.surfaceContainerHighest,
  ];
}

/// What is actually behind the label: the tint, over [surface].
Color _fillOver(Color accent, Color surface) => Color.alphaBlend(
      accent.withValues(alpha: kConfidenceChipTintAlpha),
      surface,
    );

Future<void> _pump(
  WidgetTester tester,
  ThemeData theme,
  CycleConfidence tier,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: theme,
      home: Scaffold(
        body: Center(
          child: ConfidenceChip(key: const ValueKey('chip'), tier: tier),
        ),
      ),
    ),
  );
}

void main() {
  for (final entry in _themes.entries) {
    final theme = entry.value;
    group('${entry.key} theme', () {
      for (final tier in CycleConfidence.values) {
        test('${tier.name}: the label clears 4.5:1 on its tint, on every '
            'surface', () {
          final accent = confidenceChipAccent(theme, tier);
          final label = confidenceChipLabelColor(theme);
          for (final surface in _surfacesOf(theme)) {
            final ratio = wcagContrastRatio(label, _fillOver(accent, surface));
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason: '${tier.name} label on $surface is '
                  '${ratio.toStringAsFixed(2)}:1',
            );
          }
        });

        test('${tier.name}: the outline, a graphic, clears 3:1 against the '
            'surface', () {
          final accent = confidenceChipAccent(theme, tier);
          expect(
            wcagContrastRatio(accent, theme.colorScheme.surface),
            greaterThanOrEqualTo(3.0),
          );
        });

        testWidgets('${tier.name}: draws its words in the text colour and '
            'keeps the tier colour for the outline and the tint', (
          tester,
        ) async {
          await _pump(tester, theme, tier);
          final accent = confidenceChipAccent(theme, tier);

          final text = tester.widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('chip')),
              matching: find.byType(Text),
            ),
          );
          expect(text.style?.color, theme.colorScheme.onSurface);
          expect(text.style?.color, isNot(accent));

          final box = tester.widget<Container>(
            find.descendant(
              of: find.byKey(const ValueKey('chip')),
              matching: find.byType(Container),
            ),
          );
          final decoration = box.decoration! as BoxDecoration;
          expect(
            decoration.color,
            accent.withValues(alpha: kConfidenceChipTintAlpha),
          );
          expect((decoration.border! as Border).top.color, accent);
        });
      }
    });
  }

  testWidgets('says the tier in the catalogue\'s words', (tester) async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    for (final tier in CycleConfidence.values) {
      await _pump(tester, AppTheme.lightTheme, tier);
      expect(find.text(tierLabel(l10n, tier)), findsOneWidget);
    }
  });

  testWidgets('a theme without the app\'s colour extension still draws a '
      'chip', (tester) async {
    // A bare ThemeData, as some older test harnesses build: the chip falls
    // back to colour-scheme roles rather than throwing.
    final bare = ThemeData();
    for (final tier in CycleConfidence.values) {
      await _pump(tester, bare, tier);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('chip')), findsOneWidget);
    }
    expect(
      confidenceChipAccent(bare, CycleConfidence.high),
      bare.colorScheme.primary,
    );
    expect(
      confidenceChipAccent(bare, CycleConfidence.irregular),
      bare.colorScheme.error,
    );
  });

  test('the four tiers keep four different colours', () {
    for (final theme in _themes.values) {
      final accents = {
        for (final tier in CycleConfidence.values)
          confidenceChipAccent(theme, tier),
      };
      expect(accents, hasLength(CycleConfidence.values.length));
    }
  });
}
