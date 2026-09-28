/// The screenshot runner (issue #1104): renders every (screen, device,
/// theme) triple in the fixed manifest with `flutter test`, writes the
/// PNGs plus `screenshots.json` into the output directory, and fails the
/// test run if anything refuses to render.
///
/// Run it with one command from the repo root (the site's npm wrapper):
///
/// ```
/// npm run screenshots            # from site/ — resolves the repo root
/// ```
///
/// or directly:
///
/// ```
/// flutter test tool/screenshots/render_screens_test.dart
/// ```
///
/// Environment (all optional):
///  - `LUNARLOG_SCREENSHOTS_OUT` — output directory; default
///    `site/public/screenshots` under the repo root (the site build
///    copies `public/` verbatim, so the PNGs land in `dist/`).
///  - `LUNARLOG_SCREENSHOTS_COMMIT` — the commit recorded in the index;
///    default `git rev-parse HEAD` (what the deploy job passes).
///  - `LUNARLOG_SCREENSHOTS_FILTER` — comma-separated screen ids to
///    render a subset locally (`LUNARLOG_SCREENSHOTS_FILTER=today`).
///
/// Determinism: the fabricated data and the clock are fixed
/// (`fabricated_profile.dart`), the fonts are the bundled TTFs loaded
/// into the test engine, and the manifest is walked in a stable order —
/// two runs on the same commit produce byte-identical output on the same
/// platform. The CI suite deliberately does not run this file (it writes
/// files and renders dozens of frames); its logic under test lives in the
/// pure modules (`manifest.dart`, `fabricated_profile.dart`, `index.dart`),
/// covered by `test/tool/screenshots/`.
library;

import 'dart:io';
import 'dart:typed_data' show Uint8List;
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart'
    show Brightness, SizedBox, TargetPlatform;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fabricated_profile.dart';
import 'index.dart';
import 'manifest.dart';
import 'render_harness.dart';

