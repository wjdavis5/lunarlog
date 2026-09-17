/// Reusable, searchable, collapsible tag picker (Issue #234).
///
/// Replaces `lib/ui/logging/day_sheet.dart`'s previous unfiltered [Wrap] of
/// every [kTagTaxonomy] entry in a category with: a sticky search field
/// that filters chips (and hides an attested category section entirely
/// once nothing in it matches), a "Recent" row seeded from the profile's
/// actual logging history (`lib/domain/logging/tag_recents.dart` — device-
/// local, per profile, no new sync table), and one collapsible section per
/// curated category. An option-set-unverified category
/// ([kUnverifiedTagCategories]) still renders the "unverified — pin before
/// shipping" caption instead of chips while not searching, exactly as the
/// day sheet did before this issue (and is simply skipped, like an
/// unmatched attested category, while a search is active).
///
/// Selection/toggle state is fully owned by the caller — this widget is a
/// pure view over [selected] plus its own ephemeral search text and
/// per-category collapsed set (Issue #253's single-select-category
/// behaviour, and every other selection rule, stays exactly where it
/// already lived: the day sheet's own [onToggle]).
///
/// Accessibility (Issue #234): the search field is a real [TextField] with
/// an explicit [Semantics.label] (never a bare icon button), every chip
/// gets [MaterialTapTargetSize.padded] via [IntensitySelector]'s sibling
/// treatment (see that file's doc for why this is the right mechanism —
/// same reasoning applies here), and every heading is flagged
/// [Semantics.header] so a screen reader can navigate between sections the
/// same way `day_sheet.dart`'s existing `_sectionHeading` already does.
library;

import 'package:flutter/material.dart';

import '../../domain/tags.dart';
import 'chip_semantics.dart';

typedef CategoryLabelBuilder = String Function(TagCategory category);

/// Issue #257: one chip the picker's Custom-tags section renders — the
/// registry entry's code plus the label the chip shows. A record, not a
/// [TagCode]: custom tags live in the per-profile registry, never in
/// [kTagTaxonomy], and collapsing the two would let a registry entry
/// leak into every taxonomy-driven surface.
typedef CustomTagChip = ({String code, String label});

class CategoryPicker extends StatefulWidget {
  const CategoryPicker({
    super.key,
    required this.categories,
    required this.categoryLabel,
    required this.selected,
    required this.onToggle,
    this.recentCodes = const [],
    this.enabled = true,
    this.searchHint = 'Search',
    this.searchSemanticsLabel = 'Search tags',
    this.clearSearchTooltip = 'Clear search',
    this.recentLabel = 'Recent',
    this.unverifiedNote = 'Unverified — pin before shipping',
    this.trailingBuilder,
    this.customTags = const [],
    this.customLabel = 'Custom tags',
    this.customManageTooltip = 'Manage custom tags',
    this.noneCustomNote = 'None yet — add one',
    this.onManageCustomTags,
  });

  /// Curated categories, in the order they render — the day sheet passes
  /// its own `_categoriesInOrder` (Issue #259's resolved, mode-and-
  /// preference-curated order) straight through.
  final List<TagCategory> categories;

  /// Heading text per category.
  final CategoryLabelBuilder categoryLabel;

  /// The currently-selected taxonomy codes (the day sheet's own `_tags`).
  final Set<String> selected;

  /// Fired with a tag's code when its chip (main grid or Recent row) is
  /// tapped. The caller owns every selection rule (single-select
  /// categories, session-tracking, etc.) — this widget only reports intent.
  final ValueChanged<String> onToggle;

  /// The profile's recent codes, most-recent-first (already resolved and
  /// capped by the caller's `TagRecentsStore`). Hidden while searching and
  /// when empty.
  final List<String> recentCodes;

  final bool enabled;
  final String searchHint;
  final String searchSemanticsLabel;
  final String clearSearchTooltip;
  final String recentLabel;
  final String unverifiedNote;

