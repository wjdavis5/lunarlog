/// Widget and offline tests for the help cards (Issue #139, AC4).
///
/// AC4 proof has two halves: (1) every card pumps its sheet from bundled
/// constants with no async/network gap — the sheet appears on the first
/// tap, synchronously built from const data; (2) a structural assertion
/// that the presentation files and every card's copy are free of network
/// primitives (`Image.network`, `WebView`, `http`, `url_launcher`).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/help/help_cards.dart';
import 'package:lunarlog/ui/help/help_card_view.dart';
import 'package:lunarlog/ui/help/help_library_screen.dart';

/// Pumps [child] inside a minimal app shell.
Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  group('HelpCardView (bundled rendering)', () {
    testWidgets('renders title, summary, body, source, and review date',
        (tester) async {
      await _pump(
          tester, const HelpCardView(card: HelpCards.whyNoEstimateYet));

      final card = HelpCards.whyNoEstimateYet;
      expect(find.text(card.title), findsOneWidget);
      expect(find.text(card.summary), findsOneWidget);
      for (final paragraph in card.body) {
        expect(find.text(paragraph), findsOneWidget);
      }
      expect(find.text('Source: ${card.source}'), findsOneWidget);
      expect(find.text('Reviewed: ${card.reviewDate}'), findsOneWidget);
    });

    testWidgets('every card renders without error (airplane-mode shape)',
        (tester) async {
      // Each card is const data rendered by stock Text widgets: nothing
      // to fetch, so every card must pump cleanly on its own.
      for (final card in HelpCards.all) {
        await _pump(tester, HelpCardView(card: card));
        expect(
          find.byKey(ValueKey('help-card-${card.id}')),
          findsOneWidget,
          reason: card.id,
        );
        expect(
          find.byKey(ValueKey('help-card-source-${card.id}')),
          findsOneWidget,
          reason: card.id,
        );
      }
    });
  });

  group('HelpCardLink (contextual entry point)', () {
    testWidgets('tap opens the card sheet with its provenance',
        (tester) async {
      await _pump(
        tester,
        const HelpCardLink(
          cardId: 'why-no-estimate-yet',
          label: 'Why three cycles?',
        ),
      );

      await tester.tap(find.text('Why three cycles?'));
      await tester.pumpAndSettle();

      final card = HelpCards.whyNoEstimateYet;
      expect(find.text(card.title), findsWidgets);
      expect(find.text('Source: ${card.source}'), findsOneWidget);
      expect(find.text('Reviewed: ${card.reviewDate}'), findsOneWidget);
    });

    testWidgets('unknown card id renders nothing, never a dead button',
        (tester) async {
      await _pump(tester, const HelpCardLink(cardId: 'no-such-card'));

      expect(find.byKey(const ValueKey('help-link-no-such-card')),
          findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });
  });

  group('HelpLibraryScreen', () {
    /// A viewport tall enough for all 24 rows to build at once
    /// (ListView builds lazily, so a phone-height surface hides rows).
    Future<void> pumpLibrary(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await _pump(tester, const HelpLibraryScreen());
      await tester.pump();
    }

    testWidgets('lists every bundled card', (tester) async {
      await pumpLibrary(tester);

      for (final card in HelpCards.all) {
        expect(find.byKey(ValueKey('help-library-${card.id}')),
            findsOneWidget,
            reason: card.id);
      }
    });

    testWidgets('tapping a row opens that card offline', (tester) async {
      await pumpLibrary(tester);

      await tester
          .tap(find.byKey(const ValueKey('help-library-ownership-transfer')));
      await tester.pumpAndSettle();

      final card = HelpCards.byId('ownership-transfer')!;
      expect(find.text(card.title), findsWidgets);
      expect(find.text('Reviewed: ${card.reviewDate}'), findsOneWidget);
    });
  });

  group('no network dependency (AC4 structural)', () {
    test('presentation files use no network primitives', () {
      for (final path in [
        'lib/ui/help/help_card_view.dart',
        'lib/ui/help/help_library_screen.dart',
        'lib/domain/help/help_cards.dart',
      ]) {
        final source = File(path).readAsStringSync().toLowerCase();
        for (final marker in [
          'image.network',
          'networkimage',
          'webview',
          'url_launcher',
          'http.',
          'http://',
          'https://',
        ]) {
          expect(source.contains(marker), isFalse,
              reason: '$path contains "$marker"');
        }
      }
    });
  });
}
