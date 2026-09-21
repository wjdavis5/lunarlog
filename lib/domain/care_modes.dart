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
///
/// Issue #853 splits the axis this registry used to conflate: `irregular`
/// is no longer a rival value of `ProfileMode` but a flag composed with
/// whatever life-stage mode the profile carries (`careModeCopyFor(mode,
/// irregularFraming: ...)`). The composition keeps the base mode's voice —
/// teen stays teen — and overlays the variance-expecting framing: a
/// range-style estimate label, a quiet non-alarm overdue line replacing the
/// error-styled late resolver, no tier caption, no fertile window. A teen
/// profile defaults to the flag ON until its engine confidence reaches
/// `CycleConfidence.high` (`irregularFramingInEffect`), so teen mode never
/// says "late" out of the box.
library;

import 'models/profile_mode.dart';
import 'prediction/prediction.dart' show CycleConfidence;
import 'tags.dart';

/// Builds the not-enough-history body from the live tally (issue #816):
/// [complete] completed cycles recorded so far, out of [needed]. It is a
/// function rather than a fixed string so the card can show real progress
/// in the same "completed cycles" unit the threshold counts, in every care
/// mode. The callers pass the engine's own
/// `NotEnoughHistory.usableCycleCount` and `kMinCompletedValidCycles`
/// rather than recomputing either.
typedef NotEnoughBody = String Function(int complete, int needed);

/// The shared numeric progress sentence (issue #816). Counts in
/// "completed cycles" — the unit `kMinCompletedValidCycles` counts — and
/// names what happens next rather than restating the rule. The
/// `remaining == 1` branch is the tester's own case (three logged starts,
/// two completed cycles): the next period is exactly what unlocks
/// estimates. With exactly zero completed cycles no "N more periods" count
/// is honest (the first logged period opens a cycle rather than completing
/// one), so that branch states the gap in completed cycles instead;
/// otherwise the remaining period count is exact.
///
/// Public so the cycle-history header can render the exact same tally the
/// not-enough-history card uses, in the same unit, without a second copy.
String completedCycleProgress(int complete, int needed) {
  final remaining = needed - complete;
  final String nextStep;
  if (remaining <= 1) {
    nextStep = 'estimates start after your next period';
  } else if (complete == 0) {
    nextStep = 'estimates start once you have $needed completed cycles';
  } else {
    nextStep = '$remaining more periods until estimates';
  }
  return '$complete of $needed completed cycles — $nextStep.';
}

String _standardNotEnoughBody(int complete, int needed) =>
    completedCycleProgress(complete, needed);

String _teenNotEnoughBody(int complete, int needed) =>
    'Every entry builds the picture of your cycle. '
    '${completedCycleProgress(complete, needed)}';

String _caregiverNotEnoughBody(int complete, int needed) =>
    '${completedCycleProgress(complete, needed)} Regular logging helps.';

String _irregularNotEnoughBody(int complete, int needed) =>
    '${completedCycleProgress(complete, needed)} Your estimates may stay '
    'ranges rather than dates.';

/// Issue #853: the range-style estimate label for a composed
/// (mode + irregular) profile — same hedging as the legacy `irregular`
/// mode's label, in the base mode's own register.
String _composedNextEstimateLabel(ProfileMode mode) => switch (mode) {
      ProfileMode.teen => 'Your next period may start around:',
      _ => 'Next period may start around:',
    };

/// Issue #853: the quiet overdue line replacing the error-styled late
/// resolver when the flag composes. Teen keeps its body-literacy register
/// ("still forming"); the other modes keep the legacy `irregular` mode's
/// exact line, which existing irregular-mode profiles already see. Neither
/// variant says "late" — variation is expected, not overdue.
String _composedOverdueStatusLabel(ProfileMode mode) => switch (mode) {
      ProfileMode.teen =>
        'No new period logged yet — cycles often vary while a pattern is '
            'still forming, and that is expected.',
      _ => _irregular.overdueStatusLabel,
    };

/// Issue #853: the single action a teen's quiet overdue line offers ("log
/// it when it comes" — the issue's own wording). Only the teen composition
/// carries one; the adult composition stays a text-only line, exactly the
/// behavior the legacy `irregular` mode had.
String _composedOverdueActionLabel(ProfileMode mode) => switch (mode) {
      ProfileMode.teen => 'Log it when it comes',
      _ => '',
    };

/// Issue #853: the estimate-range sentence appended to a composed mode's
/// not-enough-history body (the legacy `irregular` mode's own sentence,
/// teen-voiced for teen).
String _composedNotEnoughSuffix(ProfileMode mode) => switch (mode) {
      ProfileMode.teen =>
        ' Your estimates may stay ranges rather than dates for a while.',
      _ => ' Your estimates may stay ranges rather than dates.',
    };

