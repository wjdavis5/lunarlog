/// Widget tests for [actionSnackBar]: a snackbar with an action stays long
/// enough to use, then leaves on its own.
///
/// On the pinned Flutter a `SnackBar` built with an `action` defaults to
/// `persist: true`, and `ScaffoldMessengerState`'s timeout does nothing for
/// a persistent snackbar. So "Recorded a medium-flow period start for
/// today. / Undo" stayed on screen until swiped away, and every later
/// snackbar queued unseen behind it. These tests show a snackbar the way a
/// call site does and move the clock.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/ui/components/action_snack_bar.dart';

const Key kBar = ValueKey('action-snack-bar-under-test');
const Key kShowAction = ValueKey('show-action-snack-bar');
const Key kShowPlain = ValueKey('show-plain-snack-bar');

const String kMessage = 'Entry deleted.';
const String kLaterMessage = 'Saved on this device.';

/// One screen with two buttons: the first shows an action snackbar exactly
/// as a call site does (the flag read from `MediaQuery` at the call site),
/// the second a plain one. [accessibleNavigation] is what the platform would
/// report for someone navigating with assistive technology.
Future<void> pumpHost(
  WidgetTester tester, {
  required bool accessibleNavigation,
  VoidCallback? onAction,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(accessibleNavigation: accessibleNavigation),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  key: kShowAction,
                  onPressed: () =>
                      ScaffoldMessenger.of(context).showSnackBar(
                    actionSnackBar(
                      key: kBar,
                      content: const Text(kMessage),
                      actionLabel: 'Undo',
                      onAction: onAction ?? () {},
                      accessibleNavigation:
                          MediaQuery.accessibleNavigationOf(context),
                    ),
                  ),
                  child: const Text('Show action'),
                ),
                TextButton(
                  key: kShowPlain,
                  onPressed: () =>
                      ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text(kLaterMessage)),
                  ),
                  child: const Text('Show plain'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('the duration is eight seconds', () {
    expect(kActionSnackBarDuration, const Duration(seconds: 8));
  });

  test('the builder carries the key, content, action, duration, and the '
      'persist flag it was handed', () {
    var pressed = 0;
    const content = Text(kMessage);
    final timed = actionSnackBar(
      key: kBar,
      content: content,
      actionLabel: 'Undo',
      onAction: () => pressed++,
      accessibleNavigation: false,
    );
    expect(timed.key, kBar);
    expect(timed.content, same(content));
    expect(timed.duration, kActionSnackBarDuration);
    expect(timed.persist, isFalse);
    expect(timed.action!.label, 'Undo');
    timed.action!.onPressed();
    expect(pressed, 1);

    final persistent = actionSnackBar(
      content: content,
      actionLabel: 'Undo',
      onAction: () {},
      accessibleNavigation: true,
    );
    expect(persistent.key, isNull);
    expect(persistent.persist, isTrue);
    expect(persistent.duration, kActionSnackBarDuration);
  });

  testWidgets('stays up for the whole eight seconds, then leaves on its own',
      (tester) async {
    await pumpHost(tester, accessibleNavigation: false);

    await tester.tap(find.byKey(kShowAction));
    await tester.pumpAndSettle();
    expect(find.byKey(kBar), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    // Well past SnackBar's own four-second default: still there to be used.
    await tester.pump(const Duration(seconds: 7));
    expect(find.byKey(kBar), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(
      find.byKey(kBar),
      findsNothing,
      reason: 'past eight seconds the snackbar times out; before the '
          'helper existed it persisted until swiped away',
    );
    expect(find.text(kMessage), findsNothing);
  });

  testWidgets('with assistive navigation on it is still there after eight '
      'seconds, and long after', (tester) async {
    await pumpHost(tester, accessibleNavigation: true);

    await tester.tap(find.byKey(kShowAction));
    await tester.pumpAndSettle();
    expect(find.byKey(kBar), findsOneWidget);

    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(
      find.byKey(kBar),
      findsOneWidget,
      reason: 'someone using assistive technology keeps the action until '
          'they dismiss it, exactly as Flutter intends',
    );

    await tester.pump(const Duration(minutes: 5));
    await tester.pumpAndSettle();
    expect(find.byKey(kBar), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('a snackbar queued behind it becomes visible once it times '
      'out, instead of waiting unseen forever', (tester) async {
    await pumpHost(tester, accessibleNavigation: false);

    await tester.tap(find.byKey(kShowAction));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kShowPlain));
    await tester.pumpAndSettle();
    expect(find.text(kMessage), findsOneWidget);
    expect(find.text(kLaterMessage), findsNothing,
        reason: 'queued behind the action snackbar');

    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(find.text(kMessage), findsNothing);
    expect(find.text(kLaterMessage), findsOneWidget);
  });

  testWidgets('the action runs once and dismisses the snackbar',
      (tester) async {
    var pressed = 0;
    await pumpHost(
      tester,
      accessibleNavigation: false,
      onAction: () => pressed++,
    );

    await tester.tap(find.byKey(kShowAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(pressed, 1);
    expect(find.byKey(kBar), findsNothing);
  });
}
