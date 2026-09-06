/// Widget tests for the optional screenshot attachment field (Issue #6, U7;
/// R5, R10, R16).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app_lifecycle.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';
import 'package:lunarlog/ui/feedback/attachment_field.dart';
import 'package:provider/provider.dart';

import 'gate_test.dart' show FakeGate, FakeInactivityTimers;

class FakeAttachmentSource implements AttachmentSource {
  int pickCalls = 0;
  FeedbackAttachment? nextResult;

  /// When set, [pickImage] doesn't return until this completes, so a test
  /// can act (fire a lifecycle event, expire the gate's system-UI deadline)
  /// while the platform picker is still "open".
  Completer<FeedbackAttachment?>? hold;

  @override
  Future<FeedbackAttachment?> pickImage() async {
    pickCalls++;
    final held = hold;
    if (held != null) return held.future;
    return nextResult;
  }
}

/// The gate rig for a test that needs [AttachmentField] wired to a real
/// [GateController] (mirrors `account_test.dart`'s `pumpSection`/AE6 setup).
class GatedField {
  GatedField(this.gateController, this.gate, this.timers);
  final GateController gateController;
  final FakeGate gate;
  final FakeInactivityTimers timers;
}

Future<GatedField> pumpGatedField(
  WidgetTester tester,
  FakeAttachmentSource source,
  ValueChanged<FeedbackAttachment?> onChanged, {
  Duration systemUiDeadline = const Duration(seconds: 90),
}) async {
  final gate = FakeGate(requiresUnlock: true);
  // Fake timers: unlocking this gate arms the inactivity countdown, which
  // would otherwise leave a real Timer pending past the end of the test.
  final timers = FakeInactivityTimers();
  final gateController = GateController(
    gate: gate,
    inactivityTimerFactory: timers.factory,
    systemUiDeadline: systemUiDeadline,
  );
  addTearDown(gateController.dispose);
  gate.grantNext = true;
  await gateController.unlock();
  gateController.didChangeAppLifecycleState(AppLifecycleState.resumed);
  // Settle unlock()'s own system-UI window so its trailing tail cannot mask
  // whether the picker opens one of its own: without this, `_suppressingLock`
  // stays true from the unlock ceremony alone and a test tapping the picker
  // right after would pass even if the picker were never wrapped in
  // `duringSystemUi` at all.
  timers.fireWithDelay(kSystemUiSettleTimeout);

  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider<GateController>.value(
        value: gateController,
        child: Scaffold(
          body: AttachmentField(source: source, onChanged: onChanged),
        ),
      ),
    ),
  );
  return GatedField(gateController, gate, timers);
}

FeedbackAttachment _makeAttachment({int bytes = 1024, String mimeType = 'image/png', String filename = 'shot.png'}) =>
    FeedbackAttachment(bytes: List<int>.filled(bytes, 1), mimeType: mimeType, filename: filename);

Future<void> pumpField(WidgetTester tester, FakeAttachmentSource source, ValueChanged<FeedbackAttachment?> onChanged) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AttachmentField(source: source, onChanged: onChanged),
      ),
    ),
  );
}

