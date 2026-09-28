import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/content/cycle_literacy_library.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/safe_launch_url.dart';
import 'package:lunarlog/ui/content/cycle_literacy_article_sheet.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

Future<void> pumpSheet(
  WidgetTester tester,
  CycleLiteracyArticle article, {
  LaunchUrlFn? launchUrlFn,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: CycleLiteracyArticleSheet(
          article: article,
          launchUrlFn: launchUrlFn,
        ),
      ),
    ),
  );
}

/// Scrolls the sheet far enough to reveal the provenance footer.
Future<void> scrollToFooter(WidgetTester tester) async {
  await tester.dragUntilVisible(
    find.textContaining('Last reviewed:'),
    find.byType(ListView),
    const Offset(0, -300),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Issue #1006: provenance footer says "Last reviewed", not '
      '"Last clinical review"', (tester) async {
    final article = CycleLiteracyLibrary.menstrualCyclePhases;

    await pumpSheet(tester, article);
    await scrollToFooter(tester);

    expect(
      find.textContaining('Last reviewed: ${article.reviewDate}'),
      findsOneWidget,
    );
    expect(find.textContaining('Last clinical review'), findsNothing);
  });

  testWidgets('Issue #1103: one line per source, publisher — title', (
    tester,
  ) async {
    final article = CycleLiteracyLibrary.menstrualCyclePhases;

    await pumpSheet(tester, article);
    await scrollToFooter(tester);

    expect(article.sources, isNotEmpty);
    for (final source in article.sources) {
      final expected = source.identifier == null
          ? '${source.publisher.displayName} — ${source.title}'
          : '${source.publisher.displayName} — ${source.title} '
                '(${source.identifier})';
      expect(find.text(expected), findsOneWidget);
    }

    // The old single free-text "Source: …" line is gone.
    expect(find.textContaining('Source: '), findsNothing);
  });

  testWidgets('Issue #1103: identifier-bearing sources render in parentheses', (
    tester,
  ) async {
    final article = CycleLiteracyLibrary.firstPeriodsFirstTwoYears;

    await pumpSheet(tester, article);
    await scrollToFooter(tester);

    expect(find.textContaining('(Committee Opinion No. 651)'), findsOneWidget);
  });

  group('Issue #1132 crisis resources rendering and interaction', () {
    testWidgets(
      'PMS vs. Mood sheet contains a crisis block with tappable tel:988 / sms:988 targets',
      (tester) async {
        final launched = <Uri>[];
        final article = CycleLiteracyLibrary.pmsVsMoodWhenToAskClinician;

        await pumpSheet(
          tester,
          article,
          launchUrlFn: (url, {mode = LaunchMode.platformDefault}) async {
            launched.add(url);
            return true;
          },
        );

        // Scroll until the crisis card is visible
        await tester.dragUntilVisible(
          find.byKey(const ValueKey('crisis-resources-card')),
          find.byType(ListView),
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('crisis-resources-card')),
          findsOneWidget,
        );

        // Verify the buttons are rendered and meet >= 44x44 pt target size
        for (final label in [
          'Call 988',
          'Text 988',
          'Samaritans 116 123',
          'Childline 0800 1111',
          'NHS 111',
          'Lifeline 0808 808 8000',
          '911',
          '999',
        ]) {
          final buttonFinder = find.byKey(ValueKey('crisis-action-$label'));
          await tester.ensureVisible(buttonFinder);
          await tester.pumpAndSettle();
          expect(buttonFinder, findsOneWidget);
          final size = tester.getSize(buttonFinder);
          expect(
            size.width,
            greaterThanOrEqualTo(44.0),
            reason: '$label width must be >= 44pt',
          );
          expect(
            size.height,
            greaterThanOrEqualTo(44.0),
            reason: '$label height must be >= 44pt',
          );
        }

        // Semantics checks
        expect(
          find.bySemanticsLabel('Call 988, Suicide and Crisis Lifeline'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('Text 988, Suicide and Crisis Lifeline'),
          findsOneWidget,
        );

        // Tap Call 988
        final call988Finder = find.byKey(
          const ValueKey('crisis-action-Call 988'),
        );
        await tester.ensureVisible(call988Finder);
        await tester.tap(call988Finder);
        await tester.pumpAndSettle();
        expect(launched, contains(Uri.parse('tel:988')));

        // Tap Text 988
        final text988Finder = find.byKey(
          const ValueKey('crisis-action-Text 988'),
        );
        await tester.ensureVisible(text988Finder);
        await tester.tap(text988Finder);
        await tester.pumpAndSettle();
        expect(launched, contains(Uri.parse('sms:988')));
      },
    );

    testWidgets(
      'pmsAndProgesterone sheet renders crisis block in its dedicated section',
      (tester) async {
        final article = CycleLiteracyLibrary.pmsAndProgesterone;

        await pumpSheet(tester, article);

        await tester.dragUntilVisible(
          find.text('If You Feel Hopeless or Need Help Now'),
          find.byType(ListView),
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('If You Feel Hopeless or Need Help Now'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('crisis-resources-card')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'articles without crisis content do not render crisis resources card',
      (tester) async {
        final article = CycleLiteracyLibrary.menstrualCyclePhases;

        await pumpSheet(tester, article);
        await scrollToFooter(tester);

        expect(
          find.byKey(const ValueKey('crisis-resources-card')),
          findsNothing,
        );
      },
    );
  });

  group('Issue #1151 crisis launch failure fallback', () {
    /// Pumps the PMS sheet with [launchUrlFn] and scrolls the crisis card in.
    Future<void> pumpCrisisCard(
      WidgetTester tester,
      LaunchUrlFn launchUrlFn,
    ) async {
      await pumpSheet(
        tester,
        CycleLiteracyLibrary.pmsVsMoodWhenToAskClinician,
        launchUrlFn: launchUrlFn,
      );
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('crisis-resources-card')),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
    }

    /// The failure note names [number] and the [actionLabel] button carrying
    /// it is still visible, so the reader keeps the number on screen.
    void expectFallback(
      WidgetTester tester, {
      required String number,
      required String actionLabel,
    }) {
      final noteFinder = find.byKey(
        const ValueKey('crisis-launch-failed-note'),
      );
      expect(noteFinder, findsOneWidget);
      final noteText = tester.widget<Text>(noteFinder).data;
      expect(noteText, isNotNull);
      expect(noteText, contains(number));
      expect(
        find.byKey(ValueKey('crisis-action-$actionLabel')),
        findsOneWidget,
        reason: 'the failed number must stay visible on its button',
      );
    }

    testWidgets(
      'a launch that returns false (device can\'t place calls) shows a calm '
      'fallback naming the number',
      (tester) async {
        final launched = <Uri>[];

        await pumpCrisisCard(tester, (
          url, {
          mode = LaunchMode.platformDefault,
        }) async {
          launched.add(url);
          return false; // the iPad-shaped failure: nothing opens
        });

        // No fallback before any tap.
        expect(
          find.byKey(const ValueKey('crisis-launch-failed-note')),
          findsNothing,
        );

        final call988Finder = find.byKey(
          const ValueKey('crisis-action-Call 988'),
        );
        await tester.ensureVisible(call988Finder);
        await tester.tap(call988Finder);
        await tester.pumpAndSettle();

        expect(launched, contains(Uri.parse('tel:988')));
        expectFallback(tester, number: '988', actionLabel: 'Call 988');
      },
    );

    testWidgets(
      'a launch that throws shows the same fallback naming the number',
      (tester) async {
        await pumpCrisisCard(tester, (
          url, {
          mode = LaunchMode.platformDefault,
        }) async {
          throw PlatformException(
            code: 'failed to open URL',
            message: 'Error Domain=LSApplicationWorkspaceErrorDomain',
          );
        });

        final call999Finder = find.byKey(const ValueKey('crisis-action-999'));
        await tester.ensureVisible(call999Finder);
        await tester.tap(call999Finder);
        await tester.pumpAndSettle();

        expectFallback(tester, number: '999', actionLabel: '999');
      },
    );

    testWidgets('a successful launch shows no fallback', (tester) async {
      await pumpCrisisCard(
        tester,
        (url, {mode = LaunchMode.platformDefault}) async => true,
      );

      final call988Finder = find.byKey(
        const ValueKey('crisis-action-Call 988'),
      );
      await tester.ensureVisible(call988Finder);
      await tester.tap(call988Finder);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('crisis-launch-failed-note')),
        findsNothing,
      );
    });
  });
}
