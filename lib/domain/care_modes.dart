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
/// error-styled late resolver, no tier caption, no fertile window.
///
/// Issue #998: teen mode avoids "late" framing at *every* engine tier, not
/// only while the flag is on. A teen's cycles are still settling, and
/// "late" reads as a failure, so `_teen` carries its own quiet overdue line
/// ("No new period logged yet — a few days either way is normal.") and
/// `silencesLateBanner: true` unconditionally. The irregular-cycles framing
/// flag is a *separate* axis: it still governs the range estimate, the tier
/// caption and the fertile window (and defaults ON for a teen until
/// `CycleConfidence.high`, [irregularFramingInEffect]), but it no longer
/// decides whether the teen sees the error-styled late resolver.
///
/// Issue #850 (U7): the copy path is *lens-aware*. The reader of a screen may
/// be the profile's subject (the person whose cycle is logged) or a guardian
/// looking at someone else's profile, and
/// [`voice-and-copy.md`](docs/product/voice-and-copy.md) rule 2 requires the
/// subject to be "you" only on her own device — on a guardian's device the
/// subject is named (when the caller supplies the name) or referred to with
/// the gender-neutral "their". Every second-person string the registry used
/// to hardcode ("Your record…", "Every entry builds the picture of your
/// cycle.", "Your next period is estimated around:") is built per lens in
/// [careModeCopyFor]; the lens defaults to [GuardianLens.subject], so every
/// pre-#850 caller and its tests read exactly the old subject-voiced copy.
library;

import 'models/profile_mode.dart';
import 'prediction/prediction.dart' show CycleConfidence;
import 'sharing/guardian_lens.dart';
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
    nextStep = 'estimates start after the next period';
  } else if (complete == 0) {
    nextStep = 'estimates start once $needed completed cycles are recorded';
  } else {
    nextStep = '$remaining more periods until estimates';
  }
  return '$complete of $needed completed cycles — $nextStep.';
}

/// Issue #850 (U7): how a copy variant addresses the profile's subject. On
/// the subject's own device the reader *is* the subject, so the copy says
/// "your"; on a guardian's device the reader is someone else
/// ([voice-and-copy rule 2](docs/product/voice-and-copy.md)) so the subject
/// is named — when the caller supplies the name — or referred to with the
/// gender-neutral "their". Holding both a sentence-initial and a
/// mid-sentence form keeps the substitution grammatical ("the picture of
/// their cycle" vs. "Their record is just getting started") without every
/// builder carrying its own capitalization branch.
class _SubjectRef {
  const _SubjectRef(this.capital, this.lower);

  /// Sentence/field-initial possessive: "Your", "Their", "Maya's".
  final String capital;

  /// Mid-sentence possessive: "your", "their", "Maya's".
  final String lower;

  static _SubjectRef resolve(GuardianLens lens, String? subjectName) {
    if (lens == GuardianLens.subject) {
      return const _SubjectRef('Your', 'your');
    }
    final name = subjectName?.trim() ?? '';
    if (name.isEmpty) return const _SubjectRef('Their', 'their');
    return _SubjectRef("$name's", "$name's");
  }
}

/// The insufficient-history heading (Issue #131), in [mode]'s voice and
/// addressed to [ref]'s reader. Only `teen` voices the reader ("Your record
/// is just getting started"); every other mode already reads third-person.
String _notEnoughTitle(ProfileMode mode, _SubjectRef ref) => switch (mode) {
      ProfileMode.teen => '${ref.capital} record is just getting started',
      _ => 'Not enough history yet',
    };

/// The insufficient-history body in [mode]'s voice, addressed to [ref]'s
/// reader (Issue #816's shared progress sentence, wrapped by the mode's own
/// sentence where it has one).
String _notEnoughBody(
  ProfileMode mode,
  _SubjectRef ref,
  int complete,
  int needed,
) {
  final progress = completedCycleProgress(complete, needed);
  return switch (mode) {
    ProfileMode.teen =>
      'Every entry builds the picture of ${ref.lower} cycle. $progress',
    ProfileMode.irregular => '$progress ${ref.capital} estimates may stay '
        'ranges rather than dates.',
    _ => progress,
  };
}

/// The un-composed next-period estimate label (Issue #131), addressed to
/// [ref]'s reader. Only `teen` varies in voice; `irregular` and standard
/// already read third-person.
String _nextEstimateLabel(ProfileMode mode, _SubjectRef ref) => switch (mode) {
      ProfileMode.teen => '${ref.capital} next period is estimated around:',
      ProfileMode.irregular => 'Next period may start around:',
      _ => 'Next period estimate:',
    };

