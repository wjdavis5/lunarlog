/// Drift-row ↔ domain-model mapping. This file (and everything under
/// `lib/data/`) is the only place where storage types and domain types
/// meet (R14/R16 import discipline).
library;

import 'package:lunarlog/data/db/db.dart' as db;
import 'package:lunarlog/data/db/tables.dart' as db;
import 'package:lunarlog/domain/logging/custom_tag_registry.dart' as domain;
import 'package:lunarlog/domain/logging/day_entry_merge_event.dart' as domain;
import 'package:lunarlog/domain/models/care_note.dart' as domain;
import 'package:lunarlog/domain/models/cycle_override.dart' as domain;
import 'package:lunarlog/domain/models/day_entry.dart' as domain;
import 'package:lunarlog/domain/models/flow_level.dart' as domain;
import 'package:lunarlog/domain/models/guardian_note.dart' as domain;
import 'package:lunarlog/domain/models/local_date.dart' as domain;
import 'package:lunarlog/domain/models/measurement_unit.dart' as domain;
import 'package:lunarlog/domain/models/observation.dart' as domain;
import 'package:lunarlog/domain/models/observation_category.dart' as domain;
import 'package:lunarlog/domain/models/profile.dart' as domain;
import 'package:lunarlog/domain/models/profile_guardian.dart' as domain;
import 'package:lunarlog/domain/models/profile_mode.dart' as domain;
import 'package:lunarlog/domain/models/profile_relationship.dart' as domain;
import 'package:lunarlog/domain/logging/tracking_preferences.dart' as domain;
import 'package:lunarlog/domain/models/visit_prep_item.dart' as domain;

domain.Profile profileToDomain(db.Profile row) => domain.Profile(
      id: row.id,
      displayName: row.displayName,
      isMinor: row.isMinor,
      mode: domain.ProfileMode.fromDb(row.mode),
      // Issue #853: the nullable tri-state framing flag. A stored
      // `mode = 'irregular'` row can only predate the v28 migration or come
      // from a code path that bypassed it — decode-time mapping lives in
      // `row_codec.dart` (the wire boundary), so anything reaching here
      // already reads `standard`; this mapper just carries the flag.
      irregularFraming: row.irregularFraming,
      sortOrder: row.sortOrder,
      archivedAt: row.archivedAt,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
      birthYear: row.birthYear,
      relationship: row.relationship == null
          ? null
          : domain.ProfileRelationship.fromDb(row.relationship!),
      transferredAt: row.transferredAt,
      transferredToUserId: row.transferredToUserId,
      lastPeriodStart: row.lastPeriodStart == null
          ? null
          : domain.LocalDate.fromIso(row.lastPeriodStart!),
      typicalCycleLengthDays: row.typicalCycleLengthDays,
      typicalPeriodLengthDays: row.typicalPeriodLengthDays,
      // Issue #259: parsed here (not in the codec) so every UI read of
      // domain.Profile sees the resolved-tolerant document; a malformed
      // stored text degrades to null (all defaults), never a throwing read.
      trackingPreferences: domain.TrackingPreferences.fromJsonText(
          row.trackingPreferences),
      // Issue #255: display-unit preferences. `fromDb` degrades an
      // unrecognised stored value to the column default — presentation
      // only, so a value this build doesn't recognise never crashes a read.
      bbtUnit: domain.BbtUnit.fromDb(row.bbtUnit),
      weightUnit: domain.WeightUnit.fromDb(row.weightUnit),
    );

/// Storage `FlowLevel` -> domain `FlowLevel`. Issue #247 spotting-alias
/// translation: a stored `spotting` row (deprecated -- pre-#247 data, or
/// an old peer's sync payload) reads as [domain.FlowLevel.notBleeding]
/// here, never [domain.FlowLevel.spotting] itself (that value exists only
/// so `fromDb`/`FlowLevelConverter` never throw on old data). The day is
/// still a definite, positive "something was logged" fact, not
/// "unlogged" -- the spotting symptom itself is surfaced separately, from
/// the `observations` layer (`DriftObservationsRepository.listForProfile`
/// synthesises a `spotting` observation for a live spotting-flow row that
/// predates this migration's server-side backfill).
domain.FlowLevel flowToDomain(db.FlowLevel flow) =>
    flow == db.FlowLevel.spotting
        ? domain.FlowLevel.notBleeding
        : domain.FlowLevel.values.byName(flow.name);

