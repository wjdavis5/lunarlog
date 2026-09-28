/// Widget tests for the browser-width app frame (issue #1162): the
/// breakpoint behaviour is the contract — a pure passthrough at and below
/// [kAppFrameMaxWidth] (every phone, and the 834dp tablet the target is
/// taken from, keeps its existing layout), and a centred, capped frame on
/// a canvas surround above it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/ui/components/app_frame.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';

void main() {
  const childKey = ValueKey('frame-child');

  /// Pumps an [AppFrame] as a MaterialApp home at the given logical size
  /// and brightness; the frame's child is a childless [Container], which
  /// expands to whatever constraints the frame hands it, so its rect *is*
  /// the frame's presentation.
  Future<void> pumpFrameAt(
    WidgetTester tester,
    Size size, {
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.lightTheme
            : AppTheme.darkTheme,
        home: AppFrame(child: Container(key: childKey, color: Colors.red)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('at or below the target width (#1162)', () {
    test('the layout target is the #1104 tablet class, pinned literally', () {
      expect(kAppFrameMaxWidth, 834);
    });

    testWidgets('a phone viewport is an exact passthrough', (tester) async {
      await pumpFrameAt(tester, const Size(390, 844));
      expect(
        tester.getRect(find.byKey(childKey)),
        const Rect.fromLTWH(0, 0, 390, 844),
      );
      expect(find.byKey(kAppFrameCanvasKey), findsNothing);
      expect(find.byKey(kAppFrameBorderKey), findsNothing);
    });

    testWidgets('the 834dp tablet itself fills the frame — no surround', (
      tester,
    ) async {
      await pumpFrameAt(tester, const Size(kAppFrameMaxWidth, 1194));
      expect(
        tester.getRect(find.byKey(childKey)),
        Rect.fromLTWH(0, 0, kAppFrameMaxWidth, 1194),
      );
      expect(find.byKey(kAppFrameCanvasKey), findsNothing);
      expect(find.byKey(kAppFrameBorderKey), findsNothing);
    });

    testWidgets('the passthrough mounts the given child widget unmodified', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final child = const SizedBox.shrink(key: childKey);
      await tester.pumpWidget(MaterialApp(home: AppFrame(child: child)));
      // Identity, not equality: below the target the widget tree carries
      // the very instance it was given — no re-wrapping at all.
      expect(tester.widget(find.byKey(childKey)), same(child));
    });
  });

  group('above the target width (#1162)', () {
    testWidgets('a browser viewport centres an 834dp full-height frame', (
      tester,
    ) async {
      await pumpFrameAt(tester, const Size(1280, 800));
      // Centred horizontally: (1280 - 834) / 2 == 223 on each side, and
      // full height — the context strips live only at the sides.
      expect(
        tester.getRect(find.byKey(childKey)),
        const Rect.fromLTWH(223, 0, kAppFrameMaxWidth, 800),
      );
    });

    testWidgets('the canvas surround and hairline edge are present', (
      tester,
    ) async {
      await pumpFrameAt(tester, const Size(1280, 800));
      expect(find.byKey(kAppFrameCanvasKey), findsOneWidget);
      expect(find.byKey(kAppFrameBorderKey), findsOneWidget);
    });

    testWidgets('the surround follows the ambient theme', (tester) async {
      await pumpFrameAt(tester, const Size(1280, 800));
      expect(
        tester.widget<ColoredBox>(find.byKey(kAppFrameCanvasKey)).color,
        AppTheme.lightTheme.colorScheme.surfaceContainer,
      );

      await pumpFrameAt(
        tester,
        const Size(1280, 800),
        brightness: Brightness.dark,
      );
      expect(
        tester.widget<ColoredBox>(find.byKey(kAppFrameCanvasKey)).color,
        AppTheme.darkTheme.colorScheme.surfaceContainer,
      );
    });

    testWidgets('an extremely wide viewport stays at the target width', (
      tester,
    ) async {
      await pumpFrameAt(tester, const Size(2560, 1440));
      expect(
        tester.getRect(find.byKey(childKey)),
        Rect.fromLTWH(863, 0, kAppFrameMaxWidth, 1440),
      );
    });

    testWidgets('a route scaffold fills the frame through the production '
        'MaterialApp.builder shape', (tester) async {
      // The production mount is `MaterialApp.builder` handing the
      // Navigator to AppFrame; the frame hands the navigator loose
      // constraints (0..834 wide), and the route's own Scaffold must
      // still fill them — this pins the end-to-end presentation the
      // browser build actually shows.
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              AppFrame(child: child ?? const SizedBox.shrink()),
          home: Scaffold(
            body: Container(key: childKey, color: Colors.red),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(childKey)),
        const Rect.fromLTWH(223, 0, kAppFrameMaxWidth, 800),
      );
    });
  });
}
