/// Unit tests for the screenshot index builder (issue #1104): the JSON
/// the site (and a later store-listing upload) consumes must be stable —
/// byte-identical for identical inputs, entry order sorted regardless of
/// render completion order — and carry the fields the issue names:
/// screen id, size, theme, app version, commit.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/screenshots/index.dart';
import '../../../tool/screenshots/manifest.dart';

ScreenshotIndexEntry _entry(
  String screen,
  String device,
  ScreenshotTheme theme,
) =>
    ScreenshotIndexEntry(
      screenId: screen,
      deviceId: device,
      theme: theme,
      file: '$screen-$device-${theme.id}.png',
      width: 1290,
      height: 2796,
      storePixelSize: const (1290, 2796),
    );

void main() {
  group('buildIndexJson (#1104)', () {
    test('records app version, commit, and one entry per capture', () {
      final json = buildIndexJson(
        entries: [_entry('today', 'iphone-67', ScreenshotTheme.light)],
        appVersion: '1.2.3+45',
        commit: 'abc123',
      );
      expect(json, contains('"appVersion": "1.2.3+45"'));
      expect(json, contains('"commit": "abc123"'));
      expect(json, contains('"screen": "today"'));
      expect(json, contains('"device": "iphone-67"'));
      expect(json, contains('"theme": "light"'));
      expect(json, contains('"file": "today-iphone-67-light.png"'));
      expect(json, contains('"width": 1290'));
      expect(json, contains('"height": 2796'));
      expect(json, contains('"storeSize": "1290x2796"'));
    });

    test('is byte-identical for identical inputs', () {
      final inputs = [
        _entry('today', 'iphone-67', ScreenshotTheme.light),
        _entry('today', 'iphone-67', ScreenshotTheme.dark),
        _entry('calendar', 'pixel', ScreenshotTheme.light),
      ];
      final a = buildIndexJson(
        entries: inputs,
        appVersion: '1.0.0+1',
        commit: 'deadbeef',
      );
      final b = buildIndexJson(
        entries: inputs,
        appVersion: '1.0.0+1',
        commit: 'deadbeef',
      );
      expect(a, b);
      // And the byte-identity claim literally.
      expect(a.codeUnits, b.codeUnits);
    });

    test('sorts entries by screen, device, theme — regardless of render '
        'completion order', () {
      final json = buildIndexJson(
        entries: [
          _entry('today', 'pixel', ScreenshotTheme.dark),
          _entry('calendar', 'iphone-61', ScreenshotTheme.light),
          _entry('article', 'tablet', ScreenshotTheme.dark),
          _entry('calendar', 'iphone-61', ScreenshotTheme.dark),
          _entry('calendar', 'iphone-67', ScreenshotTheme.light),
        ],
        appVersion: '1.0.0+1',
        commit: 'deadbeef',
      );
      final order = RegExp(r'"screen": "([a-z-]+)"')
          .allMatches(json)
          .map((m) => m.group(1))
          .toList();
      expect(
        order,
        ['article', 'calendar', 'calendar', 'calendar', 'today'],
      );
      // Within one screen: device ids tie-break alphabetically, then the
      // theme id ('dark' sorts before 'light').
      final deviceOrder = RegExp(r'"device": "([a-z0-9-]+)"')
          .allMatches(json)
          .map((m) => m.group(1))
          .toList();
      expect(
        deviceOrder.skip(1).take(3),
        ['iphone-61', 'iphone-61', 'iphone-67'],
      );
      final themeOrder = RegExp(r'"theme": "([a-z]+)"')
          .allMatches(json)
          .map((m) => m.group(1))
          .toList();
      expect(themeOrder, ['dark', 'dark', 'light', 'light', 'dark']);
    });

    test('is valid JSON that round-trips', () {
      final json = buildIndexJson(
        entries: [_entry('guardians', 'tablet', ScreenshotTheme.dark)],
        appVersion: '2.0.0+7',
        commit: 'f00d',
      );
      // `jsonDecode` throws on malformed input — the assertion is the
      // decode itself plus the field spot-check.
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['appVersion'], '2.0.0+7');
      expect(decoded['commit'], 'f00d');
      final screens = decoded['screens'] as List<dynamic>;
      expect(screens, hasLength(1));
      expect((screens.single as Map<String, dynamic>)['device'], 'tablet');
    });
  });
}