/// Issue #853: the range-style estimate label for a composed
/// (mode + irregular) profile — same hedging as the legacy `irregular`
/// mode's label, in the base mode's own register (Issue #850: addressed to
/// [ref]'s reader).
String _composedNextEstimateLabel(ProfileMode mode, _SubjectRef ref) =>
    switch (mode) {
      ProfileMode.teen => '${ref.capital} next period may start around:',
      _ => 'Next period may start around:',
    };

/// Issue #998: the teen mode's own quiet overdue line, shown at *every*
/// engine tier. A teen's cycles are still settling, so a few days either
/// way is normal, and "late" would read as a failure. The irregular-cycles
/// framing flag is a separate axis ([irregularFramingInEffect]); the teen's
/// overdue wording no longer depends on it.
const String _teenOverdueStatusLabel =
    'No new period logged yet — a few days either way is normal.';

/// Issue #998: the single action the teen quiet line offers — the same
/// "log it when it comes" the #853 composition already carried.
const String _teenOverdueActionLabel = 'Log it when it comes';

/// Issue #853: the quiet overdue line replacing the error-styled late
/// resolver when the flag composes. Teen now uses its own tier-independent
/// line ([_teenOverdueStatusLabel], issue #998); the other modes keep the
/// legacy `irregular` mode's exact line, which existing irregular-mode
/// profiles already see. Neither variant says "late" — variation is
/// expected, not overdue.
String _composedOverdueStatusLabel(ProfileMode mode) => switch (mode) {
      ProfileMode.teen => _teenOverdueStatusLabel,
      _ => _irregular.overdueStatusLabel,
    };

/// Issue #853: the single action a teen's quiet overdue line offers ("log
/// it when it comes" — the issue's own wording). Only the teen composition
/// carries one; the adult composition stays a text-only line, exactly the
/// behavior the legacy `irregular` mode had.
String _composedOverdueActionLabel(ProfileMode mode) => switch (mode) {
      ProfileMode.teen => _teenOverdueActionLabel,
      _ => '',
    };

