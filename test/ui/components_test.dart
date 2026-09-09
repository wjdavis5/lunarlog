/// Widget tests for the shared `EmptyState`/`InlineError` components
/// (issue #187; B-8, B-20).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/ui/components/empty_state.dart';
import 'package:lunarlog/ui/components/inline_error.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  group('EmptyState', () {
    testWidgets('renders title and body, no illustration/action by default', (
      tester,
    ) async {
      await _pump(
        tester,
        const EmptyState(
          title: 'No entries this month',
          body: 'Tap a day to log it',
        ),
      );

      expect(find.text('No entries this month'), findsOneWidget);
      expect(find.text('Tap a day to log it'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('renders the illustration slot when given', (tester) async {
      await _pump(
        tester,
        const EmptyState(
          illustration: Icon(Icons.calendar_today),
          title: 'Title',
          body: 'Body',
        ),
      );

      expect(find.byIcon(Icons.calendar_today), findsOneWidget);
    });

    testWidgets(
        'renders and wires a primary action when label+callback are given',
        (tester) async {
      var tapped = false;
      await _pump(
        tester,
        EmptyState(
          title: 'No profiles yet',
          body: 'Add a profile to start tracking.',
          primaryActionLabel: 'Add profile',
          onPrimaryAction: () => tapped = true,
        ),
      );

      expect(find.widgetWithText(FilledButton, 'Add profile'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Add profile'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets(
        "wraps the title in Semantics(header: true) so it is a heading "
        'for screen-reader navigation (issue #308)', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const EmptyState(title: 'No entries this month', body: 'Body'),
      );

      final node = tester.getSemantics(find.text('No entries this month'));
      expect(node.flagsCollection.isHeader, isTrue);

      handle.dispose();
    });

    testWidgets(
        'titleStyle overrides the default titleMedium weight, and '
        'crossAxisAlignment.start left-aligns the title/body text '
        '(issue #308)', (tester) async {
      final theme = ThemeData();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: EmptyState(
              title: 'Not enough history yet',
              body: 'Body',
              titleStyle: theme.textTheme.headlineSmall,
              crossAxisAlignment: CrossAxisAlignment.start,
            ),
          ),
        ),
      );

      final title = tester.widget<Text>(find.text('Not enough history yet'));
      expect(title.style?.fontSize, theme.textTheme.headlineSmall?.fontSize);
      expect(title.textAlign, TextAlign.start);

      final body = tester.widget<Text>(find.text('Body'));
      expect(body.textAlign, TextAlign.start);

      final column = tester.widget<Column>(find.byType(Column));
      expect(column.crossAxisAlignment, CrossAxisAlignment.start);
    });

    test('asserts label and callback are both set or both absent', () {
      expect(
        () => EmptyState(
          title: 't',
          body: 'b',
          onPrimaryAction: () {},
        ),
        throwsAssertionError,
      );
      expect(
        () => EmptyState(
          title: 't',
          body: 'b',
          primaryActionLabel: 'go',
        ),
        throwsAssertionError,
      );
    });
  });

  group('InlineError', () {
    testWidgets('renders the message and no Retry button by default', (
      tester,
    ) async {
      await _pump(
        tester,
        const InlineError(message: "Couldn't save — try again"),
      );

      expect(find.text("Couldn't save — try again"), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
    });

    testWidgets('renders and wires a Retry button when onRetry is given', (
      tester,
    ) async {
      var retried = false;
      await _pump(
        tester,
        InlineError(
          message: "Couldn't load pending invitations.",
          onRetry: () => retried = true,
        ),
      );

      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pump();
      expect(retried, isTrue);
    });

    testWidgets(
        'wraps its message in a live region so a screen reader announces '
        'it without the operator moving focus (issue #187; B-20)',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const InlineError(message: "Couldn't delete — try again"),
      );

      final node = tester.getSemantics(find.byType(InlineError));
      expect(node.flagsCollection.isLiveRegion, isTrue);

      handle.dispose();
    });

    testWidgets(
        "the live-region node's label is exactly the message, not merely "
        'something containing it (issue #308) — pins a node whose message '
        'text is wrapped in ExcludeSemantics, which would still pass an '
        'isLiveRegion-only assertion',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const InlineError(message: "Couldn't save — try again"),
      );

      final node = tester.getSemantics(find.byType(InlineError));
      expect(node.label, "Couldn't save — try again");

      handle.dispose();
    });

    testWidgets(
        "the Retry variant's live-region label is still only the message "
        "— 'Retry' is the button's own semantics node, not folded into "
        'the message node (issue #308)',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        InlineError(
          message: "Couldn't load pending invitations.",
          onRetry: () {},
        ),
      );

      final node = tester.getSemantics(find.byType(InlineError));
      expect(node.label, "Couldn't load pending invitations.");
      expect(node.label, isNot(contains('Retry')));

      handle.dispose();
    });
  });
}
