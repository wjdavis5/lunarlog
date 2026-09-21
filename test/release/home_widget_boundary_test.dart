/// Home-screen widget boundary guard (issue #141). Mirrors
/// `fcm_presentation_manifest_test.dart`'s shape: read the native sources
/// and manifests as text and assert the invariants the widget wiring
/// depends on, since none of it compiles or runs under `flutter test`.
///
/// This is the CI-side enforcement of the issue's privacy constraints: the
/// exact key set that crosses the app-group boundary, the discreet native
/// render vocabulary, and the write-only-after-unlock intent shape. The
/// authoritative *documentation* of the boundary lives in
/// `lib/domain/widget/widget_cycle_state.dart`; this test pins the native
/// files to it so they cannot drift.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/widget/home_widget_data_store.dart';
import 'package:lunarlog/domain/widget/widget_cycle_state.dart';

import 'repo_text_helpers.dart';

const _kotlinPath =
    'android/app/src/main/kotlin/com/wjdavis5/lunarlog/LunarLogWidgetProvider.kt';
const _swiftPath = 'ios/LunarLogWidget/LunarLogWidget.swift';
const _manifestPath = 'android/app/src/main/AndroidManifest.xml';

/// Words that must never appear as rendered widget copy (a lowercase scan
/// of the render strings below; the constraint is issue #141's "no health
/// detail" default). Neutral state words like the button's "Log" are the
/// same posture the reminder actions adopted (issue #844).
const _healthWords = [
  'period',
  'menstru',
  'flow',
  'bleed',
  'spotting',
  'symptom',
  'cramp',
];

void main() {
  group('home-widget boundary guard (issue #141)', () {
    late String kotlin;
    late String swift;
    late String manifest;

    setUpAll(() {
      kotlin = readRepoFile(_kotlinPath);
      swift = readRepoFile(_swiftPath);
      manifest = readRepoFile(_manifestPath);
    });

    test('both native sides read exactly the documented payload keys',
        () {
      final keys = [
        WidgetCycleStatePayload.keyState,
        WidgetCycleStatePayload.keyCycleDay,
        WidgetCycleStatePayload.keyDaysUntilNext,
        WidgetCycleStatePayload.keyCanQuickLog,
        WidgetCycleStatePayload.keyProfileId,
        WidgetCycleStatePayload.keyAsOf,
      ];
      for (final key in keys) {
        expect(kotlin, contains('"$key"'),
            reason: '$_kotlinPath must read $key');
        expect(swift, contains('"$key"'),
            reason: '$_swiftPath must read $key');
      }

      // The exact-set side of the boundary: neither native file mentions
      // any `ll_widget_` key beyond the six (a seventh key added natively
      // would be an undocumented crossing).
      for (final source in [kotlin, swift]) {
        final mentioned = RegExp(r'll_widget_[a-z_]+')
            .allMatches(source)
            .map((m) => m.group(0)!)
            .toSet();
        expect(mentioned, containsAll(keys));
        expect(mentioned.difference(keys.toSet()), isEmpty,
            reason: 'native code references a payload key the boundary '
                'documentation does not declare: $mentioned');
      }
    });

    test('the native render vocabulary stays discreet', () {
      // The user-visible strings each native side renders. If a health
      // word ever appears here, the discreet default is broken.
      final renderStrings = [
        // Kotlin: title, countdown suffix, and the button label resource.
        ...RegExp(r'"([^"]*)"')
            .allMatches(kotlin)
            .map((m) => m.group(1)!),
        // Swift: the title/subtitle templates and the "Log" label.
        ...RegExp(r'"([^"]*)"')
            .allMatches(swift)
            .map((m) => m.group(1)!),
      ];
      for (final value in renderStrings) {
        for (final word in _healthWords) {
          expect(value.toLowerCase(), isNot(contains(word)),
              reason: 'widget render copy must not carry "$word" '
                  '(found in "$value") — the discreet default (issue #141) '
                  'is numeric-only');
        }
      }
      // The button labels, pinned: a neutral word on both platforms.
      expect(swift, contains('Text("Log")'));
      expect(readRepoFile('android/app/src/main/res/values/widget_strings.xml'),
          contains('>Log<'));
    });

    test('both natives open the app with the exact quick-log URI shape',
        () {
      // The Dart codec is the contract; the natives must build the same
      // shape (the plugin's marker parameter included).
      final quickLogShape = RegExp(
          'lunarlog://widget-quick-log\\?homeWidget=1&profile=');
      final openShape = RegExp('lunarlog://widget-open\\?homeWidget=1');
      expect(quickLogShape.hasMatch(kotlin), isTrue,
          reason: 'the Android button must open the quick-log intent');
      expect(openShape.hasMatch(kotlin), isTrue,
          reason: 'the Android body must open the app plainly');
      expect(quickLogShape.hasMatch(swift), isTrue);
      expect(openShape.hasMatch(swift), isTrue);
    });

    test('the iOS widget kind and app group match the Dart store', () {
      expect(swift, contains('let lunarLogWidgetKind = "$kLunarLogWidgetName"'),
          reason: 'the kind updateWidget(iOSName:) reloads must match');
      expect(
          swift,
          contains('"$kLunarLogAppGroup"'),
          reason: 'the suite read here must be the suite the Dart side '
              'writes');
    });

    test('the Android manifest registers the widget provider', () {
      expect(manifest, contains('android:name=".LunarLogWidgetProvider"'));
      expect(
          manifest,
          contains(
              'android:name="android.appwidget.action.APPWIDGET_UPDATE"'));
      expect(
          readRepoFile('android/app/src/main/res/xml/lunarlog_widget_info.xml'),
          contains('android:initialLayout="@layout/lunarlog_widget"'));
    });

    test('the Xcode project embeds the widget extension', () {
      final pbxproj = readRepoFile('ios/Runner.xcodeproj/project.pbxproj');
      expect(pbxproj, contains('productType = "com.apple.product-type.app-extension"'));
      expect(pbxproj, contains('Embed Foundation Extensions'));
      expect(pbxproj, contains('LunarLogWidget/LunarLogWidget.entitlements'));
      // Both Runner entitlement files declare the same app group — an app
      // group only works when every member declares it.
      final appGroup = '<string>$kLunarLogAppGroup</string>';
      for (final path in [
        'ios/Runner/Runner.entitlements',
        'ios/Runner/DebugProfile.entitlements',
        'ios/LunarLogWidget/LunarLogWidget.entitlements',
      ]) {
        expect(readRepoFile(path), contains(appGroup),
            reason: '$path must declare the shared app group');
      }
    });
  });
}
