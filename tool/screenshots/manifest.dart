/// The fixed screen manifest for the scripted site screenshots (issue
/// #1104).
///
/// Every screenshot the site (and later the App Store / Play listings)
/// shows is one (screen, device, theme) triple from this manifest — there
/// is no ad-hoc capture path. The renderer (`render_screens_test.dart`)
/// walks the full cross product, so adding a screen here is the whole
/// change; removing one retires its PNGs on the next run.
///
/// The device table is pure data: logical sizes are whole points where the
/// real device has them (iPhones), fractional where the store's pixel size
/// divides that way (Pixel 8 at 2.625x). [storePixelSize] records the
/// pixel dimensions the rendered PNG will have at [pixelRatio] — the store
/// listing sizes, recorded per the issue but never uploaded by anything in
/// this repo.
library;

/// A logical device size the screenshots are rendered at.
class ScreenshotDevice {
  const ScreenshotDevice({
    required this.id,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.pixelRatio,
    required this.storePixelSize,
    required this.description,
  });

  /// Stable id used in PNG filenames and the JSON index
  /// (e.g. `today-iphone-67-light.png`).
  final String id;

  /// Logical width/height in points the widget tree is laid out at.
  final double logicalWidth;
  final double logicalHeight;

  /// Device pixel ratio the PNG is rasterized at; the product of this and
  /// the logical size is the PNG's pixel size.
  final double pixelRatio;

  /// The store listing size the output PNG matches, recorded in the index
  /// (App Store 6.7"/6.1"/iPad requirements; Play's Pixel-class 9:16; the
  /// #1162 browser class is not a store size and records its own PNG
  /// dimensions).
  final (int, int) storePixelSize;

  final String description;

  int get pngWidth => (logicalWidth * pixelRatio).round();

  int get pngHeight => (logicalHeight * pixelRatio).round();
}

/// The device classes: a 6.7" iPhone (App Store required size), a 6.1"
/// iPhone (the other App Store required size), a Pixel (Play), one tablet
/// (iPad 11"), and — issue #1162 — a desktop-browser viewport so the
/// gallery carries the browser-width app-frame presentation.
const List<ScreenshotDevice> kScreenshotDevices = [
  ScreenshotDevice(
    id: 'iphone-67',
    logicalWidth: 430,
    logicalHeight: 932,
    pixelRatio: 3.0,
    storePixelSize: (1290, 2796),
    description: '6.7" iPhone (App Store required size)',
  ),
  ScreenshotDevice(
    id: 'iphone-61',
    logicalWidth: 393,
    logicalHeight: 852,
    pixelRatio: 3.0,
    storePixelSize: (1179, 2556),
    description: '6.1" iPhone (App Store required size)',
  ),
  ScreenshotDevice(
    id: 'pixel',
    // 412dp wide (Pixel-class) at a fractional ratio lands exactly on the
    // Play listing's 1080x2400 pixels. The width must stay integral: the
    // calendar's PageView rides ~1,024,320-page offsets (its fixed
    // million-page epoch, month_calendar.dart's _kPageIndexOffset), and a
    // fractional page extent fails the framework's debug float-precision
    // assert on those magnitudes.
    logicalWidth: 412,
    logicalHeight: 2400 / (1080 / 412),
    pixelRatio: 1080 / 412,
    storePixelSize: (1080, 2400),
    description: 'Pixel-class Android phone (Play listing)',
  ),
  ScreenshotDevice(
    id: 'tablet',
    logicalWidth: 834,
    logicalHeight: 1194,
    pixelRatio: 2.0,
    storePixelSize: (1668, 2388),
    description: 'iPad 11" (App Store tablet size)',
  ),
  ScreenshotDevice(
    id: 'browser',
    // A small-desktop browser viewport (1280x800), 1.5x device pixel
    // ratio — 1920x1200 pixels, inside the manifest test's pixel bounds.
    // Deliberately wider than the #1162 app frame's 834dp target so the
    // capture shows the centred frame with its canvas surround, not a
    // full-bleed layout (issue #1162). Not a store listing size — the
    // recorded storePixelSize is simply its own PNG size.
    logicalWidth: 1280,
    logicalHeight: 800,
    pixelRatio: 1.5,
    storePixelSize: (1920, 1200),
    description:
        'Desktop browser viewport (issue #1162 app-frame presentation; '
        'not a store size)',
  ),
];

/// The two themes every screen renders in.
enum ScreenshotTheme {
  light('light'),
  dark('dark');

  const ScreenshotTheme(this.id);

  final String id;
}

/// One line of the fixed screen manifest: what the renderer pumps for the
/// id, in the order the site's gallery lists them.
class ScreenshotScreen {
  const ScreenshotScreen({
    required this.id,
    required this.title,
    required this.description,
  });

  /// Stable id used in PNG filenames and the JSON index.
  final String id;

  /// Human title for the index (the site gallery's label).
  final String title;

  final String description;
}

/// The screens the issue's scope names, in gallery order: Today; the
/// calendar; logging a day; estimates with their confidence tiers (the
/// lower-tier Today — see `fabricated_profile.dart`'s two profiles);
/// sharing/guardians; life-stage modes; import; export; and a literacy
/// article.
const List<ScreenshotScreen> kScreenshotScreens = [
  ScreenshotScreen(
    id: 'today',
    title: 'Today',
    description: 'The Today tab with a high-confidence estimate',
  ),
  ScreenshotScreen(
    id: 'estimates',
    title: 'Estimates',
    description:
        'The Today tab at the learning tier — range estimate and its '
        'confidence framing',
  ),
  ScreenshotScreen(
    id: 'calendar',
    title: 'Calendar',
    description: 'The month calendar with logged bleeds and the predicted '
        'band',
  ),
  ScreenshotScreen(
    id: 'log-day',
    title: 'Log a day',
    description: 'The day sheet over a logged day — flow, tags, note',
  ),
  ScreenshotScreen(
    id: 'guardians',
    title: 'Sharing',
    description: 'Manage guardians for the teen profile',
  ),
  ScreenshotScreen(
    id: 'life-stage',
    title: 'Life-stage modes',
    description: 'The profile editor\'s life-stage mode chooser, open',
  ),
  ScreenshotScreen(
    id: 'import',
    title: 'Import',
    description: 'The import screen over a fabricated plan',
  ),
  ScreenshotScreen(
    id: 'export',
    title: 'Your data',
    description: 'Settings — Your data: export and import entry points',
  ),
  ScreenshotScreen(
    id: 'article',
    title: 'Cycle literacy',
    description: 'A cycle-literacy article sheet',
  ),
];