void main() {
  testWidgets('dismissing the consent dialog does not call the source', (tester) async {
    final source = FakeAttachmentSource();
    await pumpField(tester, source, (_) {});

    await tester.tap(find.byKey(const ValueKey('feedback-add-screenshot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('feedback-attachment-consent-cancel')));
    await tester.pumpAndSettle();

    expect(source.pickCalls, 0);
  });

  testWidgets('confirming consent calls the source exactly once', (tester) async {
    final source = FakeAttachmentSource()..nextResult = _makeAttachment();
    await pumpField(tester, source, (_) {});

    await tester.tap(find.byKey(const ValueKey('feedback-add-screenshot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('feedback-attachment-consent-continue')));
    await tester.pumpAndSettle();

    expect(source.pickCalls, 1);
  });

  testWidgets('a fake source returning null (cancelled) leaves the form with no attachment', (tester) async {
    final source = FakeAttachmentSource()..nextResult = null;
    FeedbackAttachment? received = _makeAttachment(); // sentinel to prove onChanged isn't called
    await pumpField(tester, source, (a) => received = a);

    await tester.tap(find.byKey(const ValueKey('feedback-add-screenshot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('feedback-attachment-consent-continue')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('feedback-attachment-selected')), findsNothing);
    expect(received, _makeAttachment(), reason: 'onChanged must not fire for a cancelled pick');
  });

  testWidgets('a 6 MiB image is rejected locally with the too-large copy and never reaches the caller',
      (tester) async {
    final source = FakeAttachmentSource()..nextResult = _makeAttachment(bytes: 6 * 1024 * 1024);
    FeedbackAttachment? received;
    await pumpField(tester, source, (a) => received = a);

    await tester.tap(find.byKey(const ValueKey('feedback-add-screenshot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('feedback-attachment-consent-continue')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('feedback-attachment-error')), findsOneWidget);
    expect(find.textContaining('too large'), findsOneWidget);
    expect(received, isNull);
    expect(find.byKey(const ValueKey('feedback-attachment-selected')), findsNothing);
  });

  testWidgets('an image/gif selection is rejected locally with the rejected copy', (tester) async {
    final source = FakeAttachmentSource()..nextResult = _makeAttachment(mimeType: 'image/gif', filename: 'shot.gif');
    FeedbackAttachment? received;
    await pumpField(tester, source, (a) => received = a);

    await tester.tap(find.byKey(const ValueKey('feedback-add-screenshot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('feedback-attachment-consent-continue')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('feedback-attachment-error')), findsOneWidget);
    expect(find.textContaining('not supported'), findsOneWidget);
    expect(received, isNull);
  });

  testWidgets('a valid selection shows filename and size and passes the attachment through', (tester) async {
    final source = FakeAttachmentSource()..nextResult = _makeAttachment(bytes: 2048, filename: 'bug.png');
    FeedbackAttachment? received;
    await pumpField(tester, source, (a) => received = a);

    await tester.tap(find.byKey(const ValueKey('feedback-add-screenshot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('feedback-attachment-consent-continue')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('feedback-attachment-selected')), findsOneWidget);
    expect(find.text('bug.png'), findsOneWidget);
    expect(received, isNotNull);
    expect(received!.filename, 'bug.png');
  });

  testWidgets('removing the attachment clears it (onChanged fires with null)', (tester) async {
    final source = FakeAttachmentSource()..nextResult = _makeAttachment();
    FeedbackAttachment? received = _makeAttachment();
    await pumpField(tester, source, (a) => received = a);

    await tester.tap(find.byKey(const ValueKey('feedback-add-screenshot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('feedback-attachment-consent-continue')));
    await tester.pumpAndSettle();
    expect(received, isNotNull);

    await tester.tap(find.byKey(const ValueKey('feedback-attachment-remove')));
    await tester.pumpAndSettle();

    expect(received, isNull);
    expect(find.byKey(const ValueKey('feedback-attachment-selected')), findsNothing);
    expect(find.byKey(const ValueKey('feedback-add-screenshot')), findsOneWidget);
  });

  group('gate suppression (#65 U2; KTD6)', () {
    testWidgets('AE6: the picker runs inside one duringSystemUi window: a '
        'background lifecycle event while it is open does not re-lock the '
        'app', (tester) async {
      final source = FakeAttachmentSource()..hold = Completer<FeedbackAttachment?>();
      final g = await pumpGatedField(tester, source, (_) {});
      expect(g.gateController.locked, isFalse);

      await tester.tap(find.byKey(const ValueKey('feedback-add-screenshot')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('feedback-attachment-consent-continue')));
      await tester.pump();

      g.gateController.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await tester.pump();

      expect(g.gateController.locked, isFalse,
          reason: 'the app opened this picker itself');
      expect(g.gateController.obscured, isTrue);

      source.hold!.complete(null);
      g.gateController.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(g.gateController.locked, isFalse);
    });

    testWidgets('with no GateController provided, a background lifecycle '
        'event during the pick has nothing to suppress and the picker still '
        'resolves normally', (tester) async {
      final source = FakeAttachmentSource()..nextResult = _makeAttachment();
      FeedbackAttachment? received;
      await pumpField(tester, source, (a) => received = a);

      await tester.tap(find.byKey(const ValueKey('feedback-add-screenshot')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('feedback-attachment-consent-continue')));
      await tester.pumpAndSettle();

      expect(received, isNotNull);
    });

    testWidgets('a stale pick after the system-UI deadline expires and '
        're-locks the gate is discarded, not stored into the form', (tester) async {
      const windowDeadline = Duration(seconds: 90);
      final source = FakeAttachmentSource()..hold = Completer<FeedbackAttachment?>();
      final sentinel = _makeAttachment(); // proves onChanged is never called
      FeedbackAttachment? received = sentinel;
      final g = await pumpGatedField(
        tester,
        source,
        (a) => received = a,
        systemUiDeadline: windowDeadline,
      );

      await tester.tap(find.byKey(const ValueKey('feedback-add-screenshot')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('feedback-attachment-consent-continue')));
      await tester.pump();
      expect(source.pickCalls, 1, reason: 'the picker is now "open"');

      // The picker never returns in time; the window's own bound fires and
      // re-locks the gate while it is still awaited (#65 U1; KTD5).
      g.timers.fireWithDelay(windowDeadline);
      expect(g.gateController.locked, isTrue);

      // The platform now hands back a (stale) successful pick, after the
      // gate already re-locked.
      source.hold!.complete(_makeAttachment(filename: 'stale.png'));
      await tester.pumpAndSettle();

      expect(received, same(sentinel),
          reason: 'onChanged must never fire for a pick that belongs to a '
              'session the gate already closed');
      expect(find.byKey(const ValueKey('feedback-attachment-selected')), findsNothing);
    });
  });
}
