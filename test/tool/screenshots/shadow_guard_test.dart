/// Unit tests for the screenshot runner's shadow guard (issue #1223):
/// the pure pixel scan must flag exactly the disabled-shadow artifact —
/// an opaque black ring hugging the Log today FAB — and nothing else.
///
/// The renderer itself (`tool/screenshots/render_screens_test.dart`) is
/// deliberately NOT run by CI (see `manifest_test.dart`'s header); this
/// file pins the scan it delegates to, over synthetic rawRgba buffers,
/// so the artifact cannot come back unnoticed between real regenerations.
library;

import 'dart:math' show max, sqrt;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/screenshots/shadow_guard.dart';

/// Euclidean distance from [p] to the nearest point of [r] (0 inside).
double _distanceToRect(Rect r, Offset p) {
  final dx = max(r.left - p.dx, max(0.0, p.dx - r.right));
  final dy = max(r.top - p.dy, max(0.0, p.dy - r.bottom));
  return sqrt(dx * dx + dy * dy);
}

void main() {
  // A 100x100 light-theme-like capture at 1x: white background, the FAB
  // sitting at (40, 40)–(60, 60).
  const width = 100;
  const height = 100;
  const fab = Rect.fromLTRB(40, 40, 60, 60);

  /// A white-filled opaque [width]x[height] buffer, repainted pixel by
  /// pixel through [paint] (rawRgba in/out, image coordinates).
  Uint8List whiteBuffer(void Function(List<int> px, int x, int y) paint) {
    final rgba = Uint8List(width * height * 4)
      ..fillRange(0, width * height * 4, 255);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        final px = [rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3]];
        paint(px, x, y);
        rgba
          ..[i] = px[0]
          ..[i + 1] = px[1]
          ..[i + 2] = px[2]
          ..[i + 3] = px[3];
      }
    }
    return rgba;
  }

  test('a clean blurred shadow over white finds nothing', () {
    // The stand-in for a real shadow: a grey ring around the button,
    // darkest at the edge and fading with distance — the light-theme
    // signature once shadows render. Darkest grey is 207, nowhere near
    // black.
    final rgba = whiteBuffer((px, x, y) {
      final d = _distanceToRect(fab, Offset(x + 0.5, y + 0.5));
      if (d < kShadowGuardCropMargin) {
        final shade = 255 - (kShadowGuardCropMargin - d).clamp(0.0, 6.0) * 8;
        px
          ..[0] = shade.round()
          ..[1] = shade.round()
          ..[2] = shade.round();
      }
    });
    expect(
      findPureBlackPixel(rgba: rgba, width: width, height: height, fab: fab),
      isNull,
    );
  });

  test('the disabled-shadow ring — opaque black just outside the '
      'button — is found, in the band and not on the button', () {
    // proxy_box.dart's stand-in: a solid shadow-colour stroke of width
    // elevation*2 centred on the edge, i.e. opaque black out to
    // `elevation` (6dp) beyond the FAB rect, all around.
    final rgba = whiteBuffer((px, x, y) {
      final d = _distanceToRect(fab, Offset(x + 0.5, y + 0.5));
      if (d < 6) {
        px
          ..[0] = 0
          ..[1] = 0
          ..[2] = 0;
      }
    });
    final finding = findPureBlackPixel(
      rgba: rgba,
      width: width,
      height: height,
      fab: fab,
    );
    expect(finding, isNotNull);
    // The first hit sits inside the scanned band but outside the button
    // itself — the ring's reach, not the button's ink.
    expect(
      fab.contains(Offset(finding!.x + 0.5, finding.y + 0.5)),
      isFalse,
    );
    expect(
      fab.inflate(kShadowGuardCropMargin)
          .contains(Offset(finding.x + 0.5, finding.y + 0.5)),
      isTrue,
    );
  });

  test('pure black inside the button is ignored (legit ink)', () {
    // A black icon glyph on the button face must not trip the guard.
    final rgba = whiteBuffer((px, x, y) {
      if (fab.contains(Offset(x + 0.5, y + 0.5))) {
        px
          ..[0] = 0
          ..[1] = 0
          ..[2] = 0;
      }
    });
    expect(
      findPureBlackPixel(rgba: rgba, width: width, height: height, fab: fab),
      isNull,
    );
  });

  test('near-black ink in the band does not trip it — only pure black',
      () {
    // Anti-aliased ring edges blend toward black without reaching it;
    // the artifact's body is exactly black, so rgb(1,1,1) stays allowed.
    final rgba = whiteBuffer((px, x, y) {
      final d = _distanceToRect(fab, Offset(x + 0.5, y + 0.5));
      if (d < 6) {
        px
          ..[0] = 1
          ..[1] = 1
          ..[2] = 1;
      }
    });
    expect(
      findPureBlackPixel(rgba: rgba, width: width, height: height, fab: fab),
      isNull,
    );
  });

  test('a transparent pixel is not the artifact', () {
    final rgba = whiteBuffer((px, x, y) {
      final d = _distanceToRect(fab, Offset(x + 0.5, y + 0.5));
      if (d >= kShadowGuardCropMargin / 2 &&
          d < kShadowGuardCropMargin) {
        px
          ..[0] = 0
          ..[1] = 0
          ..[2] = 0
          ..[3] = 0;
      }
    });
    expect(
      findPureBlackPixel(rgba: rgba, width: width, height: height, fab: fab),
      isNull,
    );
  });

  test('the crop clamps to the image bounds', () {
    // FAB pushed against the capture's bottom-right corner: the
    // inflated crop runs past the edge and must not read out of range.
    const cornerFab = Rect.fromLTRB(88, 88, 96, 96);
    final rgba = whiteBuffer((px, x, y) {
      final d = _distanceToRect(cornerFab, Offset(x + 0.5, y + 0.5));
      if (d < 6) {
        px
          ..[0] = 0
          ..[1] = 0
          ..[2] = 0;
      }
    });
    final finding = findPureBlackPixel(
      rgba: rgba,
      width: width,
      height: height,
      fab: cornerFab,
    );
    expect(finding, isNotNull);
    expect(finding!.x, lessThan(width));
    expect(finding.y, lessThan(height));
  });

  test('scans at the device pixel ratio, not just 1x', () {
    // The runner hands the scan the rasterized PNG's buffer (the
    // logical rect scaled by the device pixel ratio): the same 100x100
    // logical scene at 2x is a 200x200 buffer with the FAB at
    // (80,80)-(120,120) in pixels — while [fab] stays logical.
    const pr = 2.0;
    const prWidth = 200;
    const prHeight = 200;
    const prFabPixels = Rect.fromLTRB(80, 80, 120, 120);

    Uint8List buffer({required bool artifact}) {
      final rgba = Uint8List(prWidth * prHeight * 4);
      for (var y = 0; y < prHeight; y++) {
        for (var x = 0; x < prWidth; x++) {
          final i = (y * prWidth + x) * 4;
          // White, with the artifact ring band (edge..edge+12 device
          // px == 6 logical) in opaque black when asked for.
          final black = artifact &&
              _distanceToRect(prFabPixels, Offset(x + 0.5, y + 0.5)) < 12;
          rgba
            ..[i] = black ? 0 : 255
            ..[i + 1] = black ? 0 : 255
            ..[i + 2] = black ? 0 : 255
            ..[i + 3] = 255;
        }
      }
      return rgba;
    }

    expect(
      findPureBlackPixel(
        rgba: buffer(artifact: false),
        width: prWidth,
        height: prHeight,
        fab: fab,
        pixelRatio: pr,
      ),
      isNull,
    );
    expect(
      findPureBlackPixel(
        rgba: buffer(artifact: true),
        width: prWidth,
        height: prHeight,
        fab: fab,
        pixelRatio: pr,
      ),
      isNotNull,
    );
  });
}
