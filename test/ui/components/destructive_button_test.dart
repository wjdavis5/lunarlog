import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/ui/components/destructive_button.dart';

void main() {
  group('DestructiveButton', () {
    testWidgets('renders filled button with error colors', (tester) async {
      bool pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              error: Colors.red,
              onError: Colors.white,
            ),
          ),
          home: Scaffold(
            body: DestructiveButton(
              onPressed: () => pressed = true,
              child: const Text('Delete'),
            ),
          ),
        ),
      );

      final buttonFinder = find.byType(FilledButton);
      expect(buttonFinder, findsOneWidget);
      final filledButton = tester.widget<FilledButton>(buttonFinder);
      final theme = Theme.of(tester.element(buttonFinder));

      expect(
        filledButton.style?.backgroundColor?.resolve({}),
        theme.colorScheme.error,
      );
      expect(
        filledButton.style?.foregroundColor?.resolve({}),
        theme.colorScheme.onError,
      );

      await tester.tap(find.text('Delete'));
      expect(pressed, isTrue);
    });

    testWidgets('renders icon variant with error colors', (tester) async {
      bool pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              error: Colors.red,
              onError: Colors.white,
            ),
          ),
          home: Scaffold(
            body: DestructiveButton.icon(
              onPressed: () => pressed = true,
              icon: const Icon(Icons.delete),
              label: const Text('Delete item'),
            ),
          ),
        ),
      );

      final buttonFinder = find.byType(FilledButton);
      expect(buttonFinder, findsOneWidget);
      expect(find.byIcon(Icons.delete), findsOneWidget);
      expect(find.text('Delete item'), findsOneWidget);

      await tester.tap(find.text('Delete item'));
      expect(pressed, isTrue);
    });
  });
}
