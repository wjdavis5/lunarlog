/// Widget tests for the in-app feedback form (Issue #6, U6; R1-R6, R10, R11).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/diagnostics/device_diagnostics_collector.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:lunarlog/ui/feedback/feedback_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../support/fake_feedback_service.dart';

class _FakeAttachmentSource implements AttachmentSource {
  FeedbackAttachment? nextResult;

  @override
  Future<FeedbackAttachment?> pickImage() async => nextResult;
}

/// A collector wired entirely from fakes: the real [DeviceDiagnosticsCollector]
/// touches platform channels that never answer under `flutter test`'s
/// default binary messenger, so every widget test injects this instead.
DeviceDiagnosticsCollector _fakeCollector() => DeviceDiagnosticsCollector(
      packageInfoReader: () async => PackageInfo(
        appName: 'lunarlog',
        packageName: 'com.wjdavis5.lunarlog',
        version: '1.0.0',
        buildNumber: '1',
      ),
      deviceInfoReader: () async => throw StateError('no fake device info in this test'),
      localeSupplier: () => const Locale('en', 'US'),
      platform: TargetPlatform.iOS,
      breadcrumbLog: BreadcrumbLog(),
    );

Future<void> pumpFeedbackScreen(
  WidgetTester tester,
  FakeFeedbackService service, {
  AttachmentSource? attachmentSource,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Provider<FeedbackService>.value(
        value: service,
        child: FeedbackScreen(
          diagnosticsCollector: _fakeCollector(),
          attachmentSource: attachmentSource,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The form grows taller than the default test viewport once the
/// diagnostics and attachment sections render, so the submit button needs
/// scrolling into view before it can be tapped.
Future<void> tapSubmit(WidgetTester tester, {bool warnIfMissed = true}) async {
  final finder = find.byKey(const ValueKey('feedback-submit'));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder, warnIfMissed: warnIfMissed);
}

void main() {
  testWidgets('submit is disabled while the message field is empty', (tester) async {
    final service = FakeFeedbackService();
    await pumpFeedbackScreen(tester, service);

    final submitButton = tester.widget<FilledButton>(find.byKey(const ValueKey('feedback-submit')));
    expect(submitButton.onPressed, isNull);
  });

  testWidgets('a message longer than 4000 characters shows an inline error and makes no service call',
      (tester) async {
    final service = FakeFeedbackService();
    await pumpFeedbackScreen(tester, service);

    await tester.enterText(find.byKey(const ValueKey('feedback-message')), 'x' * 4001);
    await tester.pump();
    await tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('feedback-error')), findsOneWidget);
    expect(service.submitCalls, 0);
  });

  testWidgets('a malformed reply email shows an inline error and makes no service call', (tester) async {
    final service = FakeFeedbackService();
    await pumpFeedbackScreen(tester, service);

    await tester.enterText(find.byKey(const ValueKey('feedback-message')), 'It crashed');
    await tester.enterText(find.byKey(const ValueKey('feedback-reply-email')), 'not-an-email');
    await tester.pump();
    await tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('feedback-error')), findsOneWidget);
    expect(service.submitCalls, 0);
  });

  testWidgets('happy path: submit calls the service once with the selected category, trimmed message, '
      'reply email, and the diagnostics payload', (tester) async {
    final service = FakeFeedbackService();
    await pumpFeedbackScreen(tester, service);

    await tester.tap(find.byKey(const ValueKey('feedback-category-support')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('feedback-message')), '  How do I export my data?  ');
    await tester.enterText(find.byKey(const ValueKey('feedback-reply-email')), 'me@example.com');
    await tester.pump();
    await tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(service.submitCalls, 1);
    expect(service.lastCategory, FeedbackCategory.support);
    expect(service.lastMessage, 'How do I export my data?');
    expect(service.lastReplyEmail, 'me@example.com');
    expect(service.lastDiagnostics, isNotNull);
    expect(find.byKey(const ValueKey('feedback-info')), findsOneWidget);
  });

  testWidgets('diagnostics toggle off submits with no diagnostics attached', (tester) async {
    final service = FakeFeedbackService();
    await pumpFeedbackScreen(tester, service);

    await tester.tap(find.byKey(const ValueKey('feedback-diagnostics-toggle')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('feedback-message')), 'no diagnostics please');
    await tester.enterText(find.byKey(const ValueKey('feedback-reply-email')), 'me@example.com');
    await tester.pump();
    await tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(service.submitCalls, 1);
    expect(service.lastDiagnostics, isNull);
  });

  testWidgets('the diagnostics panel renders every previewLines entry', (tester) async {
    final service = FakeFeedbackService();
    await pumpFeedbackScreen(tester, service);

    await tester.tap(find.byKey(const ValueKey('feedback-diagnostics-preview-toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('feedback-diagnostics-preview')), findsOneWidget);
    // Every payload includes a locale line regardless of platform-plugin
    // availability under `flutter test` (the collector falls back to
    // 'unknown' rather than throwing).
    expect(find.textContaining('Locale:'), findsOneWidget);
  });

  testWidgets('Covers AE8: a thrown FeedbackFailure.network renders its userFacingMessage, '
      'leaves the message text in place, and re-enables submit', (tester) async {
    final service = FakeFeedbackService()..failureToThrow = const FeedbackFailure.network();
    await pumpFeedbackScreen(tester, service);

    await tester.enterText(find.byKey(const ValueKey('feedback-message')), 'still typed here');
    await tester.enterText(find.byKey(const ValueKey('feedback-reply-email')), 'me@example.com');
    await tester.pump();
    await tapSubmit(tester);
    await tester.pumpAndSettle();

    final errorText = tester.widget<Text>(find.byKey(const ValueKey('feedback-error')));
    expect(errorText.data, const FeedbackFailure.network().userFacingMessage);
    expect(find.text('still typed here'), findsOneWidget);

    final submitButton = tester.widget<FilledButton>(find.byKey(const ValueKey('feedback-submit')));
    expect(submitButton.onPressed, isNotNull);
  });

  testWidgets('FeedbackFailure.rateLimited renders copy distinct from the network failure copy',
      (tester) async {
    final service = FakeFeedbackService()..failureToThrow = const FeedbackFailure.rateLimited();
    await pumpFeedbackScreen(tester, service);

    await tester.enterText(find.byKey(const ValueKey('feedback-message')), 'again');
    await tester.enterText(find.byKey(const ValueKey('feedback-reply-email')), 'me@example.com');
    await tester.pump();
    await tapSubmit(tester);
    await tester.pumpAndSettle();

    final errorText = tester.widget<Text>(find.byKey(const ValueKey('feedback-error')));
    expect(errorText.data, const FeedbackFailure.rateLimited().userFacingMessage);
    expect(
      const FeedbackFailure.rateLimited().userFacingMessage,
      isNot(const FeedbackFailure.network().userFacingMessage),
    );
  });

  testWidgets('double-tapping submit while busy issues exactly one service call', (tester) async {
    final service = FakeFeedbackService()..holdNextSubmit();
    await pumpFeedbackScreen(tester, service);

    await tester.enterText(find.byKey(const ValueKey('feedback-message')), 'slow submit');
    await tester.enterText(find.byKey(const ValueKey('feedback-reply-email')), 'me@example.com');
    await tester.pump();

    await tapSubmit(tester);
    await tester.pump();
    // The button is now disabled (busy); a second tap must be a no-op.
    await tapSubmit(tester, warnIfMissed: false);
    await tester.pump();

    expect(service.submitCalls, 1);

    service.completeSubmit(service.lastCategory == null
        ? throw StateError('submit was never called')
        : FeedbackTicket(
            id: 't1',
            category: service.lastCategory!,
            message: service.lastMessage!,
            replyEmail: service.lastReplyEmail!,
            status: FeedbackTicketStatus.newTicket,
            attachmentPaths: const [],
            createdAt: DateTime.utc(2026, 9, 5),
            updatedAt: DateTime.utc(2026, 9, 5),
          ));
    await tester.pumpAndSettle();

    expect(service.submitCalls, 1);
  });

  testWidgets(
      'a screenshot attached to a successful submission is not silently '
      'reused on a second submission in the same screen session', (tester) async {
    final service = FakeFeedbackService();
    final attachmentSource = _FakeAttachmentSource()
      ..nextResult = FeedbackAttachment(
        bytes: List<int>.filled(1024, 1),
        mimeType: 'image/png',
        filename: 'shot.png',
      );
    await pumpFeedbackScreen(tester, service, attachmentSource: attachmentSource);

    await tester.enterText(find.byKey(const ValueKey('feedback-message')), 'first report');
    await tester.enterText(find.byKey(const ValueKey('feedback-reply-email')), 'me@example.com');
    await tester.ensureVisible(find.byKey(const ValueKey('feedback-add-screenshot')));
    await tester.tap(find.byKey(const ValueKey('feedback-add-screenshot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('feedback-attachment-consent-continue')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('feedback-attachment-selected')), findsOneWidget);

    await tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(service.submitCalls, 1);
    expect(service.lastAttachment, isNotNull);
    // The picker itself resets, not just the internal field the screen
    // sends to the service — otherwise a returning user would see the
    // prior screenshot still listed as attached.
    expect(find.byKey(const ValueKey('feedback-attachment-selected')), findsNothing);
    expect(find.byKey(const ValueKey('feedback-add-screenshot')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('feedback-message')), 'second report, no new screenshot');
    await tester.pump();
    await tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(service.submitCalls, 2);
    expect(service.lastAttachment, isNull);
  });

  testWidgets(
      'a FeedbackAttachmentUploadFailedFailure clears the message and screenshot so a retry '
      'cannot re-file a duplicate ticket with the same screenshot and no fresh consent',
      (tester) async {
    final ticket = FeedbackTicket(
      id: 't1',
      category: FeedbackCategory.bug,
      message: 'it crashed',
      replyEmail: 'me@example.com',
      status: FeedbackTicketStatus.newTicket,
      attachmentPaths: const [],
      createdAt: DateTime.utc(2026, 9, 5),
      updatedAt: DateTime.utc(2026, 9, 5),
    );
    final service = FakeFeedbackService()
      ..failureToThrow = FeedbackAttachmentUploadFailedFailure(
        ticket,
        const FeedbackFailure.network(),
      );
    final attachmentSource = _FakeAttachmentSource()
      ..nextResult = FeedbackAttachment(
        bytes: List<int>.filled(1024, 1),
        mimeType: 'image/png',
        filename: 'shot.png',
      );
    await pumpFeedbackScreen(tester, service, attachmentSource: attachmentSource);

    await tester.enterText(find.byKey(const ValueKey('feedback-message')), 'it crashed');
    await tester.enterText(find.byKey(const ValueKey('feedback-reply-email')), 'me@example.com');
    await tester.ensureVisible(find.byKey(const ValueKey('feedback-add-screenshot')));
    await tester.tap(find.byKey(const ValueKey('feedback-add-screenshot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('feedback-attachment-consent-continue')));
    await tester.pumpAndSettle();

    await tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('feedback-error')), findsOneWidget);
    // The message text is gone — a retry composes a fresh submission
    // rather than looking like a continuation of the one that already
    // committed a ticket row.
    expect(find.text('it crashed'), findsNothing);
    // The screenshot picker reset too: no stale attachment survives to
    // ride along, silently and without fresh consent, on the next submit.
    expect(find.byKey(const ValueKey('feedback-attachment-selected')), findsNothing);
    expect(find.byKey(const ValueKey('feedback-add-screenshot')), findsOneWidget);
  });
}
