/// Drift-backed [AccountExportSnapshotRepository] (Issue #140 review,
/// LLA-084/LLA-094): reads a profile's entries, observations, life-stage
/// mode, and cycle overrides inside one [LunarLogStorage] transaction, so a
/// concurrent write can never land between two of those reads and produce
/// an inconsistent export. Delegates to the ordinary
/// [DayEntriesRepository]/[ObservationsRepository]/[ProfileModesRepository]/
/// [CycleOverridesRepository] implementations for the actual reads (no
/// duplicated query logic) — [LunarLogStorage.db]'s transaction wrapper is
/// what makes their combination atomic, not anything special about how
/// each one reads.
library;

import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/repositories/account_export_snapshot_repository.dart';
import 'package:lunarlog/domain/repositories/cycle_overrides_repository.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart';
import 'package:lunarlog/domain/repositories/tag_registry_repository.dart';

import 'mappers.dart';

class DriftAccountExportSnapshotRepository
    implements AccountExportSnapshotRepository {
  const DriftAccountExportSnapshotRepository({
    required this.storage,
    required this.entriesRepository,
    required this.observationsRepository,
    required this.profileModesRepository,
    required this.cycleOverridesRepository,
    this.tagRegistryRepository,
  });

  final LunarLogStorage storage;
  final DayEntriesRepository entriesRepository;
  final ObservationsRepository observationsRepository;
  final ProfileModesRepository profileModesRepository;
  final CycleOverridesRepository cycleOverridesRepository;
  final TagRegistryRepository? tagRegistryRepository;

  @override
  Future<AccountExportSnapshot> forProfile(String profileId) {
    return storage.db.transaction(() async {
      final entries = await entriesRepository.listForProfile(profileId);
      final observations =
          await observationsRepository.listForProfile(profileId);
      final profileMode = await profileModesRepository.find(profileId);
      final cycleOverrides =
          await cycleOverridesRepository.listForProfile(profileId);
      // Issue #130: the profile's window-live merge disclosures join the
      // SAME coherent read (the LLA-094 straddle argument applies to the
      // disclosure rows exactly as it does to the entries they describe).
      final mergeEvents = await entriesRepository.mergeEventsForProfile(profileId);
      // Issue #824: the profile's live custom tag registry entries join the
      // same coherent read.
      final customTags = tagRegistryRepository != null
          ? await tagRegistryRepository!.listForProfile(profileId)
          : [
              for (final row in await storage.getProfileTagRegistry(profileId))
                customTagToDomain(row),
            ];
      return (
        entries: entries,
        observations: observations,
        profileMode: profileMode,
        cycleOverrides: cycleOverrides,
        mergeEvents: mergeEvents,
        customTags: customTags,
      );
    });
  }
}
