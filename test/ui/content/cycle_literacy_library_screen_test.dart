import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/content/cycle_literacy_library.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/content/cycle_literacy_article_sheet.dart';
import 'package:lunarlog/ui/content/cycle_literacy_library_screen.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';

void main() {
  Widget buildScreen({CycleLiteracyAudience initialAudience = CycleLiteracyAudience.all}) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CycleLiteracyLibraryScreen(initialAudience: initialAudience),
    );
  }

  setUp(() {});

  testWidgets('renders all filter chips and defaults to all audience', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cycle-literacy-filter-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('cycle-literacy-filter-teen')), findsOneWidget);
    expect(find.byKey(const ValueKey('cycle-literacy-filter-guardian')), findsOneWidget);

    final allChip = tester.widget<ChoiceChip>(find.byKey(const ValueKey('cycle-literacy-filter-all')));
    expect(allChip.selected, isTrue);

    // Both teen and guardian articles are visible in "All"
    expect(find.text("What 'Irregular' Really Means at 13"), findsOneWidget);
    expect(find.text('Cycle Conversations: Talking Between Teens and Parents'), findsOneWidget);
  });

  testWidgets('honors initialAudience parameter', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(buildScreen(initialAudience: CycleLiteracyAudience.teen));
    await tester.pumpAndSettle();

    final teenChip = tester.widget<ChoiceChip>(find.byKey(const ValueKey('cycle-literacy-filter-teen')));
    expect(teenChip.selected, isTrue);

    // Teen article is visible
    expect(find.text("What 'Irregular' Really Means at 13"), findsOneWidget);
    // Guardian-only article is filtered out
    expect(find.text('Cycle Conversations: Talking Between Teens and Parents'), findsNothing);
  });

  testWidgets('switching filter chips updates visible articles', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    // Switch to Guardian
    await tester.tap(find.byKey(const ValueKey('cycle-literacy-filter-guardian')));
    await tester.pumpAndSettle();

    expect(find.text('Cycle Conversations: Talking Between Teens and Parents'), findsOneWidget);
    expect(find.text("What 'Irregular' Really Means at 13"), findsNothing);

    // Switch to Teen
    await tester.tap(find.byKey(const ValueKey('cycle-literacy-filter-teen')));
    await tester.pumpAndSettle();

    expect(find.text("What 'Irregular' Really Means at 13"), findsOneWidget);
    expect(find.text('Cycle Conversations: Talking Between Teens and Parents'), findsNothing);
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
}
