/// Applies an [ImportPlan] (Issue #140,
/// `lib/domain/import/account_import.dart`) to the local store: the only
/// effectful half of import, mirroring `AccountExportWriter`'s split
/// between a pure builder and a thin platform/storage adapter.
///
/// [AccountImportCoordinator] is the glue a UI caller drives: it reads
/// enough of the current local store to plan against (only for profiles
/// the file's own ids actually match — see [AccountImportCoordinator.buildPlan]),
/// calls the pure `planImport`, and hands the result to [AccountImporter]
/// to write. [AccountImporter.apply] wraps every write for the whole
/// document in one [LunarLogStorage.db] transaction: an unexpected failure
/// partway through rolls the whole thing back (Drift transactions are
/// atomic), so a failed import never leaves a partial set of rows behind.
library;

import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/ulid.dart' show isValidUlid;
import 'package:lunarlog/data/repositories/mappers.dart';
import 'package:lunarlog/domain/import/account_import.dart';
import 'package:lunarlog/domain/models/day_entry.dart' as domain;
import 'package:lunarlog/domain/models/observation.dart' as domain;
import 'package:lunarlog/domain/models/profile.dart' as domain;
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';

/// Resolves the guardian rows for one profile id (Issue #153's
/// `GuardiansForProfile` shape, redeclared here rather than imported —
/// `lib/ui/settings/health_sync_screen.dart` lives in `lib/ui`, and
/// `lib/data` must never depend on it, R14/R16). Production wiring passes
/// `ProfileGuardiansRepository.getForProfile`; tests pass a fake, no
/// database required.
typedef GuardiansForProfileFn = Future<List<ProfileGuardian>> Function(
    String profileId);

/// Applies one already-built [ImportPlan] (Issue #140). See this file's
/// own doc comment for the transactional guarantee.
class AccountImporter {
  const AccountImporter(this._storage);

  final LunarLogStorage _storage;

  /// Writes every planned row in one transaction and returns [plan]'s own
  /// summary (accurate because the transaction is all-or-nothing: either
  /// every planned write lands, matching the summary exactly, or none of
  /// them do and this throws).
  Future<ImportPlanSummary> apply(ImportPlan plan) async {
    await _storage.db.transaction(() async {
      for (final profilePlan in plan.profiles) {
        await _applyProfile(profilePlan);
      }
    });
    return plan.summary;
  }

  Future<void> _applyProfile(ProfilePlan plan) async {
    if (plan.outcome == ProfileImportOutcome.skipped) return;
    final profileId = await _resolveProfileId(plan);
    final entriesByDate = <String, domain.DayEntry>{};
    for (final entryPlan in plan.entries) {
      entriesByDate[entryPlan.localDate.iso] =
          await _applyEntry(profileId, entryPlan);
    }
    for (final observationPlan in plan.observations) {
      await _applyObservation(profileId, observationPlan, entriesByDate);
    }
  }

  /// Issue #140 review, item 2: a *created* profile reuses the file's own
  /// [ProfilePlan.fileProfileId] rather than minting a fresh one — ULIDs
  /// are collision-free, and this is what makes re-importing the same file
  /// plan that profile as `matched` (not `created`) the second time,
  /// instead of duplicating it on the server the next time a second device
  /// signed into the same account syncs (see `ImportedProfile.id`'s doc
  /// comment in `lib/domain/import/account_import.dart`).
  Future<String> _resolveProfileId(ProfilePlan plan) async {
    if (plan.outcome == ProfileImportOutcome.matched) {
      // Issue #140 review round 2, item 6: a matched-via-tombstone plan
      // must un-delete the row (otherwise its entries/observations would
      // attach to a profile still marked deleted) but must NOT overwrite
      // its stored metadata — `reviveTombstonedProfile` does exactly that,
      // unlike `upsertProfile`. An ordinary (live) match writes nothing
      // here at all, same as before this review.
      if (plan.restoredFromTombstone) {
        await _storage.reviveTombstonedProfile(plan.fileProfileId);
      }
      return plan.fileProfileId;
    }
    final created = await _storage.upsertProfile(
      id: plan.fileProfileId,
      displayName: plan.displayName,
      isMinor: plan.isMinor,
      mode: plan.mode ?? 'standard',
      // Issue #255: a v8 export always carries both keys; an older
      // export's absent keys fall back to the column defaults, exactly
      // like `mode` above.
      bbtUnit: plan.bbtUnit ?? 'celsius',
      weightUnit: plan.weightUnit ?? 'kg',
      sortOrder: plan.sortOrder,
    );
    return created.id;
  }