db.FlowLevel flowFromDomain(domain.FlowLevel flow) =>
    db.FlowLevel.values.byName(flow.name);

domain.DayEntry dayEntryToDomain(db.DayEntry row) => domain.DayEntry(
      id: row.id,
      profileId: row.profileId,
      localDate: domain.LocalDate.fromIso(row.localDate),
      tz: row.tz,
      flow: flowToDomain(row.flow),
      tags: row.tags,
      note: row.note,
      notePrivate: row.notePrivate,
      pms: row.pms,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
      loggedByUserId: row.loggedByUserId,
      lastModifiedByUserId: row.lastModifiedByUserId,
      source: domain.DayEntrySource.fromDb(row.source),
      sourceId: row.sourceId,
      importId: row.importId,
    );

/// Issue #240: drift-row -> domain [domain.Observation]. Mirrors
/// [dayEntryToDomain]'s shape; used by [DriftObservationsRepository] so
/// account export (`kAccountExportSchemaVersion` v3) reads a real,
/// per-profile observations list instead of always exporting an empty one.
///
/// [row.category] is only nullable at the storage layer for a tombstoned
/// row (review finding: category is cleared there like every other
/// payload column); this function's only caller
/// ([DriftObservationsRepository.listForProfile]) filters tombstones out
/// by default, so a null here would mean a caller broke that contract —
/// surfaced as a clear failure rather than silently exporting a mistaken
/// empty category.
domain.Observation observationToDomain(db.Observation row) =>
    domain.Observation(
      id: row.id,
      dayEntryId: row.dayEntryId,
      profileId: row.profileId,
      localDate: domain.LocalDate.fromIso(row.localDate),
      observedAt: row.observedAt,
      tz: row.tz,
      // Issue #847: the one place the free-text stored category becomes the
      // typed closed set; an unrecognised code is retained verbatim as
      // `UnknownObservationCategory`, never degraded to a known member.
      category: domain.ObservationCategory.fromCode(
        row.category ??
            (throw StateError(
                'observationToDomain: category is null for live observation ${row.id} '
                '(only a tombstone should ever have a null category)')),
      ),
      code: row.code,
      valueNum: row.valueNum,
      valueText: row.valueText,
      unit: row.unit,
      intensity: row.intensity,
      excluded: row.excluded,
      source: domain.ObservationSource.fromDb(row.source),
      sourceId: row.sourceId,
      importId: row.importId,
      raw: row.raw,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
      loggedByUserId: row.loggedByUserId,
      lastModifiedByUserId: row.lastModifiedByUserId,
    );

/// Issue #540: fails *closed* on an unrecognised `role`/`status` rather than
/// propagating [domain.GuardianRole.fromDb]/[domain.GuardianStatus.fromDb]'s
/// null through to a `ProfileGuardian` this codebase has no null-role/
/// null-status representation for — an unknown role maps to
/// [domain.GuardianRole.viewer] (least privilege: read-only, cannot log,
/// cannot manage guardians, cannot delete the profile — see that enum's
/// `can*` getters) and an unknown status maps to
/// [domain.GuardianStatus.revoked] (never treated as an accepted
/// membership). Cross-references [domain.GuardianRole.fromDb] and
/// [domain.GuardianStatus.fromDb], whose own doc comments explain why they
/// return null instead of throwing.
domain.ProfileGuardian profileGuardianToDomain(db.ProfileGuardianData row) =>
    domain.ProfileGuardian(
      id: row.id,
      profileId: row.profileId,
      userId: row.userId,
      role: domain.GuardianRole.fromDb(row.role) ?? domain.GuardianRole.viewer,
      status:
          domain.GuardianStatus.fromDb(row.status) ?? domain.GuardianStatus.revoked,
      displayName: row.displayName,
      invitedBy: row.invitedBy,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      isSubject: row.isSubject,
    );

