/// Widget tests for [BannerAboveContent] (issue #1426): the strip the app
/// mounts above the Navigator must be in the accessibility tree, not only
/// on screen.
///
/// Every assertion about the strip reads the semantics tree —
/// `find.semantics` walks it from the root, the way a screen reader does.
/// `find.text`/`find.byKey` read the widget tree and pass whether or not
/// assistive technology is ever told the strip exists, which is how the
/// defect went unnoticed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/ui/components/banner_above_content.dart';

void main() {
  const bannerKey = ValueKey('banner');
  var actionTaps = 0;

  /// A strip shaped like the pending-invite banner: a title plus an action.
  Widget banner() => Material(
        key: bannerKey,
        child: Row(
          children: [
            const Expanded(child: Text('Banner title')),
            TextButton(
              onPressed: () => actionTaps++,
              child: const Text('Banner action'),
            ),
          ],
        ),
      );

  /// Mounts the layout where the app does: in `MaterialApp.builder`, so the
  /// strip is painted before the Navigator and its routes' modal barriers.
  Future<void> pumpAboveNavigator(WidgetTester tester) async {
    actionTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            BannerAboveContent(banner: banner(), child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(title: Text('Dialog')),
                ),
                child: const Text('Open dialog'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the strip sits above the content, which takes the rest of '
      'the height', (tester) async {
    await pumpAboveNavigator(tester);

    final strip = tester.getRect(find.byKey(bannerKey));
    final content = tester.getRect(find.byType(Scaffold));
    expect(strip.top, 0);
    expect(strip.width, 800);
    expect(content.top, strip.bottom);
    expect(content.bottom, 600);
  });

  testWidgets('a strip above the Navigator is in the accessibility tree, '
      'alongside the screen beneath it', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpAboveNavigator(tester);

    expect(find.semantics.byLabel('Banner title'), findsOne,
        reason: "the route's modal barrier must not drop the strip");
    expect(find.semantics.byLabel('Banner action'), findsOne);
    expect(find.semantics.byLabel('Open dialog'), findsOne,
        reason: 'the screen beneath stays reachable too');

    handle.dispose();
  });

  testWidgets("the strip's node has the strip's own bounds, not the whole "
      "app's", (tester) async {
    final handle = tester.ensureSemantics();
    await pumpAboveNavigator(tester);

    final node = find.semantics.byLabel('Banner title').evaluate().single;
    expect(
      node.rect,
      Offset.zero & tester.getSize(find.byKey(bannerKey)),
      reason: 'merged into an enclosing node, the title would be announced '
          'on a focus rectangle the size of the window',
    );

    handle.dispose();
  });

  testWidgets("the strip's action can be activated through semantics, and "
      'stays reachable while a dialog covers the screen beneath',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpAboveNavigator(tester);

    tester.semantics.tap(find.semantics.byLabel('Banner action'));
    expect(actionTaps, 1);

    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();

    // The dialog's barrier still blocks what is behind it in the Navigator…
    expect(find.semantics.byLabel('Dialog'), findsOne);
    expect(find.semantics.byLabel('Open dialog'), findsNothing,
        reason: 'the boundary must not stop a barrier blocking the route '
            'behind it');
    // …and the strip, which the barrier does not cover on screen either,
    // is still there.
    tester.semantics.tap(find.semantics.byLabel('Banner action'));
    expect(actionTaps, 2);

    handle.dispose();
  });
}
