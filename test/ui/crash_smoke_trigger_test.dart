/// Issue #973 acceptance coverage: the dev-only crash-report smoke trigger
/// is compile-time present only in a build where `AppConfig.crashSmokeEnabled`
/// is true, and absent otherwise.
///
/// `AboutSection.crashSmoke` is the injection seam the architecture pin
/// (`test/architecture/crash_smoke_seam_test.dart`) requires, so this test
/// exercises both the release-shaped (false — and the default, since this
/// process passes no `LUNARLOG_CRASH_SMOKE` define) and debug-shaped (true)
/// values in one default-off run. The real store-build guarantee is the
/// `kDebugMode` conjunct in `AppConfig.crashSmokeEnabled`, pinned by
/// `test/config_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/settings/about_section.dart';
import 'package:package_info_plus/package_info_plus.dart';

Future<PackageInfo> _fakePackageInfo() async => PackageInfo(
      appName: 'lunarlog',
      packageName: 'com.wjdavis5.lunarlog',
      version: '1.2.3',
      buildNumber: '42',
    );

/// Pumps an [AboutSection] with [crashSmoke] injected. `null` leaves the
/// constant to resolve (`AppConfig.crashSmokeEnabled`), which is false in
/// this test process.
Future<void> _pumpAbout(WidgetTester tester, {required bool? crashSmoke}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ListView(
          children: [
            AboutSection(
              packageInfoReader: _fakePackageInfo,
              crashSmoke: crashSmoke,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Unmounts between pumps: the resolved flag is a `late final` State field,
/// so a repump over the same element would keep the first resolution (the
/// same reason `qa_build_test.dart` unmounts between its two About pumps).
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  final dataTile = find.byKey(const ValueKey('crash-smoke-data-tile'));
  final uiTile = find.byKey(const ValueKey('crash-smoke-ui-tile'));

  testWidgets('a release-shaped build (flag off) renders no trigger',
      (tester) async {
    await _pumpAbout(tester, crashSmoke: false);
    expect(dataTile, findsNothing);
    expect(uiTile, findsNothing);
  });

  testWidgets('the default (no define) renders no trigger in this process',
      (tester) async {
    await _pumpAbout(tester, crashSmoke: null);
    expect(dataTile, findsNothing);
    expect(uiTile, findsNothing);
  });

  testWidgets('a debug-shaped build (flag on) renders both trigger tiles',
      (tester) async {
    await _unmount(tester);
    await _pumpAbout(tester, crashSmoke: true);
    expect(dataTile, findsOneWidget);
    expect(uiTile, findsOneWidget);
    expect(find.textContaining('data-layer'), findsWidgets);
    expect(find.textContaining('UI'), findsWidgets);
  });

  testWidgets('tapping either trigger neither throws nor navigates',
      (tester) async {
    await _unmount(tester);
    await _pumpAbout(tester, crashSmoke: true);

    // Sentry is uninitialized in this process, so the capture is a no-op;
    // the point is that the deliberately-thrown error is caught by the
    // trigger rather than escaping into the widget tree.
    await tester.tap(dataTile);
    await tester.pump();
    await tester.tap(uiTile);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(dataTile, findsOneWidget);
    expect(uiTile, findsOneWidget);
  });
}
