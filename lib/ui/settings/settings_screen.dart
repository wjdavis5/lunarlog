/// Settings screen: the inactivity auto-relock toggle (default on, fixed
/// 2-minute timeout, persisted via [SettingsKeys.relockEnabled];
/// backgrounding always re-locks regardless), the "Your data" section
/// (Issue #222 - reachable whenever a profile exists, regardless of
/// sign-in state) and, when the build provides an [AuthController], the
/// Account section (U6) beneath it. Reachable from the profile picker.
///
/// Route naming (U2 Approach 2b): the "Contact support" and "Privacy
/// policy" `showDialog` calls are deliberately left unnamed — both are
/// informational-only (no action beyond Close), not distinct destinations.
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:lunarlog/config.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/notifications/reminder_config_store.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/account_section.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/feedback/feedback_screen.dart'
    show kSupportEmailAddress;
import 'package:lunarlog/ui/feedback/support_history_screen.dart'
    show newestReplyActivityAt;
import 'package:lunarlog/ui/routes.dart';
import 'package:lunarlog/ui/settings/family_sharing_section.dart';
import 'package:lunarlog/ui/settings/health_sync_screen.dart';
import 'package:lunarlog/ui/settings/your_data_section.dart';
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
    final l10n = AppLocalizations.of(context);
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
    // Issue #153: dormant until a HealthKit/Health Connect adapter exists
    // (AppConfig.hasHealthSync) and never on web — see that flag's doc
    // comment. Since #193 the write flow behind it is real, but only on
    // iOS: the Health Connect half's device checklist is #202's, so the
    // tile stays hidden on Android rather than binding a profile nothing
    // syncs yet. Also needs the storage/profiles wiring a fully
    // unconfigured build (e.g. tests with no LunarLogStorage provided)
    // may not have.
    final storage = Provider.of<LunarLogStorage?>(context);
    final profilesRepository = Provider.of<ProfilesRepository?>(context);
    final hasHealthSync = AppConfig.hasHealthSync &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        storage != null &&
        profilesRepository != null;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          const YourDataSection(),
          // Issue #126: owned and shared-with-you profiles, each routing
          // to its Manage Guardians screen. Self-hiding when sharing is
          // unavailable, so unconfigured builds render exactly as before.
          const FamilySharingSection(),
          if (hasAccount) ...[
            const AccountSection(),
            const Divider(),
          ],
          if (hasFeedback)
            ListTile(
              key: const ValueKey('send-feedback-tile'),
              leading: const Icon(Icons.feedback_outlined),
              title: Text(l10n.settingsSendFeedback),
              subtitle: Text(l10n.settingsSendFeedbackSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => pushNamedScreen<void>(context, kRouteFeedbackScreen),
            )
          else
            ListTile(
              key: const ValueKey('contact-support-tile'),
              leading: const Icon(Icons.feedback_outlined),
              title: Text(l10n.settingsContactSupport),
              subtitle: Text(l10n.settingsContactSupportSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showContactSupport(context),
            ),
          if (hasFeedback) const _SupportHistoryTile(),
          const Divider(),
          // Issue #136: the per-profile local reminder configuration.
          // Present whenever the app provides the reminder configuration
          // store (i.e. reminders exist — a scheduler was wired); hidden
          // in harnesses that never built one.
          if (Provider.of<ReminderConfigService?>(context) != null)
            ListTile(
              key: const ValueKey('reminder-settings-tile'),
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Reminders'),
              subtitle: const Text(
                  'Choose which reminders fire, when, and for whom'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  pushNamedScreen<void>(context, kRouteReminderSettingsScreen),
            ),
          const Divider(),
          SwitchListTile(
            key: const ValueKey('relock-toggle'),
            title: Text(l10n.settingsRelockTitle),
            subtitle: Text(l10n.settingsRelockSubtitle),
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
          if (hasHealthSync) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                l10n.settingsHealthHeader,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              key: const ValueKey('health-sync-tile'),
              leading: const Icon(Icons.favorite_outline),
              title: Text(l10n.settingsHealthSyncTitle),
              subtitle: Text(l10n.settingsHealthSyncSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openHealthSync(context, storage, profilesRepository),
            ),
            const Divider(),
          ],
          ListTile(
            key: const ValueKey('privacy-policy-tile'),
            leading: const Icon(Icons.shield_outlined),
            title: Text(l10n.settingsPrivacyTitle),
            subtitle: Text(l10n.settingsPrivacySubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showPrivacyPolicy(context),
          ),
        ],
      ),
    );
  }

  /// Issue #153: pushes [HealthSyncScreen] with dependencies constructed
  /// the same ad hoc way `profile_picker_screen.dart` builds
  /// [ProfileGuardiansRepository] for [ManageGuardiansScreen] — no
  /// app-wide provider for it, since only this one entry point needs it.
  void _openHealthSync(
    BuildContext context,
    LunarLogStorage storage,
    ProfilesRepository profilesRepository,
  ) {
    final signedInUserId = confirmedHealthSyncUserId(
      Provider.of<AuthController?>(context, listen: false),
    );
    Navigator.of(context).push(
      buildNamedRoute<void>(
        name: kRouteHealthSyncScreen,
        builder: (_) => HealthSyncScreen(
          profilesRepository: profilesRepository,
          guardiansForProfile: ProfileGuardiansRepository(storage).getForProfile,
          binding: HealthSyncBinding(context.read<SettingsStore>()),
          signedInUserId: signedInUserId,
        ),
      ),
    );
  }

  /// R23: shown instead of the feedback form on an unconfigured build, a
  /// signed-out session, or a web build without `LUNARLOG_WEB_SYNC=true`
  /// (R24 hides the feedback tile entirely in exactly those cases, matching
  /// the account-section gating idiom above). `SelectableText` avoids
  /// adding `url_launcher` for a single `mailto:` link.
  void _showContactSupport(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsContactSupport),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.settingsContactSupportDialogBody),
            const SizedBox(height: 8),
            const SelectableText(kSupportEmailAddress),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.settingsClose),
          ),
        ],
      ),
    );
  }

  void _showPrivacyPolicy(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsPrivacyDialogTitle),
        content: SingleChildScrollView(
          child: Text(l10n.settingsPrivacyDialogBody),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.settingsClose),
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
    final l10n = AppLocalizations.of(context);
    return ListTile(
      key: const ValueKey('support-history-tile'),
      leading: const Icon(Icons.history_outlined),
      title: Text(l10n.settingsSupportHistory),
      subtitle: Text(l10n.settingsSupportHistorySubtitle),
      trailing: _unread
          ? Icon(
              Icons.circle,
              key: const ValueKey('support-history-unread-badge'),
              size: 10,
              color: Theme.of(context).colorScheme.error,
            )
          : const Icon(Icons.chevron_right),
      onTap: () => pushNamedScreen<void>(context, kRouteSupportHistoryScreen),
    );
  }
}

/// The signed-in account's id for health-sync purposes (Issue #153): null
/// unless [controller] reports [AuthController.signedIn] — mirroring
/// `AuthService`'s `confirmedUserId` extension's guard against trusting a
/// stale id during password recovery, an expired session, or no controller
/// at all. A pure top-level function (rather than inline in
/// `_openHealthSync`) so it carries its own test coverage instead of the
/// untested navigation wiring around it.
String? confirmedHealthSyncUserId(AuthController? controller) =>
    (controller?.signedIn ?? false) ? controller!.currentUserId : null;
