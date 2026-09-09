/// Drift-row ↔ domain-model mapping. This file (and everything under
/// `lib/data/`) is the only place where storage types and domain types
/// meet (R14/R16 import discipline).
library;

import 'package:lunarlog/data/db/db.dart' as db;
import 'package:lunarlog/data/db/tables.dart' as db;
import 'package:lunarlog/domain/models/day_entry.dart' as domain;
import 'package:lunarlog/domain/models/flow_level.dart' as domain;
import 'package:lunarlog/domain/models/local_date.dart' as domain;
import 'package:lunarlog/domain/models/observation.dart' as domain;
import 'package:lunarlog/domain/models/profile.dart' as domain;
import 'package:lunarlog/domain/models/profile_guardian.dart' as domain;
import 'package:lunarlog/domain/models/profile_mode.dart' as domain;
import 'package:lunarlog/domain/models/profile_relationship.dart' as domain;

domain.Profile profileToDomain(db.Profile row) => domain.Profile(
      id: row.id,
      displayName: row.displayName,
      isMinor: row.isMinor,
      mode: domain.ProfileMode.fromDb(row.mode),
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
    );

domain.FlowLevel flowToDomain(db.FlowLevel flow) =>
    domain.FlowLevel.values.byName(flow.name);

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
      category: row.category ??
          (throw StateError(
              'observationToDomain: category is null for live observation ${row.id} '
              '(only a tombstone should ever have a null category)')),
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

domain.ProfileGuardian profileGuardianToDomain(db.ProfileGuardianData row) =>
    domain.ProfileGuardian(
      id: row.id,
      profileId: row.profileId,
      userId: row.userId,
      role: domain.GuardianRole.fromDb(row.role),
      status: domain.GuardianStatus.fromDb(row.status),
      displayName: row.displayName,
      invitedBy: row.invitedBy,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
