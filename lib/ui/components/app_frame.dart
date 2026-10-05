/// The browser-width presentation (issue #1162).
///
/// The app is mobile-first, so at desktop-browser widths it used to render
/// as a phone UI stretched across the page. The full responsive rework a
/// desktop layout implies (a NavigationRail replacing the shell's bottom
/// [NavigationBar], per-tab two-pane bodies, …) is out of proportion for
/// this issue, so it takes the issue's sanctioned fallback: at widths above
/// [kAppFrameMaxWidth] the whole navigator presents as a centred app-frame
/// of the target width — the #1104 tablet class (834x1194 @2x), the layout
/// target the issue names — on a canvas-tinted surround, with a hairline
/// edge marking the frame against the canvas. That is an intentional
/// presentation, not a stretched phone, while every phone-sized surface
/// (and the 834dp tablet itself, which fills the frame exactly) keeps the
/// layout it already had.
///
/// Contract: purely presentational, like `responsive_body.dart`'s
/// [ResponsiveBody] — no behaviour change, no state change, no new
/// dependency. Below (or exactly at) [kAppFrameMaxWidth] the child is
/// returned untouched, so every existing mobile layout — and every
/// existing widget test, which runs at the 800x600 test-binding default —
/// is pixel-identical to before. The widget mounts in
/// `MaterialApp.builder` (`lib/app.dart`, and the lock screen's own
/// MaterialApp) so every route, pushed screen, and modal presents inside
/// the frame; full-width banner strips (QA build, pending invite) sit
/// above it and stay chrome.
library;

import 'package:flutter/material.dart';

/// The widest width the app presents at, and the width the centred
/// app-frame takes on wider viewports: the #1104 screenshot manifest's
/// tablet class (iPad 11" at 834 logical points), the layout target
/// issue #1162 names. Pinned literally by
/// `test/ui/components/app_frame_test.dart` so it cannot silently drift
/// off the #1104 device.
const double kAppFrameMaxWidth = 834;

/// The canvas key on the surround painted behind the frame (present only
/// above the target width — the tests find it to pin the breakpoint).
const Key kAppFrameCanvasKey = ValueKey('app-frame-canvas');

/// The key on the frame's hairline edge decoration (same presence
/// contract as [kAppFrameCanvasKey]).
const Key kAppFrameBorderKey = ValueKey('app-frame-border');

/// Presents [child] full-bleed up to [kAppFrameMaxWidth] wide, and as a
/// centred app-frame of that width on a canvas surround above it.
class AppFrame extends StatelessWidget {
  const AppFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // At or below the target the viewport is already the frame's own
        // width class — a phone, or the 834dp tablet the target is taken
        // from — so the child is presented exactly as before, unwrapped.
        if (constraints.maxWidth <= kAppFrameMaxWidth) return child;
        final scheme = Theme.of(context).colorScheme;
        return ColoredBox(
          key: kAppFrameCanvasKey,
          // One M3 step off the scaffold's own `surface`, in both themes:
          // context, not contrast.
          color: scheme.surfaceContainer,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kAppFrameMaxWidth),
              child: DecoratedBox(
                key: kAppFrameBorderKey,
                // Foreground: a plain decoration paints behind the child,
                // and the child (the navigator's opaque scaffold) would
                // cover it. The frame edge must read over the content.
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: scheme.outlineVariant),
                    right: BorderSide(color: scheme.outlineVariant),
                  ),
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
