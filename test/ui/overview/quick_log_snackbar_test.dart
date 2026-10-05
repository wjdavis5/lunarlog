/// Issue #1412: the quick-log confirmation says what the tap did. Both
/// callers (the Today card and the home-screen widget's acknowledgement in
/// `lib/app.dart`) build it through [quickLogSnackBar], so these cases pin
/// the wording and the Undo rule once for both.
///
/// The Undo snackbar is built through `actionSnackBar`, so it leaves after
/// `kActionSnackBarDuration` instead of staying until swiped away; the
/// cases at the end pin that the caller's assistive-navigation flag is what
/// decides whether it persists.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';
import 'package:lunarlog/ui/components/action_snack_bar.dart';
import 'package:lunarlog/ui/overview/quick_log_snackbar.dart';

const String kRecorded = 'Recorded a medium-flow period start for today.';
const String kAlreadyLogged =
    "Today's flow was already logged, so it stays as it was.";

void main() {
  final l10n = AppLocalizationsEn();
  const key = ValueKey('quick-log-snackbar-under-test');

  SnackBar build(
    FlowLevel? previousFlow, {
    VoidCallback? onUndo,
    bool accessibleNavigation = false,
  }) =>
      quickLogSnackBar(
        l10n: l10n,
        previousFlow: previousFlow,
        contentKey: key,
        onUndo: onUndo ?? () {},
        accessibleNavigation: accessibleNavigation,
      );

  test('a day with no entry: "recorded", with Undo wired to the callback',
      () {
    var undone = 0;
    final bar = build(null, onUndo: () => undone++);
    final content = bar.content as Text;
    expect(content.data, kRecorded);
    expect(content.key, key);
    expect(bar.action, isNotNull);
    expect(bar.action!.label, 'Undo');
    bar.action!.onPressed();
    expect(undone, 1);
  });

  test('a day raised to medium flow: still "recorded", with Undo', () {
    for (final below in [
      FlowLevel.none,
      FlowLevel.notBleeding,
      FlowLevel.light,
    ]) {
      final bar = build(below);
      expect((bar.content as Text).data, kRecorded, reason: below.name);
      expect(bar.action, isNotNull, reason: below.name);
    }
  });

  test('a day already at medium flow or heavier: "already logged", and no '
      'Undo because nothing changed', () {
    for (final kept in [
      FlowLevel.medium,
      FlowLevel.heavy,
      FlowLevel.superHeavy,
    ]) {
      final bar = build(kept);
      final content = bar.content as Text;
      expect(content.data, kAlreadyLogged, reason: kept.name);
      expect(content.key, key, reason: kept.name);
      expect(bar.action, isNull, reason: kept.name);
    }
  });

  test('the Undo snackbar times out after kActionSnackBarDuration rather '
      'than persisting until swiped', () {
    final bar = build(null);
    expect(bar.duration, kActionSnackBarDuration);
    expect(
      bar.persist,
      isFalse,
      reason: 'Flutter defaults persist to true for any snackbar with an '
          'action, which is what left "Recorded… / Undo" on screen for good',
    );
  });

  test('with assistive navigation on, the Undo snackbar persists until it '
      'is dismissed', () {
    final bar = build(null, accessibleNavigation: true);
    expect(bar.persist, isTrue);
    expect(bar.action, isNotNull);
  });

  test('the "already logged" line has no action, so it keeps the plain '
      'snackbar timeout whatever the assistive-navigation flag says', () {
    for (final accessibleNavigation in [false, true]) {
      final bar = build(FlowLevel.heavy,
          accessibleNavigation: accessibleNavigation);
      expect(bar.persist, isFalse, reason: '$accessibleNavigation');
      expect(bar.duration, const Duration(seconds: 4),
          reason: '$accessibleNavigation');
    }
  });

  // Issue #1472. The reply used to hide whatever snackbar was current, so a
  // second tap, or a tap within a few seconds of a day-sheet delete, threw
  // away the only Undo for a write that had really happened.
  group('showQuickLogSnackBar', () {
    late ScaffoldMessengerState messenger;

    Future<void> pumpHost(WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.expand())),
      );
      messenger = tester.state<ScaffoldMessengerState>(
        find.byType(ScaffoldMessenger),
      );
    }

    void tapQuickLog(FlowLevel? previousFlow, {VoidCallback? onUndo}) =>
        showQuickLogSnackBar(
          messenger,
          l10n: l10n,
          previousFlow: previousFlow,
          contentKey: key,
          onUndo: onUndo ?? () {},
          accessibleNavigation: false,
        );

    testWidgets('a second tap that changes nothing leaves the first reply and its '
        'Undo on screen, and the Undo still works', (tester) async {
      await pumpHost(tester);
      var undone = 0;

      // Tap 1 logs the day: "recorded", with Undo.
      tapQuickLog(null, onUndo: () => undone++);
      await tester.pumpAndSettle();
      expect(find.text(kRecorded), findsOneWidget);

      // Tap 2 finds the day already at medium flow.
      tapQuickLog(FlowLevel.medium);
      await tester.pumpAndSettle();
      expect(find.text(kRecorded), findsOneWidget);
      expect(find.text(kAlreadyLogged), findsNothing);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(undone, 1);
      // Nothing was left waiting behind it either.
      expect(find.text(kAlreadyLogged), findsNothing);
    });

    testWidgets('never dismisses a snackbar it did not show: an Undo from '
        'elsewhere stays, and the reply waits its turn', (tester) async {
      await pumpHost(tester);
      var deleteUndone = 0;
      messenger.showSnackBar(
        actionSnackBar(
          content: const Text('Deleted'),
          actionLabel: 'Undo',
          onAction: () => deleteUndone++,
          accessibleNavigation: false,
        ),
      );
      await tester.pumpAndSettle();

      tapQuickLog(null);
      await tester.pumpAndSettle();
      expect(find.text('Deleted'), findsOneWidget);
      expect(find.text(kRecorded), findsNothing);

      // A second tap while its own first reply is still queued must not
      // hide the other flow's snackbar either.
      tapQuickLog(FlowLevel.medium);
      await tester.pumpAndSettle();
      expect(find.text('Deleted'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(deleteUndone, 1);
      // With the other snackbar gone, the quick-log reply has its turn.
      expect(find.text(kRecorded), findsOneWidget);
    });

    testWidgets('a second tap is still answered at once when there is no '
        'Undo to lose', (tester) async {
      await pumpHost(tester);

      // Two taps on a day that was already logged: the second reply
      // replaces the first instead of queueing behind it.
      tapQuickLog(FlowLevel.heavy);
      await tester.pumpAndSettle();
      expect(find.text(kAlreadyLogged), findsOneWidget);
      tapQuickLog(FlowLevel.heavy);
      await tester.pumpAndSettle();
      expect(find.text(kAlreadyLogged), findsOneWidget);
      // One on screen and none waiting: after it times out nothing follows.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text(kAlreadyLogged), findsNothing);
    });

    testWidgets('a new write replaces the earlier quick-log message, '
        'whichever kind it was', (tester) async {
      await pumpHost(tester);
      var firstUndone = 0;
      var secondUndone = 0;

      tapQuickLog(null, onUndo: () => firstUndone++);
      await tester.pumpAndSettle();
      // The day was cleared again in between (an Undo elsewhere, a delete):
      // this tap writes, so its own Undo is the one that matters now.
      tapQuickLog(null, onUndo: () => secondUndone++);
      await tester.pumpAndSettle();
      expect(find.text(kRecorded), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(firstUndone, 0);
      expect(secondUndone, 1);
      expect(find.text(kRecorded), findsNothing);

      // And after "already logged", a tap that writes is shown at once.
      tapQuickLog(FlowLevel.medium);
      await tester.pumpAndSettle();
      expect(find.text(kAlreadyLogged), findsOneWidget);
      tapQuickLog(FlowLevel.light);
      await tester.pumpAndSettle();
      expect(find.text(kAlreadyLogged), findsNothing);
      expect(find.text(kRecorded), findsOneWidget);
    });

    testWidgets('once the first message has gone, a second tap gets its own '
        'reply', (tester) async {
      await pumpHost(tester);
      tapQuickLog(null);
      await tester.pumpAndSettle();
      await tester.pump(kActionSnackBarDuration);
      await tester.pumpAndSettle();
      expect(find.text(kRecorded), findsNothing);

      tapQuickLog(FlowLevel.medium);
      await tester.pumpAndSettle();
      expect(find.text(kAlreadyLogged), findsOneWidget);
    });
  });
}
