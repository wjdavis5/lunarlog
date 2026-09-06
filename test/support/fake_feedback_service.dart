import 'dart:async';

import 'package:lunarlog/domain/feedback/feedback_service.dart';

/// Test double for [FeedbackService] (Issue #6, U6/U8). Records the
/// arguments of the most recent [submitTicket] call and can be told to
/// throw, to hang until [completeSubmit] is called, or to answer
/// [listTickets]/[listReplies] with fixed fixtures.
class FakeFeedbackService implements FeedbackService {
  int submitCalls = 0;
  FeedbackCategory? lastCategory;
  String? lastMessage;
  String? lastReplyEmail;
  DeviceDiagnostics? lastDiagnostics;
  FeedbackAttachment? lastAttachment;

  /// When set, the next [submitTicket] call throws this instead of
  /// returning a ticket.
  FeedbackFailure? failureToThrow;

  /// When set, [submitTicket] does not resolve until [completeSubmit] is
  /// called — lets a test observe the busy state mid-flight.
  Completer<FeedbackTicket>? _pending;

  List<FeedbackTicket> ticketsToReturn = const [];
  List<FeedbackReply> repliesToReturn = const [];

  /// When set, [listTickets] throws this instead of returning [ticketsToReturn].
  FeedbackFailure? failWithOnListTickets;

  int addReplyCalls = 0;
  String? lastReplyTicketId;
  String? lastReplyMessage;

  void holdNextSubmit() {
    _pending = Completer<FeedbackTicket>();
  }

  void completeSubmit(FeedbackTicket ticket) {
    _pending?.complete(ticket);
    _pending = null;
  }

  @override
  Future<FeedbackTicket> submitTicket({
    required FeedbackCategory category,
    required String message,
    required String replyEmail,
    DeviceDiagnostics? diagnostics,
    FeedbackAttachment? attachment,
  }) async {
    submitCalls++;
    lastCategory = category;
    lastMessage = message;
    lastReplyEmail = replyEmail;
    lastDiagnostics = diagnostics;
    lastAttachment = attachment;

    final failure = failureToThrow;
    if (failure != null) {
      failureToThrow = null;
      throw failure;
    }

    final pending = _pending;
    if (pending != null) return pending.future;

    return FeedbackTicket(
      id: 't1',
      category: category,
      message: message,
      replyEmail: replyEmail,
      status: FeedbackTicketStatus.newTicket,
      attachmentPaths: const [],
      createdAt: DateTime.utc(2026, 9, 5),
      updatedAt: DateTime.utc(2026, 9, 5),
    );
  }

  @override
  Future<List<FeedbackTicket>> listTickets() async {
    final failure = failWithOnListTickets;
    if (failure != null) throw failure;
    return ticketsToReturn;
  }

  @override
  Future<List<FeedbackReply>> listReplies(String ticketId) async => repliesToReturn;

  @override
  Future<FeedbackReply> addUserReply({
    required String ticketId,
    required String message,
  }) async {
    addReplyCalls++;
    lastReplyTicketId = ticketId;
    lastReplyMessage = message;
    return FeedbackReply(
      id: 'r$addReplyCalls',
      ticketId: ticketId,
      author: FeedbackReplyAuthor.user,
      message: message,
      createdAt: DateTime.utc(2026, 9, 5),
    );
  }

  @override
  Future<String> signedAttachmentUrl(String path) async => 'https://example.com/$path';
}
