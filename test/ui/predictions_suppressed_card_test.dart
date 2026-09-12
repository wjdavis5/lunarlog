import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/birth_control.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/predictions_suppressed_card.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  group('PredictionsSuppressedCard (issue #233)', () {
    testWidgets('renders the explicit suppressed state and names the method',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const PredictionsSuppressedCard(method: BirthControlMethod.implant),
      ));

      expect(find.byKey(const ValueKey('predictions-suppressed')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('predictions-suppressed-title')),
        findsOneWidget,
      );
      final body = tester.widget<Text>(
        find.byKey(const ValueKey('predictions-suppressed-body')),
      );
      expect(body.data, contains('Implant'));
      // The disclaimer stays next to the suppressed state (R17).
      expect(
        find.byKey(const ValueKey('predictions-suppressed-disclaimer')),
        findsOneWidget,
      );
    });

    testWidgets('does not read as a not-enough-history state', (tester) async {
      await tester.pumpWidget(_wrap(
        const PredictionsSuppressedCard(method: BirthControlMethod.copperIud),
      ));
      final body = tester.widget<Text>(
        find.byKey(const ValueKey('predictions-suppressed-body')),
      );
      expect(body.data, isNot(contains('not enough history')));
      expect(body.data, contains('Copper IUD'));
    });
  });
}