  /// Optional extra content rendered directly under one category's chip
  /// [Wrap] — the day sheet uses this to keep its pain graded-intensity
  /// rows ([IntensitySelector]) exactly where they rendered before this
  /// issue. Called once per category; an empty list means nothing extra.
  final List<Widget> Function(TagCategory category)? trailingBuilder;

  /// Issue #257: the profile's LIVE, non-retired custom-tag registry
  /// entries, rendered as their own collapsible section after every
  /// curated category. Retired entries are the caller's concern (they
  /// render as inert stored chips on the sheet, never as picker chips).
  final List<CustomTagChip> customTags;

  /// Heading text for the custom-tags section.
  final String customLabel;

  /// Tooltip for the custom-tags section's manage affordance.
  final String customManageTooltip;

  /// Empty-state copy under the custom-tags section's heading when the
  /// profile has no live, non-retired custom tags yet.
  final String noneCustomNote;

  /// Issue #257: opens the create/rename/retire surface for the profile's
  /// custom tags. The section renders (with its manage affordance) even
  /// when [customTags] is empty so the first tag can be created — hence
  /// the presence of this callback, not the list, is what shows it. Null
  /// (a harness or read-only surface with no registry) hides the whole
  /// section, exactly like every other registry-driven affordance.
  final VoidCallback? onManageCustomTags;

  @override
  State<CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<CategoryPicker> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  final Set<TagCategory> _collapsed = {};

  /// Issue #257: the custom-tags section's own collapsed flag — a plain
  /// bool rather than a member of [_collapsed], which is keyed by
  /// [TagCategory] and custom tags deliberately have none.
  bool _collapsedCustom = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(TagCode tag) => _query.isEmpty || tag.display.toLowerCase().contains(_query);

  void _onSearchChanged(String value) => setState(() => _query = value.trim().toLowerCase());

  void _clearSearch() => setState(() {
        _searchController.clear();
        _query = '';
      });

  void _toggleCollapsed(TagCategory category) => setState(() {
        if (!_collapsed.add(category)) _collapsed.remove(category);
      });