/// Per-mode vocabulary and logging defaults.
class CareModeCopy {
  const CareModeCopy({
    required this.notEnoughTitle,
    required this.notEnoughBody,
    required this.nextEstimateLabel,
    required this.overdueStatusLabel,
    this.overdueActionLabel = '',
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

  /// Body of the insufficient-history card, built from the live tally —
  /// see [NotEnoughBody].
  final NotEnoughBody notEnoughBody;

  /// Label introducing the next-period estimate line (the formatted date
  /// follows it). Honesty is kept in every variant: each names the date an
  /// *estimate*, never a promise.
  final String nextEstimateLabel;

  /// Quiet status line replacing the late resolver when
  /// [silencesLateBanner] is set. Must not use "late" framing — variation
  /// is expected, not overdue.
  final String overdueStatusLabel;

  /// Issue #853: the single action offered under [overdueStatusLabel], or
  /// the empty string for a text-only line. Only the teen + irregular
  /// composition carries one ("Log it when it comes" — the issue's own
  /// wording): a quiet line with one honest way forward, never the adult
  /// resolver's "skip this cycle". The action is the same "log it" the
  /// resolver's primary button performs (it opens today's day sheet).
  final String overdueActionLabel;

  /// Whether the late resolver (the error-styled banner with log-it /
  /// skip-cycle / remind-me actions) is suppressed for this mode. The
  /// legacy `irregular` mode and every composed (mode + irregular,
  /// Issue #853) copy silence it — and, since #853, a `teen` profile
  /// carries the flag by default until its engine confidence reaches
  /// `CycleConfidence.high` (`irregularFramingInEffect`), so a
  /// first-year tracker never sees the banner.
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
  notEnoughBody: _standardNotEnoughBody,
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
  notEnoughBody: _teenNotEnoughBody,
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
  notEnoughBody: _caregiverNotEnoughBody,
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
  notEnoughBody: _irregularNotEnoughBody,
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

/// The copy for [mode] alone (the legacy single-axis lookup): a switch
/// expression naming every mode (no `_` wildcard), so adding a
/// [ProfileMode] without copy is a compile error, not a silently-wrong
/// screen.
CareModeCopy _baseCopyFor(ProfileMode mode) => switch (mode) {
      ProfileMode.standard => _standard,
      ProfileMode.teen => _teen,
      ProfileMode.caregiver => _caregiver,
      ProfileMode.irregular => _irregular,
    };

/// Issue #853: the copy for the composed axis — [mode]'s own voice with the
/// irregular framing overlaid when [irregularFraming] is in effect. The
/// base mode keeps its title, not-enough title, category order and
/// headings; the estimate label goes range-style, the late resolver is
/// silenced and replaced by the quiet [CareModeCopy.overdueStatusLabel]
/// (with the teen's single [CareModeCopy.overdueActionLabel] action), and
/// the tier caption and fertile window are hidden (a precise-looking window
/// derived from a range estimate is exactly the false precision this
/// framing exists to avoid — the same reasoning the legacy `irregular`
/// mode already applied).
///
/// [irregularFraming] is deliberately a *required* named parameter even
/// though a caller that only wants the mode axis could pass `false`: every
/// call site must state its framing choice out loud, so a future consumer
/// can never silently read estimate/banner fields off the un-composed axis.
/// Pass the *effective* flag, not the stored tri-state —
/// [irregularFramingInEffect] resolves stored value, mode, and engine tier
/// (callers that render only the mode axis — the day sheet's category
/// headings — may pass the stored default `false`, since no field they
/// read varies with the flag).
CareModeCopy careModeCopyFor(
  ProfileMode mode, {
  required bool irregularFraming,
}) {
  final base = _baseCopyFor(mode);
  // The legacy wire value is already its own full copy; composing on top
  // would double-apply.
  if (!irregularFraming || mode == ProfileMode.irregular) return base;
  return CareModeCopy(
    notEnoughTitle: base.notEnoughTitle,
    notEnoughBody: (complete, needed) =>
        '${base.notEnoughBody(complete, needed)}'
        '${_composedNotEnoughSuffix(mode)}',
    nextEstimateLabel: _composedNextEstimateLabel(mode),
    overdueStatusLabel: _composedOverdueStatusLabel(mode),
    overdueActionLabel: _composedOverdueActionLabel(mode),
    silencesLateBanner: true,
    showsTierCaption: false,
    showsFertileWindow: false,
    fertileWindowLabel: base.fertileWindowLabel,
    fertileWindowLegend: base.fertileWindowLegend,
    categoriesInOrder: base.categoriesInOrder,
    categoryLabels: base.categoryLabels,
  );
}

/// Issue #853: resolves the *effective* irregular framing for a profile.
///
/// * An explicitly stored value ([stored] non-null) wins in both
///   directions — the operator's choice is never second-guessed by the
///   engine.
/// * The engine default for an unset value is derived from the mode and
///   the prediction's confidence tier, never from age or birth year
///   ("birth year never gates", #131's standing constraint):
///   * `teen` — framing ON until the engine reaches
///     `CycleConfidence.high` ([tier] null — no active estimate yet —
///     also reads ON: the early, no-history months are exactly when the
///     alarm framing would be wrong). Once the cycles steady into `high`,
///     the framing lifts on its own; if they later become genuinely
///     irregular again, the tier drops and the framing returns.
///   * every other mode — OFF.
///
/// Pure; the caller supplies the tier the prediction stream already holds.
bool irregularFramingInEffect({
  required ProfileMode mode,
  required bool? stored,
  CycleConfidence? tier,
}) {
  if (stored != null) return stored;
  if (mode == ProfileMode.irregular) return true;
  if (mode != ProfileMode.teen) return false;
  return tier == null || tier != CycleConfidence.high;
}
