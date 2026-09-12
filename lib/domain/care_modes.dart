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
///   mode; it lives in `estimate_copy.dart` (`kEstimateDisclaimer`) so the
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
    required this.showsFertileWindow,
    required this.fertileWindowLabel,
    required this.fertileWindowLegend,
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

  /// Whether the fertile-window/ovulation estimate (issue #143) renders for
  /// this mode — the calendar band, its legend entry, and the Analysis
  /// headline row all gate on this one flag. Only `irregular` silences it:
  /// a fertile window is exactly as precise-looking as the period estimate
  /// it is derived from (a specific date range, not a vaguer framing), and
  /// `irregular` mode's whole posture is avoiding that false precision —
  /// the same reasoning [showsTierCaption] and [silencesLateBanner] already
  /// apply, extended to this estimate rather than inventing a third rule.
  final bool showsFertileWindow;

  /// Row label for the fertile-window estimate on the Analysis tab (issue
  /// #143 review, per-mode vocabulary — the same reasoning as
  /// [nextEstimateLabel]): `teen` gets plainer, less clinical phrasing than
  /// `standard`/`caregiver`. Meaningless (never rendered) when
  /// [showsFertileWindow] is false, but still a real, non-empty string —
  /// [CareModeCopy] never leaves a field blank just because one mode
  /// doesn't currently use it.
  final String fertileWindowLabel;

  /// Legend-strip and future-day-explainer wording for the same estimate
  /// (issue #143 review) — a shorter phrase than [fertileWindowLabel] fit
  /// for a legend swatch key or mid-sentence use, same per-mode variance.
  final String fertileWindowLegend;

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

/// Every [TagCategory] has a heading in every mode — including the
/// option-set-unverified ones (Issue #249's `kUnverifiedTagCategories`),
/// which the day sheet marks "unverified — pin before shipping" instead of
/// rendering invented chips.
const Map<TagCategory, String> _standardCategoryLabels = {
  TagCategory.pain: 'Pain',
  TagCategory.energy: 'Energy',
  TagCategory.sleep: 'Sleep',
  TagCategory.sleepQuality: 'Sleep quality',
  TagCategory.skin: 'Skin',
  TagCategory.hair: 'Hair',
  TagCategory.digestion: 'Digestion',
  TagCategory.stool: 'Stool',
  TagCategory.cravings: 'Cravings',
  TagCategory.breastsChest: 'Breasts & chest',
  TagCategory.hotFlashes: 'Hot flashes',
  TagCategory.urine: 'Urine',
  TagCategory.vulvaVagina: 'Vulva & vagina',
  TagCategory.body: 'Body',
  // Issue #251's feelings/mind/lifestyle categories — the old `mood`
  // grouping rebuilt (its codes re-parented, never renamed).
  TagCategory.feelings: 'Feelings',
  TagCategory.mind: 'Mind',
  TagCategory.motivation: 'Motivation',
  TagCategory.socialLife: 'Social life',
  TagCategory.leisure: 'Leisure',
  TagCategory.meditation: 'Meditation',
  TagCategory.pms: 'PMS',
  TagCategory.partying: 'Partying',
  // Issue #252's events-and-care categories.
  TagCategory.collectionMethod: 'Collection method',
  TagCategory.exercise: 'Exercise',
  TagCategory.appointments: 'Appointments',
  TagCategory.medication: 'Medication',
  TagCategory.ailments: 'Ailments',
  TagCategory.supplements: 'Supplements',
  // Issue #253's sensitive and fertility categories.
  TagCategory.sexLife: 'Sex life',
  TagCategory.discharge: 'Discharge',
  TagCategory.tests: 'Tests',
};

const CareModeCopy _standard = CareModeCopy(
  notEnoughTitle: 'Not enough history yet',
  notEnoughBody:
      'Keep logging — estimates appear once a few cycles are recorded.',
  nextEstimateLabel: 'Next period estimate:',
  overdueStatusLabel: '',
  silencesLateBanner: false,
  showsTierCaption: true,
  showsFertileWindow: true,
  fertileWindowLabel: 'Estimated fertile window',
  fertileWindowLegend: 'Estimated fertile days',
  categoriesInOrder: TagCategory.values,
  categoryLabels: _standardCategoryLabels,
);