  void _toggleCollapsedCustom() => setState(() => _collapsedCustom = !_collapsedCustom);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searching = _query.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _searchField(theme),
        if (!searching && widget.recentCodes.isNotEmpty) _recentRow(theme),
        for (final category in widget.categories)
          ..._categorySection(theme, category, searching: searching),
        ..._customTagsSection(theme, searching: searching),
      ],
    );
  }

  Widget _searchField(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        textField: true,
        label: widget.searchSemanticsLabel,
        child: TextField(
          key: const ValueKey('category-picker-search'),
          controller: _searchController,
          enabled: widget.enabled,
          // #165: a live filter — the honest keyboard action is "search"
          // (there is no submit to wire; filtering happens per keystroke).
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: widget.searchHint,
            isDense: true,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    key: const ValueKey('category-picker-search-clear'),
                    icon: const Icon(Icons.clear),
                    tooltip: widget.clearSearchTooltip,
                    onPressed: widget.enabled ? _clearSearch : null,
                  ),
          ),
          onChanged: _onSearchChanged,
        ),
      ),
    );
  }

  Widget _recentRow(ThemeData theme) {
    // Already-selected codes are dropped: they already render (selected)
    // in their own category section, so repeating them here would be a
    // redundant, confusing second chip for the same toggle rather than a
    // useful shortcut to something not yet on today's entry.
    final recentTags = [
      for (final code in widget.recentCodes)
        if (!widget.selected.contains(code) && tagByCode(code) != null) tagByCode(code)!,
    ];
    if (recentTags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(widget.recentLabel, style: theme.textTheme.labelMedium),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final tag in recentTags)
                _tagChip(tag, group: widget.recentLabel, keyPrefix: 'category-picker-recent'),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _categorySection(
    ThemeData theme,
    TagCategory category, {
    required bool searching,
  }) {
    final unverified = kUnverifiedTagCategories.contains(category);
    final tags = unverified
        ? const <TagCode>[]
        : [
            for (final tag in kTagTaxonomy)
              if (tag.category == category && _matches(tag)) tag,
          ];
    // While searching, an attested category with nothing matching (and any
    // unverified category, which never matches by definition — `tags` is
    // always empty for one) drops out entirely rather than showing an
    // empty heading or the "unverified" caption.
    if (searching && tags.isEmpty) return const [];
    final expanded = searching || !_collapsed.contains(category);
    final label = widget.categoryLabel(category);
    return [
      _sectionHeader(theme, category, label, expanded: expanded, searching: searching),
      if (expanded)
        if (unverified)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(widget.unverifiedNote, style: theme.textTheme.bodySmall),
          )
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final tag in tags)
                _tagChip(tag, group: label, keyPrefix: 'category-picker-tag'),
            ],
          ),
          ...?widget.trailingBuilder?.call(category),
        ],
    ];
  }

  Widget _sectionHeader(
    ThemeData theme,
    TagCategory category,
    String label, {
    required bool expanded,
    required bool searching,
  }) {
    final icon = _kCategoryIcons[category] ?? Icons.label_outline;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: InkWell(
        key: ValueKey('category-picker-header-${category.wireName}'),
        onTap: searching || !widget.enabled ? null : () => _toggleCollapsed(category),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              // A bare `Semantics(header: true, child: Text(...))` — the
              // same shape `day_sheet.dart`'s own `_sectionHeading` uses —
              // so the day sheet's existing category-header test helper
              // (`sheetCategoryHeaders`, which looks for exactly a `Text`
              // as a header `Semantics`' direct child) keeps working
              // unchanged; the icon/chevron sit beside it, outside that
              // node, and the whole row's tap action is a separate
              // semantics concern the day sheet's suite does not assert on.
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(label, style: theme.textTheme.labelMedium),
                ),
              ),
              if (!searching)
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tagChip(TagCode tag, {required String group, required String keyPrefix}) {
    final isSelected = widget.selected.contains(tag.code);
    return groupedChipSemantics(
      group: group,
      label: tag.display,
      selected: isSelected,
      onTap: widget.enabled ? () => widget.onToggle(tag.code) : null,
      child: FilterChip(
        key: ValueKey('$keyPrefix-${tag.code}'),
        materialTapTargetSize: MaterialTapTargetSize.padded,
        label: Text(tag.display),
        selected: isSelected,
        onSelected: widget.enabled ? (_) => widget.onToggle(tag.code) : null,
      ),
    );
  }

  /// Issue #257: the custom-tag registry section — one collapsible
  /// section over [CategoryPicker.customTags], rendered last (after every
  /// curated category), participating in the search filter exactly like a
  /// curated section, and carrying the manage affordance
  /// ([CategoryPicker.onManageCustomTags]) in its header row. The section
  /// renders even with an empty list while the manage callback is present
  /// (the first custom tag has to be creatable from here); a null callback
  /// hides it entirely.
  ///
  /// Split into [_customTagsHeader]/[_customTagsBody] (rather than one
  /// builder) at the CRAP gate's complexity ceiling — the section carries
  /// enough independent presence decisions (null callback, search miss,
  /// empty-vs-chips, expanded) that one method with them all sits past it.
  List<Widget> _customTagsSection(
    ThemeData theme, {
    required bool searching,
  }) {
    final manage = widget.onManageCustomTags;
    if (manage == null) return const [];
    final tags = [
      for (final tag in widget.customTags)
        if (_query.isEmpty || tag.label.toLowerCase().contains(_query)) tag,
    ];
    if (searching && tags.isEmpty) return const [];
    return [
      _customTagsHeader(theme, manage, searching: searching),
      if (searching || !_collapsedCustom)
        _customTagsBody(theme, tags, searching: searching),
    ];
  }

  /// The custom-tags section's header row: icon, heading, the manage
  /// affordance, and (outside a search) the collapse chevron.
  Widget _customTagsHeader(
    ThemeData theme,
    VoidCallback manage, {
    required bool searching,
  }) =>
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: InkWell(
          key: const ValueKey('category-picker-header-custom-tags'),
          onTap: searching || !widget.enabled ? null : _toggleCollapsedCustom,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Icon(Icons.label_outline,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    header: true,
                    child:
                        Text(widget.customLabel, style: theme.textTheme.labelMedium),
                  ),
                ),
                IconButton(
                  key: const ValueKey('custom-tags-manage'),
                  tooltip: widget.customManageTooltip,
                  icon: const Icon(Icons.manage_accounts_outlined),
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.enabled ? manage : null,
                ),
                if (!searching)
                  Icon(
                    _collapsedCustom ? Icons.expand_more : Icons.expand_less,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      );

  /// The custom-tags section's expanded body: the empty-state note when no
  /// live tag matches, the chip [Wrap] otherwise.
  Widget _customTagsBody(
    ThemeData theme,
    List<CustomTagChip> tags, {
    required bool searching,
  }) {
    if (tags.isEmpty && !searching) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          widget.noneCustomNote,
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final tag in tags)
            _customTagChip(tag, group: widget.customLabel),
        ],
      ),
    );
  }

  Widget _customTagChip(CustomTagChip tag, {required String group}) {
    final isSelected = widget.selected.contains(tag.code);
    return groupedChipSemantics(
      group: group,
      label: tag.label,
      selected: isSelected,
      onTap: widget.enabled ? () => widget.onToggle(tag.code) : null,
      child: FilterChip(
        key: ValueKey('category-picker-custom-${tag.code}'),
        materialTapTargetSize: MaterialTapTargetSize.padded,
        label: Text(tag.label),
        selected: isSelected,
        onSelected: widget.enabled ? (_) => widget.onToggle(tag.code) : null,
      ),
    );
  }
}

