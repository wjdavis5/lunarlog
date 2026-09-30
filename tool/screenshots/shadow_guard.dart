/// The pure pixel scan behind the screenshot runner's shadow guard
/// (issue #1223): the marketing captures must show a blurred shadow
/// around the Log today FAB, never the hard shadow-colour ring that
/// `debugDisableShadows = true` paints in its place.
///
/// The artifact's geometry, which the scan's crop is sized against: with
/// shadows disabled, `RenderPhysicalModel`/`RenderPhysicalShape` stroke
/// the elevated shape with opaque `colorScheme.shadow` at
/// `strokeWidth = elevation * 2`, centred on the shape's edge
/// (`flutter/lib/src/rendering/proxy_box.dart`) — so the visible ring
/// reaches `elevation` (6 dp on the FAB) *outside* the button, while the
/// inner half is overdrawn by the shape fill. A crop inflated by
/// [kShadowGuardCropMargin] (wider than that elevation) contains the
/// whole ring; the button's own rect is excluded from the scan, because
/// its face and icon are legitimate ink. A real blurred shadow over the
/// light theme's near-white surfaces never reaches full opacity (peak
/// key-shadow alpha at elevation 6 stays far below 1.0), so
/// fully-opaque pure black in the scanned band is the artifact's
/// signature and nothing else.
library;

import 'dart:typed_data' show Uint8List;
import 'dart:ui' show Rect;

/// How far outside the FAB the scanned crop reaches, in logical pixels:
/// wider than the FAB's elevation (6 dp — Material 3's
/// `FloatingActionButton` default, the issue's ring width) so the
/// disabled-shadow stand-in ring falls entirely inside the scan.
const double kShadowGuardCropMargin = 12;

/// One pure-black pixel found in the scanned crop, in image pixel
/// coordinates.
class ShadowGuardFinding {
  const ShadowGuardFinding({required this.x, required this.y});

  final int x;
  final int y;

  @override
  String toString() => '($x, $y)';
}

/// Scans [rgba] (row-major rawRgba, [width] x [height] pixels) for a
/// fully-opaque pure-black pixel in the crop around [fab] — a logical
/// rect, scaled by [pixelRatio] — excluding the button's own pixels.
///
/// Returns the first offending pixel, or null when the band is clean.
/// The crop is clamped to the image bounds, so a button sitting near a
/// capture's edge (the browser-class frame gutter, a notch-less top)
/// never reads out of range. Only fully-opaque `r == g == b == 0` trips
/// the guard: the stand-in ring paints opaque black
/// (`colorScheme.shadow`), anti-aliased blends and soft shadows never
/// reach full opacity, near-black ink (icon glyphs, text) must stay
/// allowed in the band, and a transparent pixel is a hole, not this
/// artifact.
ShadowGuardFinding? findPureBlackPixel({
  required Uint8List rgba,
  required int width,
  required int height,
  required Rect fab,
  double pixelRatio = 1.0,
}) {
  final crop = fab
      .inflate(kShadowGuardCropMargin)
      .intersect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
  final left = (crop.left * pixelRatio).floor().clamp(0, width - 1);
  final top = (crop.top * pixelRatio).floor().clamp(0, height - 1);
  final right = (crop.right * pixelRatio).ceil().clamp(0, width);
  final bottom = (crop.bottom * pixelRatio).ceil().clamp(0, height);
  final fabLeft = (fab.left * pixelRatio).floor();
  final fabTop = (fab.top * pixelRatio).floor();
  final fabRight = (fab.right * pixelRatio).ceil();
  final fabBottom = (fab.bottom * pixelRatio).ceil();

  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      // The button's own face and icon are legitimate ink, not shadow.
      if (x >= fabLeft && x < fabRight && y >= fabTop && y < fabBottom) {
        continue;
      }
      final i = (y * width + x) * 4;
      if (rgba[i] == 0 &&
          rgba[i + 1] == 0 &&
          rgba[i + 2] == 0 &&
          rgba[i + 3] == 255) {
        return ShadowGuardFinding(x: x, y: y);
      }
    }
  }
  return null;
}
