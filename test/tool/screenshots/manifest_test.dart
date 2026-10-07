/// Unit tests for the screenshot manifest (issue #1104): the device
/// table's pixel math must land exactly on the store sizes it records,
/// and the screen list must stay a stable, filename-safe gallery order.
///
/// The renderer itself (`tool/screenshots/render_screens_test.dart`) is
/// deliberately NOT run by CI — it writes files and renders dozens of
/// frames under `flutter test`; these tests pin the pure data it walks.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/ui/components/app_frame.dart';

import '../../../tool/screenshots/manifest.dart';

void main() {
  group('device table (#1104)', () {
    test('ids are unique and filename-safe', () {
      final ids = kScreenshotDevices.map((d) => d.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final id in ids) {
        expect(id, matches(RegExp(r'^[a-z0-9-]+$')),
            reason: 'device ids ride in PNG filenames');
      }
    });

    test('png dimensions equal logical size x pixel ratio', () {
      for (final device in kScreenshotDevices) {
        expect(
          device.pngWidth,
          device.storePixelSize.$1,
          reason: '${device.id}: rendered width must be the recorded '
              'store width',
        );
        expect(
          device.pngHeight,
          device.storePixelSize.$2,
          reason: '${device.id}: rendered height must be the recorded '
              'store height',
        );
      }
    });

    test('the issue\'s device classes are all present', () {
      expect(
        kScreenshotDevices.map((d) => d.id),
        containsAll(
          ['iphone-67', 'iphone-61', 'pixel', 'tablet', 'browser'],
        ),
      );
    });

    test('the browser viewport is wider than the #1162 app frame', () {
      // The point of the browser class (issue #1162): the capture shows
      // the centred app-frame with its canvas surround, which only exists
      // above the frame's max width — at or below it the
      // presentation is unchanged.
      final browser = kScreenshotDevices.singleWhere(
        (d) => d.id == 'browser',
      );
      expect(browser.logicalWidth, greaterThan(kAppFrameMaxWidth));
    });

    test('every device stays inside the stores\' pixel bounds', () {
      for (final device in kScreenshotDevices) {
        expect(device.logicalWidth, greaterThan(0));
        expect(device.logicalHeight, greaterThan(0));
        expect(device.pixelRatio, greaterThanOrEqualTo(1));
        // Play accepts up to 3840px on a side; nothing here should even
        // approach it.
        expect(device.pngWidth, lessThanOrEqualTo(2160));
        expect(device.pngHeight, lessThanOrEqualTo(3840));
      }
    });
  });

  group('screen manifest (#1104)', () {
    test('ids are unique and filename-safe', () {
      final ids = kScreenshotScreens.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final id in ids) {
        expect(id, matches(RegExp(r'^[a-z0-9-]+$')),
            reason: 'screen ids ride in PNG filenames');
      }
    });

    test('the issue\'s scope names all nine screens', () {
      expect(
        kScreenshotScreens.map((s) => s.id),
        containsAll([
          'today',
          'calendar',
          'log-day',
          'estimates',
          'guardians',
          'life-stage',
          'import',
          'export',
          'article',
        ]),
      );
    });

    test('the full cross product the renderer walks', () {
      // The count the runner's own completion assertion uses; a manifest
      // edit updates both through this constant, never by hand.
      final triples = kScreenshotScreens.length *
          kScreenshotDevices.length *
          ScreenshotTheme.values.length;
      expect(triples, kScreenshotScreens.length * kScreenshotDevices.length * 2);
    });
  });

  group('the Flutter-rendered device rule (issue #1431)', () {
    test('excludes exactly the browser class, and nothing else', () {
      // Since the React web client cutover (#1258) the browser figure
      // depicts the web client, captured by its own e2e fixture render
      // (webapp/e2e/browser-home-capture.spec.ts) — the Flutter harness
      // must not render it, or it would write the wrong picture over the
      // capture's name. Every other class stays Flutter-rendered.
      expect(
        kFlutterRenderedDevices.map((d) => d.id),
        kScreenshotDevices.map((d) => d.id).where((id) => id != 'browser'),
      );
      expect(kFlutterRenderedDevices, hasLength(kScreenshotDevices.length - 1));
      expect(
        kScreenshotDevices.map((d) => d.id),
        contains('browser'),
        reason: 'the class stays in the manifest as the name grammar and '
            'pixel contract the site mirrors',
      );
    });
  });
}
