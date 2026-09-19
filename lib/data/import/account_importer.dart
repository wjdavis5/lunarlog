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
import 'package:lunarlog/domain/import/account_import_coordinator.dart';
import 'package:lunarlog/domain/import/account_importer.dart';
import 'package:lunarlog/domain/models/cycle_override.dart' as domain;
import 'package:lunarlog/domain/models/day_entry.dart' as domain;
import 'package:lunarlog/domain/models/guardian_note.dart' as domain;
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart' as domain;
import 'package:lunarlog/domain/models/profile.dart' as domain;
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/logging/custom_tag_registry.dart' as domain;
import 'package:lunarlog/domain/repositories/cycle_overrides_repository.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/guardian_notes_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart'
    show GuardiansForProfile;
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart'
    show ProfileLifecycleMode;
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/tag_registry_repository.dart';

/// Applies one already-built [ImportPlan] (Issue #140). See this file's
/// own doc comment for the transactional guarantee.
class DriftAccountImporter implements AccountImporter {
  const DriftAccountImporter(this._storage);

  final LunarLogStorage _storage;

  /// Wraps the entire plan in ONE Drift transaction: an error on profile N
  /// rolls back profiles 1..N-1, entries, and observations atomically.
  @override
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
    for (final cycleOverridePlan in plan.cycleOverrides) {
      await _applyCycleOverride(profileId, cycleOverridePlan);
    }
    for (final customTagPlan in plan.customTags) {
      await _applyCustomTag(profileId, customTagPlan);
    }
    for (final guardianNotePlan in plan.guardianNotes) {
      await _applyGuardianNote(profileId, guardianNotePlan);
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
      // Issue #140 review, LLA-084: same create-only, absent-means-column-
      // default treatment as mode/bbtUnit/weightUnit above (an older
      // export simply never carried these keys).
      birthYear: plan.birthYear,
      relationship: plan.relationship?.toDb(),
      lastPeriodStart: plan.lastPeriodStart?.iso,
      typicalCycleLengthDays: plan.typicalCycleLengthDays,
      typicalPeriodLengthDays: plan.typicalPeriodLengthDays,
      // Issue #648: same create-only, absent-means-null treatment as
      // birthYear/relationship/etc above — a matched profile keeps its own
      // stored document untouched (`_resolveProfileId` never reaches here
      // for a match).
      trackingPreferences: plan.trackingPreferences?.toJsonText(),
    );
    await _applyProfileMode(created.id, plan.profileMode);
    return created.id;
  }

  /// Issue #140 review, LLA-084: writes the file's #188 life-stage
  /// mode/birth-control state onto a freshly CREATED profile only — a
  /// no-op when the file carried none (an older export, or a profile that
  /// never had a `profile_modes` row). Never called for a matched profile;
  /// `_resolveProfileId` only reaches this from the create branch, mirroring
  /// mode/bbtUnit/weightUnit's own create-only treatment (a matched
  /// profile's own stored mode/birth-control state is never overwritten).
  Future<void> _applyProfileMode(
      String profileId, ProfileLifecycleMode? mode) async {
    if (mode == null) return;
    await _storage.upsertProfileMode(
      profileId: profileId,
      mode: mode.mode.toDb(),
      modeStartedOn: mode.modeStartedOn,
      estimatedDueDate: mode.estimatedDueDate,
      birthControlMethod: mode.birthControlMethod,
      birthControlStartedOn: mode.birthControlStartedOn,
      birthControlStoppedOn: mode.birthControlStoppedOn,
    );
  }

  Future<domain.DayEntry> _applyEntry(
    String profileId,
    DayEntryPlan plan,
  ) async {
    if (plan.outcome == DayEntryImportOutcome.merge) {
      await _assertEntryNotStale(profileId, plan);
    }
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

  /// Issue #140 review, LLA-085: re-reads the live row this merge plan
  /// targets — inside the same transaction [apply] already opened — and
  /// throws [StaleImportPlanException] if it no longer matches the
  /// snapshot `planImport` merged against (see
  /// [DayEntryPlan.existingUpdatedAt]'s doc comment). Cheap: one indexed
  /// lookup per merge target, and only a merge plan ever carries an
  /// [DayEntryPlan.existingUpdatedAt] to compare — an `add` plan has
  /// nothing existing to go stale against.
  Future<void> _assertEntryNotStale(String profileId, DayEntryPlan plan) async {
    final current = await _storage.getDayEntry(
      profileId: profileId,
      localDate: plan.localDate.iso,
    );
    if (current?.updatedAt != plan.existingUpdatedAt) {
      throw const StaleImportPlanException();
    }
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
    await _storage.upsertObservation(
      // Issue #140 review round 2, item 3 (revised by LLA-086, Issue #140
      // review): reuse the file's own observation id ONLY when nothing
      // already exists under it — see `_addObservationId`'s doc comment
      // for why an `add` outcome from `planImport`'s semantic dedup alone
      // is not enough to make that reuse safe.
      id: await _addObservationId(plan.imported.id),
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

  /// Issue #140 review, LLA-084: writes one `add`-outcome cycle override.
  /// Additive like [_applyObservation] — a `skip` outcome (a live override
  /// already occupies this `cycleStartDate`) writes nothing.
  Future<void> _applyCycleOverride(
      String profileId, CycleOverridePlan plan) async {
    if (plan.outcome != CycleOverrideImportOutcome.add) return;
    await _storage.upsertCycleOverride(
      id: await _addCycleOverrideId(plan.imported.id, profileId),
      profileId: profileId,
      cycleStartDate: plan.imported.cycleStartDate.iso,
      excludedFromAverage: plan.imported.excludedFromAverage,
      manualStart: plan.imported.manualStart,
      noteId: plan.imported.noteId,
    );
  }

  /// [fileId] when it is a syntactically valid ULID AND nothing already
  /// exists at the composite (id, profileId) key — otherwise null, so
  /// [LunarLogStorage.upsertCycleOverride] mints a fresh id instead (the
  /// LLA-086 pattern, applied to `cycle_overrides`' own `(id, profile_id)`
  /// identity — see [LunarLogStorage.getCycleOverrideById]'s doc comment
  /// for why that composite key, not a bare id collision, is what matters
  /// here). `planImport`'s `_planCycleOverrides` decides `add` purely from
  /// the `cycleStartDate` — reusing a colliding file id regardless would
  /// have `upsertCycleOverride` resolve identity by the composite key and
  /// silently move an unrelated existing override onto this date.
  Future<String?> _addCycleOverrideId(String fileId, String profileId) async {
    if (!isValidUlid(fileId)) return null;
    final conflict = await _storage.getCycleOverrideById(fileId, profileId);
    return conflict == null ? fileId : null;
  }

  /// [fileId] when it is a syntactically valid ULID AND nothing already
  /// exists under it (any profile, live or tombstoned) — otherwise null,
  /// so [LunarLogStorage.upsertObservation] mints a fresh id instead (Issue
  /// #140 review, LLA-086). `planImport`'s `_planObservations` decides
  /// `add` purely from the semantic (profileId, localDate, category, code)
  /// key — it never checks whether the file's own raw id happens to
  /// already be in use — so a stored observation whose category/code
  /// changed since an earlier backup shares no semantic key with the
  /// file's row despite sharing its id. Reusing that id here regardless
  /// would have [LunarLogStorage.upsertObservation] resolve identity by id
  /// ALONE and silently overwrite the unrelated existing row, even though
  /// `planImport` called this an additive `add`. This check runs at apply
  /// time, inside the same transaction as the write, so it also catches an
  /// id a DIFFERENT profile's row already claims — the reachable case
  /// `planImport`'s own per-profile view can never see (only a
  /// storage-wide lookup can).
  Future<String?> _addObservationId(String fileId) async {
    if (!isValidUlid(fileId)) return null;
    final conflict = await _storage.getObservationById(fileId);
    return conflict == null ? fileId : null;
  }

  /// Issue #824 (kAccountExportSchemaVersion v12): writes one `add`-outcome
  /// custom tag. Additive like [_applyCycleOverride] — a `skip` outcome
  /// writes nothing.
  Future<void> _applyCustomTag(String profileId, CustomTagPlan plan) async {
    if (plan.outcome != CustomTagImportOutcome.add) return;
    final tag = plan.imported;
    final tagId = await _addCustomTagId(tag.id);
    await _storage.upsertProfileTagRegistryEntry(
      id: tagId,
      profileId: profileId,
      code: tag.code,
      displayName: tag.displayName,
      category: tag.category,
      intensityEnabled: tag.intensityEnabled,
      hiddenAt: tag.hiddenAt,
      sortOrder: tag.sortOrder,
      updatedAt: tag.updatedAt,
    );
  }

  /// [fileId] when it is a syntactically valid ULID AND nothing already
  /// exists with this id in the registry — otherwise null, so
  /// [LunarLogStorage.upsertProfileTagRegistryEntry] mints a fresh id instead.
  Future<String?> _addCustomTagId(String fileId) async {
    if (!isValidUlid(fileId)) return null;
    final conflict = await _storage.getProfileTagRegistryEntriesById(fileId);
    return conflict == null ? fileId : null;
  }

  /// Issue #870 (kAccountExportSchemaVersion v13): writes one `add`-outcome
  /// guardian note. Additive like [_applyCustomTag] — a `skip` outcome
  /// writes nothing.
  Future<void> _applyGuardianNote(
      String profileId, GuardianNotePlan plan) async {
    if (plan.outcome != GuardianNoteImportOutcome.add) return;
    final note = plan.imported;
    final noteId = await _addGuardianNoteId(note.id, profileId);
    await _storage.upsertGuardianNote(
      id: noteId,
      profileId: profileId,
      localDate: note.localDate.iso,
      tz: note.tz,
      body: note.body,
      updatedAt: note.updatedAt,
    );
  }

  /// [fileId] when it is a syntactically valid ULID AND nothing already
  /// exists under it on another profile (or live on this profile) — otherwise
  /// null, so [LunarLogStorage.upsertGuardianNote] mints a fresh id instead.
  /// If a row exists with [fileId] on this same profile and is tombstoned,
  /// [fileId] is reused so [LunarLogStorage.upsertGuardianNote] revives it.
  Future<String?> _addGuardianNoteId(String fileId, String profileId) async {
    if (!isValidUlid(fileId)) return null;
    final conflict = await _storage.getGuardianNoteById(fileId);
    if (conflict == null) return fileId;
    if (conflict.profileId == profileId && conflict.deletedAt != null) {
      return fileId;
    }
    return null;
  }
}

/// The glue between a UI caller and [AccountImporter]/`planImport`:
/// reads just enough of the current local store to plan against, then
/// applies the plan. See this file's own doc comment.
class DriftAccountImportCoordinator
    implements AccountImportCoordinator {
  const DriftAccountImportCoordinator({
    required this.profilesRepository,
    required this.dayEntriesRepository,
    required this.observationsRepository,
    required this.storage,
    this.cycleOverridesRepository,
    this.tagRegistryRepository,
    this.guardianNotesRepository,
    this.guardiansForProfile,
    this.currentUserId,
    this.currentUserIdProvider,
    this.importer,
    this.todayProvider = LocalDate.today,
  });

  final ProfilesRepository profilesRepository;
  final DayEntriesRepository dayEntriesRepository;
  final ObservationsRepository observationsRepository;
  final LunarLogStorage storage;

  /// Issue #140 review, LLA-084: feeds `planImport`'s
  /// `existingCycleOverridesByProfileId` for a *matched* profile, so a
  /// restore's cycle overrides plan additively against what the device
  /// already has, not just what a brand-new profile starts empty with.
  /// Null (a caller that skips it) reads as "no existing overrides for any
  /// matched profile" — every file cycle override then plans `add`,
  /// mirroring [guardiansForProfile]'s own null-means-no-info default.
  final CycleOverridesRepository? cycleOverridesRepository;

  /// Issue #824 (kAccountExportSchemaVersion v12): feeds `planImport`'s
  /// `existingCustomTagsByProfileId` for a *matched* profile, so custom tags
  /// plan additively without clobbering existing codes or exceeding the cap.
  final TagRegistryRepository? tagRegistryRepository;

  /// Issue #870 (kAccountExportSchemaVersion v13): feeds `planImport`'s
  /// `existingGuardianNotesByProfileId` for a *matched* profile, so guardian
  /// notes plan additively without clobbering existing notes.
  final GuardianNotesRepository? guardianNotesRepository;

  /// Null means "no guardian info available" — every matched profile
  /// fails open (writable) unless archived, the same fail-open precedent
  /// [writeBlockReasonFor] itself documents.
  final GuardiansForProfile? guardiansForProfile;

  final String? currentUserId;

  /// Issue #848: the local-civil-date seam `planImport` uses to bound every
  /// imported day entry's date. Defaults to the device's local today (a
  /// boundary clock read); tests inject a fixed date.
  final LocalDate Function() todayProvider;

  /// Resolves the acting user's id at call time, taking precedence over
  /// [currentUserId] when present. A single coordinator instance provided
  /// from the composition root uses this so an import that happens after a
  /// later sign-in still gates on the signed-in user (the UI no longer
  /// builds a fresh coordinator per pick).
  final String? Function()? currentUserIdProvider;

  /// The effectful import writer (Issue #418, AC4): typed against the
  /// domain [AccountImporter] contract, so the one-implementor contract is
  /// consumed rather than dangling. Null (tests, and callers that only
  /// plan) falls back to a [DriftAccountImporter] over [storage].
  final AccountImporter? importer;

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
  ///
  /// The acting user id: a live [currentUserIdProvider] wins over the
  /// captured [currentUserId], so one coordinator can be reused across
  /// sign-ins. Extracted from [buildPlan] to keep its complexity down.
  String? _resolveCurrentUserId() {
    final provider = currentUserIdProvider;
    if (provider != null) return provider();
    return currentUserId;
  }

  @override
  Future<ImportPlan> buildPlan(AccountImportDocument document) async {
    final currentUserId = _resolveCurrentUserId();
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
    final cycleOverridesByProfileId = <String, List<domain.CycleOverride>>{};
    final customTagsByProfileId = <String, List<domain.CustomTag>>{};
    final guardianNotesByProfileId = <String, List<domain.GuardianNote>>{};
    final guardiansByProfileId = <String, List<ProfileGuardian>>{};
    for (final id in matchedIds) {
      entriesByProfileId[id] = await dayEntriesRepository.listForProfile(id);
      observationsByProfileId[id] =
          await observationsRepository.listForProfile(id);
      cycleOverridesByProfileId[id] = await _cycleOverridesFor(id);
      customTagsByProfileId[id] = await _customTagsFor(id);
      guardianNotesByProfileId[id] = await _guardianNotesFor(id);
      guardiansByProfileId[id] = await _guardiansFor(id);
    }
    return planImport(
      document: document,
      existingProfiles: existingProfiles,
      tombstonedProfilesById: tombstonedById,
      existingEntriesByProfileId: entriesByProfileId,
      existingObservationsByProfileId: observationsByProfileId,
      existingCycleOverridesByProfileId: cycleOverridesByProfileId,
      existingCustomTagsByProfileId: customTagsByProfileId,
      existingGuardianNotesByProfileId: guardianNotesByProfileId,
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
      // Issue #848: bound every imported entry's date against the device's
      // local today (the same value the calendar uses).
      today: todayProvider(),
    );
  }

  Future<List<ProfileGuardian>> _guardiansFor(String profileId) {
    final fn = guardiansForProfile;
    return fn == null ? Future.value(const []) : fn(profileId);
  }

  Future<List<domain.CycleOverride>> _cycleOverridesFor(String profileId) {
    final repo = cycleOverridesRepository;
    return repo == null ? Future.value(const []) : repo.listForProfile(profileId);
  }

  Future<List<domain.CustomTag>> _customTagsFor(String profileId) async {
    final repo = tagRegistryRepository;
    if (repo != null) return repo.listForProfile(profileId);
    return [
      for (final row in await storage.getProfileTagRegistry(profileId))
        customTagToDomain(row),
    ];
  }

  Future<List<domain.GuardianNote>> _guardianNotesFor(String profileId) async {
    final repo = guardianNotesRepository;
    if (repo != null) return repo.listForProfile(profileId);
    return [
      for (final row in await storage.getGuardianNotesForProfile(profileId))
        guardianNoteToDomain(row),
    ];
  }

  /// Applies [plan] via the injected [importer] contract.
  @override
  Future<ImportPlanSummary> apply(ImportPlan plan) =>
      (importer ?? DriftAccountImporter(storage)).apply(plan);
}
