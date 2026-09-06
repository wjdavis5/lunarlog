/// In-app feedback UI state (Issue #6, U6): a `ChangeNotifier` wrapping
/// [FeedbackService] and [DeviceDiagnosticsCollector], shaped like
/// `lib/ui/account/sync_status_controller.dart` over its domain service.
library;

import 'package:flutter/foundation.dart';
import 'package:lunarlog/data/diagnostics/device_diagnostics_collector.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';

class FeedbackController extends ChangeNotifier {
  FeedbackController({
    required FeedbackService feedbackService,
    required DeviceDiagnosticsCollector diagnosticsCollector,
  })  : _service = feedbackService,
        _collector = diagnosticsCollector;

  final FeedbackService _service;
  final DeviceDiagnosticsCollector _collector;

  DeviceDiagnostics? _diagnostics;

  /// The collected diagnostics payload, once [loadDiagnostics] has
  /// completed; null before that (R10's preview has nothing to show yet).
  DeviceDiagnostics? get diagnostics => _diagnostics;

  /// Collects the current diagnostics payload for the form's preview panel
  /// (R10). Safe to call multiple times; the collector itself never throws.
  Future<void> loadDiagnostics() async {
    _diagnostics = await _collector.collect();
    notifyListeners();
  }

  /// Submits a ticket. [includeDiagnostics] governs whether the already
  /// -collected [diagnostics] payload rides along (R10); an attachment is
  /// opt-in (R5).
  Future<FeedbackTicket> submit({
    required FeedbackCategory category,
    required String message,
    required String replyEmail,
    required bool includeDiagnostics,
    FeedbackAttachment? attachment,
  }) {
    return _service.submitTicket(
      category: category,
      message: message,
      replyEmail: replyEmail,
      diagnostics: includeDiagnostics ? _diagnostics : null,
      attachment: attachment,
    );
  }
}
