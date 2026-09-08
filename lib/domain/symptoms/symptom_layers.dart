/// Symptom-layer queries (issue #133, roadmap R2): the pure "query over
/// history" seam behind the calendar's symptom overlays.
///
/// This is the app's first history-query surface, so the shape is kept
/// deliberately small and reusable — ranking a profile's tag usage and
/// matching a day against one tag — rather than baking calendar-specific
/// filtering in. A later search/filter feature composes these instead of
/// duplicating them. Pure Dart, no Flutter, nothing persisted (KTD8).
library;

import '../models/day_entry.dart';
import '../tags.dart';

/// At most this many symptom layers may be active at once (R2).
const int kMaxSymptomLayers = 3;

/// One tag's usage count across a profile's entries.
class TagUsage {
  const TagUsage(this.code, this.count);

  /// Stable tag code (`lib/domain/tags.dart` taxonomy).
  final String code;

  /// How many live entries carry the tag.
  final int count;

  /// Default display string; unknown codes degrade to the raw code.
  String get display => tagByCode(code)?.display ?? code;

  @override
  String toString() => 'TagUsage($code ×$count)';
}

/// Ranks tag usage across [entries], most-used first; ties break in
/// taxonomy order so the ranking is deterministic. Tombstoned entries are
/// skipped (repository reads are already live-only; the check is
/// defensive for full-fidelity inputs).
List<TagUsage> rankTagUsage(Iterable<DayEntry> entries) {
  final counts = <String, int>{};
  for (final entry in entries) {
    if (entry.deletedAt != null) continue;
    for (final tag in entry.tags) {
      counts[tag] = (counts[tag] ?? 0) + 1;
    }
  }
  final taxonomyOrder = {
    for (var i = 0; i < kTagTaxonomy.length; i++) kTagTaxonomy[i].code: i,
  };
  final ranked = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      if (byCount != 0) return byCount;
      return (taxonomyOrder[a.key] ?? taxonomyOrder.length).compareTo(
        taxonomyOrder[b.key] ?? taxonomyOrder.length,
      );
    });
  return List.unmodifiable([
    for (final entry in ranked) TagUsage(entry.key, entry.value),
  ]);
}

/// The default active layer set (R2): the profile's most-used tags, at
/// most [max]. Recomputed per stream emission until the operator first
/// toggles a layer — the selection itself is never persisted.
List<String> defaultLayerTags(
  Iterable<DayEntry> entries, {
  int max = kMaxSymptomLayers,
}) => [for (final usage in rankTagUsage(entries).take(max)) usage.code];

/// Whether [entry] (possibly absent) carries [tag] — the per-day match a
/// layer overlay renders.
bool layerMatches(DayEntry? entry, String tag) =>
    entry != null && entry.deletedAt == null && entry.tags.contains(tag);
