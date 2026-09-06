/// [FeedbackService] implementation over Supabase PostgREST, Storage, and
/// the `feedback-notify` Edge Function (Issue #6, U5; KTD6, KTD7).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:lunarlog/domain/feedback/feedback_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Bucket the attachment picker (U7) and this service agree on.
const String kFeedbackAttachmentsBucket = 'feedback-attachments';

/// How long a minted signed URL for a private attachment stays valid.
const int kSignedAttachmentUrlTtlSeconds = 300;

class SupabaseFeedbackService implements FeedbackService {
  SupabaseFeedbackService({
    required this.client,
    Uuid? idGenerator,
  }) : _idGenerator = idGenerator ?? const Uuid();

  final SupabaseClient client;
  final Uuid _idGenerator;

  @override
  Future<FeedbackTicket> submitTicket({
    required FeedbackCategory category,
    required String message,
    required String replyEmail,
    DeviceDiagnostics? diagnostics,
    FeedbackAttachment? attachment,
  }) async {
    try {
      final uid = client.auth.currentUser?.id;
      if (uid == null) throw const FeedbackFailure.unauthorized();

      final row = await client
          .from('feedback_tickets')
          .insert({
            'user_id': uid,
            'reply_email': replyEmail,
            'category': category.toDb(),
            'message': message,
            if (diagnostics != null) 'device_info': diagnostics.toJson(),
          })
          .select()
          .single();

      var ticket = _ticketFromRow(row);

      if (attachment != null) {
        ticket = await _attachAndUpdate(ticket, uid, attachment);
      }

      _notifyBestEffort(ticket.id);

      return ticket;
    } catch (error) {
      throw _mapError(error);
    }
  }

  /// Uploads [attachment] under `<uid>/<ticketId>/<uuid>.<ext>` (KTD2) and
  /// records the resulting path on the ticket.
  Future<FeedbackTicket> _attachAndUpdate(
    FeedbackTicket ticket,
    String uid,
    FeedbackAttachment attachment,
  ) async {
    final ext = _extensionFor(attachment.mimeType);
    final objectPath = '$uid/${ticket.id}/${_idGenerator.v4()}$ext';

    await client.storage.from(kFeedbackAttachmentsBucket).uploadBinary(
          objectPath,
          Uint8List.fromList(attachment.bytes),
          fileOptions: FileOptions(contentType: attachment.mimeType),
        );

    final updatedPaths = [...ticket.attachmentPaths, objectPath];
    final row = await client
        .from('feedback_tickets')
        .update({'attachment_paths': updatedPaths, 'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', ticket.id)
        .select()
        .single();

    return _ticketFromRow(row);
  }

  String _extensionFor(String mimeType) => switch (mimeType) {
        'image/png' => '.png',
        'image/jpeg' => '.jpg',
        'image/webp' => '.webp',
        _ => '',
      };

  /// R21: best-effort admin alert. A failure here must never fail the
  /// caller's submission — errors are swallowed entirely.
  void _notifyBestEffort(String ticketId) {
    unawaited(_invokeNotify(ticketId));
  }

  Future<void> _invokeNotify(String ticketId) async {
    try {
      await client.functions.invoke('feedback-notify', body: {'ticket_id': ticketId});
    } catch (error) {
      // Intentionally swallowed (R21's best-effort contract). Logged as a
      // type only, matching the R11 discipline elsewhere in this file.
      debugPrint('lunarlog feedback: notify invocation failed (${error.runtimeType})');
    }
  }

  @override
  Future<List<FeedbackTicket>> listTickets() async {
    try {
      final rows = await client
          .from('feedback_tickets')
          .select()
          .order('created_at', ascending: false);
      return [for (final row in rows) _ticketFromRow(row)];
    } catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<List<FeedbackReply>> listReplies(String ticketId) async {
    try {
      final rows = await client
          .from('feedback_replies')
          .select()
          .eq('ticket_id', ticketId)
          .order('created_at', ascending: true);
      return [for (final row in rows) _replyFromRow(row)];
    } catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<FeedbackReply> addUserReply({
    required String ticketId,
    required String message,
  }) async {
    try {
      final row = await client
          .from('feedback_replies')
          .insert({
            'ticket_id': ticketId,
            'author_type': 'user',
            'message': message,
          })
          .select()
          .single();
      return _replyFromRow(row);
    } catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<String> signedAttachmentUrl(String path) async {
    try {
      return await client.storage
          .from(kFeedbackAttachmentsBucket)
          .createSignedUrl(path, kSignedAttachmentUrlTtlSeconds);
    } catch (error) {
      throw _mapError(error);
    }
  }

  FeedbackTicket _ticketFromRow(Map<String, dynamic> row) => FeedbackTicket(
        id: row['id'] as String,
        category: FeedbackCategory.fromDb(row['category'] as String),
        message: row['message'] as String,
        replyEmail: row['reply_email'] as String,
        status: FeedbackTicketStatus.fromDb(row['status'] as String),
        attachmentPaths: [for (final p in (row['attachment_paths'] as List? ?? const [])) p as String],
        createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
        updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
      );

  FeedbackReply _replyFromRow(Map<String, dynamic> row) => FeedbackReply(
        id: row['id'] as String,
        ticketId: row['ticket_id'] as String,
        author: FeedbackReplyAuthor.fromDb(row['author_type'] as String),
        message: row['message'] as String,
        createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
      );

  /// Extends the `_mapError` ladder from `SupabaseSharingService`
  /// (`lib/data/sharing/supabase_sharing_service.dart`) with `StorageException`
  /// handling. Never surfaces a provider message (R11).
  FeedbackFailure _mapError(Object error) {
    if (error is FeedbackFailure) return error;
    if (error is SocketException || error is http.ClientException) {
      return const FeedbackFailure.network();
    }
    if (error is PostgrestException) return _mapPostgrestError(error);
    if (error is StorageException) return _mapStorageError(error);
    return const FeedbackFailure.other();
  }

  FeedbackFailure _mapPostgrestError(PostgrestException error) {
    final code = error.code ?? '';
    if (code == '42501' || code == 'PGRST301') {
      return const FeedbackFailure.unauthorized();
    }
    if (code == '55000') return const FeedbackFailure.rateLimited();
    if (code == '23514' || code == '22023') return const FeedbackFailure.invalidInput();
    final status = int.tryParse(code);
    if (status != null && status >= 500) return const FeedbackFailure.network();
    return const FeedbackFailure.other();
  }

  FeedbackFailure _mapStorageError(StorageException error) {
    switch (error.statusCode) {
      case '413':
        return const FeedbackFailure.attachmentTooLarge();
      case '415':
      case '400':
        return const FeedbackFailure.attachmentRejected();
      case '401':
      case '403':
        return const FeedbackFailure.unauthorized();
      default:
        return const FeedbackFailure.other();
    }
  }
}
