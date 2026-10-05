/// Issue #1412: the quick-log confirmation says what the tap did. Both
/// callers (the Today card and the home-screen widget's acknowledgement in
/// `lib/app.dart`) build it through [quickLogSnackBar], so these cases pin
/// the wording and the Undo rule once for both.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';
import 'package:lunarlog/ui/overview/quick_log_snackbar.dart';

const String kRecorded = 'Recorded a medium-flow period start for today.';
const String kAlreadyLogged =
    "Today's flow was already logged, so it stays as it was.";

void main() {
  final l10n = AppLocalizationsEn();
  const key = ValueKey('quick-log-snackbar-under-test');

  SnackBar build(FlowLevel? previousFlow, {VoidCallback? onUndo}) =>
      quickLogSnackBar(
        l10n: l10n,
        previousFlow: previousFlow,
        contentKey: key,
        onUndo: onUndo ?? () {},
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
}
