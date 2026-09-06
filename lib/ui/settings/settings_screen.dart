/// Settings screen: the inactivity auto-relock toggle (default on, fixed
/// 2-minute timeout, persisted via [SettingsKeys.relockEnabled];
/// backgrounding always re-locks regardless) and, when the build provides
/// an [AuthController], the Account section (U6). Reachable from the
/// profile picker.
///
/// Route naming (U2 Approach 2b): the "Contact support" and "Privacy
/// policy" `showDialog` calls are deliberately left unnamed — both are
/// informational-only (no action beyond Close), not distinct destinations.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/account_section.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/feedback/feedback_screen.dart';
import 'package:lunarlog/ui/feedback/support_history_screen.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _relock = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final store = context.read<SettingsStore>();
    () async {
      final value = await store.get(SettingsKeys.relockEnabled);
      if (!mounted) return;
      setState(() {
        _relock = value != 'false';
        _loaded = true;
      });
    }();
  }

  @override
  Widget build(BuildContext context) {
    final authController = Provider.of<AuthController?>(context);
    final hasAccount = authController != null;
    // R23: the in-app form needs a signed-in session (feedback tickets are
    // written under RLS scoped to `auth.uid()`), not merely a configured
    // `FeedbackService` — a signed-out tap must land on the support-email
    // fallback below, not on a form that fails with a permission error. No
    // `AuthController` at all means the session state can't be known, so
    // that also falls back rather than risking the form.
    final signedIn = authController?.signedIn ?? false;
    final hasFeedback = Provider.of<FeedbackService?>(context) != null && signedIn;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          if (hasAccount) ...[
            const AccountSection(),
            const Divider(),
          ],
          if (hasFeedback)
            ListTile(
              key: const ValueKey('send-feedback-tile'),
              leading: const Icon(Icons.feedback_outlined),
              title: const Text('Send feedback'),
              subtitle: const Text('Report a bug, ask a question, or share an idea'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  settings: const RouteSettings(name: kRouteFeedbackScreen),
                  builder: (_) => const FeedbackScreen(),
                ),
              ),
            )
          else
            ListTile(
              key: const ValueKey('contact-support-tile'),
              leading: const Icon(Icons.feedback_outlined),
              title: const Text('Contact support'),
              subtitle: const Text('Email us with a bug or question'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showContactSupport(context),
            ),
          if (hasFeedback) const _SupportHistoryTile(),
          const Divider(),
          SwitchListTile(
            key: const ValueKey('relock-toggle'),
            title: const Text('Relock after inactivity'),
            subtitle: const Text(
              'Locks the app after 2 minutes without input. '
              'Backgrounding relocks immediately. A sign-in or unlock '
              'prompt this app opened is the one exception: the app stays '
              'covered while it is on screen, and relocks as soon as it '
              'closes if you have left.',
            ),
            value: _relock,
            onChanged: _loaded
                ? (value) {
                    setState(() => _relock = value);
                    context
                        .read<SettingsStore>()
                        .set(SettingsKeys.relockEnabled, value ? 'true' : 'false');
                  }
                : null,
          ),
          const Divider(),
          ListTile(
            key: const ValueKey('privacy-policy-tile'),
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Privacy policy'),
            subtitle: const Text('Local-first, encrypted, zero tracking'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showPrivacyPolicy(context),
          ),
        ],
      ),
    );
  }

  /// R23: shown instead of the feedback form on an unconfigured build, a
  /// signed-out session, or a web build without `LUNARLOG_WEB_SYNC=true`
  /// (R24 hides the feedback tile entirely in exactly those cases, matching
  /// the account-section gating idiom above). `SelectableText` avoids
  /// adding `url_launcher` for a single `mailto:` link.
  void _showContactSupport(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contact support'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Email us with a bug report, question, or idea:'),
            SizedBox(height: 8),
            SelectableText(kSupportEmailAddress),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyPolicy(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('LunarLog Privacy Policy'),
        content: const SingleChildScrollView(
          child: Text(
            'LunarLog is a privacy-first, local-first cycle tracker.\n\n'
            '• Local & Encrypted: All cycle data is encrypted on your device '
            'behind biometric authentication.\n'
            '• Optional Sync: Cloud accounts (Supabase) are optional. No data is '
            'uploaded without your explicit consent.\n'
            '• Zero Ads & Tracking: We do not track you, sell data, or use ads.\n'
            '• Privacy-Scrubbed Telemetry: Crash reports (Sentry) strip all health '
            'and personal details on-device.\n'
            '• Family Custodianship: Minor profiles are managed directly by adult '
            'guardians with identical privacy protections.\n\n'
            'Canonical policy: https://github.com/wjdavis5/lunarlog/blob/main/PRIVACY.md',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// "Support history" tile (U8): a light background check against
/// [FeedbackService.listTickets] compares [newestReplyActivityAt] to the
/// stored [SettingsKeys.feedbackLastSeenAt] and shows an unread dot when a
/// reply landed since the operator last opened the screen.
class _SupportHistoryTile extends StatefulWidget {
  const _SupportHistoryTile();

  @override
  State<_SupportHistoryTile> createState() => _SupportHistoryTileState();
}

class _SupportHistoryTileState extends State<_SupportHistoryTile> {
  bool _unread = false;

  @override
  void initState() {
    super.initState();
    unawaited(_checkUnread());
  }

  Future<void> _checkUnread() async {
    try {
      final service = context.read<FeedbackService>();
      final settings = context.read<SettingsStore>();
      final tickets = await service.listTickets();
      final newest = newestReplyActivityAt(tickets);
      if (newest == null) return;
      final lastSeenRaw = await settings.get(SettingsKeys.feedbackLastSeenAt);
      final lastSeen = lastSeenRaw == null ? null : DateTime.tryParse(lastSeenRaw);
      final unread = lastSeen == null || newest.isAfter(lastSeen);
      if (mounted) setState(() => _unread = unread);
    } catch (error) {
      // Best-effort badge only; a failure here just means no badge shows.
      debugPrint('lunarlog feedback: unread check failed (${error.runtimeType})');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: const ValueKey('support-history-tile'),
      leading: const Icon(Icons.history_outlined),
      title: const Text('Support history'),
      subtitle: const Text('See replies and continue a conversation'),
      trailing: _unread
          ? const Icon(Icons.circle, key: ValueKey('support-history-unread-badge'), size: 10, color: Colors.red)
          : const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: kRouteSupportHistoryScreen),
          builder: (_) => const SupportHistoryScreen(),
        ),
      ),
    );
  }
}