  Future<domain.DayEntry> _applyEntry(
    String profileId,
    DayEntryPlan plan,
  ) async {
    final row = await _storage.upsertDayEntry(
      id: await _revivalIdFor(profileId, plan),
      profileId: profileId,
      localDate: plan.localDate.iso,
      tz: plan.tz,
      flow: flowFromDomain(plan.flow),
      tags: plan.tags,
      note: plan.note,
      pms: plan.pms,
      source: plan.source,
      sourceId: plan.sourceId,
      importId: plan.importId,
    );
    return dayEntryToDomain(row);
  }

  /// The existing (live OR tombstoned) row's id to revive, or null to let
  /// [LunarLogStorage.upsertDayEntry] insert a fresh one (Issue #140
  /// review, item 5). Only relevant for an `add` plan — a `merge` plan
  /// already targets a live row directly, by (profileId, localDate),
  /// through the ordinary `upsertDayEntry` path. See
  /// `LunarLogStorage.findDayEntryBySource`'s doc comment for why a
  /// tombstone counts as a dedup match: the server's partial unique index
  /// on (profile_id, source, source_id) is not scoped to live rows either.
  Future<String?> _revivalIdFor(String profileId, DayEntryPlan plan) async {
    if (plan.outcome != DayEntryImportOutcome.add) return null;
    final found = await _storage.findDayEntryBySource(
      profileId: profileId,
      source: plan.source,
      sourceId: plan.sourceId,
    );
    if (found != null) return found.id;
    // Issue #140 review round 2, item 3: with no existing (live or
    // tombstoned) row to revive, reuse the file's own row id when it is a
    // syntactically valid ULID (already enforced at parse time —
    // `_requireUlid`) — so two devices importing the same file converge on
    // the same row id instead of each minting a fresh one and colliding on
    // `day_entries_profile_source_source_id_uq` the next time they sync.
    // Only ever reached for an `add` plan, which by construction (`_plan
    // DayEntry` in `lib/domain/import/account_import.dart`) means no live
    // row already occupies (profileId, localDate) — the only slot this id
    // is about to claim.
    final fileId = plan.fileId;
    if (fileId != null && isValidUlid(fileId)) return fileId;
    return null;
  }

  /// Skips an observation whose date has no corresponding day entry in
  /// [entriesByDate] — never expected from a document `parseAccountImport`
  /// accepted (every exported observation's profile also exports the day
  /// entry it belongs to), but defensive rather than a crash if it ever
  /// happens, since `observations.day_entry_id` has no null variant to
  /// fall back to.
  Future<void> _applyObservation(
    String profileId,
    ObservationPlan plan,
    Map<String, domain.DayEntry> entriesByDate,
  ) async {
    if (plan.outcome != ObservationImportOutcome.add) return;
    final entry = entriesByDate[plan.imported.localDate.iso];
    if (entry == null) return;
    final fileId = plan.imported.id;
    await _storage.upsertObservation(
      // Issue #140 review round 2, item 3: reuse the file's own
      // observation id when it is a syntactically valid ULID (already
      // enforced at parse time) — an `add` outcome means `planImport`'s
      // `_planObservations` found no existing row at this (profileId,
      // localDate, category, code), so nothing already occupies the slot
      // this id is about to claim. Mirrors `_revivalIdFor`'s day-entry
      // treatment; see that method's doc comment for the convergence
      // rationale.
      id: isValidUlid(fileId) ? fileId : null,
      dayEntryId: entry.id,
      profileId: profileId,
      localDate: plan.imported.localDate.iso,
      observedAt: plan.imported.observedAt,
      tz: plan.imported.tz,
      category: plan.imported.category,
      code: plan.imported.code,
      valueNum: plan.imported.valueNum,
      valueText: plan.imported.valueText,
      unit: plan.imported.unit,
      intensity: plan.imported.intensity,
      excluded: plan.imported.excluded,
      // `observations_source_check` (`supabase/migrations/
      // 20260908160000_observations.sql`) has no `file_import` value —
      // unlike `day_entries_source_check` (#159), which does — and this
      // issue makes no schema change to add one, so the source label falls
      // back to `manual`. Issue #140 review, item 6: `sourceId` is left
      // NULL here, not the file's original observation id — the partial
      // unique index `observations_profile_source_source_id_uq` is on
      // (profile_id, source, source_id), so writing a non-null sourceId
      // under `source = 'manual'` would claim a slot in that index that a
      // genuinely manual observation (device sync, another client) could
      // legitimately need later, and there is no dedup benefit to writing
      // it: with `source` forced to `manual` regardless of what the file
      // carried, this row can never be found again by the (profile,
      // source, sourceId) triple `findDayEntryBySource`-style lookup
      // day-entry dedup (item 5) relies on, so observations don't get that
      // same tombstone-revival treatment on re-import — a re-imported
      // observation instead falls through to the existing (date, category,
      // code) dedup in `planImport`'s `_planObservations`, which only sees
      // *live* rows (Issue #240), so re-importing after deleting a day's
      // observations legitimately re-adds them as new rows.
      source: 'manual',
      sourceId: null,
      raw: plan.imported.raw,
    );
  }
}

