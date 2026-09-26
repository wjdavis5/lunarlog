import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/content/cycle_literacy_library.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/content/cycle_literacy_article_sheet.dart';
import 'package:lunarlog/ui/content/cycle_literacy_library_screen.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';

void main() {
  Widget buildScreen({
    CycleLiteracyAudience initialAudience = CycleLiteracyAudience.all,
  }) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CycleLiteracyLibraryScreen(initialAudience: initialAudience),
    );
  }

  setUp(() {});

  testWidgets('renders all filter chips and defaults to all audience', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('cycle-literacy-filter-all')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('cycle-literacy-filter-teen')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('cycle-literacy-filter-guardian')),
      findsOneWidget,
    );

    final allChip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('cycle-literacy-filter-all')),
    );
    expect(allChip.selected, isTrue);

    // Both teen and guardian articles are visible in "All"
    expect(find.text("What 'Irregular' Really Means at 13"), findsOneWidget);
    expect(
      find.text('Cycle Conversations: Talking Between Teens and Parents'),
      findsOneWidget,
    );
  });

  testWidgets('honors initialAudience parameter', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      buildScreen(initialAudience: CycleLiteracyAudience.teen),
    );
    await tester.pumpAndSettle();

    final teenChip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('cycle-literacy-filter-teen')),
    );
    expect(teenChip.selected, isTrue);

    // Teen article is visible
    expect(find.text("What 'Irregular' Really Means at 13"), findsOneWidget);
    // Guardian-only article is filtered out
    expect(
      find.text('Cycle Conversations: Talking Between Teens and Parents'),
      findsNothing,
    );
  });

  testWidgets('switching filter chips updates visible articles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    // Switch to Guardian
    await tester.tap(
      find.byKey(const ValueKey('cycle-literacy-filter-guardian')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Cycle Conversations: Talking Between Teens and Parents'),
      findsOneWidget,
    );
    expect(find.text("What 'Irregular' Really Means at 13"), findsNothing);

    // Switch to Teen
    await tester.tap(find.byKey(const ValueKey('cycle-literacy-filter-teen')));
    await tester.pumpAndSettle();

    expect(find.text("What 'Irregular' Really Means at 13"), findsOneWidget);
    expect(
      find.text('Cycle Conversations: Talking Between Teens and Parents'),
      findsNothing,
    );
  });

  testWidgets('tapping an article opens the article sheet', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text("What 'Irregular' Really Means at 13"));
    await tester.pumpAndSettle();

    expect(find.byType(CycleLiteracyArticleSheet), findsOneWidget);
    expect(find.text('Anovulatory Cycles and Maturation'), findsOneWidget);
  });

  testWidgets('selected audience articles appear first at the top (#1088)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // 1. Teen filter active: Teen articles appear first under "Written for teens"
    await tester.pumpWidget(
      buildScreen(initialAudience: CycleLiteracyAudience.teen),
    );
    await tester.pumpAndSettle();

    expect(find.text('Written for teens'), findsOneWidget);

    final listTiles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .toList();
    expect(listTiles.length, greaterThanOrEqualTo(2));

    // The very first article tile must be a teen article
    expect(
      find.descendant(
        of: find.byWidget(listTiles[0]),
        matching: find.text(
          'First Periods: What to Expect in the First Two Years',
        ),
      ),
      findsOneWidget,
    );

    // The second article tile must be the second teen article
    expect(
      find.descendant(
        of: find.byWidget(listTiles[1]),
        matching: find.text("What 'Irregular' Really Means at 13"),
      ),
      findsOneWidget,
    );

    // General articles appear further down below the featured section
    expect(
      find.text('The Four Key Phases of the Menstrual Cycle'),
      findsOneWidget,
    );

    // 2. Guardian filter active: Guardian article appears first under "Written for guardians"
    await tester.tap(
      find.byKey(const ValueKey('cycle-literacy-filter-guardian')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Written for guardians'), findsOneWidget);
    expect(find.text('Written for teens'), findsNothing);

    final guardianListTiles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .toList();
    expect(
      find.descendant(
        of: find.byWidget(guardianListTiles[0]),
        matching: find.text(
          'Cycle Conversations: Talking Between Teens and Parents',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('badge uses localized ARB string and theme typography (#1087)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    // Badges must use the localized chip nouns "Teens" and "Guardians", not hard-coded English "For Teens"
    expect(find.text('For Teens'), findsNothing);
    expect(find.text('For Guardians'), findsNothing);

    // Filter chip + article badges: 2 teen articles have "Teens" badge, 1 guardian article has "Guardians" badge
    // Plus the 1 filter chip each:
    expect(find.text('Teens'), findsNWidgets(3)); // 1 chip + 2 article badges
    expect(
      find.text('Guardians'),
      findsNWidgets(2),
    ); // 1 chip + 1 article badge
  });

  testWidgets(
    'AX-XXXL Dynamic Type: teen badge does not squeeze title into mid-word breaks (#1087)',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(3.1)),
            child: child!,
          ),
          home: const CycleLiteracyLibraryScreen(
            initialAudience: CycleLiteracyAudience.teen,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Locate the first periods article title
      final titleFinder = find.text(
        'First Periods: What to Expect in the First Two Years',
      );
      expect(titleFinder, findsOneWidget);

      // Assert the badge is in a Column above the title, never in a Row alongside it (#1087)
      final parentColumnFinder = find.ancestor(
        of: titleFinder,
        matching: find.byType(Column),
      );
      expect(parentColumnFinder, findsWidgets);

      // The badge and title are children of the Column (badge first, title second)
      final columnWidget = tester.widget<Column>(parentColumnFinder.first);
      expect(columnWidget.children.length, greaterThanOrEqualTo(2));

      final renderParagraph = tester.renderObject<RenderParagraph>(titleFinder);

      // Measure the longest word in the title ("Periods:") at 3.1x scale
      final textPainter = TextPainter(
        text: TextSpan(text: 'Periods:', style: renderParagraph.text.style),
        textDirection: TextDirection.ltr,
        textScaler: const TextScaler.linear(3.1),
      )..layout();

      // The RenderParagraph width must be >= the width of its longest word,
      // proving the title is not squeezed into a column narrower than its longest word.
      expect(
        renderParagraph.size.width,
        greaterThanOrEqualTo(textPainter.width),
      );
    },
  );
}
