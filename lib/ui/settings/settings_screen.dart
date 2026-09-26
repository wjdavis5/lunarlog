/// Settings screen, restructured into sections (Issue #226; source B-18):
/// the eight first-class sections — Your data / Appearance / Reminders /
/// Calendar / Family & sharing / Privacy & security / Help / About — render
/// in that order, each headed by the shared `SettingsSection` component so
/// the ordering is data (this build method's children list), not layout.
/// Two further sections ride along where their content already existed:
/// Health (issue #153's iOS-only health-sync tile, between Your data and
/// Appearance) and the conditional Account section (between Family &
/// sharing and Privacy & security, unchanged from its pre-#226 spot).
///
/// What each section holds: Your data is export/import (Issues #222/#140,
/// `YourDataSection`, which hosts its own `SettingsSection` so it keeps
/// self-hiding on web); Reminders holds the per-profile reminder
/// configuration (#136) *and* the caregiver alert preferences promoted out
/// of Manage Guardians (#226's core fix — one tap from here instead of
/// four levels through a profile's caregiver screen; the old Manage
/// Guardians entry stays); Calendar holds the week-start and date-format
/// pickers (new in #226) plus the per-profile predictions (#225) and
/// measurement-unit (#457) sections; Privacy & security keeps the
/// inactivity auto-relock toggle (default on, persisted via
/// [SettingsKeys.relockEnabled]) with its operator-selectable timeout
/// (issue #762: 2 minutes / 15 minutes / 1 hour, default 1 hour,
/// persisted via [SettingsKeys.relockTimeout]; backgrounding always
/// re-locks regardless — its explanation survives intact, now with
/// section-mates), the app PIN (#271), and the privacy policy; Help holds
/// the offline help library (#139), feedback/support, and support history;
/// About holds the version/build line and the licences entry.
///
/// Route naming: "Contact support" is deliberately left unnamed as an
/// informational dialog (no action beyond Close), and the licence page
/// (`showLicensePage`) offers no `RouteSettings` so it stays unnamed too.
/// "Privacy policy" is a full-screen route (`kRoutePrivacyPolicyScreen`).
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:lunarlog/config.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';
import 'package:lunarlog/domain/health/health_deviation.dart';
import 'package:lunarlog/domain/health/health_import.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/notifications/notification_preferences_service.dart';
import 'package:lunarlog/domain/notifications/reminder_config_store.dart';
import 'package:lunarlog/domain/profiles/profile_erasure_service.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/gate_controller.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/account_section.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/components/settings_section.dart';
import 'package:lunarlog/ui/components/responsive_body.dart';
import 'package:lunarlog/ui/content/cycle_literacy_library_screen.dart';
import 'package:lunarlog/ui/help/help_library_screen.dart';
import 'package:lunarlog/ui/feedback/feedback_screen.dart'
    show kSupportEmailAddress;
import 'package:lunarlog/ui/feedback/support_history_screen.dart'
    show newestReplyActivityAt;
import 'package:lunarlog/ui/gate/pin_settings_tile.dart';
import 'package:lunarlog/ui/routes.dart';
import 'package:lunarlog/ui/settings/about_section.dart';
import 'package:lunarlog/ui/settings/calendar_settings_section.dart';
import 'package:lunarlog/ui/settings/family_sharing_section.dart';
import 'package:lunarlog/ui/settings/health_sync_screen.dart';
import 'package:lunarlog/ui/settings/home_widget_section.dart';
import 'package:lunarlog/ui/settings/measurement_units_settings_section.dart';
import 'package:lunarlog/ui/settings/predictions_settings_section.dart';
import 'package:lunarlog/ui/settings/your_data_section.dart';
import 'package:lunarlog/ui/sharing/notification_preferences_screen.dart';
import 'package:lunarlog/ui/startup/qa_build_banner.dart'
    show kQaBuildRelockNote;
import 'package:lunarlog/ui/theme/appearance.dart';
import 'package:provider/provider.dart';

