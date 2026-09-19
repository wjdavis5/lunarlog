/// The per-profile predictions toggle section for Settings (Issue #225).
///
/// Allows turning cycle predictions on or off per profile.
/// When off, suppresses estimates, rolled estimates, calendar prediction
/// bands, and prediction-derived reminders for that profile, while
/// logging, history, and statistics remain intact.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/birth_control.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/profiles/birth_control_choices.dart';
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

  // Issue #877: the per-profile `profile_modes` row (life-stage mode and
  // birth-control method) that can suppress predictions regardless of the
  // stored `showPredictions` flag. Nullable — a test or a reduced
  // composition without the repository simply renders the toggle as before.
  final modesRepo = Provider.of<ProfileModesRepository?>(context);

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
          modesRepo: modesRepo,
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
    required this.modesRepo,
    required this.singleProfile,
  });

  final Profile profile;
  final SettingsStore settings;
  final ProfileModesRepository? modesRepo;
  final bool singleProfile;

  @override
  State<_ProfilePredictionTile> createState() => _ProfilePredictionTileState();
}

class _ProfilePredictionTileState extends State<_ProfilePredictionTile> {
  late Stream<String?> _settingsStream;
  late Stream<ProfileLifecycleMode?> _modeStream;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _settingsStream = widget.settings.watch(
      predictionsEnabledSettingKey(widget.profile.id),
    );
    final modesRepo = widget.modesRepo;
    _modeStream = modesRepo == null
        ? Stream<ProfileLifecycleMode?>.value(null)
        : modesRepo.watch(widget.profile.id);
  }

  @override
  void didUpdateWidget(_ProfilePredictionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id ||
        oldWidget.settings != widget.settings ||
        oldWidget.modesRepo != widget.modesRepo) {
      _subscribe();
    }
  }

  /// Issue #877: the reason predictions are suppressed for this profile even
  /// when the stored flag is on, or null when the toggle is the only thing
  /// governing them.
  ///
  /// This deliberately delegates to the predictor's own policy — #528's
  /// [CyclePredictionService.suppressesPrediction] for life-stage modes and
  /// #233's [birthControlPredictionKind] (via [birthControlMethodInEffectOn])
  /// for a continuous method in effect — rather than restating the mode or
  /// method lists here, so Settings can never disagree with Today.
  String? _suppressionReason(
    ProfileLifecycleMode? row,
    AppLocalizations l10n,
  ) {
    if (row == null) return null;
    if (CyclePredictionService.suppressesPrediction(row.mode)) {
      return l10n.settingsPredictionsSuppressedByModeSubtitle(row.mode.label);
    }
    final method = birthControlMethodInEffectOn(
      storedMethod: row.birthControlMethod,
      startedOn: row.birthControlStartedOn,
      stoppedOn: row.birthControlStoppedOn,
      date: LocalDate.today(),
    );
    if (method != null &&
        birthControlPredictionKind(method) ==
            BirthControlPredictionKind.continuous) {
      return l10n.settingsPredictionsSuppressedByMethodSubtitle(
        birthControlChoiceLabel(
          birthControlChoiceForStored(method.toDb()),
          l10n,
        ),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<String?>(
      stream: _settingsStream,
      builder: (context, settingsSnapshot) {
        final enabled = parsePredictionsEnabled(settingsSnapshot.data);
        return StreamBuilder<ProfileLifecycleMode?>(
          stream: _modeStream,
          builder: (context, modeSnapshot) {
            // Issue #877: while a mode (or a continuous method) suppresses
            // predictions the toggle is disabled and its subtitle names the
            // real cause. The stored flag is never rewritten by this state,
            // so the user's own preference returns the moment the mode does.
            final suppressionReason =
                _suppressionReason(modeSnapshot.data, l10n);
            final switchTile = SwitchListTile(
              key: widget.singleProfile
                  ? const ValueKey('predictions-toggle')
                  : ValueKey('predictions-toggle-${widget.profile.id}'),
              title: Text(
                widget.singleProfile
                    ? l10n.settingsPredictionsTitle
                    : l10n.settingsPredictionsProfileTitle(
                        widget.profile.displayName),
              ),
              subtitle: Text(
                suppressionReason ?? l10n.settingsPredictionsSubtitle,
              ),
              value: enabled,
              onChanged: suppressionReason != null
                  ? null
                  : (value) {
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
      },
    );
  }
}
