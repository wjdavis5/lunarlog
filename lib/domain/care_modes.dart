/// Care-mode copy registry (Issue #131, R12): the per-mode vocabulary for
/// the overview panel and the day sheet's category headings, plus the
/// category surfacing order that doubles as the mode's logging defaults.
///
/// Design constraints the registry encodes (Issue #131, hard requirements):
/// * Mode is presentation, not permission — nothing here is consulted by
///   any authorization path, and a test pins that.
/// * `teen` is not a reduced app: its category order surfaces every
///   category `standard` does, merely in a different order; a test pins
///   that the ordering is a permutation, never a subset.
/// * The estimate disclaimer is rendered by the overview card in every
///   mode; it lives in `overview_panel.dart` (`kEstimateDisclaimer`) so the
///   same fixed string appears next to every estimate regardless of mode.
/// * Vocabulary is prospective presentation only — switching modes never
///   touches a saved entry (tests pin that in `test/ui/profiles_test.dart`
///   and `test/domain/repositories_test.dart`).
///
/// Pure Dart (R14/R16); `test/architecture/layering_test.dart` enforces the
/// import discipline.
library;

import 'models/profile_mode.dart';
import 'tags.dart';

/// Per-mode vocabulary and logging defaults.
class CareModeCopy {
  const CareModeCopy({
    required this.notEnoughTitle,
    required this.notEnoughBody,
    required this.nextEstimateLabel,
    required this.overdueStatusLabel,
    required this.silencesLateBanner,
    required this.showsTierCaption,
    required this.categoriesInOrder,
    required this.categoryLabels,
  });

  /// Heading of the insufficient-history card.
  final String notEnoughTitle;

  /// Body of the insufficient-history card.
  final String notEnoughBody;

  /// Label introducing the next-period estimate line (the formatted date
  /// follows it). Honesty is kept in every variant: each names the date an
  /// *estimate*, never a promise.
  final String nextEstimateLabel;

  /// Quiet status line replacing the late resolver when
  /// [silencesLateBanner] is set. Must not use "late" framing — variation
  /// is expected, not overdue.
  final String overdueStatusLabel;

  /// Whether the late resolver (the error-styled banner with log-it /
  /// skip-cycle / remind-me actions) is suppressed for this mode. Only
  /// `irregular` silences it (Issue #131: "irregular mode specifically
  /// silences the late banner").
  final bool silencesLateBanner;

  /// Whether the overview's tier caption (issue #213: the short
  /// "Learning"/"Irregular" line under the estimate, below `high`
  /// confidence) renders for this mode. Only `irregular` silences it — that
  /// mode already replaces the late banner with its own quiet, non-numeric
  /// status line, so the separate tier caption would say much the same
  /// thing a second time.
  final bool showsTierCaption;

  /// Which tracking categories are surfaced first (Issue #131 defaults):
  /// the day sheet renders headings in this order. Always a permutation of
  /// [TagCategory.values] — teen reorders (body literacy first), it never
  /// removes a category ("teen is not a euphemism for a reduced app").
  final List<TagCategory> categoriesInOrder;

  /// Heading text per category for the day sheet.
  final Map<TagCategory, String> categoryLabels;

  /// The heading for [category] in this mode.
  String categoryLabel(TagCategory category) => categoryLabels[category]!;
}

const Map<TagCategory, String> _standardCategoryLabels = {
  TagCategory.pain: 'Pain',
  TagCategory.body: 'Body',
  TagCategory.mood: 'Mood',
  TagCategory.other: 'Other',
};

const CareModeCopy _standard = CareModeCopy(
  notEnoughTitle: 'Not enough history yet',
  notEnoughBody: 'Keep logging — estimates appear once a few cycles are recorded.',
  nextEstimateLabel: 'Next period estimate:',
  overdueStatusLabel: '',
  silencesLateBanner: false,
  showsTierCaption: true,
  categoriesInOrder: TagCategory.values,
  categoryLabels: _standardCategoryLabels,
);

const CareModeCopy _teen = CareModeCopy(
  notEnoughTitle: 'Your record is just getting started',
  notEnoughBody: 'Every entry builds the picture of your cycle. Estimates '
      'appear once a few cycles are recorded.',
  nextEstimateLabel: 'Your next period is estimated around:',
  overdueStatusLabel: '',
  silencesLateBanner: false,
  showsTierCaption: true,
  // Body-literacy framing surfaces how the body feels first; every
  // standard category is still here, only reordered (not a reduced app).
  categoriesInOrder: [
    TagCategory.body,
    TagCategory.mood,
    TagCategory.pain,
    TagCategory.other,
  ],
  categoryLabels: {
    TagCategory.pain: 'Pain',
    TagCategory.body: 'How your body feels',
    TagCategory.mood: 'Mood',
    TagCategory.other: 'Other',
  },
);

const CareModeCopy _caregiver = CareModeCopy(
  notEnoughTitle: 'Not enough history yet',
  notEnoughBody: 'Estimates appear once a few cycles are recorded — regular '
      'logging helps.',
  nextEstimateLabel: 'Next period estimate:',
  overdueStatusLabel: '',
  silencesLateBanner: false,
  showsTierCaption: true,
  categoriesInOrder: TagCategory.values,
  categoryLabels: _standardCategoryLabels,
);

const CareModeCopy _irregular = CareModeCopy(
  notEnoughTitle: 'Not enough history yet',
  notEnoughBody: 'Keep logging — estimates appear once a few cycles are '
      'recorded, and yours may stay ranges rather than dates.',
  nextEstimateLabel: 'Next period may start around:',
  overdueStatusLabel: 'No new period logged yet — with irregular cycles, '
      'variation like this is common and expected.',
  silencesLateBanner: true,
  // Issue #131 cheap fix: the overdue status line above already carries
  // this mode's own "variation is expected" framing, so the tier caption
  // is redundant here — silenced the same way the late banner is.
  showsTierCaption: false,
  categoriesInOrder: TagCategory.values,
  categoryLabels: _standardCategoryLabels,
);

/// The copy for [mode]. A switch expression naming every mode (no `_`
/// wildcard): adding a [ProfileMode] without copy is a compile error, not a
/// silently-wrong screen.
CareModeCopy careModeCopyFor(ProfileMode mode) => switch (mode) {
      ProfileMode.standard => _standard,
      ProfileMode.teen => _teen,
      ProfileMode.caregiver => _caregiver,
      ProfileMode.irregular => _irregular,
    };