/// Issue #853: the estimate-range sentence appended to a composed mode's
/// not-enough-history body (the legacy `irregular` mode's own sentence,
/// teen-voiced for teen; Issue #850: addressed to [ref]'s reader).
String _composedNotEnoughSuffix(ProfileMode mode, _SubjectRef ref) =>
    switch (mode) {
      ProfileMode.teen => ' ${ref.capital} estimates may stay ranges rather '
          'than dates for a while.',
      _ => ' ${ref.capital} estimates may stay ranges rather than dates.',
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
  /// legacy `irregular` mode, every composed (mode + irregular, Issue #853)
  /// copy, and `teen` (Issue #998, at every engine tier) silence it — so a
  /// teen never sees the banner, whether or not its cycles have steadied.
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
  /// `standard`. Meaningless (never rendered) when
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

/// The lens-independent half of one mode's copy (Issue #850): every field
/// whose value reads the same to every viewer — the quiet overdue line and
/// its action, the three estimate flags, the fertile-window vocabulary, and
/// the category order and headings. [careModeCopyFor] builds the
/// lens-dependent fields (title, not-enough body, estimate label) around
/// this structure from a [_SubjectRef], so a second-person string can never
/// be baked into a structural constant again. Field semantics are documented
/// once on [CareModeCopy], the assembled public type.
class _ModeCopy {
  const _ModeCopy({
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

  final String overdueStatusLabel;
  final String overdueActionLabel;
  final bool silencesLateBanner;
  final bool showsTierCaption;
  final bool showsFertileWindow;
  final String fertileWindowLabel;
  final String fertileWindowLegend;
  final List<TagCategory> categoriesInOrder;
  final Map<TagCategory, String> categoryLabels;
}

const _ModeCopy _standard = _ModeCopy(
  overdueStatusLabel: '',
  silencesLateBanner: false,
  showsTierCaption: true,
  showsFertileWindow: true,
  fertileWindowLabel: 'Estimated fertile window',
  fertileWindowLegend: 'Estimated fertile days',
  categoriesInOrder: TagCategory.values,
  categoryLabels: _standardCategoryLabels,
);

const _ModeCopy _teen = _ModeCopy(
  overdueStatusLabel: _teenOverdueStatusLabel,
  overdueActionLabel: _teenOverdueActionLabel,
  // Issue #998: teen mode avoids "late" framing at every tier — a teen's
  // cycles are still settling, and "late" reads as a failure. This is
  // independent of the irregular-cycles framing flag, which only controls
  // the range estimate, the tier caption and the fertile window.
  silencesLateBanner: true,
  showsTierCaption: true,
  showsFertileWindow: true,
  // Issue #143 review: plainer, less clinical phrasing than
  // standard's "Estimated fertile window" — matches this mode's
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

const _ModeCopy _irregular = _ModeCopy(
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

/// The structural (lens-independent) copy for [mode] alone: a switch
/// expression naming every mode (no `_` wildcard), so adding a [ProfileMode]
/// without copy is a compile error, not a silently-wrong screen.
_ModeCopy _baseStructureFor(ProfileMode mode) => switch (mode) {
      ProfileMode.standard => _standard,
      ProfileMode.teen => _teen,
      // Issue #850: the legacy `caregiver` wire value folds into standard —
      // a guardian is a per-viewer lens now, not a mode, so there is no
      // caregiver-specific vocabulary.
      ProfileMode.caregiver => _standard,
      ProfileMode.irregular => _irregular,
    };

/// Issue #852/#853's un-composed copy — [mode]'s voice, addressed to [ref]'s
/// reader, with [structure]'s flags/vocabulary untouched.
CareModeCopy _plainCopy(
  ProfileMode mode,
  _ModeCopy structure,
  _SubjectRef ref,
) =>
    CareModeCopy(
      notEnoughTitle: _notEnoughTitle(mode, ref),
      notEnoughBody: (complete, needed) =>
          _notEnoughBody(mode, ref, complete, needed),
      nextEstimateLabel: _nextEstimateLabel(mode, ref),
      overdueStatusLabel: structure.overdueStatusLabel,
      overdueActionLabel: structure.overdueActionLabel,
      silencesLateBanner: structure.silencesLateBanner,
      showsTierCaption: structure.showsTierCaption,
      showsFertileWindow: structure.showsFertileWindow,
      fertileWindowLabel: structure.fertileWindowLabel,
      fertileWindowLegend: structure.fertileWindowLegend,
      categoriesInOrder: structure.categoriesInOrder,
      categoryLabels: structure.categoryLabels,
    );

/// Issue #853's composed copy — the irregular framing overlaid, still
/// addressed to [ref]'s reader.
CareModeCopy _composedCopy(
  ProfileMode mode,
  _ModeCopy structure,
  _SubjectRef ref,
) =>
    CareModeCopy(
      notEnoughTitle: _notEnoughTitle(mode, ref),
      notEnoughBody: (complete, needed) =>
          '${_notEnoughBody(mode, ref, complete, needed)}'
          '${_composedNotEnoughSuffix(mode, ref)}',
      nextEstimateLabel: _composedNextEstimateLabel(mode, ref),
      overdueStatusLabel: _composedOverdueStatusLabel(mode),
      overdueActionLabel: _composedOverdueActionLabel(mode),
      silencesLateBanner: true,
      showsTierCaption: false,
      showsFertileWindow: false,
      fertileWindowLabel: structure.fertileWindowLabel,
      fertileWindowLegend: structure.fertileWindowLegend,
      categoriesInOrder: structure.categoriesInOrder,
      categoryLabels: structure.categoryLabels,
    );

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
///
/// Issue #850 (U7): [lens] selects who the copy addresses. It defaults to
/// [GuardianLens.subject], so every pre-#850 caller reads exactly the
/// subject-voiced copy it always did. Under [GuardianLens.guardian] the
/// subject is never "you": the enumerated second-person strings read
/// "[subjectName]'s …" when a name is supplied and the gender-neutral
/// "their …" otherwise. [subjectName] is ignored under the subject lens.
CareModeCopy careModeCopyFor(
  ProfileMode mode, {
  required bool irregularFraming,
  GuardianLens lens = GuardianLens.subject,
  String? subjectName,
}) {
  final ref = _SubjectRef.resolve(lens, subjectName);
  final structure = _baseStructureFor(mode);
  // The legacy wire value is already its own full copy; composing on top
  // would double-apply.
  if (!irregularFraming || mode == ProfileMode.irregular) {
    return _plainCopy(mode, structure, ref);
  }
  return _composedCopy(mode, structure, ref);
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
///     irregular again, the tier drops and the framing returns. Issue
///     #998: this axis controls the range estimate, tier caption and
///     fertile window only — a teen's quiet overdue line and suppressed
///     late resolver hold at every tier regardless of its value.
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
