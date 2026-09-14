/// Per-profile tracking preferences (Issue #259): which tracking categories
/// the day sheet surfaces, and in what order, as one synced JSON document
/// stored on the profile itself (`profiles.tracking_preferences` — a
/// partial override map, not a dedicated synced table; see the migration's
/// header for the recorded storage call).
///
/// The document holds `{category: {enabled: bool, sort_order: int}}` keyed
/// by [TagCategoryWireName.wireName]. It is a **partial** map on purpose:
/// any category the document does not mention resolves to its default —
/// enabled, ordered after the customized ones by the care mode's own
/// surfacing order ([resolveTrackingCategories]' `defaultOrder`). That is
/// what keeps the mechanism forward-compatible with taxonomy growth
/// (Issue #249's unverified categories, and the categories #251 (TM-4b)
/// and #253 (TM-4d) will add): a document written before a category
/// existed never hides it, and a newly-adopted category simply shows up in
/// its default place until the profile's guardians curate it.
///
/// The one default that is not "enabled" is the minor-visibility rule
/// (global assumption #2, cited by #251 (TM-4b) and #253 (TM-4d)):
/// [kMinorDefaultHiddenTrackingCategories] lists the categories that
/// default to *disabled* on an `isMinor` profile, while staying enabled —
/// and enabling — for everyone else. The categories themselves do not
/// exist in [TagCategory] yet (their issues own the vocabulary); the rule
/// is keyed by wire name so it is already in force the moment they land.
/// Like every default here it is a default only: a `primary_guardian` can
/// enable a hidden category explicitly (the stored entry then wins), and
/// the server never enforces or even knows the rule — the preference is
/// presentation curation, never permission, and hiding a category never
/// deletes or hides already-logged entries for it.
///
/// Pure Dart (R14/R16); the server stores the document verbatim (shape
/// checked, category keys free text — the taxonomy is client-owned, the
/// `observations.category` "stored, never rejected" precedent).
library;

import 'dart:convert';

import '../tags.dart';

/// Categories that default to **disabled** on an `isMinor` profile
/// (Issue #259, per global assumption #2; the mechanism #251 (TM-4b) and
/// #253 (TM-4d) depend on for their minor-visibility toggles). Keyed by
/// [TagCategoryWireName.wireName] because the categories themselves are
/// not in [TagCategory] until their own issues land — the set is the
/// pre-wired rule, not dead weight. An explicit stored entry always
/// overrides the default: a primary guardian can enable a hidden category.
const Set<String> kMinorDefaultHiddenTrackingCategories = {
  'partying',
  'sex_life',
};

/// One category's stored preference (Issue #259).
class TrackingCategoryPreference {
  const TrackingCategoryPreference({required this.enabled, required this.sortOrder});

  /// Whether the category is surfaced in the day sheet. `false` hides the
  /// category from the picker without touching any already-logged data
  /// for it (Issue #259 AC3).
  final bool enabled;

  /// Curated position among the customized categories (ascending first).
  final int sortOrder;

  @override
  bool operator ==(Object other) =>
      other is TrackingCategoryPreference &&
      other.enabled == enabled &&
      other.sortOrder == sortOrder;

  @override
  int get hashCode => Object.hash(enabled, sortOrder);

  @override
  String toString() => 'TrackingCategoryPreference($enabled, $sortOrder)';
}

/// A profile's parsed tracking-preferences document (Issue #259).
///
/// Parsing is deliberately tolerant: an entry that does not match the
/// expected shape is dropped (that category resolves to its default)
/// rather than failing the whole document, and a category this build does
/// not know is kept for the round trip (a newer client's entry must
/// survive an older client's re-save) but never resolves to a surface.
/// A preference document is UI curation, never health content — a garbage
/// entry must degrade to "default", never break logging.
class TrackingPreferences {
  TrackingPreferences(Map<String, TrackingCategoryPreference> entries)
      : _entries = Map.of(entries);

  final Map<String, TrackingCategoryPreference> _entries;

  /// The stored entries keyed by category wire name. Unmodifiable view;
  /// may contain keys outside the current [TagCategory] set (kept for the
  /// round trip).
  Map<String, TrackingCategoryPreference> get entries =>
      Map.unmodifiable(_entries);

  /// The stored entry for [category], or null when the document does not
  /// curate it (the category resolves to its default).
  TrackingCategoryPreference? operator [](TagCategory category) =>
      _entries[category.wireName];

  /// An empty document: every category resolves to its default.
  const TrackingPreferences.empty() : _entries = const {};