/// Renders the full manifest. One `testWidgets` drives the whole walk so
/// the fonts load once and the index is written exactly once, after every
/// capture; per-triple failures name their screen in the aggregate
/// failure message.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The issue's enforcement line: the tool fails when a profile name
  // isn't on the generator's list — before a single frame renders.
  requireFabricatedNames(
    fabricatedScreenshotProfiles().map((p) => p.name),
    kFabricatedProfileNames,
  );

  final filterRaw = Platform.environment['LUNARLOG_SCREENSHOTS_FILTER'];
  final filter = filterRaw?.split(',').map((s) => s.trim()).toSet();
  final screens = filter == null || filter.isEmpty
      ? kScreenshotScreens
      : (() {
          final known = kScreenshotScreens.map((s) => s.id).toSet();
          final unknown = filter.where((f) => !known.contains(f)).toList();
          if (unknown.isNotEmpty) {
            throw StateError(
              'LUNARLOG_SCREENSHOTS_FILTER names unknown screen(s): '
              '${unknown.join(', ')}. Manifest ids: ${known.join(', ')}.',
            );
          }
          return kScreenshotScreens
              .where((s) => filter.contains(s.id))
              .toList();
        })();

  testWidgets(
    'renders every manifest screenshot and writes the index',
    (tester) async {
      await loadScreenshotFonts();
      final out = _outputDir()..createSync(recursive: true);
      final commit = await _resolveCommit(tester);
      final appVersion = _readAppVersion();

      final entries = <ScreenshotIndexEntry>[];
      final failures = <String>[];
      for (final screen in screens) {
        for (final device in kScreenshotDevices) {
          for (final theme in ScreenshotTheme.values) {
            final label = '${screen.id}/${device.id}/${theme.id}';
            try {
              entries.add(
                await _renderOne(tester, out, screen, device, theme),
              );
            } catch (error, stackTrace) {
              failures.add('$label: $error\n$stackTrace');
            }
          }
        }
      }

      if (failures.isNotEmpty) {
        fail(
          '${failures.length} of ${screens.length * kScreenshotDevices.length * 2} '
          'captures failed:\n${failures.join('\n---\n')}',
        );
      }

      final indexFile = File('${out.path}${Platform.pathSeparator}'
          'screenshots.json');
      final indexJson = buildIndexJson(
        entries: entries,
        appVersion: appVersion,
        commit: commit,
      );
      // dart:io completes only inside `runAsync` under the test binding's
      // fake clock — every async write in this file goes through it.
      await tester.runAsync(() => indexFile.writeAsString(indexJson,
          flush: true));
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}

Future<ScreenshotIndexEntry> _renderOne(
  WidgetTester tester,
  Directory out,
  ScreenshotScreen screen,
  ScreenshotDevice device,
  ScreenshotTheme theme,
) async {
  final world = await ScreenshotWorld.create();
  try {
    tester.view.physicalSize = Size(
      device.logicalWidth * device.pixelRatio,
      device.logicalHeight * device.pixelRatio,
    );
    tester.view.devicePixelRatio = device.pixelRatio;
    tester.platformDispatcher.platformBrightnessTestValue =
        theme == ScreenshotTheme.light ? Brightness.light : Brightness.dark;
    // iPhone-shaped devices render as iOS, the Pixel and the iPad as
    // their own platforms — the same adaptive chrome a real device shows.
    // The #1162 browser class renders as macOS: a real desktop browser
    // reports its desktop OS (never iOS), and macOS is the deterministic
    // stand-in for the desktop-browser posture the app frame presents in.
    debugDefaultTargetPlatformOverride = switch (device.id) {
      'pixel' => TargetPlatform.android,
      'browser' => TargetPlatform.macOS,
      _ => TargetPlatform.iOS,
    };

    final plan = sceneFor(world, screen);
    // The provider scope wraps the MaterialApp (as lib/app.dart scopes
    // the production tree), so modal routes — the day sheet, the article
    // sheet — resolve providers from the root navigator's context.
    await tester.pumpWidget(
      providersFor(
        world,
        child: screenshotApp(theme: theme, child: plan.home),
      ),
    );
    await settleScene(tester);
    final interact = plan.interact;
    if (interact != null) {
      await interact(tester);
      await settleScene(tester);
    }

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(kScreenshotBoundaryKey),
    );
    final pngBytes = await tester.runAsync<Uint8List>(() async {
      // `toImage` rasterizes the boundary's layer tree; `toByteData`
      // encodes the PNG off the test's fake clock — both need the real
      // async zone `runAsync` provides.
      final image = await boundary.toImage(pixelRatio: device.pixelRatio);
      final byteData = await image.toByteData(format: ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('PNG encoding returned null for '
            '${screen.id}-${device.id}-${theme.id}');
      }
      return byteData.buffer.asUint8List();
    });
    if (pngBytes == null) {
      // Unreachable while the closure above throws instead of returning
      // null — a belt-and-braces check for the runner's contract.
      throw StateError('render returned no bytes for '
          '${screen.id}-${device.id}-${theme.id}');
    }

    final file = File(
      '${out.path}${Platform.pathSeparator}'
      '${screen.id}-${device.id}-${theme.id}.png',
    );
    // See the index write below/above: dart:io needs `runAsync` here too.
    await tester.runAsync(() => file.writeAsBytes(pngBytes, flush: true));

    return ScreenshotIndexEntry(
      screenId: screen.id,
      deviceId: device.id,
      theme: theme,
      file: file.uri.pathSegments.last,
      width: device.pngWidth,
      height: device.pngHeight,
      storePixelSize: device.storePixelSize,
    );
  } finally {
    debugDefaultTargetPlatformOverride = null;
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await world.dispose();
  }
}

Directory _outputDir() {
  final configured = Platform.environment['LUNARLOG_SCREENSHOTS_OUT'];
  if (configured != null && configured.isNotEmpty) {
    return Directory(configured);
  }
  return Directory('site${Platform.pathSeparator}public'
      '${Platform.pathSeparator}screenshots');
}

Future<String> _resolveCommit(WidgetTester tester) async {
  final configured = Platform.environment['LUNARLOG_SCREENSHOTS_COMMIT'];
  if (configured != null && configured.isNotEmpty) return configured;
  try {
    // `Process.run` is real-event-loop IO: under the test binding it only
    // completes inside `runAsync`.
    final result = await tester
        .runAsync(() => Process.run('git', const ['rev-parse', 'HEAD']));
    if (result != null && result.exitCode == 0) {
      return (result.stdout as String).trim();
    }
  } on Object {
    // Fall through to 'unknown' — a missing git binary must not stop a
    // local render.
  }
  return 'unknown';
}

String _readAppVersion() {
  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) return 'unknown';
  final match = RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());
  return match?.group(1) ?? 'unknown';
}
