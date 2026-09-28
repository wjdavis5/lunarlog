import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/safe_launch_url.dart';
import 'package:lunarlog/ui/settings/privacy_policy_screen.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

/// Issue #1164: the in-app privacy screen is a summary whose canonical
/// policy pointer is a real action — a "Read the full privacy policy"
/// button opening https://lunarlog.app/privacy through `safeLaunchUrl`
/// (the injected-launcher seam, the crisis card's #1155 failure-fallback
/// pattern) — and whose title says "summary", not "the full document".
void main() {
  /// The action sits below the eight-bullet summary, past the fold of the
  /// default 800x600 test surface, so every test pumps a tall viewport
  /// instead (the same below-the-fold reality `settings_test.dart`'s
  /// `useTallSettingsViewport` helper works around).
  Future<void> pumpScreen(
    WidgetTester tester, {
    LaunchUrlFn? launchUrlFn,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PrivacyPolicyScreen(launchUrlFn: launchUrlFn),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapOpenFullPolicy(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('open-full-privacy-policy')));
    await tester.pumpAndSettle();
  }

  testWidgets('reads as a summary: retitled title, lead-in note, no dead '
      'plain-text "Canonical policy" pointer', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Privacy at a glance'), findsOneWidget);
    expect(
      find.textContaining('This screen is a short summary'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('open-full-privacy-policy')),
        findsOneWidget);
    // The old untappable pointer line is gone from the body — the URL is
    // carried by the lead-in note and the button now, never as orphaned
    // prose at the end of the summary.
    expect(find.textContaining('Canonical policy:'), findsNothing);
  });

  testWidgets('the button launches exactly https://lunarlog.app/privacy',
      (tester) async {
    final urls = <Uri>[];
    await pumpScreen(
      tester,
      launchUrlFn: (url, {mode = LaunchMode.platformDefault}) async {
        urls.add(url);
        return true;
      },
    );

    await tapOpenFullPolicy(tester);

    expect(urls, [Uri.parse('https://lunarlog.app/privacy')]);
    // A successful launch never shows the fallback.
    expect(
      find.byKey(const ValueKey('privacy-policy-open-failed-note')),
      findsNothing,
    );
  });

  testWidgets('a failed launch (`false`) shows the calm note naming the URL, '
      'the #1155 pattern', (tester) async {
    await pumpScreen(
      tester,
      launchUrlFn:
          (url, {mode = LaunchMode.platformDefault}) async => false,
    );

    await tapOpenFullPolicy(tester);

    expect(
      find.byKey(const ValueKey('privacy-policy-open-failed-note')),
      findsOneWidget,
    );
    expect(find.textContaining("Couldn't open the page"), findsOneWidget);
    // The URL survives the failure — the parent can read it from the note
    // (the lead-in note and the failure note both carry it).
    expect(
      find.textContaining('https://lunarlog.app/privacy'),
      findsNWidgets(2),
    );
  });

  testWidgets('a thrown launch lands on the same fallback, never a silent '
      'button', (tester) async {
    await pumpScreen(
      tester,
      launchUrlFn: (url, {mode = LaunchMode.platformDefault}) async {
        throw PlatformException(code: 'activityNotFound');
      },
    );

    await tapOpenFullPolicy(tester);

    expect(
      find.byKey(const ValueKey('privacy-policy-open-failed-note')),
      findsOneWidget,
    );
  });

  testWidgets('a later success clears a previously shown fallback',
      (tester) async {
    var fail = true;
    await pumpScreen(
      tester,
      launchUrlFn: (url, {mode = LaunchMode.platformDefault}) async {
        final result = !fail;
        fail = false;
        return result;
      },
    );

    await tapOpenFullPolicy(tester);
    expect(
      find.byKey(const ValueKey('privacy-policy-open-failed-note')),
      findsOneWidget,
    );

    await tapOpenFullPolicy(tester);
    expect(
      find.byKey(const ValueKey('privacy-policy-open-failed-note')),
      findsNothing,
    );
  });
}
