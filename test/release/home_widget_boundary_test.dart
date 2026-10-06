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
import 'package:lunarlog/l10n/app_localizations_en.dart';

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

    test('each side reads every key, not just names it', () {
      // The test above is satisfied by a key's name appearing anywhere. The
      // iPhone widget declared `ll_widget_as_of` and never read it, so it
      // counted from the day the system rebuilt its timeline, not from the
      // day the app wrote the counts.
      const swiftNames = [
        'state',
        'cycleDay',
        'daysUntilNext',
        'canQuickLog',
        'profileId',
        'asOf',
      ];
      for (final name in swiftNames) {
        expect(
          RegExp('string\\(forKey: PayloadKey\\.$name\\)').hasMatch(swift),
          isTrue,
          reason: '$_swiftPath declares PayloadKey.$name and must read it',
        );
      }
      const kotlinNames = [
        'KEY_STATE',
        'KEY_CYCLE_DAY',
        'KEY_DAYS_UNTIL_NEXT',
        'KEY_CAN_QUICK_LOG',
        'KEY_PROFILE_ID',
        'KEY_AS_OF',
      ];
      for (final name in kotlinNames) {
        expect(kotlin, contains('prefs.getString($name,'),
            reason: '$_kotlinPath declares $name and must read it');
      }
    });

    test('both sides count on from the day the app wrote the counts', () {
      // The counts are right on `ll_widget_as_of`. Either widget can be
      // redrawn days later with the app unopened in between, and has to
      // add the days since.
      expect(
        kotlin,
        contains('daysBetween(asOf, LocalDate.now())'),
        reason: 'Android rolls by the days since the as-of date',
      );
      expect(kotlin, contains('val day = baseDay + rolled'));

      // iPhone: the timeline (and the snapshot) roll by the days since the
      // as-of date, and each later entry by its own offset on top.
      expect(swift, contains('func daysSinceAsOf('));
      expect(
        RegExp(r'let elapsed = daysSinceAsOf\(\s*readAsOf\(\),')
            .hasMatch(swift),
        isTrue,
      );
      expect(swift, contains('base.rolled(by: elapsed + offset)'));
      expect(swift, isNot(contains('base.rolled(by: offset)')),
          reason: 'counting from today shows the stored day as today\'s');
      expect(
        RegExp(r'readRender\(\)\.rolled\(\s*by: daysSinceAsOf\(')
            .hasMatch(swift),
        isTrue,
        reason: 'the snapshot is rolled too',
      );
      // Read on the Gregorian calendar, whatever the phone is set to: the
      // app wrote the date on that calendar.
      expect(swift, contains('Calendar(identifier: .gregorian)'));
    });

    test('the Android widget asks to be redrawn just after midnight', () {
      // Issue #1548. The count changes at midnight. The system's periodic
      // update runs every 24 hours from whenever the widget was placed, so
      // on its own the widget showed yesterday's number until that time of
      // day came round.
      // (`\r?`: on a Windows checkout the file has CRLF line endings.)
      final onUpdate = RegExp(
        r'override fun onUpdate\([\s\S]*?\r?\n    \}\r?\n',
      ).firstMatch(kotlin)!.group(0)!;
      expect(onUpdate, contains('scheduleMidnightRefresh(context)'),
          reason: 'every draw asks for the next one');
      expect(
        kotlin,
        contains('WidgetMidnight.nextRefreshMillis(Instant.now(), '
            'ZoneId.systemDefault())'),
      );
      // Not a wake-up alarm: nobody is looking at a sleeping phone, and it
      // is delivered when the phone next wakes.
      expect(kotlin, contains('AlarmManager.RTC,'));
      expect(kotlin, isNot(contains('AlarmManager.RTC_WAKEUP')));
      expect(kotlin, isNot(contains('setExact')),
          reason: 'an exact alarm needs a permission this app does not hold');

      // A changed clock or time zone moves the count too.
      for (final action in [
        'Intent.ACTION_TIME_CHANGED',
        'Intent.ACTION_TIMEZONE_CHANGED',
        'ACTION_MIDNIGHT_REFRESH',
      ]) {
        expect(kotlin, contains('$action,'), reason: '$action redraws');
      }
      final receiver = RegExp(
        r'<receiver\s+android:name="\.LunarLogWidgetProvider"[\s\S]*?</receiver>',
      ).firstMatch(manifest)!.group(0)!;
      expect(receiver, contains('android.intent.action.TIME_SET'));
      expect(receiver, contains('android.intent.action.TIMEZONE_CHANGED'));
      expect(receiver, contains('android:exported="false"'));
    });

    test('the Android Log button is a quiet pill with a full-size touch '
        'target', () {
      final layout = readRepoFile(
          'android/app/src/main/res/layout/lunarlog_widget.xml');
      final button = RegExp(r'<Button[\s\S]*?/>').firstMatch(layout)!.group(0)!;
      // It was a stock grey button in capitals, about 24dp tall to touch.
      // It is the one control on the widget that records something.
      expect(button, contains('android:id="@+id/widget_quick_log"'));
      expect(button,
          contains('android:background="@drawable/lunarlog_widget_log_pill"'));
      expect(button, contains('android:textAllCaps="false"'));
      expect(button, contains('android:minHeight="48dp"'));
      expect(button, contains('android:minWidth="64dp"'));
      // The pill is inset inside that height, so it looks 32dp tall.
      final pill = readRepoFile(
          'android/app/src/main/res/drawable/lunarlog_widget_log_pill.xml');
      expect(pill, contains('android:insetTop="8dp"'));
      expect(pill, contains('android:insetBottom="8dp"'));
    });

    test('the Android widget picker shows a sample, and it stays discreet',
        () {
      final info = readRepoFile(
          'android/app/src/main/res/xml/lunarlog_widget_info.xml');
      expect(info,
          contains('android:previewLayout="@layout/lunarlog_widget_preview"'),
          reason: 'without a preview the picker shows a blank card');
      expect(info, contains('android:description="@string/widget_description"'));

      // The sample is fixed text: it has no ids for the provider to fill,
      // so it can never carry anyone's stored state.
      final preview = readRepoFile(
          'android/app/src/main/res/layout/lunarlog_widget_preview.xml');
      expect(preview, isNot(contains('android:id=')));
      expect(preview, contains('@string/widget_preview_title'));

      // Every string the widget and its picker entry can show is free of
      // health words, the same rule as the rendered copy.
      final strings = readRepoFile(
          'android/app/src/main/res/values/widget_strings.xml');
      final values = RegExp(r'<string name="[^"]+">([^<]*)</string>')
          .allMatches(strings)
          .map((m) => m.group(1)!)
          .toList();
      expect(values, containsAll(['Day 14', '≈7 d', 'Log']));
      for (final value in values) {
        for (final word in _healthWords) {
          expect(value.toLowerCase(), isNot(contains(word)),
              reason: 'a widget string must not carry "$word" ("$value")');
        }
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

    test('what Settings says a tap does is what each platform does', () {
      final l10n = AppLocalizationsEn();
      final android = l10n.settingsHomeWidgetDisclosureAndroid;
      final iphone = l10n.settingsHomeWidgetDisclosure;

      // Android: two tap targets. The button carries the quick-log intent
      // and the body opens the app, in both branches of the render.
      expect(
        RegExp(
          r'setOnClickPendingIntent\(\s*R\.id\.widget_quick_log,\s*'
          r'launchPendingIntent\(context, quickLogUri\(',
        ).hasMatch(kotlin),
        isTrue,
        reason: 'only the Log button records the period on Android',
      );
      expect(
        'setOnClickPendingIntent(R.id.widget_root, '
                'launchPendingIntent(context, openUri()))'
            .allMatches(kotlin)
            .length,
        2,
        reason: 'the rest of the widget opens the app, with or without the '
            'button',
      );
      expect(
        RegExp(r'R\.id\.widget_root,\s*launchPendingIntent\(context, '
                r'quickLogUri')
            .hasMatch(kotlin),
        isFalse,
      );
      // So the Android note names the button, by its own label, and says
      // what a tap elsewhere does.
      expect(
        readRepoFile('android/app/src/main/res/values/widget_strings.xml'),
        contains('<string name="widget_quick_log_label">Log</string>'),
      );
      expect(android, contains('it has a Log button'));
      expect(android, contains('Tapping anywhere else on the widget opens '
          'the app.'));

      // iPhone: one tap target, the whole widget, carrying the quick-log
      // URL whenever the profile can be logged for. No Link gives the pill
      // a target of its own.
      expect(swift, contains('.widgetURL(tapUrl)'));
      expect(swift, isNot(contains('Link(')));
      expect(
        RegExp(
          r'private var tapUrl: URL\? \{\s*if entry\.render\.canQuickLog,',
        ).hasMatch(swift),
        isTrue,
      );
      // So the iPhone note says a tap on the widget itself records it. If
      // the pill ever gets its own target, this note has to change with it.
      expect(iphone, contains('tapping it records a period started today'));
      expect(iphone, isNot(contains('Log button')));
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
