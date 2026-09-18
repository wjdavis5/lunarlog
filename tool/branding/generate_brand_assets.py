#!/usr/bin/env python3
"""Regenerate lunarlog's platform raster branding from one source of truth.

Source of truth: ``assets/branding/app_icon_1024.png`` — the 1024x1024 brand
mark (a crescent moon with dashed cycle markers embracing a family). Every
raster this script writes is derived from it, so the app icon, the iOS launch
images, the Android launch mark, and the Android adaptive-icon layers can
never drift apart. Nothing here is hand-edited; re-run the script instead.

Why a committed Python script rather than ``flutter_launcher_icons`` /
``flutter_native_splash``: those packages only cover part of this surface
(launcher icons and splash respectively, and neither emits an Android
*monochrome* adaptive layer from our mark), so adopting them would mean two
new dev dependencies plus reconciliation of their generated output. A
self-contained script mirrors the repo's existing non-Dart tooling
(``scripts/asc.rb``) and keeps the app's pubspec/lockfile free of a
build-time-only image library.

Requirements: Python 3.10+ with Pillow (``pip install Pillow``). This is a
maintenance tool run by hand when the brand mark changes — it is deliberately
not wired into CI or the build.

Usage, from the repository root::

    python tool/branding/generate_brand_assets.py

What it writes (all checked in):

* ``ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{,@2x,@3x}.png``
* ``android/app/src/main/res/drawable-*/launch_mark.png``
* ``android/app/src/main/res/drawable-*/ic_launcher_foreground.png``
* ``android/app/src/main/res/drawable-*/ic_launcher_monochrome.png``
* ``android/app/src/main/res/mipmap-*/ic_launcher.png``

The XML that references these (``mipmap-anydpi-v26/ic_launcher.xml``,
``drawable/launch_background.xml`` and its ``drawable-v21`` twin,
``values/colors.xml``) is hand-authored declarative config, not generated —
it is its own source of truth and diffable as such.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]

SOURCE_ICON = REPO_ROOT / "assets" / "branding" / "app_icon_1024.png"

IOS_LAUNCH_DIR = (
    REPO_ROOT / "ios" / "Runner" / "Assets.xcassets" / "LaunchImage.imageset"
)
ANDROID_RES = REPO_ROOT / "android" / "app" / "src" / "main" / "res"

# The mark's own background purple, sampled from the source icon (the rounded
# square behind the moon and figures). There is no brand-purple design token
# in `lib/ui/theme/` today — the app's theme seed is a teal (#00696F) — so the
# mark's background is the only brand-true choice for the launch/icon
# background, and it keeps the light mark legible.
BRAND_BACKGROUND = (55, 21, 108)

# The moon+family artwork inside the source's rounded-square badge, measured
# from the source with the badge's border excluded. Kept as an explicit
# constant so the extraction is auditable and stable across re-runs.
MARK_BBOX = (129, 122, 894, 900)

# Luminance ramp used to key the flat background out of the cropped mark.
# Background luminance is ~41; the light-purple figures ~174 and the moon
# brighter still. The two stops sit between those so anti-aliased edges stay
# soft while the intentional dark-purple negative space (the child cutout,
# the gaps between figures) becomes genuinely transparent.
ALPHA_LO = 62.0
ALPHA_HI = 120.0

# 1x iOS launch image canvas (points), matching the storyboard's declared
# LaunchImage size; the mark occupies a comfortable share of it.
IOS_LAUNCH_CANVAS = (168, 185)
IOS_LAUNCH_MARK_HEIGHT = 120

# Android launcher-icon densities and their scale factor from mdpi.
DENSITIES = {
    "mdpi": 1.0,
    "hdpi": 1.5,
    "xhdpi": 2.0,
    "xxhdpi": 3.0,
    "xxxhdpi": 4.0,
}

# Android adaptive icons are a 108dp canvas with a guaranteed-visible central
# circle; keeping the art inside 60% leaves it clear of every launcher mask.
ADAPTIVE_CANVAS_DP = 108
ADAPTIVE_MARK_FRACTION = 0.60

# Legacy (pre-v26) launcher icon canvas in dp, and how much of it the mark fills.
LEGACY_CANVAS_DP = 48
LEGACY_MARK_FRACTION = 0.60

# The Android launch mark is drawn at 128dp (see drawable-*/launch_mark.png).
LAUNCH_MARK_DP = 128


def _luminance(pixel: tuple[int, int, int]) -> float:
    r, g, b = pixel
    return 0.299 * r + 0.587 * g + 0.114 * b


def _pixels(image: Image.Image):
    """Return [image]'s pixel sequence.

    Pillow 14 deprecates ``getdata`` in favour of ``get_flattened_data``;
    preferring the new name when present keeps this script warning-free on
    both sides of that change without pinning a Pillow version.
    """
    getter = getattr(image, "get_flattened_data", None) or image.getdata
    return getter()


def load_mark() -> Image.Image:
    """Return the moon+family mark as RGBA with a transparent background.

    The badge's flat background is keyed out with a luminance ramp so the
    source's anti-aliased edges survive; the artwork keeps its own colours
    (white moon, light-purple figures) for use on the brand background.
    """
    if not SOURCE_ICON.is_file():
        raise SystemExit(f"brand mark not found: {SOURCE_ICON}")

    source = Image.open(SOURCE_ICON).convert("RGB")
    cropped = source.crop(MARK_BBOX)

    span = ALPHA_HI - ALPHA_LO
    alphas: list[int] = []
    for pixel in _pixels(cropped):
        alpha = (_luminance(pixel) - ALPHA_LO) / span
        if alpha <= 0:
            alphas.append(0)
        elif alpha >= 1:
            alphas.append(255)
        else:
            alphas.append(int(alpha * 255))

    mask = Image.new("L", cropped.size)
    mask.putdata(alphas)

    mark = cropped.convert("RGBA")
    mark.putalpha(mask)
    return mark


def _scaled(mark: Image.Image, height: int) -> Image.Image:
    """Scale [mark] to [height], preserving aspect ratio, LANCZOS-filtered."""
    width = max(1, round(mark.width * height / mark.height))
    return mark.resize((width, height), Image.Resampling.LANCZOS)


def _paste_centred(canvas: Image.Image, art: Image.Image) -> None:
    """Alpha-composite [art] centred on [canvas] in place."""
    x = (canvas.width - art.width) // 2
    y = (canvas.height - art.height) // 2
    canvas.alpha_composite(art, dest=(x, y))


def write_ios_launch_images(mark: Image.Image) -> list[Path]:
    """Write the three iOS LaunchImage densities, transparent around the mark."""
    written: list[Path] = []
    for scale, suffix in ((1, ""), (2, "@2x"), (3, "@3x")):
        canvas = Image.new(
            "RGBA",
            (IOS_LAUNCH_CANVAS[0] * scale, IOS_LAUNCH_CANVAS[1] * scale),
            (0, 0, 0, 0),
        )
        _paste_centred(canvas, _scaled(mark, IOS_LAUNCH_MARK_HEIGHT * scale))
        path = IOS_LAUNCH_DIR / f"LaunchImage{suffix}.png"
        canvas.save(path, "PNG")
        written.append(path)
    return written


def write_android_launch_marks(mark: Image.Image) -> list[Path]:
    """Write the centred Android launch mark at every density (128dp)."""
    written: list[Path] = []
    for density, factor in DENSITIES.items():
        size = round(LAUNCH_MARK_DP * factor)
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        _paste_centred(canvas, _scaled(mark, size))
        path = ANDROID_RES / f"drawable-{density}" / "launch_mark.png"
        path.parent.mkdir(parents=True, exist_ok=True)
        canvas.save(path, "PNG")
        written.append(path)
    return written


def write_adaptive_layers(mark: Image.Image) -> list[Path]:
    """Write the adaptive-icon foreground and monochrome layers (108dp)."""
    written: list[Path] = []
    for density, factor in DENSITIES.items():
        size = round(ADAPTIVE_CANVAS_DP * factor)
        art = _scaled(mark, round(size * ADAPTIVE_MARK_FRACTION))

        foreground = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        _paste_centred(foreground, art)

        # The monochrome layer is a silhouette: the system supplies the tint,
        # so only the alpha channel is meaningful. White is the documented
        # convention for the source artwork. It shares the foreground's
        # 108dp canvas and safe-zone geometry — Android scales either layer to
        # the full icon bounds, so a tightly-cropped silhouette would
        # overflow every launcher mask.
        silhouette = Image.new("RGBA", art.size, (255, 255, 255, 0))
        silhouette.putalpha(art.getchannel("A"))
        monochrome = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        _paste_centred(monochrome, silhouette)

        out_dir = ANDROID_RES / f"drawable-{density}"
        out_dir.mkdir(parents=True, exist_ok=True)
        for name, image in (
            ("ic_launcher_foreground.png", foreground),
            ("ic_launcher_monochrome.png", monochrome),
        ):
            path = out_dir / name
            image.save(path, "PNG")
            written.append(path)
    return written


def write_legacy_launcher_icons(mark: Image.Image) -> list[Path]:
    """Write the pre-v26 launcher icons: brand background plus centred mark."""
    written: list[Path] = []
    for density, factor in DENSITIES.items():
        size = round(LEGACY_CANVAS_DP * factor)
        canvas = Image.new("RGBA", (size, size), BRAND_BACKGROUND + (255,))
        _paste_centred(canvas, _scaled(mark, round(size * LEGACY_MARK_FRACTION)))
        path = ANDROID_RES / f"mipmap-{density}" / "ic_launcher.png"
        path.parent.mkdir(parents=True, exist_ok=True)
        canvas.save(path, "PNG")
        written.append(path)
    return written


def main() -> int:
    mark = load_mark()
    written = [
        *write_ios_launch_images(mark),
        *write_android_launch_marks(mark),
        *write_adaptive_layers(mark),
        *write_legacy_launcher_icons(mark),
    ]
    if not written:
        print("nothing written", file=sys.stderr)
        return 1
    print(f"wrote {len(written)} files from {SOURCE_ICON.relative_to(REPO_ROOT)}")
    for path in written:
        print(f"  {path.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
