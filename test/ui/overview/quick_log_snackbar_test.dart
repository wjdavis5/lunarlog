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
}