  /// Parses the JSON-text form [LunarLogStorage] stores (and the wire
  /// carries as a JSON object). Null (the never-customized default) and
  /// the empty document are distinct inputs but resolve identically.
  /// Returns null for a null/empty input and for a document that is not a
  /// JSON object at all — same degradation as a malformed entry.
  static TrackingPreferences? fromJsonText(String? text) {
    if (text == null || text.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final entries = <String, TrackingCategoryPreference>{};
    decoded.forEach((key, value) {
      if (key is! String || value is! Map) return;
      final enabled = value['enabled'];
      final sortOrder = value['sort_order'];
      if (enabled is! bool) return;
      if (sortOrder is! int) return;
      entries[key] =
          TrackingCategoryPreference(enabled: enabled, sortOrder: sortOrder);
    });
    return TrackingPreferences(entries);
  }

  /// The JSON-text form stored locally and (as a decoded object) on the
  /// wire. Null when there is nothing to store.
  String? toJsonText() {
    if (_entries.isEmpty) return null;
    return jsonEncode({
      for (final entry in _entries.entries)
        entry.key: {
          'enabled': entry.value.enabled,
          'sort_order': entry.value.sortOrder,
        },
    });
  }

  @override
  bool operator ==(Object other) =>
      other is TrackingPreferences && _mapEquals(other._entries, _entries);

  @override
  int get hashCode => Object.hashAllUnordered(
      [for (final e in _entries.entries) Object.hash(e.key, e.value)]);

  @override
  String toString() => 'TrackingPreferences(${_entries.keys.toList()})';
}

bool _mapEquals(Map<String, TrackingCategoryPreference> a,
        Map<String, TrackingCategoryPreference> b) =>
    a.length == b.length &&
    a.entries.every((e) => identical(b[e.key], e.value) || b[e.key] == e.value);

/// The default enabled state for a category the document never mentions
/// (Issue #259): enabled for everyone, except the minor-hidden set on an
/// `isMinor` profile (global assumption #2; AC4). An explicit stored entry
/// always overrides this default — a primary guardian can enable a hidden
/// category, and nothing here is ever consulted by an authorization path.
bool defaultTrackingEnabled(TagCategory category, {required bool isMinor}) =>
    !(isMinor &&
        kMinorDefaultHiddenTrackingCategories.contains(category.wireName));

/// Resolves the day sheet's surfaced categories (Issue #259 AC1/AC2): the
/// profile's curated set and order first, then the uncurated remainder in
/// [defaultOrder] (the care mode's surfacing order, Issue #131), with
/// [defaultTrackingEnabled] applied to never-mentioned categories.
///
/// * Enabled = the stored entry's `enabled` when the document curates the
///   category, else [defaultTrackingEnabled].
/// * Order = explicit `sort_order` first (ascending; ties broken by
///   [defaultOrder] position, so the result is always deterministic),
///   then the uncurated categories in [defaultOrder] order.
/// * Categories the document mentions that this build does not know, and
///   disabled categories, never appear. Disabling hides a category from
///   the picker without deleting or hiding anything already logged for it
///   (AC3) — logged tags keep round-tripping through the sheet's save
///   path untouched.
List<TagCategory> resolveTrackingCategories({
  required List<TagCategory> defaultOrder,
  TrackingPreferences? preferences,
  bool isMinor = false,
}) {
  final curated = <_CuratedCategory>[];
  final fallback = <TagCategory>[];
  final defaultPosition = <TagCategory, int>{
    for (final (index, category) in defaultOrder.indexed) category: index,
  };

  // Walk the default order so the fallback half is already in position
  // order and the curated half's tie-break is stable.
  for (final category in defaultOrder) {
    final entry = preferences?[category];
    final enabled =
        entry?.enabled ?? defaultTrackingEnabled(category, isMinor: isMinor);
    if (!enabled) continue;
    if (entry != null) {
      curated.add(_CuratedCategory(category, entry.sortOrder));
    } else {
      fallback.add(category);
    }
  }

  curated.sort((a, b) => a.rankAgainst(b, defaultPosition: defaultPosition));
  return [...curated.map((c) => c.category), ...fallback];
}

/// One curated category mid-resolution: its [sortOrder] from the document
/// plus a tie-break comparator against the default-order positions.
class _CuratedCategory {
  const _CuratedCategory(this.category, this.sortOrder);

  final TagCategory category;
  final int sortOrder;

  /// Ascending `sort_order`; ties break by [defaultOrder] position so the
  /// result is always deterministic.
  int rankAgainst(_CuratedCategory other,
      {required Map<TagCategory, int> defaultPosition}) {
    final byOrder = sortOrder.compareTo(other.sortOrder);
    if (byOrder != 0) return byOrder;
    return (defaultPosition[category] ?? 0)
        .compareTo(defaultPosition[other.category] ?? 0);
  }
}