/// The glue between a UI caller and [AccountImporter]/`planImport`:
/// reads just enough of the current local store to plan against, then
/// applies the plan. See this file's own doc comment.
class AccountImportCoordinator {
  const AccountImportCoordinator({
    required this.profilesRepository,
    required this.dayEntriesRepository,
    required this.observationsRepository,
    required this.storage,
    this.guardiansForProfile,
    this.currentUserId,
  });

  final ProfilesRepository profilesRepository;
  final DayEntriesRepository dayEntriesRepository;
  final ObservationsRepository observationsRepository;
  final LunarLogStorage storage;

  /// Null means "no guardian info available" — every matched profile
  /// fails open (writable) unless archived, the same fail-open precedent
  /// [writeBlockReasonFor] itself documents.
  final GuardiansForProfileFn? guardiansForProfile;

  final String? currentUserId;

  /// Builds the plan for [document] against the local store's current
  /// state (Issue #140). Only fetches entries/observations/guardians for
  /// profile ids the document and the local store both hold — a profile
  /// the document is about to create needs none of that.
  ///
  /// A document id absent from [profilesRepository]'s live list (Issue
  /// #140 review round 2, item 6) is also checked, one [storage] lookup
  /// at a time, against a tombstoned local profile at that id — a
  /// soft-deleted profile the account import file is restoring, which must
  /// plan as `matched` (with `restoredFromTombstone`), not `created`; see
  /// [planImport]'s and `ProfilePlan.restoredFromTombstone`'s doc comments.
  Future<ImportPlan> buildPlan(AccountImportDocument document) async {
    final existingProfiles = await profilesRepository.list();
    final existingIds = {for (final p in existingProfiles) p.id};
    final matchedIds = <String>{};
    final tombstonedById = <String, domain.Profile>{};
    for (final p in document.profiles) {
      if (existingIds.contains(p.id)) {
        matchedIds.add(p.id);
        continue;
      }
      final row = await storage.getProfile(p.id, includeTombstones: true);
      if (row != null && row.deletedAt != null) {
        tombstonedById[p.id] = profileToDomain(row);
        matchedIds.add(p.id);
      }
    }
    final entriesByProfileId = <String, List<domain.DayEntry>>{};
    final observationsByProfileId = <String, List<domain.Observation>>{};
    final guardiansByProfileId = <String, List<ProfileGuardian>>{};
    for (final id in matchedIds) {
      entriesByProfileId[id] = await dayEntriesRepository.listForProfile(id);
      observationsByProfileId[id] =
          await observationsRepository.listForProfile(id);
      guardiansByProfileId[id] = await _guardiansFor(id);
    }
    return planImport(
      document: document,
      existingProfiles: existingProfiles,
      tombstonedProfilesById: tombstonedById,
      existingEntriesByProfileId: entriesByProfileId,
      existingObservationsByProfileId: observationsByProfileId,
      writeBlockReason: (profile) => writeBlockReasonFor(
        profile: profile,
        guardians: guardiansByProfileId[profile.id] ?? const [],
        currentUserId: currentUserId,
      ),
      // Issue #140 review, item 10: reuses the same guardian rows
      // `writeBlockReason` above already fetched — cheap, no extra query —
      // to drive `ImportPlan.sharesWithOtherGuardians`'s preview
      // disclosure. "Other" means an accepted guardian who isn't the
      // importing session's own user, mirroring `acceptedGuardianFor`'s
      // own null-safe reading of [currentUserId].
      hasOtherGuardians: (profile) =>
          (guardiansByProfileId[profile.id] ?? const []).any((g) =>
              g.status == GuardianStatus.accepted &&
              g.userId != currentUserId),
    );
  }

  Future<List<ProfileGuardian>> _guardiansFor(String profileId) {
    final fn = guardiansForProfile;
    return fn == null ? Future.value(const []) : fn(profileId);
  }

  /// Applies [plan] via [AccountImporter].
  Future<ImportPlanSummary> apply(ImportPlan plan) =>
      AccountImporter(storage).apply(plan);
}
