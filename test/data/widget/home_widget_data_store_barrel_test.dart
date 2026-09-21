/// Unit tests for the widget data store's platform-safe barrel (issue
/// #141): the surface gate follows the target platform, and the stub twin
/// keeps the same public constants as the IO twin (the boundary guard pins
/// them through this barrel, so a drift between the conditional branches
/// would silently change the contract).
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/widget/home_widget_data_store.dart';

void main() {
  group('hasHomeWidgetSurface (the composition gate)', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('true on the two widget platforms', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(hasHomeWidgetSurface, isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(hasHomeWidgetSurface, isTrue);
    });

    test('false everywhere else', () {
      for (final platform in [
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(hasHomeWidgetSurface, isFalse, reason: platform.name);
      }
    });
  });

  test('the barrel surfaces the same constants on every branch', () {
    // On the VM test host the conditional selects the IO twin; this pin
    // plus the web build's own compile of the stub keeps the two branches
    // honest (the values are also pinned natively by
    // test/release/home_widget_boundary_test.dart).
    expect(kLunarLogAppGroup, 'group.com.wjdavis5.lunarlog.widgets');
    expect(kLunarLogWidgetName, 'LunarLogWidget');
    expect(kLunarLogWidgetAndroidName, 'LunarLogWidgetProvider');
  });
}
