/// The per-profile BBT/weight display-unit section for Settings (Issue
/// #457): editable now that #457 gives the storage half (`profiles.bbt_unit`
/// /`weight_unit`, Issue #255) a real UI consumer — #377's own "Not done"
/// noted the settings picker "lands with its first consumer", which this
/// section is.
///
/// Mirrors [PredictionsSettingsSection]'s shape (single-profile vs.
/// multi-profile heading, a [ProfileController]-first / [ProfilesRepository]
/// -watch fallback) but writes straight through [ProfilesRepository.update]
/// rather than a [SettingsStore] key — these two fields live on the
/// [Profile] row itself (synced, shared with every guardian), not a
/// device-local preference.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/models/measurement_unit.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:provider/provider.dart';

class MeasurementUnitsSettingsSection extends StatelessWidget {
  const MeasurementUnitsSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final profilesRepository = Provider.of<ProfilesRepository?>(context);
    if (profilesRepository == null) return const SizedBox.shrink();
    final controller = Provider.of<ProfileController?>(context);
    if (controller != null) {
      return _buildWithProfiles(
        context,
        controller.activeProfiles,
        profilesRepository,
      );
    }
    return _ProfilesRepoWatcher(profilesRepository: profilesRepository);
  }
}

class _ProfilesRepoWatcher extends StatefulWidget {
  const _ProfilesRepoWatcher({required this.profilesRepository});

  final ProfilesRepository profilesRepository;

  @override
  State<_ProfilesRepoWatcher> createState() => _ProfilesRepoWatcherState();
}

class _ProfilesRepoWatcherState extends State<_ProfilesRepoWatcher> {
  late Stream<List<Profile>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.profilesRepository.watch();
  }

  @override
  void didUpdateWidget(_ProfilesRepoWatcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profilesRepository != widget.profilesRepository) {
      _stream = widget.profilesRepository.watch();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Profile>>(
      stream: _stream,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const [];
        final active = [for (final p in all) if (p.archivedAt == null) p];
        return _buildWithProfiles(context, active, widget.profilesRepository);
      },
    );
  }
}

Widget _buildWithProfiles(
  BuildContext context,
  List<Profile> profiles,
  ProfilesRepository repository,
) {
  if (profiles.isEmpty) return const SizedBox.shrink();
  final single = profiles.length == 1;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final profile in profiles)
        _ProfileMeasurementUnitsTile(
          key: ValueKey('measurement-units-tile-${profile.id}'),
          profile: profile,
          repository: repository,
          singleProfile: single,
        ),
      const Divider(),
    ],
  );
}

class _ProfileMeasurementUnitsTile extends StatelessWidget {
  const _ProfileMeasurementUnitsTile({
    super.key,
    required this.profile,
    required this.repository,
    required this.singleProfile,
  });

  final Profile profile;
  final ProfilesRepository repository;
  final bool singleProfile;

  Future<void> _setBbtUnit(BbtUnit unit) =>
      repository.update(profile.copyWith(bbtUnit: unit));

  Future<void> _setWeightUnit(WeightUnit unit) =>
      repository.update(profile.copyWith(weightUnit: unit));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final suffix = singleProfile ? '' : '-${profile.id}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            singleProfile
                ? l10n.settingsMeasurementUnitsTitle
                : l10n.settingsMeasurementUnitsProfileTitle(
                    profile.displayName,
                  ),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          _unitRow(
            label: l10n.settingsMeasurementUnitsBbtLabel,
            child: SegmentedButton<BbtUnit>(
              key: ValueKey('measurement-units-bbt$suffix'),
              segments: [
                ButtonSegment(
                  value: BbtUnit.celsius,
                  label: Text(bbtUnitSymbol(BbtUnit.celsius)),
                ),
                ButtonSegment(
                  value: BbtUnit.fahrenheit,
                  label: Text(bbtUnitSymbol(BbtUnit.fahrenheit)),
                ),
              ],
              selected: {profile.bbtUnit},
              onSelectionChanged: (selection) =>
                  unawaited(_setBbtUnit(selection.first)),
            ),
          ),
          const SizedBox(height: 8),
          _unitRow(
            label: l10n.settingsMeasurementUnitsWeightLabel,
            child: SegmentedButton<WeightUnit>(
              key: ValueKey('measurement-units-weight$suffix'),
              segments: [
                ButtonSegment(
                  value: WeightUnit.kg,
                  label: Text(weightUnitSymbol(WeightUnit.kg)),
                ),
                ButtonSegment(
                  value: WeightUnit.lb,
                  label: Text(weightUnitSymbol(WeightUnit.lb)),
                ),
              ],
              selected: {profile.weightUnit},
              onSelectionChanged: (selection) =>
                  unawaited(_setWeightUnit(selection.first)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _unitRow({required String label, required Widget child}) => Row(
        children: [
          Expanded(child: Text(label)),
          child,
        ],
      );
}
