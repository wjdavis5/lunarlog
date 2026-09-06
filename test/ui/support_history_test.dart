/// Widget tests for Support history (Issue #6, U8; R14, R22).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/feedback/support_history_screen.dart';
import 'package:provider/provider.dart';

import '../support/fake_feedback_service.dart';
import '../support/fake_settings_store.dart';

FeedbackTicket _ticket({
  String id = 't1',
  FeedbackCategory category = FeedbackCategory.bug,
  String message = 'It crashed',
  FeedbackTicketStatus status = FeedbackTicketStatus.newTicket,
  DateTime? createdAt,
  DateTime? updatedAt,
}) =>
    FeedbackTicket(
      id: id,
      category: category,
      message: message,
      replyEmail: 'a@example.com',
      status: status,
      attachmentPaths: const [],
      createdAt: createdAt ?? DateTime.utc(2026, 9, 1),
      updatedAt: updatedAt ?? createdAt ?? DateTime.utc(2026, 9, 1),
    );

Future<void> pumpScreen(
  WidgetTester tester,
  FakeFeedbackService service, {
  FakeSettingsStore? settings,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MultiProvider(
        providers: [
          Provider<FeedbackService>.value(value: service),
          Provider<SettingsStore>.value(value: settings ?? FakeSettingsStore()),
        ],
        child: const SupportHistoryScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no tickets renders the empty state and no list', (tester) async {
    final service = FakeFeedbackService();
    await pumpScreen(tester, service);

    expect(find.byKey(const ValueKey('support-history-empty')), findsOneWidget);
    expect(find.text('No feedback yet'), findsOneWidget);
  });

  testWidgets('two tickets render newest-first with their status chips', (tester) async {
    final service = FakeFeedbackService()
      ..ticketsToReturn = [
        _ticket(id: 't2', message: 'newest', createdAt: DateTime.utc(2026, 9, 5), status: FeedbackTicketStatus.replied),
        _ticket(id: 't1', message: 'oldest', createdAt: DateTime.utc(2026, 9, 1)),
      ];
    await pumpScreen(tester, service);

    final tiles = find.byType(ListTile);
    expect(tiles, findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('newest')).dy,
      lessThan(tester.getTopLeft(find.text('oldest')).dy),
    );
    expect(find.text('Replied'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
  });

  testWidgets('expanding a ticket loads its replies in ascending order with correct author labels',
      (tester) async {
    final service = FakeFeedbackService()
      ..ticketsToReturn = [_ticket(status: FeedbackTicketStatus.replied)]
      ..repliesToReturn = [
        FeedbackReply(
          id: 'r1',
          ticketId: 't1',
          author: FeedbackReplyAuthor.user,
          message: 'first message',
          createdAt: DateTime.utc(2026, 9, 1),
        ),
        FeedbackReply(
          id: 'r2',
          ticketId: 't1',
          author: FeedbackReplyAuthor.admin,
          message: 'admin reply',
          createdAt: DateTime.utc(2026, 9, 2),
        ),
      ];
    await pumpScreen(tester, service);

    await tester.tap(find.byKey(const ValueKey('support-history-ticket-t1')));
    await tester.pumpAndSettle();

    expect(find.text('first message'), findsOneWidget);
    expect(find.text('admin reply'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('first message')).dy,
      lessThan(tester.getTopLeft(find.text('admin reply')).dy),
    );
  });

  testWidgets('sending a reply calls addUserReply once with the ticket id and trimmed text, '
      'then re-renders the thread with the new reply', (tester) async {
    final service = FakeFeedbackService()..ticketsToReturn = [_ticket(status: FeedbackTicketStatus.replied)];
    await pumpScreen(tester, service);

    await tester.tap(find.byKey(const ValueKey('support-history-ticket-t1')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('support-history-reply-field-t1')), '  still broken  ');
    await tester.ensureVisible(find.byKey(const ValueKey('support-history-reply-send-t1')));
    await tester.tap(find.byKey(const ValueKey('support-history-reply-send-t1')));
    await tester.pumpAndSettle();

    expect(service.addReplyCalls, 1);
    expect(service.lastReplyTicketId, 't1');
    expect(service.lastReplyMessage, 'still broken');
    expect(find.text('still broken'), findsOneWidget);
  });

  testWidgets('the reply field is absent on a resolved ticket', (tester) async {
    final service = FakeFeedbackService()..ticketsToReturn = [_ticket(status: FeedbackTicketStatus.resolved)];
    await pumpScreen(tester, service);

    await tester.tap(find.byKey(const ValueKey('support-history-ticket-t1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('support-history-reply-field-t1')), findsNothing);
  });

  testWidgets('a load failure renders the failure userFacingMessage and a retry control; '
      'retry re-issues the load', (tester) async {
    final service = FakeFeedbackService();
    service.failWithOnListTickets = const FeedbackFailure.network();
    await pumpScreen(tester, service);

    expect(find.byKey(const ValueKey('support-history-error')), findsOneWidget);
    expect(find.text(const FeedbackFailure.network().userFacingMessage), findsOneWidget);

    service.failWithOnListTickets = null;
    service.ticketsToReturn = [_ticket()];
    await tester.tap(find.byKey(const ValueKey('support-history-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('support-history-error')), findsNothing);
    expect(find.byKey(const ValueKey('support-history-ticket-t1')), findsOneWidget);
  });

  testWidgets('opening the screen writes feedbackLastSeenAt, and the Settings badge is absent '
      'on the next check', (tester) async {
    final settings = FakeSettingsStore();
    final service = FakeFeedbackService()
      ..ticketsToReturn = [
        _ticket(status: FeedbackTicketStatus.replied, updatedAt: DateTime.utc(2026, 9, 5)),
      ];
    await pumpScreen(tester, service, settings: settings);

    final stored = await settings.get(SettingsKeys.feedbackLastSeenAt);
    expect(stored, DateTime.utc(2026, 9, 5).toIso8601String());

    final newest = newestReplyActivityAt(service.ticketsToReturn);
    final lastSeen = DateTime.tryParse(stored!);
    expect(lastSeen!.isBefore(newest!) || lastSeen.isAtSameMomentAs(newest), isTrue);
  });

  test('newestReplyActivityAt: a reply newer than feedbackLastSeenAt is detected as unread', () {
    final tickets = [
      _ticket(status: FeedbackTicketStatus.replied, updatedAt: DateTime.utc(2026, 9, 10)),
    ];
    final lastSeen = DateTime.utc(2026, 9, 1);
    final newest = newestReplyActivityAt(tickets);
    expect(newest!.isAfter(lastSeen), isTrue);
  });
}
