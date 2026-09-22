/// In-app feedback form (Issue #6, U6; R1, R2, R3, R4, R6, R10, R11, R23).
/// Pushed from Settings when a [FeedbackService] is provided. Category
/// chips, a message field, an editable reply email pre-filled from the
/// signed-in account, a diagnostics preview toggle, and the submit action.
///
/// Shaped like `lib/ui/account/sign_in_screen.dart`: the `_run(action)`
/// busy/error/info wrapper, no `Form`/`TextFormField`, imperative validation
/// before the service call, and every field kept intact on an ordinary
/// failure (R6) — except a [FeedbackAttachmentUploadFailedFailure], whose
/// message and attachment are deliberately cleared (see `_run` below).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/feedback/device_diagnostics_collector.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/components/inline_error.dart';
import 'package:lunarlog/ui/feedback/attachment_field.dart';
import 'package:lunarlog/ui/feedback/feedback_controller.dart';
import 'package:lunarlog/ui/l10n/feedback_failure_copy.dart';
import 'package:provider/provider.dart';

/// The support address shown when no feedback form is available (R23).
const String kSupportEmailAddress = 'will@wjdavis5.net';

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({
    super.key,
    @visibleForTesting this.diagnosticsCollector,
    @visibleForTesting this.attachmentSource,
  });

  /// Test seam: the real [DeviceDiagnosticsCollector] touches
  /// `package_info_plus`/`device_info_plus` platform channels that never
  /// answer under `flutter test`'s default binary messenger (no registered
  /// mock), so a widget test that doesn't need real device data injects a
  /// fake collector here instead of hanging.
  @visibleForTesting
  final DeviceDiagnosticsCollector? diagnosticsCollector;

  /// Test seam: defaults to the tree-provided [AttachmentSource] (U7).
  @visibleForTesting
  final AttachmentSource? attachmentSource;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _message = TextEditingController();
  final _replyEmail = TextEditingController();

  late final FeedbackController _controller;
  late final AttachmentSource _attachmentSource;

  FeedbackCategory _category = FeedbackCategory.bug;
  bool _diagnosticsOn = true;
  bool _diagnosticsExpanded = false;
  FeedbackAttachment? _attachment;
  bool _busy = false;
  String? _error;
  String? _info;

  /// Bumped on every successful submission and used as [AttachmentField]'s
  /// key, forcing a fresh [State] for it: the field keeps its own selection
  /// internally, so clearing [_attachment] alone would leave a submitted
  /// screenshot still showing as attached in the picker UI even though it
  /// no longer rides along with the next submission.
  int _formGeneration = 0;

  @override
  void initState() {
    super.initState();
    final service = context.read<FeedbackService>();
    _controller = FeedbackController(
      feedbackService: service,
      diagnosticsCollector: widget.diagnosticsCollector ??
          context.read<DeviceDiagnosticsCollector>(),
    )..addListener(_onControllerChanged);
    _attachmentSource =
        widget.attachmentSource ?? context.read<AttachmentSource>();
    _replyEmail.text = context.read<AuthController?>()?.currentUser?.email ?? '';
    unawaited(_controller.loadDiagnostics());
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _message.dispose();
    _replyEmail.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
    } on FeedbackFailure catch (failure) {
      if (mounted) {
        setState(() {
          _error = feedbackFailureCopy(AppLocalizations.of(context), failure);
          if (failure is FeedbackAttachmentUploadFailedFailure) {
            // The ticket row already committed with this message text —
            // unlike every other FeedbackFailure case, a retry here is not
            // a fresh attempt at the same submission, it starts a new
            // ticket. Clearing the message keeps that new-ticket framing
            // honest, and clearing the screenshot is mandatory: leaving it
            // attached would silently re-upload and re-attach it (with no
            // fresh consent) onto that new ticket, filing a duplicate
            // ticket and firing a duplicate admin alert for one failure.
            _message.clear();
            _attachment = null;
            _formGeneration++;
          }
        });
      }
    } catch (error) {
      debugPrint('lunarlog feedback: submit failed (${error.runtimeType})');
      if (mounted) {
        setState(() => _error = feedbackFailureCopy(
            AppLocalizations.of(context), const FeedbackFailure.other()));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() => _run(() async {
        final message = _message.text.trim();
        if (message.isEmpty) return;
        if (message.length > 4000) {
          setState(() => _error =
              AppLocalizations.of(context).feedbackScreenMessageTooLong);
          return;
        }
        final replyEmail = _replyEmail.text.trim();
        if (!_emailPattern.hasMatch(replyEmail)) {
          setState(() => _error =
              AppLocalizations.of(context).feedbackScreenReplyEmailInvalid);
          return;
        }
        await _controller.submit(
          category: _category,
          message: message,
          replyEmail: replyEmail,
          includeDiagnostics: _diagnosticsOn,
          attachment: _attachment,
        );
        _message.clear();
        if (mounted) {
          setState(() {
            // Clear the screenshot along with the message: leaving it
            // behind would silently re-upload and re-attach it (with no
            // fresh consent) to whatever the user submits next in this
            // screen session, and it may carry minors' health data (R5).
            _attachment = null;
            _formGeneration++;
            _info = AppLocalizations.of(context).feedbackScreenThanks(replyEmail);
          });
        }
      });

  List<Widget> _buildCategoryChips() => [
        Text(AppLocalizations.of(context).feedbackScreenCategoryLabel,
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final category in FeedbackCategory.values)
              ChoiceChip(
                key: ValueKey('feedback-category-${category.toDb()}'),
                label: Text(category.label),
                selected: _category == category,
                onSelected: _busy ? null : (_) => setState(() => _category = category),
              ),
          ],
        ),
      ];

  Widget _buildMessageField() => TextField(
        key: const ValueKey('feedback-message'),
        controller: _message,
        enabled: !_busy,
        maxLines: 6,
        minLines: 3,
        // #165: multiline — the honest keyboard action is "newline" (a
        // "done" action would steal the enter key from line breaks).
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          labelText: AppLocalizations.of(context).feedbackScreenMessageLabel,
          alignLabelWithHint: true,
        ),
        onChanged: (_) => setState(() {}),
      );

  /// #165: the form's last single-line field — `email` is the honest
  /// autofill hint, and "done" submits (the Send feedback action).
  Widget _buildReplyEmailField() => TextField(
        key: const ValueKey('feedback-reply-email'),
        controller: _replyEmail,
        enabled: !_busy,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        autofillHints: const [AutofillHints.email],
        decoration: InputDecoration(
            labelText: AppLocalizations.of(context).feedbackScreenReplyEmailLabel),
      );

  List<Widget> _buildDiagnosticsSection() => [
        SwitchListTile(
          key: const ValueKey('feedback-diagnostics-toggle'),
          contentPadding: EdgeInsets.zero,
          title: Text(AppLocalizations.of(context).feedbackScreenDiagnosticsTitle),
          subtitle: Text(
              AppLocalizations.of(context).feedbackScreenDiagnosticsSubtitle),
          value: _diagnosticsOn,
          onChanged: _busy ? null : (value) => setState(() => _diagnosticsOn = value),
        ),
        if (_diagnosticsOn)
          InkWell(
            key: const ValueKey('feedback-diagnostics-preview-toggle'),
            onTap: () => setState(() => _diagnosticsExpanded = !_diagnosticsExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(_diagnosticsExpanded ? Icons.expand_less : Icons.expand_more, size: 20),
                  const SizedBox(width: 4),
                  Text(AppLocalizations.of(context)
                      .feedbackScreenDiagnosticsPreview),
                ],
              ),
            ),
          ),
        if (_diagnosticsOn && _diagnosticsExpanded)
          Padding(
            key: const ValueKey('feedback-diagnostics-preview'),
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in _controller.diagnostics?.previewLines() ?? const <String>[])
                  Text(line, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
      ];

  List<Widget> _buildStatusMessages() => [
        if (_error != null) ...[
          const SizedBox(height: 12),
          InlineError(
            key: const ValueKey('feedback-error'),
            message: _error!,
            onRetry:
                _busy || _message.text.trim().isEmpty ? null : _submit,
          ),
        ],
        if (_info != null) ...[
          const SizedBox(height: 12),
          Text(_info!, key: const ValueKey('feedback-info')),
        ],
      ];

  List<Widget> _buildPendingIndicator() => [
        if (_busy)
          const Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: SizedBox(
                key: ValueKey('feedback-pending'),
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ];

  Widget _buildAttachmentField() => AttachmentField(
        key: ValueKey('feedback-attachment-field-$_formGeneration'),
        source: _attachmentSource,
        onChanged: (attachment) => setState(() => _attachment = attachment),
      );

  Widget _buildSubmitButton() => FilledButton(
        key: const ValueKey('feedback-submit'),
        onPressed: _busy || _message.text.trim().isEmpty ? null : _submit,
        child: Text(AppLocalizations.of(context).feedbackScreenSendButton),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).feedbackScreenTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ..._buildCategoryChips(),
          const SizedBox(height: 16),
          _buildMessageField(),
          const SizedBox(height: 8),
          _buildReplyEmailField(),
          const SizedBox(height: 8),
          ..._buildDiagnosticsSection(),
          const SizedBox(height: 8),
          _buildAttachmentField(),
          ..._buildStatusMessages(),
          const SizedBox(height: 16),
          ..._buildPendingIndicator(),
          _buildSubmitButton(),
        ],
      ),
    );
  }
}
