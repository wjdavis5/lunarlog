/// The Settings screen's "Home-screen widget" section (issue #141): which
/// profile the widget shows, plus the privacy disclosure about what the
/// widget renders.
///
/// The section self-hosts its `SettingsSection` (the
/// `FamilySharingSection` shape) so it can hide as a unit where there is no
/// widget surface: web and desktop builds render none of it, and a build
/// without the profile repositories (bare test harnesses) does too.
///
/// Profile choice persists through `SettingsKeys.widgetProfileId` — the
/// empty string means "follow the app's active profile" (the default). The
/// picker offers only profiles the operator can log for: a known `viewer`
/// role is excluded here (`widgetProfileOptions`' role rule, the same rule
/// the write path re-verifies), while a profile demoted to viewer *after*
/// being pinned simply loses its quick-log button — the widget keeps
/// showing the discreet state.
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/widget/widget_profile_options.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/components/settings_section.dart';

class HomeWidgetSection extends StatelessWidget {
  const HomeWidgetSection({super.key});

  /// Whether this platform has the widget surface (and so the section
  /// renders at all). Same gate the composition root applies to the
  /// runtime: iOS/Android only.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  @override
  Widget build(BuildContext context) {
    if (!isSupported) return const SizedBox.shrink();
    final profiles = Provider.of<ProfilesRepository?>(context);
    final guardians = Provider.of<ProfileGuardiansRepository?>(context);
    final settings = Provider.of<SettingsStore?>(context);
    if (profiles == null || guardians == null || settings == null) {
      return const SizedBox.shrink();
    }
    return SettingsSection(
      id: 'home-widget',
      title: AppLocalizations.of(context).settingsSectionHomeWidget,
      children: [
        _WidgetProfileTile(profiles: profiles, guardians: guardians, settings: settings),
        _WidgetPrivacyNote(),
      ],
    );
  }
}

/// The "Widget profile" tile: shows the current target and opens the
/// picker dialog.
class _WidgetProfileTile extends StatelessWidget {
  const _WidgetProfileTile({
    required this.profiles,
    required this.guardians,
    required this.settings,
  });

  final ProfilesRepository profiles;
  final ProfileGuardiansRepository guardians;
  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<List<Profile>>(
      stream: profiles.watch(),
      builder: (context, profilesSnapshot) =>
          StreamBuilder<String?>(
            stream: settings.watch(SettingsKeys.widgetProfileId),
            builder: (context, selectionSnapshot) {
              final active = [
                if (profilesSnapshot.hasData)
                  for (final profile in profilesSnapshot.data!)
                    if (profile.archivedAt == null) profile,
              ];
              final pinnedId = selectionSnapshot.data;
              final pinned = pinnedId == null || pinnedId.isEmpty
                  ? null
                  : active.where((p) => p.id == pinnedId).firstOrNull;
              final subtitle = pinned?.displayName ??
                  l10n.settingsHomeWidgetFollowActive;
              return ListTile(
                key: const ValueKey('home-widget-profile-tile'),
                leading: const Icon(Icons.widgets_outlined),
                title: Text(l10n.settingsHomeWidgetProfileTitle),
                subtitle: Text(subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: active.isEmpty
                    ? null
                    : () => unawaited(
                        _openPicker(context, l10n, active, pinnedId),
                      ),
              );
            },
          ),
    );
  }

  /// Loads each active profile's eligibility fresh at open time (the role
  /// answer is a live fact, not a cached one), then shows the radio
  /// dialog. Viewer-role profiles are excluded — the same rule the write
  /// path enforces.
  Future<void> _openPicker(
    BuildContext context,
    AppLocalizations l10n,
    List<Profile> active,
    String? currentId,
  ) async {
    final currentUserId = context.read<AuthController?>()?.currentUserId;
    final selectable = <WidgetProfileOption>[];
    for (final profile in active) {
      final rows = await guardians.getForProfile(profile.id);
      selectable.addAll(
        widgetProfileOptions(
          profiles: [profile],
          guardiansForProfile: rows,
          currentUserId: currentUserId,
        ).where((option) => option.canQuickLog),
      );
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.settingsHomeWidgetProfileTitle),
        children: [
          RadioGroup<String?>(
            groupValue: currentId,
            onChanged: (value) {
              Navigator.of(dialogContext).pop();
              unawaited(
                context.read<SettingsStore>().set(
                      SettingsKeys.widgetProfileId,
                      value ?? '',
                    ),
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String?>(
                  key: const ValueKey('home-widget-option-follow'),
                  value: null,
                  title: Text(l10n.settingsHomeWidgetFollowActive),
                ),
                for (final option in selectable)
                  RadioListTile<String?>(
                    key: ValueKey('home-widget-option-${option.profileId}'),
                    value: option.profileId,
                    title: Text(option.profileName),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The privacy disclosure under the picker: the widget's discreet default
/// and the gated quick-log behavior, in the app's own words.
class _WidgetPrivacyNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('home-widget-privacy-note'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        AppLocalizations.of(context).settingsHomeWidgetDisclosure,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
