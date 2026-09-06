/// Support history: the operator's own feedback tickets, their reply
/// threads, and a way to continue an open thread (Issue #6, U8; R14, R22).
///
/// Shaped like `lib/ui/sharing/manage_guardians_screen.dart`: a
/// null-means-loading list, an explicit empty state, and inline error/retry
/// rather than a raw provider string.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:provider/provider.dart';

/// True once a ticket has at least one reply (a reply is the only thing
/// that ever moves status away from `new`), the signal
/// [SupportHistoryScreen] uses to decide whether a ticket contributes to
/// the Settings unread badge (U8's "newest reply timestamp it can see").
bool hasReplyActivity(FeedbackTicket ticket) => ticket.status != FeedbackTicketStatus.newTicket;

/// The newest [FeedbackTicket.updatedAt] among tickets with
/// [hasReplyActivity], or null when none have been replied to yet. Every
/// reply insert stamps the parent ticket's `updated_at`
/// (`feedback_replies_touch_ticket`, U1), so this is a reliable proxy for
/// "the newest reply timestamp" without an eager per-ticket reply fetch.
DateTime? newestReplyActivityAt(List<FeedbackTicket> tickets) {
  DateTime? newest;
  for (final ticket in tickets) {
    if (!hasReplyActivity(ticket)) continue;
    if (newest == null || ticket.updatedAt.isAfter(newest)) newest = ticket.updatedAt;
  }
  return newest;
}

String _categoryLabel(FeedbackCategory category) => category.label;

String _firstLine(String message) {
  final newline = message.indexOf('\n');
  final line = newline < 0 ? message : message.substring(0, newline);
  return line.length > 80 ? '${line.substring(0, 80)}…' : line;
}

class SupportHistoryScreen extends StatefulWidget {
  const SupportHistoryScreen({super.key});

  @override
  State<SupportHistoryScreen> createState() => _SupportHistoryScreenState();
}

class _SupportHistoryScreenState extends State<SupportHistoryScreen> {
  late final FeedbackService _service;
  SettingsStore? _settings;

  List<FeedbackTicket>? _tickets;
  String? _error;

  final Map<String, List<FeedbackReply>> _repliesByTicket = {};
  final Set<String> _expandedTicketIds = {};
  final Set<String> _loadingRepliesTicketIds = {};
  final Map<String, TextEditingController> _replyControllers = {};
  final Set<String> _sendingReplyTicketIds = {};

  @override
  void initState() {
    super.initState();
    _service = context.read<FeedbackService>();
    _settings = context.read<SettingsStore?>();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final controller in _replyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _tickets = null;
      _error = null;
    });
    try {
      final tickets = await _service.listTickets();
      if (!mounted) return;
      setState(() => _tickets = tickets);
      final newest = newestReplyActivityAt(tickets);
      if (newest != null) {
        await _settings?.set(SettingsKeys.feedbackLastSeenAt, newest.toUtc().toIso8601String());
      }
    } on FeedbackFailure catch (failure) {
      if (mounted) setState(() => _error = failure.userFacingMessage);
    } catch (error) {
      debugPrint('lunarlog feedback: support history load failed (${error.runtimeType})');
      if (mounted) setState(() => _error = const FeedbackFailure.other().userFacingMessage);
    }
  }

  Future<void> _toggleExpanded(FeedbackTicket ticket) async {
    if (_expandedTicketIds.contains(ticket.id)) {
      setState(() => _expandedTicketIds.remove(ticket.id));
      return;
    }
    setState(() => _expandedTicketIds.add(ticket.id));
    if (_repliesByTicket.containsKey(ticket.id)) return;
    setState(() => _loadingRepliesTicketIds.add(ticket.id));
    try {
      final replies = await _service.listReplies(ticket.id);
      if (!mounted) return;
      setState(() => _repliesByTicket[ticket.id] = replies);
    } catch (error) {
      debugPrint('lunarlog feedback: reply load failed (${error.runtimeType})');
      if (mounted) setState(() => _repliesByTicket[ticket.id] = const []);
    } finally {
      if (mounted) setState(() => _loadingRepliesTicketIds.remove(ticket.id));
    }
  }

  Future<void> _sendReply(FeedbackTicket ticket) async {
    final controller = _replyControllers[ticket.id];
    final text = controller?.text.trim() ?? '';
    if (text.isEmpty || _sendingReplyTicketIds.contains(ticket.id)) return;
    setState(() => _sendingReplyTicketIds.add(ticket.id));
    try {
      final reply = await _service.addUserReply(ticketId: ticket.id, message: text);
      if (!mounted) return;
      setState(() {
        _repliesByTicket[ticket.id] = [...?_repliesByTicket[ticket.id], reply];
      });
      controller?.clear();
    } catch (error) {
      debugPrint('lunarlog feedback: reply send failed (${error.runtimeType})');
    } finally {
      if (mounted) setState(() => _sendingReplyTicketIds.remove(ticket.id));
    }
  }

  Widget _buildEmptyState(ThemeData theme) => Center(
        child: Column(
          key: const ValueKey('support-history-empty'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text('No feedback yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Reports you send from Settings appear here.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      );

  Widget _buildErrorState(ThemeData theme) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, key: const ValueKey('support-history-error')),
            const SizedBox(height: 8),
            TextButton(
              key: const ValueKey('support-history-retry'),
              onPressed: _load,
              child: const Text('Retry'),
            ),
          ],
        ),
      );

  Widget _buildTicketTile(BuildContext context, FeedbackTicket ticket) {
    final theme = Theme.of(context);
    final expanded = _expandedTicketIds.contains(ticket.id);
    return Column(
      key: ValueKey('support-history-ticket-${ticket.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: Text(_categoryLabel(ticket.category)),
          subtitle: Text(_firstLine(ticket.message)),
          trailing: Chip(label: Text(ticket.status.label)),
          onTap: () => _toggleExpanded(ticket),
        ),
        if (expanded) _buildThread(context, ticket, theme),
      ],
    );
  }

  Widget _buildThread(BuildContext context, FeedbackTicket ticket, ThemeData theme) {
    if (_loadingRepliesTicketIds.contains(ticket.id)) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final replies = _repliesByTicket[ticket.id] ?? const [];
    final controller = _replyControllers.putIfAbsent(ticket.id, () => TextEditingController());
    final canReply = ticket.status != FeedbackTicketStatus.resolved;
    final sending = _sendingReplyTicketIds.contains(ticket.id);
    return Padding(
      key: ValueKey('support-history-thread-${ticket.id}'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final reply in replies)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(reply.author.label, style: theme.textTheme.labelMedium),
                  Text(reply.message),
                ],
              ),
            ),
          if (canReply) ...[
            TextField(
              key: ValueKey('support-history-reply-field-${ticket.id}'),
              controller: controller,
              enabled: !sending,
              decoration: const InputDecoration(labelText: 'Reply'),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: ValueKey('support-history-reply-send-${ticket.id}'),
                onPressed: sending ? null : () => _sendReply(ticket),
                child: const Text('Send'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tickets = _tickets;
    return Scaffold(
      appBar: AppBar(title: const Text('Support history')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _error != null
            ? ListView(children: [SizedBox(height: 200, child: _buildErrorState(theme))])
            : tickets == null
                ? const Center(child: CircularProgressIndicator())
                : tickets.isEmpty
                    ? ListView(children: [SizedBox(height: 300, child: _buildEmptyState(theme))])
                    : ListView.separated(
                        itemCount: tickets.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) => _buildTicketTile(context, tickets[index]),
                      ),
      ),
    );
  }
}