/// Issue #128: drift-row -> domain [domain.CareNote]. Mirrors
/// [dayEntryToDomain]'s shape; used by [CareContentRepository] so account
/// export (`kAccountExportSchemaVersion` v6) reads a real, per-profile
/// care-notes list instead of always exporting an empty one.
domain.CareNote careNoteToDomain(db.CareNoteData row) => domain.CareNote(
      id: row.id,
      profileId: row.profileId,
      body: row.body,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
      loggedByUserId: row.loggedByUserId,
      lastModifiedByUserId: row.lastModifiedByUserId,
    );

/// Issue #801: drift-row -> domain [domain.GuardianNote]. Mirrors
/// [careNoteToDomain]'s shape, plus the dated identity (`localDate`/`tz`).
domain.GuardianNote guardianNoteToDomain(db.GuardianNoteData row) =>
    domain.GuardianNote(
      id: row.id,
      profileId: row.profileId,
      localDate: domain.LocalDate.fromIso(row.localDate),
      tz: row.tz,
      body: row.body,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
      loggedByUserId: row.loggedByUserId,
      lastModifiedByUserId: row.lastModifiedByUserId,
    );

/// Issue #188: drift-row -> domain [domain.CycleOverride]. Issue #140
/// review, LLA-084: used by `DriftCycleOverridesRepository.listForProfile`
/// so account export can carry the full-fidelity row (id, manualStart,
/// noteId included), not just the excluded-from-average boolean.
domain.CycleOverride cycleOverrideToDomain(db.CycleOverrideData row) =>
    domain.CycleOverride(
      id: row.id,
      profileId: row.profileId,
      cycleStartDate: row.cycleStartDate,
      excludedFromAverage: row.excludedFromAverage,
      manualStart: row.manualStart,
      noteId: row.noteId,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
    );

/// Issue #128: drift-row -> domain [domain.VisitPrepItem]. Mirrors
/// [careNoteToDomain]'s shape, plus the kind (Issue #851) and check state.
domain.VisitPrepItem visitPrepItemToDomain(db.VisitPrepItemData row) =>
    domain.VisitPrepItem(
      id: row.id,
      profileId: row.profileId,
      body: row.body,
      kind: domain.VisitPrepItemKind.fromDb(row.kind),
      isChecked: row.isChecked,
      checkedByUserId: row.checkedByUserId,
      checkedAt: row.checkedAt,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
      loggedByUserId: row.loggedByUserId,
      lastModifiedByUserId: row.lastModifiedByUserId,
    );

/// Issue #130: storage row -> domain merge-disclosure event (the day
/// sheet's notice model). The `field` normalisation mirrors the codec's:
/// an unrecognised value can only come from a broken writer and degrades
/// to `note`.
domain.DayEntryMergeEvent dayEntryMergeEventToDomain(
        db.DayEntryMergeEventData row) =>
    domain.DayEntryMergeEvent(
      id: row.id,
      profileId: row.profileId,
      localDateIso: row.localDate,
      winningRowId: row.winningRowId,
      losingRowId: row.losingRowId,
      field: domain.DayEntryMergeEventField.fromDb(row.field),
      losingValueText: row.losingValueText,
      losingAuthorUserId: row.losingAuthorUserId,
      winningAuthorUserId: row.winningAuthorUserId,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );

/// Issue #257: storage row -> domain [domain.CustomTag]. The repository
/// read is already scoped to live rows (tombstones filtered in storage),
/// so the mapper carries `deletedAt` through for completeness only.
domain.CustomTag customTagToDomain(db.ProfileTagRegistryEntry row) =>
    domain.CustomTag(
      id: row.id,
      profileId: row.profileId,
      code: row.code,
      displayName: row.displayName,
      category: row.category,
      intensityEnabled: row.intensityEnabled,
      hiddenAt: row.hiddenAt,
      sortOrder: row.sortOrder,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
    );
