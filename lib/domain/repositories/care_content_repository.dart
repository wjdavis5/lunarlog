/// Repository seam for a profile's shared care content (Issue #128):
/// standing care notes and the visit-prep checklist. Every method is scoped
/// to exactly one profile id (R3).
library;

import '../models/care_note.dart';
import '../models/visit_prep_item.dart';

abstract interface class CareContentRepository {
  /// The profile's live care notes, oldest write first.
  Future<List<CareNote>> listCareNotes(String profileId);

  /// Live view of [listCareNotes] for reactive UI.
  Stream<List<CareNote>> watchCareNotes(String profileId);

  /// Creates (no [id]) or revises ([id] set) a care note.
  Future<CareNote> saveCareNote({
    String? id,
    required String profileId,
    required String body,
  });

  /// Tombstones a care note (never a hard delete — the deletion syncs).
  Future<void> deleteCareNote(String id);

  /// The profile's live visit-prep items, unchecked first.
  Future<List<VisitPrepItem>> listPrepItems(String profileId);

  /// Live view of [listPrepItems] for reactive UI.
  Stream<List<VisitPrepItem>> watchPrepItems(String profileId);

  /// Issue #851: the profile's live supplies items (kind == supply),
  /// unstocked first. Same ordering, role gating, and tombstone semantics
  /// as [listPrepItems] — a supply item is the same substrate with a
  /// different `kind`.
  Future<List<VisitPrepItem>> listSupplyItems(String profileId);

  /// Live view of [listSupplyItems] for reactive UI.
  Stream<List<VisitPrepItem>> watchSupplyItems(String profileId);

  /// Adds an unchecked item to one of the profile's lists. [kind] defaults
  /// to the visit-prep checklist (Issue #851 adds `supply`).
  Future<VisitPrepItem> addPrepItem({
    String? id,
    required String profileId,
    required String body,
    VisitPrepItemKind kind = VisitPrepItemKind.visitPrep,
  });

  /// Revises an item's text, keeping its check state. Null when the item
  /// is not held locally.
  Future<VisitPrepItem?> editPrepItem({
    required String id,
    required String body,
  });

  /// Checks (or unchecks) an item, recording [checkedByUserId] (the bound
  /// account, or null for a never-synced local-only operator) on a check
  /// and clearing it on an uncheck. Null when the item is not held locally
  /// or is tombstoned.
  Future<VisitPrepItem?> setPrepItemChecked({
    required String id,
    required bool checked,
    String? checkedByUserId,
  });

  /// Tombstones a prep item (never a hard delete).
  Future<void> deletePrepItem(String id);

  /// Tombstones every *checked*, live item on one of the profile's lists —
  /// unchecked items survive. Returns the number of items cleared. [kind]
  /// defaults to the visit-prep list (the pre-#851 behavior); pass
  /// [VisitPrepItemKind.supply] to clear only the supplies list.
  Future<int> clearCheckedPrepItems(
    String profileId, {
    VisitPrepItemKind kind = VisitPrepItemKind.visitPrep,
  });
}
