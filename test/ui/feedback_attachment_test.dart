/// Widget tests for the optional screenshot attachment field (Issue #6, U7;
/// R5, R10, R16).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';
import 'package:lunarlog/ui/feedback/attachment_field.dart';

class FakeAttachmentSource implements AttachmentSource {
  int pickCalls = 0;
  FeedbackAttachment? nextResult;

  @override
  Future<FeedbackAttachment?> pickImage() async {
    pickCalls++;
    return nextResult;
  }
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
}
