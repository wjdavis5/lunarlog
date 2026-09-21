/// The real `home_widget`-backed [WidgetDataStore] (issue #141) — the one
/// place in the app that touches the plugin's static API, mirroring the
/// repo's platform-adapter seam discipline (`FlutterLocalNotificationsScheduler`,
/// `GoogleSignInClient`, the health channels): everything testable lives
/// above this file in pure Dart, and this file is thin plugin wrapping.
///
/// **Do not import this file directly** — import the
/// `home_widget_data_store.dart` barrel, which conditionally selects this
/// implementation on IO platforms and a throwing stub on web: the plugin's
/// own Dart source imports `dart:io` unconditionally, so a plain import
/// would fail the web build.
///
/// ## Platform notes (verified against home_widget 0.8.1's source — the
/// dependency is pinned exactly in `pubspec.yaml` because these details
/// are the contract this file and the native widget code both rely on)
///
/// * **iOS**: `HomeWidget.saveWidgetData` writes `UserDefaults(suiteName:)`
///   with the app group set once via `setAppGroupId` (the constructor).
///   Without the App Group entitlement (both Runner and widget extension)
///   the suite is unwritable from a signed build — the device checklist
///   owns provisioning it; an unsigned build compiles and runs regardless.
/// * **Android**: the plugin writes plain `SharedPreferences` in the
///   `HomeWidgetPreferences` file, which the native
///   `LunarLogWidgetProvider` reads back directly; `refresh` broadcasts
///   `APPWIDGET_UPDATE` to that provider class.
/// * **Tap delivery**: the widget's buttons open the app (activity intent
///   on Android, `widgetURL` on iOS) carrying a `lunarlog://` URI; this
///   file surfaces those as `initialLaunch`/`launches`. No background
///   callback engine is registered — deliberately: a headless Dart
///   callback would run outside the app's gate, and the quick-log write
///   must never run there (issue #141's non-negotiable constraint).
library;

import 'dart:async' show unawaited;

import 'package:home_widget/home_widget.dart';
import 'package:lunarlog/domain/widget/widget_data_store.dart';

/// The app group both the Runner and the widget extension are entitled to,
/// and the suite the payload is written into. Must match
/// `LunarLogWidget.entitlements`' and the Runner entitlements'
/// `com.apple.security.application-groups` entry.
const String kLunarLogAppGroup = 'group.com.wjdavis5.lunarlog.widgets';

/// The `kind` of the iOS widget (`WidgetCenter.reloadTimelines(ofKind:)`)
/// and the Android provider class name the plugin resolves against the app
/// package (`com.wjdavis5.lunarlog.LunarLogWidgetProvider`). Both must
/// match the native declarations.
const String kLunarLogWidgetName = 'LunarLogWidget';
const String kLunarLogWidgetAndroidName = 'LunarLogWidgetProvider';

/// [WidgetDataStore] over the `home_widget` plugin.
class HomeWidgetDataStore implements WidgetDataStore {
  HomeWidgetDataStore() {
    // Best effort: on a platform target without the plugin host (a unit
    // test that forces an iOS/Android targetPlatform override, say) the
    // channel call fails — that must never surface as an unhandled async
    // error; the payload saves themselves report their own failure the
    // same way the plugin returns false.
    unawaited(
      HomeWidget.setAppGroupId(kLunarLogAppGroup).catchError(
        (Object _) => false,
      ),
    );
  }

  @override
  Future<void> savePayload(Map<String, String> payload) async {
    for (final entry in payload.entries) {
      await HomeWidget.saveWidgetData<String>(entry.key, entry.value);
    }
  }

  @override
  Future<void> refresh() async {
    await HomeWidget.updateWidget(
      name: kLunarLogWidgetName,
      androidName: kLunarLogWidgetAndroidName,
      iOSName: kLunarLogWidgetName,
    );
  }

  @override
  Future<Uri?> initialLaunch() => HomeWidget.initiallyLaunchedFromHomeWidget();

  @override
  Stream<Uri> get launches =>
      HomeWidget.widgetClicked.where((uri) => uri != null).cast<Uri>();
}
