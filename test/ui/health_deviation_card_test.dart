/// `HealthDeviationCard` (Issue #799): the read-only, dismissible
/// "Apple Health noticed…" card renders each insight, the second-opinion
/// subtitle, and fires its dismissal — never any action beyond that.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/health/health_deviation.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/overview/health_deviation_card.dart';

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('renders every deviation kind and the second-opinion subtitle',
      (tester) async {
    final snapshot = HealthDeviationSnapshot(
      insights: [
        HealthDeviationInsight(
          kind: HealthDeviationKind.irregularMenstrualCycles,
          start: LocalDate(2026, 5, 1),
          end: LocalDate(2026, 5, 30),
        ),
        HealthDeviationInsight(
          kind: HealthDeviationKind.infrequentMenstrualCycles,
          start: LocalDate(2026, 6, 1),
          end: LocalDate(2026, 6, 1),
        ),
        HealthDeviationInsight(
          kind: HealthDeviationKind.prolongedMenstrualPeriods,
          start: LocalDate(2026, 7, 1),
          end: LocalDate(2026, 7, 12),
        ),
        HealthDeviationInsight(
          kind: HealthDeviationKind.persistentIntermenstrualBleeding,
          start: LocalDate(2026, 8, 1),
          end: LocalDate(2026, 8, 3),
        ),
      ],
      observedAt: DateTime.utc(2026, 9, 15),
    );

    await tester.pumpWidget(
      _host(HealthDeviationCard(snapshot: snapshot, onDismiss: () {})),
    );

    expect(find.byKey(const ValueKey('health-deviation-card')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('health-deviation-card-title')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('health-deviation-card-subtitle')),
      findsOneWidget,
    );
    for (final kind in HealthDeviationKind.values) {
      expect(
        find.byKey(ValueKey('health-deviation-${kind.wire}')),
        findsOneWidget,
      );
    }
  });

  testWidgets('tapping dismiss invokes the callback', (tester) async {
    var dismissed = 0;
    final snapshot = HealthDeviationSnapshot(
      insights: [
        HealthDeviationInsight(
          kind: HealthDeviationKind.irregularMenstrualCycles,
          start: LocalDate(2026, 5, 1),
          end: LocalDate(2026, 5, 30),
        ),
      ],
      observedAt: DateTime.utc(2026, 9, 15),
    );

    await tester.pumpWidget(
      _host(
        HealthDeviationCard(
          snapshot: snapshot,
          onDismiss: () => dismissed++,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('health-deviation-dismiss')));
    await tester.pump();
    expect(dismissed, 1);
  });
}
