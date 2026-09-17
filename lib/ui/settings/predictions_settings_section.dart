/// The per-profile predictions toggle section for Settings (Issue #225).
///
/// Allows turning cycle predictions on or off per profile.
/// When off, suppresses estimates, rolled estimates, calendar prediction
/// bands, and prediction-derived reminders for that profile, while
/// logging, history, and statistics remain intact.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:provider/provider.dart';

class PredictionsSettingsSection extends StatelessWidget {
  const PredictionsSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<ProfileController?>(context);
    if (controller != null) {
      return _buildWithProfiles(context, controller.activeProfiles);
    }
    final profilesRepo = Provider.of<ProfilesRepository?>(context);
    if (profilesRepo == null) return const SizedBox.shrink();

    return _ProfilesRepoWatcher(profilesRepo: profilesRepo);
  }
}

class _ProfilesRepoWatcher extends StatefulWidget {
  const _ProfilesRepoWatcher({required this.profilesRepo});

  final ProfilesRepository profilesRepo;

  @override
  State<_ProfilesRepoWatcher> createState() => _ProfilesRepoWatcherState();
}

class _ProfilesRepoWatcherState extends State<_ProfilesRepoWatcher> {
  late Stream<List<Profile>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.profilesRepo.watch();
  }

  @override
  void didUpdateWidget(_ProfilesRepoWatcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profilesRepo != widget.profilesRepo) {
      _stream = widget.profilesRepo.watch();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Profile>>(
      stream: _stream,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const [];
        final active = [for (final p in all) if (p.archivedAt == null) p];
        return _buildWithProfiles(context, active);
      },
    );
  }
}

Widget _buildWithProfiles(BuildContext context, List<Profile> profiles) {
  if (profiles.isEmpty) return const SizedBox.shrink();
  final settings = Provider.of<SettingsStore?>(context);
  if (settings == null) return const SizedBox.shrink();

  final single = profiles.length == 1;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final profile in profiles)
        _ProfilePredictionTile(
          key: ValueKey('prediction-tile-${profile.id}'),
          profile: profile,
          settings: settings,
          singleProfile: single,
        ),
      const Divider(),
    ],
  );
}

class _ProfilePredictionTile extends StatefulWidget {
  const _ProfilePredictionTile({
    super.key,
    required this.profile,
    required this.settings,
    required this.singleProfile,
  });

  final Profile profile;
  final SettingsStore settings;
  final bool singleProfile;

  @override
  State<_ProfilePredictionTile> createState() => _ProfilePredictionTileState();
}

class _ProfilePredictionTileState extends State<_ProfilePredictionTile> {
  late Stream<String?> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.settings.watch(
      predictionsEnabledSettingKey(widget.profile.id),
    );
  }

  @override
  void didUpdateWidget(_ProfilePredictionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id ||
        oldWidget.settings != widget.settings) {
      _stream = widget.settings.watch(
        predictionsEnabledSettingKey(widget.profile.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<String?>(
      stream: _stream,
      builder: (context, snapshot) {
        final enabled = parsePredictionsEnabled(snapshot.data);
        final switchTile = SwitchListTile(
          key: widget.singleProfile
              ? const ValueKey('predictions-toggle')
              : ValueKey('predictions-toggle-${widget.profile.id}'),
          title: Text(
            widget.singleProfile
                ? l10n.settingsPredictionsTitle
                : l10n.settingsPredictionsProfileTitle(widget.profile.displayName),
          ),
          subtitle: Text(l10n.settingsPredictionsSubtitle),
          value: enabled,
          onChanged: (value) {
            unawaited(widget.settings.set(
              predictionsEnabledSettingKey(widget.profile.id),
              encodePredictionsEnabled(value),
            ));
          },
        );

        if (widget.singleProfile) {
          return KeyedSubtree(
            key: ValueKey('predictions-toggle-${widget.profile.id}'),
            child: switchTile,
          );
        }
        return switchTile;
      },
    );
  }
}