/// The localized label for a relock-timeout [Duration] (issue #762).
/// Any value outside [kRelockTimeoutOptions] (only possible from a test
/// or a future build) reads as the 1-hour default, matching
/// [relockTimeoutFromStored]'s fallback. A top-level function (rather
/// than inline in the tile) so it carries its own test coverage instead
/// of the untested navigation wiring around it.
String relockTimeoutLabel(AppLocalizations l10n, Duration value) {
  if (value == kRelockTimeout2Minutes) {
    return l10n.settingsRelockTimeout2Minutes;
  }
  if (value == kRelockTimeout15Minutes) {
    return l10n.settingsRelockTimeout15Minutes;
  }
  return l10n.settingsRelockTimeout1Hour;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.qaBuild, this.showAppBar = true});

  /// Issue #739: whether this is a QA build (`LUNARLOG_QA_BUILD=true`),
  /// resolved once through [AppConfig.qaBuild] — the `mfaEnabled`
  /// null-means-AppConfig injection idiom, so widget tests exercise both
  /// flag values in one default-off run. While true the relock toggle
  /// renders disabled and off (relock is structurally off in
  /// [GateController] for such a build), with the QA note as its subtitle.
  final bool? qaBuild;

  /// Issue #826: when Settings is embedded as the shell's More tab
  /// (`AppShell`), the shell owns the one AppBar for every tab — the shared
  /// sync-failure banner is the shell body's first child, so it must sit
  /// below an AppBar the shell controls on More too. `false` suppresses
  /// this screen's own AppBar so the More tab never doubles it; the
  /// standalone push sites (`kRouteSettingsScreen`) keep the default
  /// `true` and keep carrying their own.
  final bool showAppBar;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _relock = true;
  Duration _relockTimeout = kRelockTimeout1Hour;
  bool _loaded = false;

  /// Issue #739: the resolved QA-build flag for this screen's render.
  late final bool _qaBuild = widget.qaBuild ?? AppConfig.qaBuild;

  @override
  void initState() {
    super.initState();
    final store = context.read<SettingsStore>();
    unawaited(() async {
      final value = await store.get(SettingsKeys.relockEnabled);
      final timeoutRaw = await store.get(SettingsKeys.relockTimeout);
      if (!mounted) return;
      setState(() {
        _relock = value != 'false';
        _relockTimeout = relockTimeoutFromStored(timeoutRaw);
        _loaded = true;
      });
    }());
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
    final hasFeedback =
        Provider.of<FeedbackService?>(context) != null && signedIn;
    // Issues #153/#458: dormant until a HealthKit/Health Connect adapter
    // exists (AppConfig.hasHealthSync) and never on web — see that flag's
    // doc comment. Since #193 the write flow behind it is real on iOS, and
    // since #458 the read path is real on Android too (the write adapter
    // #345/#374 had landed earlier), so the tile renders on both wired OS
    // stores. Also needs the repository wiring a fully unconfigured build
    // (e.g. tests with no repositories provided) may not have.
    final profilesRepository = Provider.of<ProfilesRepository?>(context);
    final guardiansRepository = Provider.of<ProfileGuardiansRepository?>(
      context,
    );
    final hasHealthSync =
        AppConfig.hasHealthSync &&
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android) &&
        profilesRepository != null &&
        guardiansRepository != null;
    // Issue #226: the Reminders section renders whenever either of its
    // halves can — the reminder-configuration store (#136) or the
    // caregiver alert preferences service (#5). A build with neither
    // (unconfigured, no push, no scheduler) shows no empty header.
    final hasReminders =
        Provider.of<ReminderConfigService?>(context) != null ||
        Provider.of<NotificationPreferencesService?>(context) != null;
    return Scaffold(
      // Issue #826: `showAppBar` is false only when the shell supplies the
      // More tab's AppBar; see that field's doc.
      appBar:
          widget.showAppBar ? AppBar(title: Text(l10n.settingsTitle)) : null,
      body: ResponsiveBody(
        child: ListView(
        children: [
          // 1. Your data (Issue #222/#140) — self-hosts its SettingsSection
          // so it can keep self-hiding as a unit (web builds render none
          // of it).
          YourDataSection(
            profileErasureService:
                Provider.of<ProfileErasureService?>(context, listen: false),
          ),
          // Issue #153: iOS-only health-app binding, kept as its own
          // section where it already was one.
          if (hasHealthSync)
            _healthSection(l10n, profilesRepository, guardiansRepository),
          // 2. Appearance (Issue #137): the theme-mode override, persisted
          // through the same device-local store the relock toggle uses.
          // The main `MaterialApp` (and the lock screen, via the shell)
          // watch the same key, so a change here re-themes the app with no
          // controller in between.
          SettingsSection(
            id: 'appearance',
            title: l10n.settingsSectionAppearance,
            children: [const _AppearanceTile()],
          ),
          // 2b. Home-screen widget (Issue #141): which profile the widget
          // shows, plus the privacy disclosure. Self-hosts its
          // SettingsSection so it self-hides as a unit (web/desktop render
          // none of it).
          const HomeWidgetSection(),
          // 3. Reminders: the per-profile local reminder configuration
          // (Issue #136) plus the caregiver alert preferences promoted out
          // of Manage Guardians (Issue #226's core fix).
          if (hasReminders) _remindersSection(context, l10n),
          // 4. Calendar (Issue #226): week-start and date-format pickers,
          // plus the per-profile predictions (#225) and measurement-unit
          // (#457) sections that were already settings.
          SettingsSection(
            id: 'calendar',
            title: l10n.settingsSectionCalendar,
            children: const [
              FirstDayOfWeekTile(),
              DateFormatTile(),
              PredictionsSettingsSection(),
              MeasurementUnitsSettingsSection(),
            ],
          ),
          // 5. Family & sharing (Issue #126): owned and shared-with-you
          // profiles, each routing to its Manage Guardians screen.
          // Self-hosts its SettingsSection so it self-hides as a unit when
          // sharing is unavailable.
          const FamilySharingSection(),
          if (hasAccount) ...[const AccountSection(), const Divider()],
          // 6. Privacy & security: the relock toggle (its explanation
          // intact, now among section-mates), the app PIN (#271), and the
          // privacy policy.
          _privacySecuritySection(context, l10n),
          // 7. Help: the offline help library (Issue #139 — every card
          // ships in the app bundle, so this needs no network),
          // feedback/support, and support history.
          _helpSection(context, l10n, hasFeedback: hasFeedback),
          // 8. About (Issue #226): app version, build number, licences.
          SettingsSection(
            id: 'about',
            title: l10n.settingsSectionAbout,
            children: const [AboutSection()],
          ),
        ],
        ),
      ),
    );
  }

  /// Issue #153's health-sync section (gated at the call site by
  /// [AppConfig.hasHealthSync] plus non-null repositories).
  Widget _healthSection(
    AppLocalizations l10n,
    ProfilesRepository profilesRepository,
    ProfileGuardiansRepository guardiansRepository,
  ) {
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final sourceTitle = isAndroid ? 'Health Connect' : 'Health app';
    final source = isAndroid ? 'Health Connect' : 'the Health app';
    return SettingsSection(
      id: 'health',
      title: l10n.settingsHealthHeader,
      children: [
        ListTile(
          key: const ValueKey('health-sync-tile'),
          leading: const Icon(Icons.favorite_outline),
          title: Text(l10n.settingsHealthSyncTitle(sourceTitle)),
          subtitle: Text(l10n.settingsHealthSyncSubtitle(source)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openHealthSync(
            context,
            profilesRepository,
            guardiansRepository,
          ),
        ),
      ],
    );
  }

  /// The Reminders section's children (gated at the call site on either
  /// half of the section existing): the per-profile reminder configuration
  /// (Issue #136) plus the caregiver alert preferences promoted out of
  /// Manage Guardians (Issue #226's core fix).
  Widget _remindersSection(BuildContext context, AppLocalizations l10n) =>
      SettingsSection(
        id: 'reminders',
        title: l10n.settingsSectionReminders,
        children: [
          // Issue #136: present whenever the app provides the reminder
          // configuration store (i.e. reminders exist — a scheduler was
          // wired); hidden in harnesses that never built one.
          if (context.watch<ReminderConfigService?>() != null)
            ListTile(
              key: const ValueKey('reminder-settings-tile'),
              leading: const Icon(Icons.notifications_outlined),
              title: Text(l10n.settingsReminderSettingsTitle),
              subtitle: Text(l10n.settingsReminderSettingsSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  pushNamedScreen<void>(context, kRouteReminderSettingsScreen),
            ),
          const _CaregiverAlertsTiles(),
        ],
      );

  /// The Privacy & security section's children: the relock toggle (its
  /// explanation intact, now among section-mates), the app PIN (#271), and
  /// the privacy policy.
  Widget _privacySecuritySection(BuildContext context, AppLocalizations l10n) =>
      SettingsSection(
        id: 'privacy-security',
        title: l10n.settingsSectionPrivacySecurity,
        children: [
          SwitchListTile(
            key: const ValueKey('relock-toggle'),
            title: Text(l10n.settingsRelockTitle),
            // Issue #739: a QA build renders the toggle disabled and off
            // with the QA note as its subtitle — relock is permanently off
            // in [GateController] for such a build, so an interactive
            // switch claiming otherwise would lie. Issue #762: the
            // subtitle names the selected timeout, never a hard-coded one.
            subtitle: Text(
              _qaBuild
                  ? kQaBuildRelockNote
                  : l10n.settingsRelockSubtitle(
                      relockTimeoutLabel(l10n, _relockTimeout),
                    ),
            ),
            value: _qaBuild ? false : _relock,
            onChanged: _loaded && !_qaBuild
                ? (value) {
                    setState(() => _relock = value);
                    unawaited(
                      context.read<SettingsStore>().set(
                        SettingsKeys.relockEnabled,
                        value ? 'true' : 'false',
                      ),
                    );
                  }
                : null,
          ),
          // Issue #762: the operator-selectable inactivity timeout — a
          // fixed 2 minutes / 15 minutes / 1 hour choice (default 1 hour),
          // persisted via [SettingsKeys.relockTimeout]. Disabled in a QA
          // build (relock is structurally off there, so a choice would
          // lie), but stays interactive while the toggle itself is off:
          // the choice is remembered and applies when relock is
          // re-enabled.
          ListTile(
            key: const ValueKey('relock-timeout-tile'),
            leading: const Icon(Icons.timer_outlined),
            title: Text(l10n.settingsRelockTimeoutTitle),
            subtitle: Text(relockTimeoutLabel(l10n, _relockTimeout)),
            trailing: const Icon(Icons.chevron_right),
            enabled: _loaded && !_qaBuild,
            onTap: _loaded && !_qaBuild
                ? () => _openRelockTimeoutPicker(context, l10n)
                : null,
          ),
          // Issue #271: optional in-app PIN, a second lock layer on top of
          // the device credential above — self-hiding when unconfigured.
          const PinSettingsTile(),
          ListTile(
            key: const ValueKey('privacy-policy-tile'),
            leading: const Icon(Icons.shield_outlined),
            title: Text(l10n.settingsPrivacyTitle),
            subtitle: Text(l10n.settingsPrivacySubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showPrivacyPolicy(context),
          ),
        ],
      );

  /// Issue #762: the relock-timeout picker dialog — the three fixed
  /// durations in [kRelockTimeoutOptions], mirroring the appearance
  /// tile's picker shape (`RadioGroup` owning the selection).
  Future<void> _openRelockTimeoutPicker(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.settingsRelockTimeoutTitle),
        children: [
          RadioGroup<Duration>(
            groupValue: _relockTimeout,
            onChanged: (value) {
              if (value != null) unawaited(_pickRelockTimeout(value));
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in kRelockTimeoutOptions)
                  RadioListTile<Duration>(
                    key: ValueKey('relock-timeout-option-${option.inMinutes}'),
                    value: option,
                    title: Text(relockTimeoutLabel(l10n, option)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Persists a relock-timeout choice (issue #762): closes the picker,
  /// updates the tile optimistically, and writes through [SettingsStore]
  /// — the gate's own watch picks the change up, which is the entire
  /// propagation mechanism, no controller in between.
  Future<void> _pickRelockTimeout(Duration value) async {
    Navigator.of(context).pop();
    setState(() => _relockTimeout = value);
    await context
        .read<SettingsStore>()
        .set(SettingsKeys.relockTimeout, storedRelockTimeout(value));
  }

  /// The Help section's children: the offline help library (Issue #139 —
  /// every card ships in the app bundle, so this needs no network),
  /// feedback/support, and support history.
  Widget _helpSection(
    BuildContext context,
    AppLocalizations l10n, {
    required bool hasFeedback,
  }) =>
      SettingsSection(
        id: 'help',
        title: l10n.settingsSectionHelp,
        children: [
          ListTile(
            key: const ValueKey('settings-cycle-literacy-tile'),
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(l10n.settingsCycleLiteracyTitle),
            subtitle: Text(l10n.settingsCycleLiteracySubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              CycleLiteracyLibraryScreen.route(),
            ),
          ),
          ListTile(
            key: const ValueKey('settings-help-tile'),
            leading: const Icon(Icons.help_outline),
            title: Text(l10n.settingsHelpTitle),
            subtitle: Text(l10n.settingsHelpSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              buildNamedRoute<void>(
                name: kRouteHelpLibraryScreen,
                builder: (_) => const HelpLibraryScreen(),
              ),
            ),
          ),
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
        ],
      );

  /// Issue #153: pushes [HealthSyncScreen] with the tree-provided
  /// [ProfileGuardiansRepository] (the same contract the rest of the UI
  /// reads) rather than a repository constructed from raw storage.
  void _openHealthSync(
    BuildContext context,
    ProfilesRepository profilesRepository,
    ProfileGuardiansRepository guardiansRepository,
  ) {
    final signedInUserId = confirmedHealthSyncUserId(
      Provider.of<AuthController?>(context, listen: false),
    );
    Navigator.of(context).push(
      buildNamedRoute<void>(
        name: kRouteHealthSyncScreen,
        builder: (_) => HealthSyncScreen(
          profilesRepository: profilesRepository,
          guardiansForProfile: guardiansRepository.getForProfile,
          binding: HealthSyncBinding(context.read<SettingsStore>()),
          signedInUserId: signedInUserId,
          importer: Provider.of<HealthImportRunner?>(context, listen: false),
          // Issue #799: refreshes the overview's deviation snapshot after a
          // pass. Null on a build with no health sync, in which case the
          // import simply skips it.
          deviationInsights: Provider.of<HealthDeviationInsights?>(
            context,
            listen: false,
          ),
          // Issue #959: the OS permission status line reads this narrow
          // probe (never the write port). Null on a build with no native
          // permission surface, in which case the screen renders no line.
          permissionProbe:
              Provider.of<HealthPermissionProbe?>(context, listen: false),
          // Issue #458: writes are still iOS-only; Android wires only the
          // import runner, so the screen must not describe writes there.
          writeEnabled: defaultTargetPlatform == TargetPlatform.iOS,
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
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.settingsContactSupport),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.settingsContactSupportDialogBody),
                const SizedBox(height: 8),
                const SelectableText(kSupportEmailAddress),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.settingsClose),
            ),
          ],
        ),
      ),
    );
  }

  void _showPrivacyPolicy(BuildContext context) {
    unawaited(pushNamedScreen<void>(context, kRoutePrivacyPolicyScreen));
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
      final lastSeen = lastSeenRaw == null
          ? null
          : DateTime.tryParse(lastSeenRaw);
      final unread = lastSeen == null || newest.isAfter(lastSeen);
      if (mounted) setState(() => _unread = unread);
    } catch (error) {
      // Best-effort badge only; a failure here just means no badge shows.
      debugPrint(
        'lunarlog feedback: unread check failed (${error.runtimeType})',
      );
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

/// Issue #226's core fix: the caregiver alert preferences
/// ([NotificationPreferencesScreen], Issue #5 U8) promoted into Settings'
/// Reminders section — one tile per active profile, one tap from here
/// instead of four levels through profile → row overflow → Caregivers →
/// Notifications. Self-hiding (no tiles at all) when the build provides no
/// [NotificationPreferencesService] or no profiles have landed yet,
/// matching `FamilySharingSection`'s own gating; the Manage Guardians
/// entry point stays untouched, so both paths work.
class _CaregiverAlertsTiles extends StatefulWidget {
  const _CaregiverAlertsTiles();

  @override
  State<_CaregiverAlertsTiles> createState() => _CaregiverAlertsTilesState();
}

class _CaregiverAlertsTilesState extends State<_CaregiverAlertsTiles> {
  ProfilesRepository? _profilesRepository;
  late Stream<List<Profile>> _profiles;

  @override
  void initState() {
    super.initState();
    _profilesRepository = Provider.of<ProfilesRepository?>(
      context,
      listen: false,
    );
    if (_profilesRepository != null) {
      _profiles = _profilesRepository!.watch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = _profilesRepository;
    final service = Provider.of<NotificationPreferencesService?>(context);
    if (repository == null || service == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<List<Profile>>(
      stream: _profiles,
      builder: (context, snapshot) {
        final profiles = snapshot.data;
        if (profiles == null || profiles.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final profile in profiles)
              if (profile.archivedAt == null)
                ListTile(
                  key: ValueKey('caregiver-alerts-${profile.id}'),
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: Text(l10n.settingsCaregiverAlertsTitle),
                  subtitle: Text(profile.displayName),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    buildNamedRoute<void>(
                      name: kRouteNotificationPreferencesScreen,
                      builder: (_) => NotificationPreferencesScreen(
                        profile: profile,
                        preferencesService: service,
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

/// Issue #137: the appearance-override tile. Renders the current mode in
/// its subtitle (kept live through the same `watch` the app shell uses,
/// so an external change — a settings write from any surface — updates
/// it) and opens a three-option picker dialog. Writes go straight through
/// [SettingsStore.set]; the `MaterialApp`s' own watches pick the change
/// up, which is the entire propagation mechanism — no controller.
class _AppearanceTile extends StatefulWidget {
  const _AppearanceTile();

  @override
  State<_AppearanceTile> createState() => _AppearanceTileState();
}

class _AppearanceTileState extends State<_AppearanceTile> {
  ThemeMode _mode = ThemeMode.system;
  StreamSubscription<String?>? _sub;

  @override
  void initState() {
    super.initState();
    // The store's watch seeds the current value on subscribe (null when
    // unset — which parses to `ThemeMode.system`), so one subscription
    // covers both the initial read and every later change.
    _sub = context
        .read<SettingsStore>()
        .watch(SettingsKeys.themeMode)
        .listen((value) {
          if (mounted) setState(() => _mode = themeModeFromStored(value));
        });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
    super.dispose();
  }

  String _label(AppLocalizations l10n) => switch (_mode) {
        ThemeMode.system => l10n.appearanceOptionSystem,
        ThemeMode.light => l10n.appearanceOptionLight,
        ThemeMode.dark => l10n.appearanceOptionDark,
      };

  Future<void> _pick(ThemeMode mode) async {
    Navigator.of(context).pop();
    setState(() => _mode = mode);
    await context
        .read<SettingsStore>()
        .set(SettingsKeys.themeMode, storedThemeMode(mode));
  }

  Future<void> _openPicker() async {
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.settingsThemeTitle),
        children: [
          // `RadioGroup` (rather than per-tile `groupValue`/`onChanged`,
          // deprecated since Flutter 3.32) owns the selection: the tiles
          // below carry only `value`, and the group's `onChanged` funnels
          // every tap into [_pick].
          RadioGroup<ThemeMode>(
            groupValue: _mode,
            onChanged: (mode) {
              if (mode != null) unawaited(_pick(mode));
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in ThemeMode.values)
                  RadioListTile<ThemeMode>(
                    key: ValueKey('appearance-option-${mode.name}'),
                    value: mode,
                    title: Text(switch (mode) {
                      ThemeMode.system => l10n.appearanceOptionSystem,
                      ThemeMode.light => l10n.appearanceOptionLight,
                      ThemeMode.dark => l10n.appearanceOptionDark,
                    }),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      key: const ValueKey('appearance-tile'),
      leading: const Icon(Icons.brightness_6_outlined),
      title: Text(l10n.settingsThemeTitle),
      subtitle: Text(_label(l10n)),
      trailing: const Icon(Icons.chevron_right),
      onTap: _openPicker,
    );
  }
}