/// Category icon fallback (Issue #234 AC: "falls back to a Material icon
/// if illustrations are not wired") — #164 (UX-11)'s illustration decision
/// has not landed, so every category uses a plain, generic Material icon
/// rather than a bespoke asset. A category missing from this map (there
/// should be none) falls back to [Icons.label_outline] in
/// [_CategoryPickerState._sectionHeader].
const Map<TagCategory, IconData> _kCategoryIcons = {
  TagCategory.pain: Icons.healing_outlined,
  TagCategory.energy: Icons.bolt_outlined,
  TagCategory.sleep: Icons.bedtime_outlined,
  TagCategory.sleepQuality: Icons.nightlight_outlined,
  TagCategory.skin: Icons.face_retouching_natural_outlined,
  TagCategory.hair: Icons.content_cut_outlined,
  TagCategory.digestion: Icons.restaurant_outlined,
  TagCategory.stool: Icons.wc_outlined,
  TagCategory.cravings: Icons.icecream_outlined,
  TagCategory.breastsChest: Icons.favorite_border,
  TagCategory.hotFlashes: Icons.local_fire_department_outlined,
  TagCategory.urine: Icons.water_drop_outlined,
  TagCategory.vulvaVagina: Icons.spa_outlined,
  TagCategory.body: Icons.accessibility_new_outlined,
  TagCategory.feelings: Icons.mood_outlined,
  TagCategory.mind: Icons.psychology_outlined,
  TagCategory.motivation: Icons.trending_up_outlined,
  TagCategory.socialLife: Icons.groups_outlined,
  TagCategory.leisure: Icons.beach_access_outlined,
  TagCategory.meditation: Icons.self_improvement_outlined,
  TagCategory.pms: Icons.error_outline,
  TagCategory.partying: Icons.local_bar_outlined,
  TagCategory.collectionMethod: Icons.inventory_2_outlined,
  TagCategory.exercise: Icons.fitness_center_outlined,
  TagCategory.appointments: Icons.event_outlined,
  TagCategory.medication: Icons.medication_outlined,
  TagCategory.ailments: Icons.sick_outlined,
  TagCategory.supplements: Icons.medication_liquid_outlined,
  TagCategory.sexLife: Icons.favorite_outline,
  TagCategory.discharge: Icons.opacity_outlined,
  TagCategory.tests: Icons.science_outlined,
};
