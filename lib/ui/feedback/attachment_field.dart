/// Optional screenshot attachment field (Issue #6, U7; R5, R10, R16).
/// Presents an explicit consent step before invoking [AttachmentSource]
/// (`lib/ui/account/upload_consent_screen.dart`'s framing), enforces the
/// client-side caps (one image, 5 MiB, PNG/JPEG/WebP) before ever handing
/// the attachment to the caller, and never renders a preview thumbnail —
/// only the filename and size — so the sheet itself cannot display health
/// content behind a lock screen.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/app_lifecycle.dart' show GateController;
import 'package:lunarlog/domain/feedback/feedback_service.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:provider/provider.dart';

const Set<String> kAllowedAttachmentMimeTypes = {'image/png', 'image/jpeg', 'image/webp'};

class AttachmentField extends StatefulWidget {
  const AttachmentField({super.key, required this.source, required this.onChanged});

  final AttachmentSource source;

  /// Called with the current attachment (or null when removed/rejected)
  /// every time the selection changes.
  final ValueChanged<FeedbackAttachment?> onChanged;

  @override
  State<AttachmentField> createState() => _AttachmentFieldState();
}

class _AttachmentFieldState extends State<AttachmentField> {
  FeedbackAttachment? _attachment;
  String? _error;

  /// Runs [action] inside the gate's system-UI window when a gate is in
  /// scope (mirrors `sign_in_screen.dart`'s `_duringProviderUi`; #65 U2;
  /// KTD6), so the platform image picker opened by [AttachmentSource]
  /// cannot re-lock the app mid-pick and strand the operator at the lock
  /// screen. The gate is read nullably: harnesses that mount this widget
  /// without one have nothing to suppress anyway.
  Future<T> _duringSystemUi<T>(Future<T> Function() action) {
    final gate = context.read<GateController?>();
    return gate == null ? action() : gate.duringSystemUi(action);
  }

  /// Clears any attachment, shows [message], and reports the removal to the
  /// caller — the one recoverable-rejection outcome every cap shares.
  void _rejectWith(String message) {
    setState(() {
      _attachment = null;
      _error = message;
    });
    widget.onChanged(null);
  }

  /// Applies the post-read caps (5 MiB, PNG/JPEG/WebP) to a pick that has
  /// already crossed into Dart — the belt-and-braces twin of the source's
  /// pre-read length rejection (#207): the source check keeps oversized
  /// files from ever being read, and this one still guards sources that
  /// bypass it. Returns the attachment unchanged, or null after having
  /// shown the rejection.
  FeedbackAttachment? _validate(FeedbackAttachment picked) {
    if (picked.sizeBytes > kMaxAttachmentBytes) {
      _rejectWith('That image is too large. Choose one under 5 MB.');
      return null;
    }
    if (!kAllowedAttachmentMimeTypes.contains(picked.mimeType)) {
      _rejectWith('That file type is not supported. Choose a PNG, JPEG, or WebP image.');
      return null;
    }
    return picked;
  }

  Future<void> _addScreenshot() async {
    // Captured before the first `await` (the consent dialog itself is not a
    // gate-suppressed system-UI window), so this is a synchronous
    // `BuildContext` read rather than one crossing an async gap. Compared
    // again once the picker resolves — see the comment at that check.
    final gate = context.read<GateController?>();
    final generation = gate?.generation;

    final consented = await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: kRouteAttachmentConsentDialog),
      builder: (context) => AlertDialog(
        title: const Text('Attach a screenshot?'),
        content: const Text(
          'Screenshots of this app usually contain cycle data for a family '
          'member. Only attach one if it helps explain the issue.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('feedback-attachment-consent-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('feedback-attachment-consent-continue'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (consented != true) return;

    // Mirrors the generation guard `unlock()`/`reauthenticate()` run on their
    // own credential prompts (`app_lifecycle.dart`'s `GateController`): if
    // the system-UI deadline fires and re-locks the gate while the platform
    // picker is still open, `_duringSystemUi` still lets the pick resolve,
    // but its result belongs to a session the gate already closed and must
    // not be stored into the form behind the (now re-locked) screen.
    FeedbackAttachment? picked;
    try {
      picked = await _duringSystemUi(widget.source.pickImage);
    } on AttachmentTooLargeException {
      // The source rejected the pick on the file's length *before* reading
      // its bytes (#207). Same recoverable copy as the post-read cap in
      // `_validate`, which stays as the guard for sources that bypass the
      // pre-read check.
      if (gate != null && gate.generation != generation) return;
      _rejectWith('That image is too large. Choose one under 5 MB.');
      return;
    }
    if (gate != null && gate.generation != generation) return;
    if (picked == null) return;

    final validated = _validate(picked);
    if (validated == null) return;

    setState(() {
      _attachment = validated;
      _error = null;
    });
    widget.onChanged(validated);
  }

  void _remove() {
    setState(() {
      _attachment = null;
      _error = null;
    });
    widget.onChanged(null);
  }

  String _sizeLabel(int bytes) => '${(bytes / 1024).ceil()} KB';

  @override
  Widget build(BuildContext context) {
    final attachment = _attachment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (attachment == null)
          OutlinedButton.icon(
            key: const ValueKey('feedback-add-screenshot'),
            onPressed: _addScreenshot,
            icon: const Icon(Icons.attach_file),
            label: const Text('Add screenshot'),
          )
        else
          ListTile(
            key: const ValueKey('feedback-attachment-selected'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.image_outlined),
            title: Text(attachment.filename),
            subtitle: Text(_sizeLabel(attachment.sizeBytes)),
            trailing: IconButton(
              key: const ValueKey('feedback-attachment-remove'),
              icon: const Icon(Icons.close),
              tooltip: 'Remove attachment',
              onPressed: _remove,
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _error!,
              key: const ValueKey('feedback-attachment-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
