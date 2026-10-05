import { useT } from '../i18n/t';
import { DASH_SEPARATOR, RANGE_SEPARATOR } from '../i18n/punctuation';
import type { ActivePrediction, Prediction } from '../domain/schemas';
import {
  homeEstimateView,
  isoDateFormatter,
  profileModeFromDb,
  type HomeEstimateView,
  type WebProfileMode,
} from '../lib/profiles/profile-views';

/**
 * The profile home's estimate card (issue #1253): cycle day, period-day
 * line, the next-period estimate with its confidence, and the framing the
 * profile's care mode composes — a teen is never "late" (#853/#998), the
 * irregular framing shows ranges and quiet lines instead of a late
 * banner, life-stage modes and birth control suppress the estimate
 * outright, and every estimate carries the R17 disclaimer. All copy rides
 * the ARB catalogue.
 */

const kDateLocale = 'en';

/** Formats an ISO date the way the app's estimate row does (medium). */
export const formatEstimateDate = isoDateFormatter(kDateLocale, { dateStyle: 'medium' });

/** The catalogue id for one prediction's tier chip label. */
export function tierLabelId(tier: ActivePrediction['tier']) {
  switch (tier) {
    case 'high':
      return 'cycleConfidenceHigh' as const;
    case 'learning':
      return 'cycleConfidenceLearning' as const;
    case 'irregular':
      return 'cycleConfidenceIrregular' as const;
    case 'provisional':
      return 'cycleConfidenceProvisional' as const;
  }
}

/** The catalogue id for one prediction's tier explainer line. */
export function tierSummaryId(tier: ActivePrediction['tier']) {
  switch (tier) {
    case 'high':
      return 'cycleConfidenceSummaryHigh' as const;
    case 'learning':
      return 'cycleConfidenceSummaryLearning' as const;
    case 'irregular':
      return 'cycleConfidenceSummaryIrregular' as const;
    case 'provisional':
      return 'cycleConfidenceSummaryProvisional' as const;
  }
}

/** The catalogue id for a birth-control method's display name. */
export function birthControlLabelId(method: string) {
  switch (method) {
    case 'pill':
      return 'birthControlPill' as const;
    case 'hormonalIud':
      return 'birthControlHormonalIud' as const;
    case 'copperIud':
      return 'birthControlCopperIud' as const;
    case 'implant':
      return 'birthControlImplant' as const;
    case 'shot':
      return 'birthControlInjection' as const;
    case 'ring':
      return 'birthControlRing' as const;
    case 'patch':
      return 'birthControlPatch' as const;
    case 'condom':
      return 'birthControlCondom' as const;
    case 'other':
      return 'birthControlOther' as const;
    default:
      return 'birthControlNotAnswered' as const;
  }
}

/** The catalogue id for a life-stage mode's display name. */
export function lifecycleModeLabelId(mode: string) {
  switch (mode) {
    case 'conceive':
      return 'webDayModeConceive' as const;
    case 'pregnancy':
      return 'webDayModePregnancy' as const;
    case 'perimenopause':
      return 'webDayModePerimenopause' as const;
    case 'postpartum':
      return 'webDayModePostpartum' as const;
    default:
      return 'webDayModeTracking' as const;
  }
}

/**
 * The overdue line's catalogue id for the composed framing — a teen's
 * quiet line at every tier (#998), the irregular framing's line for every
 * other mode (`_composedOverdueStatusLabel`).
 */
export function composedOverdueLineId(mode: WebProfileMode) {
  return mode === 'teen'
    ? ('webHomeTeenOverdueLine' as const)
    : ('webHomeIrregularOverdueLine' as const);
}

/** The estimate heading's catalogue id (care_modes' label composition). */
export function estimateHeadingId(view: Extract<HomeEstimateView, { kind: 'active' }>) {
  if (view.composed) return 'webHomeNextEstimateRangeLabel' as const;
  if (view.mode === 'teen') return 'webHomeNextEstimateLabelTeen' as const;
  return 'webHomeNextEstimateLabel' as const;
}

/** The insufficient-history progress step's catalogue id and values. */
export function notEnoughProgress(
  completed: number,
  needed: number,
): {
  id:
    | 'webHomeNotEnoughNextPeriodStep'
    | 'webHomeNotEnoughFirstCyclesStep'
    | 'webHomeNotEnoughRemainingStep';
  values?: Record<string, number>;
} {
  const remaining = needed - completed;
  if (remaining <= 1) return { id: 'webHomeNotEnoughNextPeriodStep' };
  if (completed === 0) {
    return { id: 'webHomeNotEnoughFirstCyclesStep', values: { needed } };
  }
  return { id: 'webHomeNotEnoughRemainingStep', values: { remaining } };
}

