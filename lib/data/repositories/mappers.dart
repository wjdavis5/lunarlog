/// Drift-row ↔ domain-model mapping. This file (and everything under
/// `lib/data/`) is the only place where storage types and domain types
/// meet (R14/R16 import discipline).
library;

import 'package:lunarlog/data/db/db.dart' as db;
import 'package:lunarlog/data/db/tables.dart' as db;
import 'package:lunarlog/domain/models/day_entry.dart' as domain;
import 'package:lunarlog/domain/models/flow_level.dart' as domain;
import 'package:lunarlog/domain/models/local_date.dart' as domain;
import 'package:lunarlog/domain/models/profile.dart' as domain;
import 'package:lunarlog/domain/models/profile_guardian.dart' as domain;

domain.Profile profileToDomain(db.Profile row) => domain.Profile(
      id: row.id,
      displayName: row.displayName,
      isMinor: row.isMinor,
      sortOrder: row.sortOrder,
      archivedAt: row.archivedAt,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
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
