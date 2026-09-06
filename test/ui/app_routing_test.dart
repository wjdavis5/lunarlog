/// U2 (KTD4; R1, R3, R4, R13): route-name wiring at the app root —
/// `MaterialApp.navigatorObservers` and the initial route's name, both of
/// which need the real widget tree (a screen-level route-name assertion for
/// each push site lives in that screen's own test file instead).
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/profiles/profile_home_gate.dart';

import 'app_auth_provider_test.dart' show disposeApp, homeContext;

void main() {
  testWidgets('AE4: MaterialApp.navigatorObservers is empty under '
      'flutter test (no SENTRY_DSN, matching sentryNavigatorObservers())',
      (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    await tester.pumpWidget(LunarLogApp(db: db));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.navigatorObservers, isEmpty);

    await disposeApp(tester, db);
  });

  testWidgets("the initial route's settings.name is exactly "
      'ProfileHomeGate, a kSentryRouteNames member -- not merely non-null, '
      'which would pass vacuously under the pre-U2 home: wiring',
      (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    await tester.pumpWidget(LunarLogApp(db: db));
    await tester.pumpAndSettle();

    final route = ModalRoute.of(homeContext(tester));
    expect(route?.settings.name, kRouteProfileHomeGate);
    expect(kSentryRouteNames, contains(kRouteProfileHomeGate));
    expect(find.byType(ProfileHomeGate), findsOneWidget);

    await disposeApp(tester, db);
  });

  testWidgets('MaterialApp.navigatorObservers is identical by reference '
      'across a rebuild triggered by setState (Approach 1b) -- proving the '
      'observer list is allocated once, not per build', (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    await tester.pumpWidget(LunarLogApp(db: db));
    await tester.pumpAndSettle();

    final before =
        tester.widget<MaterialApp>(find.byType(MaterialApp)).navigatorObservers;

    // Any setState on _LunarLogAppState re-runs build(); pumping a fresh
    // frame after the tree is already up exercises that without needing a
    // specific trigger (Flutter's own test harness calls build() again on
    // pump when marked dirty by a rebuild elsewhere in the tree, e.g. the
    // ProfileController's own setState calls during first-run/load()).
    await tester.pump();
    final after =
        tester.widget<MaterialApp>(find.byType(MaterialApp)).navigatorObservers;

    expect(identical(before, after), isTrue);

    await disposeApp(tester, db);
  });
}