export function ProfileHomeStatus(props: {
  prediction: Prediction;
  profileMode: string;
  storedIrregularFraming: boolean | null | undefined;
  todayIso: string;
  displayName: string;
}) {
  const t = useT();
  const view = homeEstimateView({
    prediction: props.prediction,
    profileMode: profileModeFromDb(props.profileMode),
    storedIrregularFraming: props.storedIrregularFraming,
    todayIso: props.todayIso,
  });

  if (view.kind === 'disabled') {
    return (
      <section className="card" aria-labelledby="home-estimate-title">
        <h2 className="card-title" id="home-estimate-title">
          {props.displayName}
        </h2>
        <p className="home-state-title">{t('predictionsDisabledTitle')}</p>
        <p className="card-body">{t('predictionsDisabledBody')}</p>
      </section>
    );
  }

  if (view.kind === 'suppressed') {
    return (
      <section className="card" aria-labelledby="home-estimate-title">
        <h2 className="card-title" id="home-estimate-title">
          {props.displayName}
        </h2>
        <p className="home-state-title">{t('predictionsSuppressedTitle')}</p>
        <p className="card-body">
          {view.lifecycleModeDb !== null
            ? t('predictionsSuppressedByModeBody', {
                mode: t(lifecycleModeLabelId(view.lifecycleModeDb)),
              })
            : t('predictionsSuppressedBody', {
                method: t(
                  view.methodDb !== null
                    ? birthControlLabelId(view.methodDb)
                    : 'birthControlNotAnswered',
                ),
              })}
        </p>
      </section>
    );
  }

  if (view.kind === 'notEnoughHistory') {
    const step = notEnoughProgress(view.completedCycles, view.neededCycles);
    return (
      <section className="card" aria-labelledby="home-estimate-title">
        <h2 className="card-title" id="home-estimate-title">
          {props.displayName}
        </h2>
        <p className="home-state-title">
          {view.teen ? t('webHomeNotEnoughTitleTeen') : t('webHomeNotEnoughTitle')}
        </p>
        <p className="card-body">
          {t('webHomeNotEnoughProgress', {
            completed: view.completedCycles,
            needed: view.neededCycles,
            nextStep: t(step.id, step.values),
          })}
        </p>
      </section>
    );
  }

  // Active estimate. Phase line: the app's wheel reads "Period, day N"
  // during an episode and "Cycle day N" otherwise.
  const phaseLine = view.duringEpisode
    ? t('cycleWheelPhasePeriodDay', { day: Math.max(view.episodeDay, 1) })
    : t('cycleWheelCenterCycleDay', { day: view.cycleDay });
  const estimateText =
    view.estimate.kind === 'date'
      ? formatEstimateDate(view.estimate.iso)
      : `${formatEstimateDate(view.estimate.startIso)}${RANGE_SEPARATOR}${formatEstimateDate(view.estimate.endIso)}`;
  const showTierCaption = !view.composed && view.tier !== 'high';
  const overdueLine =
    view.overdue === null
      ? null
      : view.composed
        ? t(composedOverdueLineId(view.mode))
        : view.mode === 'teen'
          ? t('webHomeTeenOverdueLine')
          : t('lateResolverDaysLate', { count: view.overdue.daysLate ?? 0 });

  return (
    <section className="card" aria-labelledby="home-estimate-title">
      <h2 className="card-title" id="home-estimate-title">
        {props.displayName}
      </h2>
      <p className="home-phase">{phaseLine}</p>
      <p className="home-estimate">
        <span className="home-estimate-label">{t(estimateHeadingId(view))}</span>{' '}
        <span className="home-estimate-value">{estimateText}</span>
      </p>
      {showTierCaption ? (
        <p className="home-tier">
          {t(tierLabelId(view.tier))}
          {DASH_SEPARATOR}
          {t(tierSummaryId(view.tier))}
        </p>
      ) : null}
      {overdueLine !== null ? <p className="home-overdue">{overdueLine}</p> : null}
      {view.staleHistory ? (
        <p className="home-stale">
          <strong>{t('overviewStaleHistoryTitle')}</strong> {t('overviewStaleHistoryBody')}
        </p>
      ) : null}
      {view.unusuallyLongCycle ? (
        <p className="home-stale">
          <strong>{t('overviewLongCycleTitle')}</strong> {t('overviewLongCycleBody')}
        </p>
      ) : null}
      <p className="home-disclaimer">{t('webHomeEstimateDisclaimer')}</p>
    </section>
  );
}