const CareModeCopy _teen = CareModeCopy(
  notEnoughTitle: 'Your record is just getting started',
  notEnoughBody:
      'Every entry builds the picture of your cycle. Estimates '
      'appear once a few cycles are recorded.',
  nextEstimateLabel: 'Your next period is estimated around:',
  overdueStatusLabel: '',
  silencesLateBanner: false,
  showsTierCaption: true,
  showsFertileWindow: true,
  // Issue #143 review: plainer, less clinical phrasing than
  // standard/caregiver's "Estimated fertile window" — matches this mode's
  // existing body-literacy framing (e.g. `categoryLabels`'s "How your body
  // feels" above).
  fertileWindowLabel: 'Days pregnancy is more likely (estimate)',
  fertileWindowLegend: 'Days pregnancy is more likely',
  // Body-literacy framing surfaces how the body feels first; every
  // standard category is still here, only reordered (not a reduced app).
  categoriesInOrder: [
    TagCategory.body,
    TagCategory.feelings,
    TagCategory.mind,
    TagCategory.pain,
    TagCategory.energy,
    TagCategory.sleep,
    TagCategory.sleepQuality,
    TagCategory.skin,
    TagCategory.hair,
    TagCategory.digestion,
    TagCategory.stool,
    TagCategory.cravings,
    TagCategory.breastsChest,
    TagCategory.hotFlashes,
    TagCategory.urine,
    TagCategory.vulvaVagina,
    TagCategory.motivation,
    TagCategory.socialLife,
    TagCategory.leisure,
    TagCategory.meditation,
    TagCategory.pms,
    TagCategory.partying,
    // Issue #252's events-and-care categories, appended after the
    // lifestyle cluster (every standard category is still here — the
    // order stays a permutation, never a subset).
    TagCategory.collectionMethod,
    TagCategory.exercise,
    TagCategory.appointments,
    TagCategory.medication,
    TagCategory.ailments,
    TagCategory.supplements,
    // Issue #253's sensitive and fertility categories, appended after the
    // events/care cluster (the order stays a permutation, never a subset).
    TagCategory.sexLife,
    TagCategory.discharge,
    TagCategory.tests,
  ],
  categoryLabels: {
    TagCategory.pain: 'Pain',
    TagCategory.energy: 'Energy',
    TagCategory.sleep: 'Sleep',
    TagCategory.sleepQuality: 'Sleep quality',
    TagCategory.skin: 'Skin',
    TagCategory.hair: 'Hair',
    TagCategory.digestion: 'Digestion',
    TagCategory.stool: 'Stool',
    TagCategory.cravings: 'Cravings',
    TagCategory.breastsChest: 'Breasts & chest',
    TagCategory.hotFlashes: 'Hot flashes',
    TagCategory.urine: 'Urine',
    TagCategory.vulvaVagina: 'Vulva & vagina',
    TagCategory.body: 'How your body feels',
    TagCategory.feelings: 'Feelings',
    TagCategory.mind: 'Mind',
    TagCategory.motivation: 'Motivation',
    TagCategory.socialLife: 'Social life',
    TagCategory.leisure: 'Leisure',
    TagCategory.meditation: 'Meditation',
    TagCategory.pms: 'PMS',
    TagCategory.partying: 'Partying',
    // Issue #252's events-and-care categories (same headings as
    // standard — only body gets teen-specific vocabulary).
    TagCategory.collectionMethod: 'Collection method',
    TagCategory.exercise: 'Exercise',
    TagCategory.appointments: 'Appointments',
    TagCategory.medication: 'Medication',
    TagCategory.ailments: 'Ailments',
    TagCategory.supplements: 'Supplements',
    // Issue #253's sensitive and fertility categories (same headings as
    // standard — only body gets teen-specific vocabulary).
    TagCategory.sexLife: 'Sex life',
    TagCategory.discharge: 'Discharge',
    TagCategory.tests: 'Tests',
  },
);

const CareModeCopy _caregiver = CareModeCopy(
  notEnoughTitle: 'Not enough history yet',
  notEnoughBody:
      'Estimates appear once a few cycles are recorded — regular '
      'logging helps.',
  nextEstimateLabel: 'Next period estimate:',
  overdueStatusLabel: '',
  silencesLateBanner: false,
  showsTierCaption: true,
  showsFertileWindow: true,
  fertileWindowLabel: 'Estimated fertile window',
  fertileWindowLegend: 'Estimated fertile days',
  categoriesInOrder: TagCategory.values,
  categoryLabels: _standardCategoryLabels,
);

const CareModeCopy _irregular = CareModeCopy(
  notEnoughTitle: 'Not enough history yet',
  notEnoughBody:
      'Keep logging — estimates appear once a few cycles are '
      'recorded, and yours may stay ranges rather than dates.',
  nextEstimateLabel: 'Next period may start around:',
  overdueStatusLabel:
      'No new period logged yet — with irregular cycles, '
      'variation like this is common and expected.',
  silencesLateBanner: true,
  // Issue #131 cheap fix: the overdue status line above already carries
  // this mode's own "variation is expected" framing, so the tier caption
  // is redundant here — silenced the same way the late banner is.
  showsTierCaption: false,
  // Issue #143: same reasoning as showsTierCaption above — a fertile-window
  // estimate is exactly the kind of false precision this mode's status
  // line already exists to avoid, so it is silenced too rather than
  // rendered alongside a "variation is common and expected" message.
  showsFertileWindow: false,
  // Unused while showsFertileWindow is false — kept as real,
  // standard-matching strings (never blank) so a future mode that flips
  // showsFertileWindow back on inherits sensible copy rather than an
  // empty row.
  fertileWindowLabel: 'Estimated fertile window',
  fertileWindowLegend: 'Estimated fertile days',
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
