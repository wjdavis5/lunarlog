/// Runs Flutter's own accessibility guidelines over the app's main screens,
/// on both platforms.
///
/// Two guidelines, both about geometry and semantics, so their answers do
/// not depend on how text is rasterised:
///
///  * every tappable thing has a label a screen reader can say
///    ([labeledTapTargetGuideline]);
///  * every tappable thing is big enough to hit: 48 by 48 on Android
///    ([androidTapTargetGuideline]), 44 by 44 on iOS
///    ([iOSTapTargetGuideline]).
///
/// The screens are the screenshot tool's scenes (`tool/screenshots/`):
/// real widgets over fabricated profiles with the app's own fonts, at the
/// logical size of a 6.1-inch iPhone and of a Pixel. They were written for
/// the marketing site's captures, and they are the nearest thing the
/// repository has to "the app as a person sees it" under `flutter test`.
///
/// Why this exists: running these two guidelines over those scenes for the
/// first time found the calendar's month title, a tap target 28 high beside
/// 48-high buttons. Nothing else failed, and nothing was checking.
///
/// The text-contrast guideline is deliberately not here. It measures the
/// rendered pixels, and on small text it reads the anti-aliased blend as
/// the text colour, so it reported body text at 2:1 that is 9:1 by its
/// tokens. Contrast is tested from the tokens in `theme_test.dart`.
library;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/screenshots/manifest.dart';
import '../../tool/screenshots/render_harness.dart';

/// The two phone shapes, and the platform each renders as.
const _platforms = <String, TargetPlatform>{
  'iphone-61': TargetPlatform.iOS,
  'pixel': TargetPlatform.android,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('both phone shapes are still in the screenshot manifest', () {
    expect(
      kScreenshotDevices.map((device) => device.id),
      containsAll(_platforms.keys),
    );
  });

  for (final screen in kScreenshotScreens) {
    for (final MapEntry(key: deviceId, value: platform)
        in _platforms.entries) {
      testWidgets('${screen.id} on $deviceId: every tap target is labelled '
          'and big enough', (tester) async {
        final device =
            kScreenshotDevices.firstWhere((d) => d.id == deviceId);
        await loadScreenshotFonts();
        final handle = tester.ensureSemantics();
        final world = await ScreenshotWorld.create();
        try {
          tester.view.physicalSize = Size(
            device.logicalWidth * device.pixelRatio,
            device.logicalHeight * device.pixelRatio,
          );
          tester.view.devicePixelRatio = device.pixelRatio;
          debugDefaultTargetPlatformOverride = platform;

          final plan = sceneFor(world, screen);
          await tester.pumpWidget(
            providersFor(
              world,
              child: screenshotApp(
                theme: ScreenshotTheme.light,
                child: plan.home,
              ),
            ),
          );
          await settleScene(tester);
          final interact = plan.interact;
          if (interact != null) {
            await interact(tester);
            await settleScene(tester);
          }

          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(
            tester,
            meetsGuideline(
              platform == TargetPlatform.android
                  ? androidTapTargetGuideline
                  : iOSTapTargetGuideline,
            ),
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          handle.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 100));
          await world.dispose();
        }
      });
    }
  }
}
