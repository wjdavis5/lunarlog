/// Domain interface and data models for in-app feedback (Issue #6, U3).
///
/// Pure Dart: no Flutter and no Supabase types cross this boundary.
library;

import 'package:meta/meta.dart';

/// Element-wise string-list equality shared by [DeviceDiagnostics] and
/// [FeedbackTicket]'s `==`, factored out so each stays a single expression
/// under the CRAP gate's per-method complexity threshold.
bool _sameStrings(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The four feedback categories the server's check constraint accepts
/// (KTD3-adjacent; see `feedback_tickets_category_check`).
enum FeedbackCategory {
  bug,
  featureRequest,
  support,
  other;

  /// The exact string the server column stores.
  String toDb() => switch (this) {
        FeedbackCategory.bug => 'bug',
        FeedbackCategory.featureRequest => 'feature_request',
        FeedbackCategory.support => 'support',
        FeedbackCategory.other => 'other',
      };

  /// Human-readable label for the form's category selector.
  String get label => switch (this) {
        FeedbackCategory.bug => 'Bug',
        FeedbackCategory.featureRequest => 'Feature request',
        FeedbackCategory.support => 'Support',
        FeedbackCategory.other => 'Other',
      };

  static FeedbackCategory fromDb(String value) => switch (value) {
        'bug' => FeedbackCategory.bug,
        'feature_request' => FeedbackCategory.featureRequest,
        'support' => FeedbackCategory.support,
        'other' => FeedbackCategory.other,
        _ => throw ArgumentError.value(value, 'value', 'unknown feedback category'),
      };
}

/// Server-owned ticket lifecycle (`feedback_tickets.status`); see U1's
/// `feedback_tickets_status_check` and the status-machine triggers.
enum FeedbackTicketStatus {
  newTicket,
  triage,
  replied,
  resolved;

  String toDb() => switch (this) {
        FeedbackTicketStatus.newTicket => 'new',
        FeedbackTicketStatus.triage => 'triage',
        FeedbackTicketStatus.replied => 'replied',
        FeedbackTicketStatus.resolved => 'resolved',
      };

  String get label => switch (this) {
        FeedbackTicketStatus.newTicket => 'New',
        FeedbackTicketStatus.triage => 'In triage',
        FeedbackTicketStatus.replied => 'Replied',
        FeedbackTicketStatus.resolved => 'Resolved',
      };

  static FeedbackTicketStatus fromDb(String value) => switch (value) {
        'new' => FeedbackTicketStatus.newTicket,
        'triage' => FeedbackTicketStatus.triage,
        'replied' => FeedbackTicketStatus.replied,
        'resolved' => FeedbackTicketStatus.resolved,
        _ => throw ArgumentError.value(value, 'value', 'unknown feedback ticket status'),
      };
}

/// Who authored a [FeedbackReply]; see U1's `feedback_replies_author_type_check`.
enum FeedbackReplyAuthor {
  user,
  admin;

  String toDb() => switch (this) {
        FeedbackReplyAuthor.user => 'user',
        FeedbackReplyAuthor.admin => 'admin',
      };

  String get label => switch (this) {
        FeedbackReplyAuthor.user => 'You',
        FeedbackReplyAuthor.admin => 'Support',
      };

  static FeedbackReplyAuthor fromDb(String value) => switch (value) {
        'user' => FeedbackReplyAuthor.user,
        'admin' => FeedbackReplyAuthor.admin,
        _ => throw ArgumentError.value(value, 'value', 'unknown feedback reply author'),
      };
}

/// Diagnostics payload (R7/R8/R9/R10): every key [toJson] emits is one of the
/// KTD3 server allowlist keys, and [previewLines] is exactly what the form
/// shows the operator before submission (R10).
@immutable
class DeviceDiagnostics {
  const DeviceDiagnostics({
    required this.os,
    required this.osVersion,
    required this.model,
    required this.appVersion,
    required this.buildNumber,
    required this.locale,
    required this.breadcrumbs,
  });

  final String os;
  final String osVersion;
  final String model;
  final String appVersion;
  final String buildNumber;
  final String locale;

  /// Formatted breadcrumb lines (already reduced to a category and a name by
  /// [BreadcrumbLog]; never a `data` map). At most 25 entries.
  final List<String> breadcrumbs;

  /// Emits exactly the seven KTD3 allowlist keys, never more.
  Map<String, Object?> toJson() => {
        'os': os,
        'os_version': osVersion,
        'model': model,
        'app_version': appVersion,
        'build_number': buildNumber,
        'locale': locale,
        'breadcrumbs': breadcrumbs,
      };

  /// Human-readable lines for the diagnostics preview panel (R10): the
  /// operator sees exactly this before choosing to submit it.
  List<String> previewLines() => [
        'OS: $os $osVersion',
        'Device: $model',
        'App version: $appVersion ($buildNumber)',
        'Locale: $locale',
        if (breadcrumbs.isEmpty)
          'Recent activity: none recorded'
        else
          'Recent activity (${breadcrumbs.length}):',
        ...breadcrumbs,
      ];

  @override
  bool operator ==(Object other) =>
      other is DeviceDiagnostics &&
      (os, osVersion, model, appVersion, buildNumber, locale) ==
          (other.os, other.osVersion, other.model, other.appVersion, other.buildNumber, other.locale) &&
      _sameStrings(breadcrumbs, other.breadcrumbs);

  @override
  int get hashCode => Object.hash(
        os,
        osVersion,
        model,
        appVersion,
        buildNumber,
        locale,
        Object.hashAll(breadcrumbs),
      );
}

/// An optional screenshot attachment (U7): bytes plus enough metadata to
/// name and upload the object. Never carries a preview thumbnail path — the
/// UI shows filename and size only (U7 approach), so nothing here implies a
/// rendered preview.
@immutable
class FeedbackAttachment {
  const FeedbackAttachment({
    required this.bytes,
    required this.mimeType,
    required this.filename,
  });

  final List<int> bytes;
  final String mimeType;
  final String filename;

  int get sizeBytes => bytes.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeedbackAttachment &&
          runtimeType == other.runtimeType &&
          mimeType == other.mimeType &&
          filename == other.filename &&
          sizeBytes == other.sizeBytes;

  @override
  int get hashCode => Object.hash(mimeType, filename, sizeBytes);
}

/// A submitted feedback ticket, as read back from the server.
@immutable
class FeedbackTicket {
  const FeedbackTicket({
    required this.id,
    required this.category,
    required this.message,
    required this.replyEmail,
    required this.status,
    required this.attachmentPaths,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final FeedbackCategory category;
  final String message;
  final String replyEmail;
  final FeedbackTicketStatus status;
  final List<String> attachmentPaths;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      other is FeedbackTicket &&
      (id, category, message, replyEmail, status, createdAt, updatedAt) ==
          (other.id, other.category, other.message, other.replyEmail, other.status, other.createdAt,
              other.updatedAt) &&
      _sameStrings(attachmentPaths, other.attachmentPaths);

  @override
  int get hashCode => Object.hash(
        id,
        category,
        message,
        replyEmail,
        status,
        Object.hashAll(attachmentPaths),
        createdAt,
        updatedAt,
      );
}

/// One message in a ticket's thread.
@immutable
class FeedbackReply {
  const FeedbackReply({
    required this.id,
    required this.ticketId,
    required this.author,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String ticketId;
  final FeedbackReplyAuthor author;
  final String message;
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeedbackReply &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          ticketId == other.ticketId &&
          author == other.author &&
          message == other.message &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(id, ticketId, author, message, createdAt);
}

/// Typed failures for feedback operations. [userFacingMessage] never echoes
/// a raw provider error (R11); [toString] carries only the case name.
@immutable
sealed class FeedbackFailure implements Exception {
  const FeedbackFailure();

  const factory FeedbackFailure.network() = FeedbackNetworkFailure;
  const factory FeedbackFailure.unauthorized() = FeedbackUnauthorizedFailure;
  const factory FeedbackFailure.rateLimited() = FeedbackRateLimitedFailure;
  const factory FeedbackFailure.invalidInput() = FeedbackInvalidInputFailure;
  const factory FeedbackFailure.attachmentTooLarge() = FeedbackAttachmentTooLargeFailure;
  const factory FeedbackFailure.attachmentRejected() = FeedbackAttachmentRejectedFailure;
  const factory FeedbackFailure.notFound() = FeedbackNotFoundFailure;
  const factory FeedbackFailure.other() = FeedbackOtherFailure;

  String get userFacingMessage;

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class FeedbackNetworkFailure extends FeedbackFailure {
  const FeedbackNetworkFailure();
  @override
  String get userFacingMessage =>
      'Could not reach the server. Check your connection and try again.';
  @override
  String toString() => 'FeedbackFailure.network';
}

final class FeedbackUnauthorizedFailure extends FeedbackFailure {
  const FeedbackUnauthorizedFailure();
  @override
  String get userFacingMessage => 'You do not have permission for this action.';
  @override
  String toString() => 'FeedbackFailure.unauthorized';
}

final class FeedbackRateLimitedFailure extends FeedbackFailure {
  const FeedbackRateLimitedFailure();
  @override
  String get userFacingMessage =>
      "You've sent a few reports already — please try again in a bit.";
  @override
  String toString() => 'FeedbackFailure.rateLimited';
}

final class FeedbackInvalidInputFailure extends FeedbackFailure {
  const FeedbackInvalidInputFailure();
  @override
  String get userFacingMessage => 'Check your message and try again.';
  @override
  String toString() => 'FeedbackFailure.invalidInput';
}

final class FeedbackAttachmentTooLargeFailure extends FeedbackFailure {
  const FeedbackAttachmentTooLargeFailure();
  @override
  String get userFacingMessage => 'That image is too large. Choose one under 5 MB.';
  @override
  String toString() => 'FeedbackFailure.attachmentTooLarge';
}

final class FeedbackAttachmentRejectedFailure extends FeedbackFailure {
  const FeedbackAttachmentRejectedFailure();
  @override
  String get userFacingMessage =>
      'That file type is not supported. Choose a PNG, JPEG, or WebP image.';
  @override
  String toString() => 'FeedbackFailure.attachmentRejected';
}

final class FeedbackNotFoundFailure extends FeedbackFailure {
  const FeedbackNotFoundFailure();
  @override
  String get userFacingMessage => 'That ticket could not be found.';
  @override
  String toString() => 'FeedbackFailure.notFound';
}

final class FeedbackOtherFailure extends FeedbackFailure {
  const FeedbackOtherFailure();
  @override
  String get userFacingMessage => 'Something went wrong. Please try again.';
  @override
  String toString() => 'FeedbackFailure.other';
}

/// Thrown by `SupabaseFeedbackService.submitTicket` when the ticket insert
/// already committed but the follow-on attachment upload then failed. A bare
/// rethrow of [attachmentFailure] at that point would read to the caller as
/// total failure — nothing saved — and send the operator retyping their
/// message and resubmitting straight into R17's 5/hour rate limit with a
/// duplicate ticket. Carrying the already-created [ticket] instead makes the
/// failure atomic *in effect*: the caller always knows the message was
/// received and the ticket is recoverable (it already exists, without the
/// attachment, and is visible in Support history) rather than orphaned and
/// silent.
final class FeedbackAttachmentUploadFailedFailure extends FeedbackFailure {
  const FeedbackAttachmentUploadFailedFailure(this.ticket, this.attachmentFailure);

  /// The ticket the insert already committed, before the attachment step
  /// failed.
  final FeedbackTicket ticket;

  /// The mapped (never-raw; R11) failure the attachment upload raised.
  final FeedbackFailure attachmentFailure;

  @override
  String get userFacingMessage =>
      'Your message was sent — no need to resend it. The attachment did '
      'not upload (${attachmentFailure.userFacingMessage}) You can find '
      'your ticket in Support history.';
  @override
  String toString() => 'FeedbackFailure.attachmentUploadFailed';
}

/// Plugin-facing seam for picking a screenshot to attach (U7). The concrete
/// adapter (`ImagePickerAttachmentSource`) is the only untestable-under-
/// `flutter-test` piece; this interface itself stays pure Dart.
abstract interface class AttachmentSource {
  /// Shows the platform image picker and returns the selected image, or
  /// null when the operator cancelled.
  Future<FeedbackAttachment?> pickImage();
}

/// Contract for submitting feedback and reading the resulting thread.
abstract interface class FeedbackService {
  /// Submits a new ticket (R1-R6, R21). [diagnostics] is omitted entirely
  /// when the operator switched the diagnostics toggle off (R10).
  Future<FeedbackTicket> submitTicket({
    required FeedbackCategory category,
    required String message,
    required String replyEmail,
    DeviceDiagnostics? diagnostics,
    FeedbackAttachment? attachment,
  });

  /// The caller's own tickets, newest first (R22).
  Future<List<FeedbackTicket>> listTickets();

  /// A ticket's reply thread, oldest first (R22).
  Future<List<FeedbackReply>> listReplies(String ticketId);

  /// Adds a `user`-authored reply to an open thread (R14, R22).
  Future<FeedbackReply> addUserReply({
    required String ticketId,
    required String message,
  });

  /// A short-lived signed URL for a private attachment object path.
  Future<String> signedAttachmentUrl(String path);
}
