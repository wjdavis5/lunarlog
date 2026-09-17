/// Issue #257: the per-profile custom-tag registry repository -- the
/// create/rename/retire surface the day sheet's tag picker drives, and the
/// read the picker renders from.
library;

import '../logging/custom_tag_registry.dart';

abstract class TagRegistryRepository {
  /// The profile's LIVE registry entries (tombstoned rows excluded),
  /// retired entries included -- retirement is a picker concern
  /// ([CustomTag.offered]), not a read filter (retired entries still
  /// resolve stored codes to display names). Ordered by [CustomTag.code]
  /// for a stable list.
  Future<List<CustomTag>> listForProfile(String profileId);

  /// Stream variant of [listForProfile] for reactive UI (the day sheet
  /// re-renders when a co-guardian's registry write syncs in).
  Stream<List<CustomTag>> watchForProfile(String profileId);

  /// Creates a registry entry for [label] (validated with
  /// [validateCustomTagLabel] against [registry] first -- the caller owns
  /// that check so the UI can show a field-level error instead of an
  /// exception). Returns the created entry.
  Future<CustomTag> create({
    required String profileId,
    required String label,
  });

  /// Rewrites [tagId]'s display label. The entry's code is immutable (a
  /// rename never breaks stored references); throws [ArgumentError] when
  /// [label] is invalid or [tagId] is unknown/tombstoned.
  Future<CustomTag> rename({required String tagId, required String label});

  /// RETIRES the entry: sets `hidden_at`, removing the code from the
  /// day-sheet picker while every stored row referencing it keeps
  /// rendering. Never deletes anything (Issue #257's core rule).
  Future<void> retire(String tagId);
}
